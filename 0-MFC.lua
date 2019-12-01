ardour {
	["type"]    = "dsp",
	name        = "0-MFC",
	category    = "Example",
	license     = "MIT",
	author      = "Thomas Brand",
	description = [[Multi Fader Control by using input and output ports of 0-SD and 0-FC lua plugins on strips]]
}

--[[
this plugin uses other plugins on tracks and then decides on further actions.
it can be used in a stopped or a rolling session, where the mixer view will show everything
needed for the following scenarios.

for a given range of track indices (defined in 0-MFC), the track with the lowest index having 
a signal above the defined threshold (defined in 0-SD per track) will be faded in,
all other tracks will be faded out (defined in 0-FC per track).

this plugin constellation can be used to have an array of fallback channels
that switch "scene" by using the track's faders in a configurable way.

the track with the highest index can be seen as the "background" track.
the scenario works for simple 2 track cases and can extend to more demanding setups
via tracks grouped as busses and with that the possibility to create sort of precedence trees.
one could have on track index 0 the console microphone, and on the last track some elevator music.
or on another track having a stream that's connected at a given time by an external process, that's
only being played if no track with a higher priority (=lower index) is active or the opposite, 
overrule any other tracks etc.

speed and delay of fades are configurable. one track might be set so that it takes a long 
time before handing over to a following track with lower priority having a signal above the treshold, 
but a very short time to be the active track again if a signal is available again.
setting the DelayConfirmOver parameter of 0-SD to 0 will be good to activate a channel immediately 
i.e. by hitting on the mike (or on the notebook if it has an internal microphone).
if DelayConfirmUnder is set to 5 seconds, the channel will "close" again if singer didn't sing or speaker
didn't speak above the threshold during that period.
of course this trigger could be used to put individual tracks ready to record and do transport control;
however this is currently not implemented. it could be an alternative to record all tracks or the 
master track if needed. this involves manually setting up everything for recording at this time.

the main focus of 0-MFC is to operate the brilliant ardour mixer in an automatic live manner:
to select and forward an input (only one) by signal level and precedence rules and turning off 
or lowering the gain of non-active inputs.

this can be useful for a hobbyist radio station to semi-automatically run a program, and to be 
sure that something is on air at all times having connected a (possibly local, always playing) 
source to the track with the highest index.

if the auto fader logic is useful for semi-automatic / dynamic mixing in a non-standard way 
(i.e. create a quickly changing random audio layer as a function of the array) has yet to be explored.

a possible configuration and stack of processors on one track:

-set fixed to "IN" to process any signal that is connected to the track audio input ports

-input trim (enable in preferences)
-custom meter point (enable with button at bottom right of strip)
-0-SD (silence detection lua script, plugin index 0, reading input before fader)*
-0-FC (fader control, plugin index 1)* **
-a-Inline Scope (showing trimmed input signal)
-fader (auto controlled, having effect on output signal)
-a-Inline Scope (showing trimmed & faded output signal going to master)

*0-MFC looks for the *first* 0-SD and 0-FC plugins found on involved tracks
**set input param TrackIndex to the index of the track where the 0-FC plugin is on

-duplicate track n times (there is currently a non-hard limit for 16 tracks)

-add this plugin (0-MFC.lua) anywhere on any track or bus, i.e. the masterbus.
-configure the start index and count of tracks to involve for evaluation.
-i.e. set 0-SD Threshold of first track to a high value so that StatusConfirmed will be 0 
-see how faders move, depending on 0-SD, 0-FC and 0-MFC settings.
-the lowest channel index number having a signal above the threshold level will be faded up, any other channel faded down

to control faders manually again:
-deactivate this plugin (0-MFC) and set FadeAction of 0-FC plugins on tracks to Released
OR
-deactivate 0-FC plugins on tracks

hint: to switch the priority of a track after creating the array, simply move it to a lower index.
make sure that 0-FC TrackSelection is set to automatic in order for this to work.

leave me a comment if anything doesn't work as you'd expect
--]]

-- return possible i/o configurations
-------------------------------------------------------------------------------
function dsp_ioconfig ()
	-- -1, -1 = any number of channels as long as input and output count matches
	return { { midi_in = 0, midi_out = 1, audio_in = -1, audio_out = -1}, }
end

local sense_plugin='0-SD'
local sense_plugin_output_StatusConfirmed='StatusConfirmed'

local control_plugin='0-FC'
local control_plugin_input_TrackSelection='TrackSelection'
local control_plugin_input_TrackIndex='TrackIndex'
local control_plugin_input_FadeAction='FadeAction'

local midi_event = { 0xb0, 0x50, 0x00 }
--all 3 bytes will be updated based on
--    -channel (user setting)
--    -cc      (user setting)
--    -active track index (dynamic evaluation)

local current_track_index=0

-- control port(s)
-------------------------------------------------------------------------------
function dsp_params ()
	return
	{
		{ ["type"] = "input",
			name = "TrackIndexStart", --1
			doc = "Track index of track with highest priority.",
			min = 0, max = 15, default = 0, integer = true },
		{ ["type"] = "input",
			name = "TrackCount", --2
			doc = "How many tracks (including the first at TrackIndexStart) to consider for auto fading.",
			min = 0, max = 15, default = 0, integer = true },
		{ ["type"] = "output",
			name = "ActiveTrackIndex", --3
			doc = "The index of the currently active (faded in) track.",
			min = 0, max = 15, default = 0, integer = true },
		{ ["type"] = "input",
			name = "SendMidi", --4
			doc = "If enabled, notify track index change via MIDI.",
			min = 0, max = 1, default = 1, toggled = true },
		{ ["type"] = "input",
			name = "SendMidiContinuous", --5
			doc = "If enabled, notify active track index in each cycle via MIDI.",
			min = 0, max = 1, default = 0, toggled = true },
		{ ["type"] = "input",
			name = "SendMidiChannel", --6
			doc = "Set the MIDI channel to be used for sending out notifications.",
			min = 1, max = 16, default = 1, integer = true },
		{ ["type"] = "input",
			name = "SendMidiCC", --7
			doc = "Set the MIDI controller number to be used for sending out notifications.",
			min = 0, max = 101, default = 80, integer = true },
	}
end -- dsp_params()

--
-------------------------------------------------------------------------------
function get_route_id_by_index(index)
	if index==nil or index < 0 then return nil end
	local r=Session:get_remote_nth_route(index)
	if r:isnil() then return nil end
	return r:to_stateful():id():to_s()
end

--
---------------------------------------------------------------------
function get_nth_plugin_id_by_name(route_id, name, nth_match) --nth_match 0: first match
	if route_id==nil or name==nil or nth_match==nil then return nil end

	local r=Session:route_by_id(PBD.ID(route_id))
	if r:isnil() then return nil end

	--getting plugin count (?)
	local proc
	local matches=0
	local i=0
	--try and error
	repeat
		-- get Nth Ardour::Processor
		proc = r:nth_plugin (i)
		if (not proc:isnil() and proc:display_name () == name) then
			if matches == nth_match then
				return proc:to_stateful():id():to_s()
			else
				matches=matches+1
			end
		end
		i = i + 1
	until proc:isnil()
	return nil
end

--
-------------------------------------------------------------------------------
function get_nth_plugin_parameter_index_by_name(plugin_id, name, nth_match) --nth_match 0: first match
	if plugin_id==nil or name==nil or nth_match==nil then return nil end

	local proc=Session:processor_by_id(PBD.ID(plugin_id))
	if proc:isnil() then return nil end

	local pinsert=proc:to_insert()
	if pinsert:isnil() then return nil end

	local plugin=pinsert:plugin(0)
	--this includes both input AND output ports
	local param_count=plugin:parameter_count()
	--print(param_count)

	local matches=0

	for param_index=0,param_count-1 do
		local _,pd = plugin:get_parameter_descriptor(param_index,ARDOUR.ParameterDescriptor())
		-- t[2].label --.. " " .. t[2].lower .. " " .. t[2].upper
		if pd[2].label == name then
			if matches == nth_match then
				--local ctrl = Evoral.Parameter(ARDOUR.AutomationType.PluginAutomation,0,param_index)
				return param_index
			else
				matches=matches+1
			end
		end
	end
	return nil
end -- get_nth_plugin_parameter_index_by_name()

--
-------------------------------------------------------------------------------
function get_plugin_control_value(plugin_id, param_index)
	if plugin_id==nil or param_index==nil or param_index < 0 then return nil end

	local proc=Session:processor_by_id(PBD.ID(plugin_id))
	if proc:isnil() then return nil end

	local pinsert=proc:to_insert()
	if pinsert:isnil() then return nil end

	local val,ok=ARDOUR.LuaAPI.get_plugin_insert_param(pinsert,param_index,ok)
	if ok==false then return nil end
	return val
end

--
-------------------------------------------------------------------------------
function set_plugin_control_value(plugin_id, param_index, value)
	if plugin_id==nil or param_index==nil or param_index < 0 or value==nul then return nil end

	local proc=Session:processor_by_id(PBD.ID(plugin_id))
	if proc:isnil() then return nil end

	local pinsert=proc:to_insert()
	if pinsert:isnil() then return nil end

	--not a good idea to try to set an output control value
	return ARDOUR.LuaAPI.set_plugin_insert_param(pinsert,param_index,value)
end

--
-------------------------------------------------------------------------------
function dsp_init (rate)
--	local tbl = {}
--	self:table ():set (tbl);
	print ("'0-MFC.lua' initialized (dsp_init).")
end -- dsp_init()

-------------------------------------------------------------------------------
function fade(rid, direction) -- -1 fade_out +1 fade_in
	if rid==nil or rid < 0 or direction==nil then return nil end

	local plugin_id=get_nth_plugin_id_by_name(get_route_id_by_index(rid),control_plugin,0)
	if plugin_id==nil then return false end

	--if plugin has set TrackSelection to Automatic (1) then set track index
	local param_index=get_nth_plugin_parameter_index_by_name(plugin_id, control_plugin_input_TrackSelection, 0)
	if param_index==nil then return false end

	local sel_style=get_plugin_control_value(plugin_id, param_index)
	if sel_style==nil then return false end

	if math.floor(sel_style) == 1 then --set track id

		local param_index=get_nth_plugin_parameter_index_by_name(plugin_id, control_plugin_input_TrackIndex, 0)
		if param_index==nil then return false end
		set_plugin_control_value(plugin_id, param_index, rid)
	end

	--find and trigger fade action
	local param_index=get_nth_plugin_parameter_index_by_name(plugin_id, control_plugin_input_FadeAction, 0)
	if param_index==nil then return false end

	return set_plugin_control_value(plugin_id, param_index, direction)
end -- fade()

-------------------------------------------------------------------------------
function fade_in(rid)
	return fade(rid,1)
end -- fade_in()

-------------------------------------------------------------------------------
function fade_out(rid)
	return fade(rid,-1)
end -- fade_in()

-------------------------------------------------------------------------------
--function dsp_runmap (bufs, in_map, out_map, n_samples, offset)

function dsp_run (_, _, n_samples)

	assert (type(midiout) == "table")
	local cnt = 1;

	function tx_midi (time, data)
		midiout[cnt] = {}
		midiout[cnt]["time"] = time;
		midiout[cnt]["data"] = data;
		cnt = cnt + 1;
	end

	local ctrl = CtrlPorts:array ()
	local first_track_index=math.floor(ctrl[1])
	local track_count=math.floor(ctrl[2])
	local current_track_index=math.floor(ctrl[3])

	local send_midi=math.floor(ctrl[4])
	local send_midi_cont=math.floor(ctrl[5])

	local send_midi_channel=math.floor(ctrl[6])
	local send_midi_cc=math.floor(ctrl[7])

	midi_event[1]=(0xb0 + (send_midi_channel - 1)) --set channel
	midi_event[2]=send_midi_cc --set cc number

	local function fade_out_all_except(index)
		--print ("fade out except index " .. index)
		if index < first_track_index or index > first_track_index+track_count-1 then return end
		for track_index = first_track_index, first_track_index+track_count-1 do
			if not (index == track_index) then
				--print ("fading out track index " .. track_index)
				fade_out(track_index)
			end
		end
	end

	for track_index = first_track_index, first_track_index+track_count-1 do
		local plugin_id=get_nth_plugin_id_by_name(get_route_id_by_index(track_index),sense_plugin,0)
		if not(plugin_id==nil) then
			local param_index=get_nth_plugin_parameter_index_by_name(plugin_id, sense_plugin_output_StatusConfirmed, 0)
			if not(param_index==nil) then
				local val1=math.floor(get_plugin_control_value(plugin_id, param_index))
				if val1 == 1 then
					fade_out_all_except(track_index)
					fade_in(track_index)

					if not (current_track_index == track_index) then
						print ('MFC: switch to track index '..track_index )
						ctrl[3]=track_index --set current/new active track
						midi_event[3]=track_index --indicate active channel as controller value
						--notify when change happened
						if (send_midi == 1) and (send_midi_cont == 0) then
							tx_midi(1, midi_event)
						end
					end

					--if continous notification is enabled
					if (send_midi == 1) and (send_midi_cont == 1) then
						tx_midi(1, midi_event)
					end

					break;
				elseif val1 == 0 then
					fade_out(track_index)
				end
			end --param_index not nil
		end --plugin_id not nil
	end --for involved tracks

	-- request redraw 
	self:queue_draw ()
end -- dsp_runmap()

local txt = nil -- cache font description (in GUI context)
-------------------------------------------------------------------------------
function render_inline (ctx, w, max_h)
	-- could display something here
	h=0
	return {w, h}
end -- render_inline()
-- EOF

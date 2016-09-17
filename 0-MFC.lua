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
-0-SD (silence detection lua script, plugin index 0, reading input before fader)* /!\
-0-FC (fader control, plugin index 1)**
-a-Inline Scope (showing trimmed input signal)
-fader (auto controlled, having effect on output signal)
-a-Inline Scope (showing trimmed & faded output signal going to master)

*0-MFC looks for the 0-SD plugin on involved tracks at index 0, always.
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

leave me a comment if anything doesn't work as you'd expect
--]]

-- return possible i/o configurations
-------------------------------------------------------------------------------
function dsp_ioconfig ()
	-- -1, -1 = any number of channels as long as input and output count matches
	return { { audio_in = -1, audio_out = -1}, }
end

-- control port(s)
-------------------------------------------------------------------------------
function dsp_params ()
	return
	{
		{ ["type"] = "input",
			name = "TrackIndexStart", --1
			doc = "Track index of track with highest priority",
			min = 0, max = 15, default = 0, integer = true },
		{ ["type"] = "input",
			name = "TrackCount", --2
			doc = "How many tracks (including the first at TrackIndexStart) to consider for auto fading.",
			min = 0, max = 15, default = 0, integer = true },
		{ ["type"] = "output",
			name = "ActiveTrackIndex", --3
			doc = "The index of the currently active (faded in) track.",
			min = 0, max = 15, default = 0, integer = true },
	}
end -- dsp_params()

-------------------------------------------------------------------------------
function dsp_init (rate)
	print ("'0-MFC.lua' initialized (dsp_init).")
end -- dsp_init()

-------------------------------------------------------------------------------
function get_plugin_param_value(rid, pid, param_id)
	local track = Session:get_remote_nth_route(rid)
	if track:isnil() then return nil end
	local proc = track:nth_plugin (pid)
	if proc:isnil() then return nil end
	local pinsert=proc:to_insert()
	if pinsert:isnil() then return nil end
	local outval=ARDOUR.LuaAPI.get_plugin_insert_param(pinsert,param_id)

	return outval
end -- get_plugin_param_value()

-------------------------------------------------------------------------------
function fade(rid, direction) -- -1 fade_out +1 fade_in
	local pid=1
	local fade_param_id=4

	local track = Session:get_remote_nth_route(rid)
	if track:isnil() then return nil end
	local proc = track:nth_plugin (pid)
	if proc:isnil() then return nil end
	local pinsert=proc:to_insert()
	if pinsert:isnil() then return nil end

	ARDOUR.LuaAPI.set_plugin_insert_param(pinsert,fade_param_id,direction)

	--print("set " .. rid .. " direction " .. direction )
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
function dsp_runmap (bufs, in_map, out_map, n_samples, offset)
	-- passthrough all data
	ARDOUR.DSP.process_map (bufs, in_map, out_map, n_samples, offset, ARDOUR.DataType ("audio"))
	ARDOUR.DSP.process_map (bufs, in_map, out_map, n_samples, offset, ARDOUR.DataType ("midi"))

	local ctrl = CtrlPorts:array ()
	local first_track_index=math.floor(ctrl[1])
	local track_count=math.floor(ctrl[2])

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
		local val1=get_plugin_param_value(track_index,0,4) --get from first plugin on strip 5th value
		if val1 == 1 then
			fade_out_all_except(track_index)
			fade_in(track_index)
			ctrl[3]=track_index
			break;
		elseif val1 == 0 then
			fade_out(track_index)
		end
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

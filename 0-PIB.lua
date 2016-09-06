ardour {
	["type"]    = "dsp",
	name        = "0-PIB",
	category    = "Example",
	license     = "MIT",
	author      = "Thomas Brand",
	description = [[Plugin Browser]]
}

--[[
focus and value setting
select item and step values with midi increment/decrement impulses
--]]

local padding = 2
local line_height = 10

-- return possible i/o configurations
-------------------------------------------------------------------------------
function dsp_ioconfig ()
	-- -1, -1 = any number of channels as long as input and output count matches
	return { { midi_in = 1, midi_out = 1, audio_in = -1, audio_out = -1}, }
end

-- control port(s)
-------------------------------------------------------------------------------
function dsp_params ()
	return
	{
		{ ["type"] = "input",
			name = "DisplayHeight", --1
			doc = "Rastered height of inline widget",
			min = 1, max = 4, default = 3, integer = true },

		{ ["type"] = "input",
			name = "DecrementImpulseControllerNumber", --2
			doc = "",
			min = 0, max = 127, default = 20, integer = true },
		{ ["type"] = "input",
			name = "DecrementImpulseControllerValue", --3
			doc = "",
			min = 0, max = 127, default = 2, integer = true },
		{ ["type"] = "input",
			name = "IncrementImpulseControllerNumber", --4
			doc = "",
			min = 0, max = 127, default = 20, integer = true },
		{ ["type"] = "input",
			name = "IncrementImpulseControllerValue", --5
			doc = "",
			min = 0, max = 127, default = 3, integer = true },

		{ ["type"] = "input",
			name = "DecrementImpulseControllableNumber", --6
			doc = "",
			min = 0, max = 127, default = 10, integer = true },
		{ ["type"] = "input",
			name = "DecrementImpulseControllableValue", --7
			doc = "",
			min = 0, max = 127, default = 2, integer = true },
		{ ["type"] = "input",
			name = "IncrementImpulseControllableNumber", --8
			doc = "",
			min = 0, max = 127, default = 10, integer = true },
		{ ["type"] = "input",
			name = "IncrementImpulseControllableValue", --9
			doc = "",
			min = 0, max = 127, default = 3, integer = true },

		{ ["type"] = "input",
			name = "PotPushImpulseControllerNumber", --10
			doc = "",
			min = 0, max = 127, default = 50, integer = true },
		{ ["type"] = "input",
			name = "PotPushImpulseControllerValue", --11
			doc = "",
			min = 0, max = 127, default = 1, integer = true },
		{ ["type"] = "input",
			name = "PotReleaseImpulseControllerNumber", --12
			doc = "",
			min = 0, max = 127, default = 50, integer = true },
		{ ["type"] = "input",
			name = "PotReleaseImpulseControllerValue", --13
			doc = "",
			min = 0, max = 127, default = 0, integer = true },
	}
end -- dsp_params()

-------------------------------------------------------------------------------
function dsp_init (rate)
	-- allocate memory for 4 integers
	self:shmem():allocate(4)
	local shared_buffer = self:shmem():to_int(0):array()
	for i = 1, 4 do
		shared_buffer[i] = 0
	end
--[[
	buffer layout (1-based array)
val     [1]: controller value: relative change (increment count - decrement count)
        [2]: controller last direction
        [3]: push status
line    [4]: controllable value: relative change (increment count - decrement count)
--]]

	-- create a table of objects to share with the GUI
	local tbl = {}
	tbl['track_rid'] = 0
	tbl['track_name'] = ""
	tbl['plugin_id'] = 0
	tbl['plugin_name'] = ""
	tbl['plugin_param_id'] = 0
	tbl['plugin_param_name'] = ""

	-- "self" is a special DSP variable referring
	-- to the plugin instance itself.
	--
	-- "table()" is-a http://manual.ardour.org/lua-scripting/class_reference/#ARDOUR.LuaTableRef
	-- which allows to store/retrieve lua-tables to share them other interpreters
	self:table ():set (tbl);

	print ("'0-Pot.lua' initialized (dsp_init).")
end -- dsp_init()

-------------------------------------------------------------------------------
function is_dec_controller(ev)
	local ctrl = CtrlPorts:array () -- get control port array (read/write)
	local midi_dec_controller=math.floor(ctrl[2])
	local midi_dec_controller_value=math.floor(ctrl[3])
	if ev[2] == midi_dec_controller and ev[3] == midi_dec_controller_value then
		return 1
	else
		return 0
	end
end

-------------------------------------------------------------------------------
function is_inc_controller(ev)
	local ctrl = CtrlPorts:array ()
	local midi_inc_controller=math.floor(ctrl[4])
	local midi_inc_controller_value=math.floor(ctrl[5])
	if ev[2] == midi_inc_controller and ev[3] == midi_inc_controller_value then
		return 1
	else
		return 0
	end
end

-------------------------------------------------------------------------------
function is_dec_controllable(ev)
	local ctrl = CtrlPorts:array ()
	local midi_dec_controllable=math.floor(ctrl[6])
	local midi_dec_controllable_value=math.floor(ctrl[7])
	if ev[2] == midi_dec_controllable and ev[3] == midi_dec_controllable_value then
		return 1
	else
		return 0
	end
end

-------------------------------------------------------------------------------
function is_inc_controllable(ev)
	local ctrl = CtrlPorts:array ()
	local midi_inc_controllable=math.floor(ctrl[8])
	local midi_inc_controllable_value=math.floor(ctrl[9])
	if ev[2] == midi_inc_controllable and ev[3] == midi_inc_controllable_value then
		return 1
	else
		return 0
	end
end

-------------------------------------------------------------------------------
function is_midi_push(ev)
	local ctrl = CtrlPorts:array ()
	local midi_push_controller=math.floor(ctrl[10])
	local midi_push_controller_value=math.floor(ctrl[11])
	if ev[2] == midi_push_controller and ev[3] == midi_push_controller_value then
		return 1
	else
		return 0
	end
end

-------------------------------------------------------------------------------
function is_midi_release(ev)
	local ctrl = CtrlPorts:array ()
	local midi_release_controller=math.floor(ctrl[12])
	local midi_release_controller_value=math.floor(ctrl[13])
	if ev[2] == midi_release_controller and ev[3] == midi_release_controller_value then
		return 1
	else
		return 0
	end
end

-------------------------------------------------------------------------------
function get_track_name_from_rid(rid)
	local track = Session:get_remote_nth_route(rid)
	if not track:isnil() then
		return track:name()
	end
	return 'n/a'
end

-------------------------------------------------------------------------------
function get_plugin_name(rid, pid)
	local track = Session:get_remote_nth_route(rid)
	if not track:isnil() then
		local proc = track:nth_plugin (pid)
		if not proc:isnil() then
			return proc:name()
		end
	end
	return 'n/a'
end

-------------------------------------------------------------------------------
function get_plugin_param_name(rid, pid, param_id)
	function error()
		return "" .. string.format("%d",rid) .. " " .. string.format("%d",pid) .. " " .. string.format("%d",param_id)
	end
	local track = Session:get_remote_nth_route(rid)
	if track:isnil() then return error() end
	local proc = track:nth_plugin (pid)
	if proc:isnil() then return error() end
	local pinsert=proc:to_insert()
	if pinsert:isnil() then return error() end
	local plugin=pinsert:plugin(0)
	--this includes both input AND output ports
	local param_count=plugin:parameter_count()
	if param_id >= 0 and param_id < param_count then
		local _,t = plugin:get_parameter_descriptor(param_id,ARDOUR.ParameterDescriptor())
	---	local ctrl = Evoral.Parameter(ARDOUR.AutomationType.PluginAutomation,0,param_id)
		return t[2].label --.. " " .. t[2].lower .. " " .. t[2].upper
	end
	return error()
end -- get_plugin_param_name()

-------------------------------------------------------------------------------
function set_track_name()
	local tbl = self:table ():get ()
	tbl['track_name']=get_track_name_from_rid(tbl['track_rid'])
	self:table ():set (tbl);
end

-------------------------------------------------------------------------------
function set_plugin_name()
	local tbl = self:table ():get ()
	tbl['plugin_name']=get_plugin_name(tbl['track_rid'],tbl['plugin_id'])
	self:table ():set (tbl);
end

-------------------------------------------------------------------------------
function set_plugin_param_name()
	local tbl = self:table ():get ()
	tbl['plugin_param_name']=get_plugin_param_name(tbl['track_rid'],tbl['plugin_id'],tbl['plugin_param_id'])
	self:table ():set (tbl);
end

-------------------------------------------------------------------------------
function dsp_runmap (bufs, in_map, out_map, n_samples, offset)
	-- passthrough all data
	ARDOUR.DSP.process_map (bufs, in_map, out_map, n_samples, offset, ARDOUR.DataType ("audio"))
	ARDOUR.DSP.process_map (bufs, in_map, out_map, n_samples, offset, ARDOUR.DataType ("midi"))

	local shared_buffer = self:shmem():to_int(0):array()
	local tbl = self:table ():get () -- get shared memory table

	local last_value_direction=shared_buffer[2]

	local increment_value_count=0
	local decrement_value_count=0
	local increment_controllable_count=0
	local decrement_controllable_count=0

	-- then fill the event buffer
	local ib = in_map:get (ARDOUR.DataType ("midi"), 0) -- index of 1st midi input

	if ib ~= ARDOUR.ChanMapping.Invalid then
		local events = bufs:get_midi (ib):table () -- copy event list into a lua table

		-- iterate over all MIDI events
		for _, e in pairs (events) do
			-- print (e:channel (), e:time (), e:size (), e:buffer():array()[1], e:buffer():get
			local ev = e:buffer():array()

			if ev[1] >> 4 == 11 then --CC
				-- print ("cc " .. ev[2] .. " " .. ev[3])
				if is_dec_controller(ev)==1 then
					decrement_value_count=decrement_value_count+1
					last_value_direction=-1
				elseif is_inc_controller(ev)==1 then
					increment_value_count=increment_value_count+1
					last_value_direction=1
				elseif is_dec_controllable(ev)==1 then
					decrement_controllable_count=decrement_controllable_count+1
				elseif is_inc_controllable(ev)==1 then
					increment_controllable_count=increment_controllable_count+1
				elseif is_midi_push(ev)==1 then
					shared_buffer[3]=1
				elseif is_midi_release(ev)==1 then
					shared_buffer[3]=0
				end
			end -- if cc event
		end -- for midi events
	end -- if channel mapping valid

	-- limit 0, 127
	shared_buffer[1]=math.min(127, math.max(0, shared_buffer[1]+increment_value_count-decrement_value_count))

	-- set last direction
	if shared_buffer[1]==0 then
		shared_buffer[2]=-2
	elseif shared_buffer[1]==127 then
		shared_buffer[2]=2
	else
		shared_buffer[2]=last_value_direction 
	end

	-- limit 0, 2
	shared_buffer[4]=math.min(2, math.max(0, shared_buffer[4]+increment_controllable_count-decrement_controllable_count))

	if shared_buffer[4]==0 then
		tbl['track_rid']=math.max(0, tbl['track_rid']+increment_value_count-decrement_value_count)
	elseif shared_buffer[4]==1 then
		tbl['plugin_id']=math.max(0, tbl['plugin_id']+increment_value_count-decrement_value_count)
	elseif shared_buffer[4]==2 then
		tbl['plugin_param_id']=math.max(0, tbl['plugin_param_id']+increment_value_count-decrement_value_count)
	end

	self:table ():set (tbl);

	set_track_name()
	set_plugin_name()
	set_plugin_param_name()

	--print ("track id " .. tbl['track_rid'] .. " name " .. tbl['track_name'] .. " plugin id " .. tbl['plugin_id'] .. " plugin name " .. tbl['plugin_name'])

	-- request redraw 
	self:queue_draw ()
end -- dsp_runmap()

local txt = nil -- cache font description (in GUI context)

-------------------------------------------------------------------------------
function render_inline (ctx, w, max_h)
	local ctrl = CtrlPorts:array () -- control port array
	local shared_buffer = self:shmem():to_int(0):array()
	local tbl = self:table ():get () -- get shared memory table

	local selected_line = shared_buffer[4]
	local line_count = math.floor(ctrl[1])

	h = 2 * padding + line_count * line_height
	if h > max_h then h=max_h end

	-- prepare text rendering
	-- http://manual.ardour.org/lua-scripting/class_reference/#Cairo:PangoLayout
	if not txt then txt = Cairo.PangoLayout (ctx, "Mono 10px") end

	-- ctx is-a http://manual.ardour.org/lua-scripting/class_reference/#Cairo:Context
	-- 2D vector graphics http://cairographics.org/

	-- "inline" function
	-------------------------------------------------------------------------------
	function draw_key_value_line (line,key,value,autohide_key)
		if selected_line==line then
			ctx:set_source_rgba (.0, .0, .0, 1.0)
		else
			ctx:set_source_rgba (.9, .9, .9, 1.0)
		end

		if w < 100 and autohide_key==1 then
			txt:set_text (string.format ("%s",value))
		else
			txt:set_text (string.format ("%s %s",key,value))
		end

		local tw, th = txt:get_pixel_size ()
		ctx:move_to (0+padding,line*line_height+padding)
		txt:show_in_cairo_context (ctx)
	end

	-- clear background
	ctx:rectangle (0, 0, w, h)
	ctx:set_source_rgba (.2, .2, .2, 1.0)
	ctx:fill ()

	--draw highlight
	ctx:rectangle (0+padding, padding + selected_line * line_height, w, padding+line_height)
	ctx:set_source_rgba (.2, .9, .2, 0.5)
	ctx:fill ()

	draw_key_value_line (0, string.format("%d)",tbl['track_rid']), tbl['track_name'], 1)
	draw_key_value_line (1, string.format("%d)",tbl['plugin_id']), tbl['plugin_name'], 1)
	draw_key_value_line (2, string.format("%d)",tbl['plugin_param_id']), tbl['plugin_param_name'], 1)

	return {w, h}
end -- render_inline()
-- EOF

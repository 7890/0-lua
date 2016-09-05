ardour {
	["type"]    = "dsp",
	name        = "0-Pot",
	category    = "Example",
	license     = "MIT",
	author      = "Thomas Brand",
	description = [[Knob]]
}

--[[
draw rotation knob with n steps
step rotate knob with midi increment/decrement impulses
--]]

local steps_per_rotation=32 --128
local padding=2

local M_PI=3.14159265359
local full_turn=2 * M_PI

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
			min = 2, max = 11, default = 7, integer = true },

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

	[1]: controller value: current value + relative change (increment count - decrement count)
	[2]: controller last direction
	[3]: push status
	[4]: controllable value: current value + relative change (increment count - decrement count)
--]]
	print ("'0-Pot.lua' initialized (dsp_init).")
end

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
function dsp_runmap (bufs, in_map, out_map, n_samples, offset)
--	local ctrl = CtrlPorts:array () -- get control port array (read/write)
	local shared_buffer = self:shmem():to_int(0):array()

	local last_value_direction=shared_buffer[2]

	local increment_value_count=0
	local decrement_value_count=0
	local increment_controllable_count=0
	local decrement_controllable_count=0

	-- passthrough all data
	ARDOUR.DSP.process_map (bufs, in_map, out_map, n_samples, offset, ARDOUR.DataType ("audio"))
	ARDOUR.DSP.process_map (bufs, in_map, out_map, n_samples, offset, ARDOUR.DataType ("midi"))

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

	local fast_factor=1
	-- limit 0, 127
	shared_buffer[1]=math.min(127, math.max(0, shared_buffer[1]+fast_factor*increment_value_count-fast_factor*decrement_value_count))

	-- set last direction
	if shared_buffer[1]==0 then
		shared_buffer[2]=-2
	elseif shared_buffer[1]==127 then
		shared_buffer[2]=2
	else
		shared_buffer[2]=last_value_direction 
	end

	-- limit 0, 127
	shared_buffer[4]=math.min(127, math.max(0, shared_buffer[4]+increment_controllable_count-decrement_controllable_count))

	-- force redraw 
	self:queue_draw ()
end -- dsp_runmap()

local txt1 = nil -- cache font description (in GUI context)
local txt2 = nil
local txt = nil 
-------------------------------------------------------------------------------
function render_inline (ctx, w, max_h)
	local ctrl = CtrlPorts:array () -- control port array
	local shared_buffer = self:shmem():to_int(0):array()

	local rotation_32_step = shared_buffer[1]
	local last_value_direction = shared_buffer[2]
	local push_status = shared_buffer[3]
	local controllable_value = shared_buffer[4]

	local line_count = math.floor(ctrl[1])
	local line_height = 10

	if (w > max_h) then
		h = max_h
	else
		h = line_count * line_height
	end

	-- prepare text rendering
	-- http://manual.ardour.org/lua-scripting/class_reference/#Cairo:PangoLayout
	if line_count > 8 then
		if not txt1 then txt1 = Cairo.PangoLayout (ctx, "Mono 20px") end
		txt=txt1
	else
		if not txt2 then txt2 = Cairo.PangoLayout (ctx, "Mono 10px") end
		txt=txt2
	end

	-- ctx is-a http://manual.ardour.org/lua-scripting/class_reference/#Cairo:Context
	-- 2D vector graphics http://cairographics.org/

	-- clear background
	ctx:rectangle (0, 0, w, h)
	ctx:set_source_rgba (.2, .2, .2, 1.0)
	ctx:fill ()
--[[
      ___
     /   \
    |     |---0 rad
     \___/  v


 n steps/0
        | >
       _|_
      /   \        
     |     |
      \___/
--]]
	local rotation_32_step_rad=(math.floor(rotation_32_step) / steps_per_rotation)

	if line_count > 5 then
		-- knob "3D" background
--		ctx:set_source_rgba (.0, .0, .0, 0.9)
--		ctx:arc(0+w/2, 4+h/2, h/3, 0, full_turn)
--		ctx:fill ()

		-- knob background
		if push_status==0 then
			ctx:set_source_rgba (.5, .9, .5, 1.0)
		else
			ctx:set_source_rgba (.9, .5, .5, 1.0)
		end

		ctx:arc(w/2, h/2, h/3, 0.0, full_turn)
		ctx:fill ()

		-- knob inner

		ctx:set_source_rgba (.1, .1, .1, 1.0)

		ctx:arc(w/2, h/2, 0.9*h/3, 0, full_turn)
		ctx:fill ()

		-- directed cut, default north
		local ang1=(-0.25 * M_PI) + rotation_32_step_rad * full_turn
		local ang2=( 1.25 * M_PI) + rotation_32_step_rad * full_turn

--		local ang1=(-1.25 * M_PI) + rotation_32_step_rad * full_turn
--		local ang2=( 0.25 * M_PI) + rotation_32_step_rad * full_turn

		if push_status==0 then
			ctx:set_source_rgba (.5, .9, .5, 1.0)
		else
			ctx:set_source_rgba (.9, .5, .5, 1.0)
		end

		ctx:arc_negative(w/2, h/2, 0.91*h/3, ang1, ang2)
		ctx:fill ()

		-- directed line
		ctx:set_source_rgba (.1, .1, .1, 1.0)

		ctx:arc(w/2, h/2, h/3, 0, 1.5 * M_PI + rotation_32_step_rad * full_turn)
		ctx:line_to(w/2,h/2)
		ctx:stroke()

		-- full knob outline
		ctx:set_source_rgba (.1, .1, .1, 1.0)
		ctx:arc(w/2, h/2, h/3, 0, full_turn)
		ctx:stroke()
	end -- if line_count > 5

	ctx:set_source_rgba (.9, .9, .9, 1.0)

	-- write text, centered
	txt:set_text (string.format ("%.0f",rotation_32_step));
	local tw, th = txt:get_pixel_size ()

	ctx:move_to ((w-tw)/2, h/2-th/2)
	txt:show_in_cairo_context (ctx)

	local label=""
	if line_count > 3 and line_count < 9 and w > 80 then label="ctrl " end
	-- write text, top left
	txt:set_text (string.format ("%s%s",label,controllable_value));
	-- tw, th = txt:get_pixel_size ()
	ctx:move_to (0+padding,0+padding)
	txt:show_in_cairo_context (ctx)
--[[
	label=""
	if line_count > 3 and line_count < 9 then label="seg " end
	-- write text, top right
	txt:set_text (string.format ("%s%d",label,42)); --
	tw, th = txt:get_pixel_size ()
	ctx:move_to (w-padding-tw,0+padding)
	txt:show_in_cairo_context (ctx)
--]]
	if line_count > 2 then
		local symbolizer=""
		if     last_value_direction==-2 then symbolizer="MIN"
		elseif last_value_direction==-1 then symbolizer="-"
		elseif last_value_direction== 2 then symbolizer="MAX"
		elseif last_value_direction== 1 then symbolizer="+"
		end
--[[
		-- write text, bottom left
		txt:set_text (string.format ("%s",symbolizer));
		tw, th = txt:get_pixel_size ()
		ctx:move_to (0+padding,h-padding-th)
		txt:show_in_cairo_context (ctx)
--]]
		-- write text, bottom right
		txt:set_text (string.format ("%s",symbolizer));
		tw, th = txt:get_pixel_size ()
		ctx:move_to (w-padding-tw,h-padding-th)
		txt:show_in_cairo_context (ctx)
	end -- if line_count > 2

	return {w, h}
end -- render_inline()
-- EOF

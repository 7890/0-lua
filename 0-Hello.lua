ardour {
	["type"]    = "dsp",
	name        = "0-Hello",
	category    = "Example",
	license     = "MIT",
	author      = "Thomas Brand",
	description = [[Hello World]]
}

--[[
a totally useless plugin, trying out Ardour LUA inline display on a strip.

based on a-Pong / Ardour Lua Task Force
--]]

-- return possible i/o configurations
function dsp_ioconfig ()
	-- -1, -1 = any number of channels as long as input and output count matches
	return { [1] = { audio_in = -1, audio_out = -1}, }
end

-- control port(s)
function dsp_params ()
	return
	{
		{ ["type"] = "input", name = "StrikeThrough", min = 0, max = 1, default = 0, toggled = true },
		{ ["type"] = "input", name = "StrokeWidth", min = 0, max = 50, default = 10 },
		{ ["type"] = "input", name = "Transparency", min = 0, max = 1, default = .5 },
	}
end

function dsp_init (rate)
end

-- callback: process "n_samples" of audio
-- ins, outs are http://manual.ardour.org/lua-scripting/class_reference/#C:FloatArray
-- pointers to the audio buffers
function dsp_run (ins, outs, n_samples)
	local ctrl = CtrlPorts:array () -- get control port array (read/write)
	-- forward audio if processing is not in-place
	for c = 1,#outs do
		-- check if output and input buffers for this channel are identical
		-- http://manual.ardour.org/lua-scripting/class_reference/#C:FloatArray
		if not ins[c]:sameinstance (outs[c]) then
			-- fast (accelerated) copy
			-- http://manual.ardour.org/lua-scripting/class_reference/#ARDOUR:DSP
			ARDOUR.DSP.copy_vector (outs[c], ins[c], n_samples)
		end
	end

	-- force redraw 
	self:queue_draw ()
end

-------------------------------------------------------------------------------
--- inline display

local txt = nil -- cache font description (in GUI context)

function render_inline (ctx, w, max_h)
	local ctrl = CtrlPorts:array () -- control port array

	if (w > max_h) then
		h = max_h
	else
		h = w
	end

	-- prepare text rendering
	if not txt then
		-- allocate PangoLayout and set font
		--http://manual.ardour.org/lua-scripting/class_reference/#Cairo:PangoLayout
		txt = Cairo.PangoLayout (ctx, "Mono 10px")
	end

	-- ctx is-a http://manual.ardour.org/lua-scripting/class_reference/#Cairo:Context
	-- 2D vector graphics http://cairographics.org/

	-- clear background
	ctx:rectangle (0, 0, w, h)
	ctx:set_source_rgba (.2, .2, .2, 1.0)
	ctx:fill ()

	-- create inner background
	ctx:rectangle (5, 5, w-10, h-10)
	ctx:set_source_rgba (.0, .9, .0, 1.0)
	ctx:fill ()

	-- write text, centered
	txt:set_text (string.format ("%s","hello world"));
	local tw, th = txt:get_pixel_size ()
	ctx:set_source_rgba (0, 0, 0, 1.0)
	ctx:move_to ((w-tw)/2, h/2-th)
	txt:show_in_cairo_context (ctx)

	-- overlay transparent rectangle
	ctx:rectangle (10, 10, w-20, h-20)
	ctx:set_source_rgba (.0, .0, .9, 0.1)
	ctx:fill ()

	-- ctrl array starts at number 1
	if (ctrl[1] > 0) then
		-- prepare line and dot rendering
		ctx:set_line_cap (Cairo.LineCap.Round)
		ctx:set_line_width (ctrl[2])
		ctx:set_source_rgba (.9, .0, .0, ctrl[3])

		-- strike through test
		ctx:move_to(0,0)
		ctx:line_to(w,h)
		ctx:stroke()
		ctx:move_to(0,h)
		ctx:line_to(w,0)
		ctx:stroke()
	end
	return {w, h}
end --render_inline()

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
--]]

local steps_per_rotation=32
local padding=4

local M_PI=3.14159265359

-- return possible i/o configurations
function dsp_ioconfig ()
	-- -1, -1 = any number of channels as long as input and output count matches
	return { [1] = { audio_in = -1, audio_out = -1}, }
end

-- control port(s)
function dsp_params ()
	return
	{
		{ ["type"] = "input", name = "RotationStepNumber", min = 0, max = steps_per_rotation, default = 0 },
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
	local rotation_32_step=math.floor(ctrl[1])

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

	local full_turn=2 * M_PI
	local rotation_32_step_rad=(math.floor(rotation_32_step) / steps_per_rotation)

	-- knob "3D" background
--	ctx:set_source_rgba (.0, .0, .0, 0.9)
--	ctx:arc(0+w/2, 4+h/2, h/3, 0, full_turn)
--	ctx:fill ()

	-- knob background
	ctx:set_source_rgba (.5, .9, .5, 1.0)
	ctx:arc(w/2, h/2, h/3, 0.0, full_turn)
	ctx:fill ()

	-- knob inner
	ctx:set_source_rgba (.1, .1, .1, 1.0)
	ctx:arc(w/2, h/2, 0.9*h/3, 0, full_turn)
	ctx:fill ()

	-- directed cut, default north
	local ang1=(-0.25 * M_PI) + rotation_32_step_rad * full_turn
	local ang2=( 1.25 * M_PI) + rotation_32_step_rad * full_turn

	ctx:set_source_rgba (.4, .9, .4, 1.0)
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

	-- write text, centered
	txt:set_text (string.format ("%.0f",rotation_32_step));
	local tw, th = txt:get_pixel_size ()
	ctx:set_source_rgba (0.9, 0.9, 0.9, 1.0)

	ctx:move_to ((w-tw)/2, h/2-th/2)
	txt:show_in_cairo_context (ctx)

	-- write text, top left
	txt:set_text (string.format ("%s","foo"));
	-- tw, th = txt:get_pixel_size ()
	ctx:move_to (0+padding,0+padding)
	txt:show_in_cairo_context (ctx)

	-- write text, top right
	txt:set_text (string.format ("%s","bar"));
	tw, th = txt:get_pixel_size ()
	ctx:move_to (w-padding-tw,0+padding)
	txt:show_in_cairo_context (ctx)

	-- write text, bottom left
	txt:set_text (string.format ("%s","A"));
	tw, th = txt:get_pixel_size ()
	ctx:move_to (0+padding,h-padding-th)
	txt:show_in_cairo_context (ctx)

	-- write text, bottom right
	txt:set_text (string.format ("%s","B"));
	tw, th = txt:get_pixel_size ()
	ctx:move_to (w-padding-tw,h-padding-th)
	txt:show_in_cairo_context (ctx)

	return {w, h}
end --render_inline()

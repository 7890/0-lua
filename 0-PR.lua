ardour {
	["type"]    = "dsp",
	name        = "0-PR",
	category    = "Example",
	license     = "MIT",
	author      = "Thomas Brand",
	description = [[Draw Piano Roll]]
}

--[[
draw piano roll

based on 0-Hello
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
		{ ["type"] = "input", name = "ShowKeyboard", min = 0, max = 1, default = 1, toggled = true }, --1
		{ ["type"] = "input", name = "WhiteKeyHeight", min = 15, max = 100, default = 40 }, --2
		{ ["type"] = "input", name = "WhiteKeyCount", min = 1, max = 127, default = 7, integer = true }, --3
		{ ["type"] = "input", name = "FirstKeyC", min = -1, max = 9, default = 5, integer = true }, --4
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

	local pr_on=ctrl[1] -- show / hide pr
	local k_count=ctrl[3] -- white key count (i.e. 7 (+5 black)  == one octave)
	local k_w=w/k_count -- white key width
	local k_h=ctrl[2] -- white key height
	local k_x=0 -- horizontal drawing start position 
	local k_y=h-k_h -- vertical drawing start positon, place keyboard at bottom
	local k_first_c=ctrl[4] -- the first key is a c, from -1 ... 9

	-- prepare text rendering
	if not txt then
		-- allocate PangoLayout and set font
		--http://manual.ardour.org/lua-scripting/class_reference/#Cairo:PangoLayout
		txt = Cairo.PangoLayout (ctx, "Mono 8px")
	end

	-- ctx is-a http://manual.ardour.org/lua-scripting/class_reference/#Cairo:Context
	-- 2D vector graphics http://cairographics.org/

	-- clear background
	ctx:rectangle (0, 0, w, h)
	ctx:set_source_rgba (.2, .2, .2, 1.0)
	ctx:fill ()

	-- ctrl array starts at number 1
	if (pr_on > 0) then
		-- prepare line and dot rendering
		ctx:set_line_cap (Cairo.LineCap.Round)
		ctx:set_line_width (1.0)

		--draw key roll background
		ctx:set_source_rgba (.9, .9, .9, 1.0)
		ctx:rectangle (k_x,k_y,k_count*k_w,k_h)
		ctx:fill ()

		-- draw keys
		for i = 1, k_count do
			k_x = (i-1) * k_w -- advance horizontal pos

			-- draw white keys border
			ctx:set_source_rgba (.1, .1, .1, 1.0)
			ctx:rectangle (k_x,k_y,k_w,k_h)
			ctx:stroke ()

			if i % 7 == 2 or i % 7 == 6 then -- black keys: place full middle of white, 2, 6
				ctx:set_source_rgba (.0, .0, .0, 1.0)
				ctx:rectangle (k_x- 3*k_w/8  , k_y, 3*k_w/4, 2*k_h/3)
				ctx:fill ()
			elseif i % 7 == 3 or (i > 0 and i % 7 == 0) then -- black keys: place slightly right, 3, 7
				ctx:set_source_rgba (.0, .0, .0, 1.0)
				ctx:rectangle (k_x- 2*k_w/8  , k_y, 3*k_w/4, 2*k_h/3)
				ctx:fill ()
			elseif i % 7 == 5 then -- black keys: place slightly left, 5
				ctx:set_source_rgba (.0, .0, .0, 1.0)
				ctx:rectangle (k_x- 4*k_w/8  , k_y, 3*k_w/4, 2*k_h/3)
				ctx:fill ()
			end -- if black key

			if i % 7 == 1 and k_count <15 then --mark c, only if not more than 2 octaves
				local c_x=k_first_c
				if i> 7 then c_x=k_first_c+1 end
				ctx:set_source_rgba (.1, .1, .1, 1.0)
				txt:set_text (string.format ("%d", c_x)) --write c number on key
				local tw, th = txt:get_pixel_size ()
				ctx:move_to (k_x+0.5,h-th-5)
				txt:show_in_cairo_context (ctx)
			end -- if c key
		end -- for k_count
	end -- if pr_on
	return {w, h}
end -- render_inline()
-- EOF

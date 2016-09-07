ardour {
	["type"]    = "dsp",
	name        = "0-PR",
	category    = "Example",
	license     = "MIT",
	author      = "Thomas Brand",
	description = [[Draw Piano Roll]]
}

-------------------------------------------------------------------------------
--[[
draw piano roll

based on 0-Hello

                      1 1 1
 1  2 3 4 5  6  7 8 9 0 1 2
    1   2       3   4   5
   |x| |x|     |x| |x| |x|
|   |   |   |   |   |   |   |
------------------------------
 1   2   3   4   5   6   7

0   1   2   3   4   5   6
*   *
k_w k_w

black keys width: 3*k_w/4

black keys offset to left

1, 4: 3 * k_w/8   (middle)

2, 5:     k_w/4 (slightly right)

3:        k_w/2 (slightly left)

draw white:
|   |   |
       <.
    |-->|
draw black:
|   |
   <.
  |-->|

--]]

-- return possible i/o configurations
-------------------------------------------------------------------------------
function dsp_ioconfig ()
	-- -1, -1 = any number of channels as long as input and output count matches
	return { [1] = { audio_in = -1, audio_out = -1}, }
end

-- control port(s)
-------------------------------------------------------------------------------
function dsp_params ()
	return
	{
		{ ["type"] = "input", name = "ShowKeyboard", min = 0, max = 1, default = 1, toggled = true }, --1
		{ ["type"] = "input", name = "WhiteKeyHeight", min = 15, max = 100, default = 40 }, --2
		{ ["type"] = "input", name = "WhiteKeyCount", min = 1, max = 127, default = 7, integer = true }, --3
		{ ["type"] = "input", name = "FirstKeyC", min = -1, max = 9, default = 5, integer = true }, --4
	}
end -- dsp_params()

-------------------------------------------------------------------------------
function dsp_init (rate)
	print ("'0-PR.lua' initialized (dsp_init).")
end

-- get total number of invovled keys, for a given white key count, starting a C
-------------------------------------------------------------------------------
function get_black_and_white_key_count (white_key_count)
	local octaves=math.floor(white_key_count / 7)
	local black_keys=octaves*5
	local remain=white_key_count % 7
	if remain == 0 then
		return white_key_count+black_keys
	elseif remain == 1 then
		return white_key_count+black_keys
	elseif remain == 2 then
		return white_key_count+black_keys+1
	elseif remain == 3 then
		return white_key_count+black_keys+2
	elseif remain == 4 then
		return white_key_count+black_keys+2
	elseif remain == 5 then
		return white_key_count+black_keys+3
	elseif remain == 6 then
		return white_key_count+black_keys+4
	end
end -- get_black_and_white_key_count()

-------------------------------------------------------------------------------
function get_offset_from_c (current_key, key_width)
	local octaves=math.floor (current_key / 12)
	local offset_base=octaves * 7 * key_width

	-- white keys
	if     current_key % 12 == 0 then 
		return offset_base  + 0 * key_width
	elseif current_key % 12 == 1 then
		return offset_base  + 1 * key_width
	elseif current_key % 12 == 3 then
		return offset_base  + 2 * key_width
	elseif current_key % 12 == 5 then
		return offset_base  + 3 * key_width
	elseif current_key % 12 == 6 then
		return offset_base  + 4 * key_width
	elseif current_key % 12 == 8 then
		return offset_base  + 5 * key_width
	elseif current_key % 12 == 10 then
		return offset_base  + 6 * key_width

	-- black keys
	elseif current_key % 12 == 2 then
		return offset_base  + 1 * key_width - 3 * key_width/8
	elseif current_key % 12 == 4 then
		return offset_base  + 2 * key_width -     key_width/4
	elseif current_key % 12 == 7 then
		return offset_base  + 4 * key_width -     key_width/2
	elseif current_key % 12 == 9 then
		return offset_base  + 5 * key_width - 3 * key_width/8
	elseif current_key % 12 == 11 then
		return offset_base  + 6 * key_width -     key_width/4
	end
end -- get_offset_from_c()

-------------------------------------------------------------------------------
function is_white_key_from_c (current_key)
	if     current_key % 12 == 2 then return 0 --false
	elseif current_key % 12 == 4 then return 0
	elseif current_key % 12 == 7 then return 0
	elseif current_key % 12 == 9 then return 0
	elseif current_key % 12 == 11 then return 0
	else return 1 --true
	end
end

-- callback: process "n_samples" of audio
-- ins, outs are http://manual.ardour.org/lua-scripting/class_reference/#C:FloatArray
-- pointers to the audio buffers
-------------------------------------------------------------------------------
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
	-- request redraw
	self:queue_draw ()
end -- dsp_run()

local txt = nil -- cache font description (in GUI context)
-------------------------------------------------------------------------------
function render_inline (ctx, w, max_h)
	local ctrl = CtrlPorts:array () -- control port array

	if (w > max_h) then
		h = max_h
	else
		h = w
	end

	local pr_on=ctrl[1] -- show / hide pr
	local k_count=math.floor(ctrl[3]) -- white key count (i.e. 7 (+5 black) == one octave)
	local k_w=w/k_count -- white key width
	local k_h=ctrl[2] -- white key height
	local k_x=0 -- horizontal drawing start position 
	local k_y=h-k_h -- vertical drawing start positon, place keyboard at bottom
	local k_first_c=math.floor(ctrl[4]) -- the first key is a c, from -1 ... 9
	local total_key_count=get_black_and_white_key_count(k_count)

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

		-- draw white keys
		for i = 1, total_key_count do
			if min_note_number  +  i > 128 then break end
			k_x = get_offset_from_c(i, k_w)
			if is_white_key_from_c (i) == 1 then
				-- draw white keys border
				ctx:set_source_rgba (.1, .1, .1, 1.0)
				ctx:rectangle (k_x-k_w, k_y, k_w, k_h)
				ctx:stroke ()
				-- print ("i " .. i .. " k_x " .. k_x .. " white")

				-- print octave number on c key
				if i % 12 == 1 and total_key_count < 25 then
					local c_x=k_first_c
					if i > 12 then c_x=k_first_c+1 end
					ctx:set_source_rgba (.1, .1, .1, 1.0)
					txt:set_text (string.format ("%d", c_x)) --write c number on key
					local tw, th = txt:get_pixel_size ()
					ctx:move_to (k_x-k_w+0.5,h-th-5)
					txt:show_in_cairo_context (ctx)
				end
			end
		end -- for total_key_count

		-- draw over black keys
		for i = 1, total_key_count do
			if min_note_number  +  i > 128 then break end
			k_x = get_offset_from_c(i, k_w)
			if is_white_key_from_c (i) == 0 then
				ctx:set_source_rgba (.0, .0, .0, 1.0)
				ctx:rectangle (k_x, k_y, 3*k_w/4, 2*k_h/3)
				ctx:fill ()
				-- print ("i " .. i .. " k_x " .. k_x .. " black")
			end
		end -- for total_key_count
	end -- if pr_on
	return {w, h}
end -- render_inline()
-- EOF

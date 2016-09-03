ardour {
	["type"]    = "dsp",
	name        = "0-MKB",
	category    = "Visualization",
	license     = "GPLv2",
	author      = "Thomas Brand",
	description = [[Visualize MIDI note ON and OFF events along with the velocity]]
}

--[[
show midi note on/off events as bars. height of bar shows velocity.

based on 0-PR and a-MIDI Monitor / Ardour Team
--]]

function dsp_ioconfig ()
	return { { midi_in = 1, midi_out = 1, audio_in = -1, audio_out = -1}, }
end

function dsp_params ()
	return
	{
		{ ["type"] = "input",
			name = "ShowKeyboard",
			doc = "Show or hide piano roll",
			min = 0, max = 1, default = 1, toggled = true }, --1
		{ ["type"] = "input",
			name = "WhiteKeyHeight",
			doc = "Set height of white keys",
			min = 10, max = 100, default = 40 }, --2
		{ ["type"] = "input",
			name = "WhiteKeyCount",
			doc = "Set visible number of white keys starting from c",
			min = 1, max = 70, default = 7, integer = true }, --3
		{ ["type"] = "input",
			name = "FirstKeyC",
			doc = "Number of first visible c. -1 ... 9",
			min = -1, max = 9, default = 5, integer = true }, --4
		{ ["type"] = "input",
			name = "ShowNoteStatus", --5
			doc = "Show or hide note ON and OFF velocity bars",
			min = 0, max = 1, default = 1, toggled = true },
		{ ["type"] = "input",
			name = "DisplayHeight", --6
			doc = "Rastered height of inline widget",
			min = 1, max = 11, default = 11, integer = true },
		{ ["type"] = "input",
			name = "ShowNoteHighlight", --7
			doc = "Highlight keys with a dot when note is on", 
			min = 0, max = 1, default = 1, toggled = true },
	}
end -- dsp_params()

function dsp_init (rate)
	-- create a shmem space to hold status of 128 keys
	self:shmem():allocate(128) ---

	-- remember which notes were on (and store velocity, 0-127), init to off (-1)
	local note_on_buffer = self:shmem():to_int(0):array()
	for i = 1, 128 do
		note_on_buffer[i] = -1
	end
end

function dsp_runmap (bufs, in_map, out_map, n_samples, offset)
	local note_on_buffer = self:shmem():to_int(0):array()

	-- passthrough all data
	ARDOUR.DSP.process_map (bufs, in_map, out_map, n_samples, offset, ARDOUR.DataType ("audio"))
	ARDOUR.DSP.process_map (bufs, in_map, out_map, n_samples, offset, ARDOUR.DataType ("midi"))

	-- then fill the event buffer
	local ib = in_map:get (ARDOUR.DataType ("midi"), 0) -- index of 1st midi input

	if ib ~= ARDOUR.ChanMapping.Invalid then
		local events = bufs:get_midi (ib):table () -- copy event list into a lua table

		-- iterate over all MIDI events
		for _, e in pairs (events) do
			-- print (e:channel (), e:time (), e:size (), e:buffer():array()[1], e:buffer():get_table(e:size ())[1])
			local ev = e:buffer():array()

			-- test if event is note on or off, remember in note_on_buffer
			if ev[1] >> 4 == 8 then --OFF
				note_on_buffer[ev[2] + 1]=-1
			elseif ev[1] >> 4 == 9 then --ON
				note_on_buffer[ev[2] + 1]=ev[3]
			end
		end
	end
---	self:shmem():atomic_set_int(0, pos)

	self:queue_draw ()
end -- dsp_runmap()

local txt = nil -- a pango context

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
end --get_offset_from_c

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

-------------------------------------------------------------------------------
function render_inline (ctx, w, max_h)
	local ctrl = CtrlPorts:array ()
	local ns_on=ctrl[5] -- show / hide note status
	local line_count = math.floor(ctrl[6])
	local line_height = 10

	local note_on_buffer = self:shmem():to_int(0):array()

	if (w > max_h) then
		h = max_h
	else
		h = line_count * line_height

	end

	local pr_on=ctrl[1] -- show / hide pr
	local kh_on=ctrl[7] -- highlight keys when note is on
	local k_count=math.floor(ctrl[3]) -- white key count (i.e. 7 (+5 black)  == one octave)
	local k_w=w/k_count -- white key width
	local k_h=ctrl[2] -- white key height
	local k_x=0 -- horizontal drawing start position 
	local k_y=h-k_h -- vertical drawing start positon, place keyboard at bottom
	local k_first_c=math.floor(ctrl[4]) -- the first key is a c, from -1 ... 9
	local total_key_count=get_black_and_white_key_count(k_count)
	local current_first_c=k_first_c
	local min_note_number=(current_first_c+1)*12 --as received from ardour. 0 min

	-- limit key roll height when total widget height is small
	if k_h > h then k_h=h k_y=h-k_h end

	local M_PI=3.14159265359

	-- prepare text rendering
	if not txt then
		-- allocate PangoLayout and set font
		--http://manual.ardour.org/lua-scripting/class_reference/#Cairo:PangoLayout
		txt = Cairo.PangoLayout (ctx, "Mono 8px")
	end

	-- clear background
	ctx:rectangle (0, 0, w, h)
	ctx:set_source_rgba (.2, .2, .2, 1.0)
	ctx:fill ()

	-- prepare line and dot rendering
	--- ctx:set_line_cap (Cairo.LineCap.Round)
	ctx:set_line_width (1.0)

	if pr_on > 0 then
		--draw key roll background
		ctx:set_source_rgba (.9, .9, .9, 1.0)
		ctx:rectangle (k_x,k_y,k_count*k_w,k_h)
		ctx:fill ()

		-- draw white keys
		for i = 1, total_key_count do
			if min_note_number  +  i > 128 then break end

			k_x = get_offset_from_c(i, k_w)
			local velo_height = (h - k_h) * note_on_buffer[min_note_number  +  i] / 128

			if is_white_key_from_c (i) == 1 then
				-- draw white keys border
				ctx:set_source_rgba (.1, .1, .1, 1.0)
				ctx:rectangle (k_x-k_w, k_y, k_w, k_h)
				ctx:stroke ()
				-- print ("i " .. i .. " k_x " .. k_x .. " white")
				-- draw dot on key if note on
				if (kh_on == 1 and note_on_buffer[min_note_number  +  i]>=0) then
					ctx:set_source_rgba (.9, .1, .1, 1.0)
					ctx:arc(k_x-k_w/2, h-5, 0.25*k_w, 0.0, 2 * M_PI)
					ctx:fill()
				end
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
				-- draw dot on key if note on
				if (kh_on == 1 and note_on_buffer[min_note_number  +  i]>=0) then
					ctx:set_source_rgba (.1, .9, .1, 1.0)
					ctx:arc(k_x+3*k_w/8, k_y+5, 0.25*k_w, 0.0, 2 * M_PI)
					ctx:fill()
				end
			end
		end -- for total_key_count
	end -- if pr_on

	if ns_on > 0 then
		if pr_on <= 0 then k_h=0 k_y=h end

		-- draw white velocity bars
		for i = 1, total_key_count do
			if min_note_number  +  i > 128 then break end
			k_x = get_offset_from_c(i, k_w)
			local velo_height = (h - k_h) * note_on_buffer[min_note_number  +  i] / 128

			if is_white_key_from_c (i) == 1 then
				-- draw velocity bar
				if (note_on_buffer[min_note_number  +  i]>=0) then
					ctx:set_source_rgba (.9, .9, .9, 1.0)
					ctx:move_to(k_x-k_w/2, k_y-velo_height)
					ctx:rel_line_to (0, velo_height)
					ctx:stroke()
				end
			end
		end -- for total_key_count

		-- draw black velocity bars
		for i = 1, total_key_count do
			if min_note_number  +  i > 128 then break end
			k_x = get_offset_from_c(i, k_w)
			local velo_height = (h - k_h) * note_on_buffer[min_note_number  +  i] / 128

			if is_white_key_from_c (i) == 0 then
				-- draw velocity bar
				if (note_on_buffer[min_note_number  +  i]>=0) then
					ctx:set_source_rgba (.0, .0, .0, 1.0)
					ctx:move_to(k_x+3*k_w/8, k_y-velo_height)
					ctx:rel_line_to (0, velo_height)
					ctx:stroke()
				end
			end
		end -- for total_key_count
	end -- if ns_on

	return {w, h}
end

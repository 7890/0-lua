ardour {
	["type"]    = "dsp",
	name        = "0-TPI",
	category    = "Example",
	license     = "MIT",
	author      = "Thomas Brand",
	description = [[Transport information, showing time distance to several points on the timeline. Legend:  phd: Playhead. lst: Last Stop. len: Length. ses: Session Start. see: Session End. los: Loop Start. loe: Loop End. prv: Previous Marker. nxt: Next Marker.]]
}

--[[
show information about transport state
use table to pass along data
use inline method to show key/value pairs
use scalepoints to set format
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
			min = 2, max = 11, default = 11, integer = true },
		{ ["type"] = "input",
			name = "DisplayFormat", --2
			doc = "Show as frames (default) or seconds",
			min = 0, max = 1, default = 0, enum = true, scalepoints =
			{
				["Frames"] = 0,
				["Seconds"] = 1,
			}
		},
	}
end -- dsp_params()

-------------------------------------------------------------------------------
function dsp_init (rate)
	-- create a table of objects to share with the GUI
	local tbl = {}
	tbl['samplerate'] = 0
	tbl['playhead_pos'] = 0

	tbl['transport_rolling'] = 0
	tbl['transport_speed'] = 0
	tbl['last_transport_start_pos'] = 0
	tbl['prev_marker_pos'] = 0
	tbl['next_marker_pos'] = 0
	tbl['session_start_pos'] = 0
	tbl['session_end_pos'] = 0
	tbl['loop_start_pos'] = 0
	tbl['loop_end_pos'] = 0

--	tbl[''] = 0

	-- "self" is a special DSP variable referring
	-- to the plugin instance itself.
	--
	-- "table()" is-a http://manual.ardour.org/lua-scripting/class_reference/#ARDOUR.LuaTableRef
	-- which allows to store/retrieve lua-tables to share them other interpreters
	self:table ():set (tbl);
	print ("'0-TPI.lua' initialized (dsp_init).")
end

-------------------------------------------------------------------------------
function dsp_runmap (bufs, in_map, out_map, n_samples, offset)
	-- passthrough all data
	ARDOUR.DSP.process_map (bufs, in_map, out_map, n_samples, offset, ARDOUR.DataType ("audio"))
	ARDOUR.DSP.process_map (bufs, in_map, out_map, n_samples, offset, ARDOUR.DataType ("midi"))

	local tbl = self:table ():get () -- get shared memory table

	if Session:transport_rolling() == true then
		tbl['transport_rolling'] = 1
	else
		tbl['transport_rolling'] = 0
	end
	tbl['samplerate'] = Session:nominal_frame_rate ()
	tbl['playhead_pos'] = Session:transport_frame ()
	tbl['transport_speed'] = Session:transport_speed()
	tbl['last_transport_start_pos'] = Session:last_transport_start()
	tbl['prev_marker_pos'] = Session:locations():first_mark_before(tbl['playhead_pos'], false)
	tbl['next_marker_pos'] = Session:locations():first_mark_after(tbl['playhead_pos'], false)
	local session_range=Session:locations():session_range_location ()
	if session_range then
		tbl['session_start_pos'] = session_range:start()
		tbl['session_end_pos'] = session_range:_end()
	end
	local loop_range=Session:locations():auto_loop_location ()
	if loop_range then
		tbl['loop_start_pos'] = loop_range:start()
		tbl['loop_end_pos'] = loop_range:_end()
	end

	-- "write back"
	self:table ():set (tbl);

	-- request redraw 
	self:queue_draw ()
end -- dsp_runmap()

local txt = nil -- cache font description (in GUI context)

-------------------------------------------------------------------------------
function render_inline (ctx, w, max_h)
	-- ctx is-a http://manual.ardour.org/lua-scripting/class_reference/#Cairo:Context
	-- 2D vector graphics http://cairographics.org/

	local ctrl = CtrlPorts:array () -- control port array
	local tbl = self:table ():get () -- get shared memory table

	-- "inline" function
	-------------------------------------------------------------------------------
	function draw_key_value_line (line,key,value,autohide_key)
		ctx:set_source_rgba (.9, .9, .9, 1.0)

		if w < 100 and autohide_key==1 then key="" end
		txt:set_text (key)
		tw, th = txt:get_pixel_size ()
		ctx:move_to (0+padding,line*line_height+padding)
		txt:show_in_cairo_context (ctx)

		txt:set_text (value)
		tw, th = txt:get_pixel_size ()
		ctx:move_to (w-padding-tw,line*line_height+padding)
		txt:show_in_cairo_context (ctx)
	end
	-------------------------------------------------------------------------------
	function frames_to_seconds (frames)
		return frames / tbl['samplerate']
	end

	-------------------------------------------------------------------------------
	local line_count = math.floor (ctrl[1])
	local display_frames_as = math.floor (ctrl[2])

	if (w > max_h) then
		h = max_h
	else
		h = 2 * padding + line_count * line_height
	end

	-- prepare text rendering
	-- http://manual.ardour.org/lua-scripting/class_reference/#Cairo:PangoLayout
	if not txt then txt = Cairo.PangoLayout (ctx, "Mono 10px") end

	-- clear background
	ctx:rectangle (0, 0, w, h)
	ctx:set_source_rgba (.2, .2, .2, 1.0)
	ctx:fill ()

	local transport_text="Stopped"
	if w < 100 then transport_text="Stop" end
	if tbl['transport_rolling'] == 1 and w >= 100 then
		transport_text="Playing"
	elseif tbl['transport_rolling'] == 1 and w < 100 then
		transport_text="Play"
	end

	draw_key_value_line (0, "Transport", "", 0)
	draw_key_value_line (1, transport_text, string.format ("%.2f", tbl['transport_speed']), 0)

	if display_frames_as == 0 then
		draw_key_value_line (2, "phd", string.format ("%d", tbl['playhead_pos']), 1 )
		draw_key_value_line (3, "lst", string.format ("%d", tbl['last_transport_start_pos']), 1 )
		draw_key_value_line (4, "len", string.format ("%d", (tbl['playhead_pos'] - tbl['last_transport_start_pos'])), 1 )
		draw_key_value_line (5, "ses", string.format ("%d", (tbl['session_start_pos'] - tbl['playhead_pos'])), 1 )
		draw_key_value_line (6, "see", string.format ("%d", (tbl['session_end_pos'] - tbl['playhead_pos'])), 1 )
		draw_key_value_line (7, "los", string.format ("%d", (tbl['loop_start_pos'] - tbl['playhead_pos'])), 1 )
		draw_key_value_line (8, "loe", string.format ("%d", (tbl['loop_end_pos'] - tbl['playhead_pos'])), 1 )
		draw_key_value_line (9, "prv", string.format ("%d", (tbl['prev_marker_pos'] -tbl['playhead_pos'])), 1 )
		draw_key_value_line (10, "nxt", string.format ("%d", (tbl['next_marker_pos'] - tbl['playhead_pos'])), 1 )
	elseif display_frames_as == 1 then
		draw_key_value_line (2, "phd", string.format ("%.2f", frames_to_seconds(tbl['playhead_pos']) ), 1 )
		draw_key_value_line (3, "lst", string.format ("%.2f", frames_to_seconds(tbl['last_transport_start_pos'])), 1 )
		draw_key_value_line (4, "len", string.format ("%.2f", frames_to_seconds((tbl['playhead_pos'] - tbl['last_transport_start_pos']))), 1 )
		draw_key_value_line (5, "ses", string.format ("%.2f", frames_to_seconds((tbl['playhead_pos'] - tbl['session_start_pos']))), 1 )
		draw_key_value_line (6, "see", string.format ("%.2f", frames_to_seconds((tbl['playhead_pos'] - tbl['session_end_pos']))), 1 )
		draw_key_value_line (7, "los", string.format ("%.2f", frames_to_seconds((tbl['playhead_pos'] - tbl['loop_start_pos']))), 1 )
		draw_key_value_line (8, "loe", string.format ("%.2f", frames_to_seconds((tbl['playhead_pos'] - tbl['loop_end_pos']))), 1 )
		draw_key_value_line (9, "prv", string.format ("%.2f", frames_to_seconds((tbl['playhead_pos'] - tbl['prev_marker_pos']))), 1 )
		draw_key_value_line (10, "nxt", string.format ("%.2f", frames_to_seconds((tbl['playhead_pos'] - tbl['next_marker_pos']))), 1 )
	end

	return {w, h}
end -- render_inline()
-- EOF

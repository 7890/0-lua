ardour {
	["type"]    = "dsp",
	name        = "0-Template",
	category    = "Example",
	license     = "MIT",
	author      = "Thomas Brand",
	description = [[Skeleton for scripts]]
}

--[[
--]]

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
			min = 1, max = 11, default = 7, integer = true },
	}
end -- dsp_params()

-------------------------------------------------------------------------------
function dsp_init (rate)
	print ("'0-Template.lua' initialized (dsp_init).")
end -- dsp_init()

-------------------------------------------------------------------------------
function dsp_runmap (bufs, in_map, out_map, n_samples, offset)
	-- passthrough all data
	ARDOUR.DSP.process_map (bufs, in_map, out_map, n_samples, offset, ARDOUR.DataType ("audio"))
	ARDOUR.DSP.process_map (bufs, in_map, out_map, n_samples, offset, ARDOUR.DataType ("midi"))

	-- request redraw 
	self:queue_draw ()
end -- dsp_runmap()

local txt = nil -- cache font description (in GUI context)
-------------------------------------------------------------------------------
function render_inline (ctx, w, max_h)
	return {w, h}
end -- render_inline()
-- EOF

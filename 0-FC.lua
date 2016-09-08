ardour {
	["type"]    = "dsp",
	name        = "0-FC",
	category    = "Example",
	license     = "MIT",
	author      = "Thomas Brand",
	description = [[Fader Control]]
}

--[[
set gain control of a track. fade between min and max gain.
change is done in steps. one step is done per process cycle.
fade speeds depends on period size and samplerate (not time)!
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
			name = "TrackIndex", --1
			doc = "",
			min = 0, max = 8, default = 0, integer = true },
		{ ["type"] = "input",
			name = "MinGain", --2
			doc = "",
			min = 0, max = 1, default = 0 },
		{ ["type"] = "input",
			name = "MaxGain", --3
			doc = "",
			min = 0, max = 2, default = 1 },
		{ ["type"] = "input",
			name = "FadeSteps", --4
			doc = "",
			min = 1, max = 500, default = 64 },

		{ ["type"] = "input",
			name = "FadeAction", --5
			doc = "",
			min = -1, max = 1, default = 0, enum = true, scalepoints =
			{
				["Fade Out"] = -1,
				["(None)"] = 0,
				["Fade In"] = 1,
			}
		},
	}
end -- dsp_params()

-------------------------------------------------------------------------------
function dsp_init (rate)
	local tbl = {}
	tbl['samplerate'] = 0
	tbl['frames_since_start'] = 0
	tbl['track_index']=0
	tbl['fader_level']=0
	-- -1: fading out
	--  0: (no action)
	--  1: fading in
	tbl['fader_status']=0
	tbl['fader_min_gain']=0
	tbl['fader_max_gain']=0
	tbl['fade_steps']=0
	tbl['fade_steps_size']=0
	self:table ():set (tbl);
	print ("'0-FC.lua' initialized (dsp_init).")
end -- dsp_init()

-------------------------------------------------------------------------------
function dsp_runmap (bufs, in_map, out_map, n_samples, offset)
	-- passthrough all data
	ARDOUR.DSP.process_map (bufs, in_map, out_map, n_samples, offset, ARDOUR.DataType ("audio"))
	ARDOUR.DSP.process_map (bufs, in_map, out_map, n_samples, offset, ARDOUR.DataType ("midi"))

	local ctrl = CtrlPorts:array ()
	local tbl = self:table ():get ()

	tbl['samplerate'] = Session:nominal_frame_rate ()
	tbl['frames_since_start'] = tbl['frames_since_start'] + n_samples

	tbl['track_index']=math.floor(ctrl[1])
	tbl['fader_status']=math.floor(ctrl[5])

	tbl['fader_min_gain']=ctrl[2]
	tbl['fader_max_gain']=ctrl[3]

	tbl['fade_steps']=math.floor(ctrl[4])
	tbl['fade_steps_size']=1/tbl['fade_steps']

	local track = Session:get_remote_nth_route(tbl['track_index'])
	if track:isnil() then return end
	local ac = track:amp ():gain_control () -- ARDOUR:AutomationControl

	local level=ac:get_value()
	local fade_step_size=tbl['fade_steps_size']

	-- fade in or out or don't do anything at all
	if tbl['fader_status'] == -1 and not (tbl['fader_level'] == tbl['fader_min_gain']) then
		ac:set_value( math.max(tbl['fader_min_gain'],level - fade_step_size) ,PBD.GroupControlDisposition.NoGroup)
	elseif tbl['fader_status'] == 1 and not (tbl['fader_level'] == tbl['fader_max_gain']) then
		ac:set_value( math.min(tbl['fader_max_gain'],level + fade_step_size),PBD.GroupControlDisposition.NoGroup)
	end

	-- possibly updated fader_level
	tbl['fader_level'] = level

	self:table ():set (tbl);

	-- request redraw 
	self:queue_draw ()
end -- dsp_runmap()

local txt = nil -- cache font description (in GUI context)
-------------------------------------------------------------------------------
function render_inline (ctx, w, max_h)
--	local ctrl = CtrlPorts:array ()
--	local tbl = self:table ():get ()
	h=0
	return {w, h}
end -- render_inline()
-- EOF

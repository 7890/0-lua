ardour {
	["type"]    = "dsp",
	name        = "0-SD",
	category    = "Example",
	license     = "MIT",
	author      = "Thomas Brand",
	description = [[Silence Detector]]
}

--[[
read signal peak levels and sort them under or over a given threshold

x <  treshold:  under
x >= threshold: over

ConfirmDelayUnder: how long value needs to be below threshold to trigger confirmed UNDER status
ConfirmDelayOver: how long value needs to be over threshold to trigger confirmed OVER status

based on voice_activate.lua / Ardour Lua Task Force
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
		{ ["type"] = "input", name = "Threshold", min = -80, max = 6, default = -50, doc = "dBFS" }, --1
		{ ["type"] = "input", name = "ConfirmDelayUnder", min = 0, max = 60, default = 2, doc = "s" }, --2
		{ ["type"] = "input", name = "ConfirmDelayOver", min = 0, max = 60, default = 2, doc = "s" }, --3

		{ ["type"] = "input", name = "LockOutputStatus", min = 0, max = 2, default = 2,
			doc = "Set operation mode of StatusConfirmed output port.",
			enum = true, scalepoints =
			{
				["Lock to 0"] = 0,
				["Lock to 1"] = 1,
				["Evaluate"] = 2,
			}
		}, --4
		{ ["type"] = "output", name = "Status", min = 0, max = 1, 
			doc="Indicate current under/over status", enum = true,
			scalepoints=
			{
				["under"] = 0,
				["over"] = 1,
			}
		}, --5
		{ ["type"] = "output", name = "StatusConfirmed", min = 0, max = 1,
			doc="Indicate delayed/confirmed under/over status", enum = true,
			scalepoints=
			{
				["under"] = 0,
				["over"] = 1,
			}
		}, --6
	}
end -- dsp_params()

-------------------------------------------------------------------------------
function dsp_init (rate)
	local tbl = {}
	tbl['n_channels']=0
	tbl['samplerate'] = 0
	tbl['frames_since_start'] = 0
	tbl['under_range_count']=0
	tbl['over_range_count']=0
	tbl['last_change_frames']=0
	tbl['last_change_confirmed_frames']=0
	self:table ():set (tbl);
	print ("'0-SD.lua' initialized (dsp_init).")
end -- dsp_init()

-------------------------------------------------------------------------------
function dsp_configure (ins, outs)
	local tbl = self:table ():get ()
	tbl['n_channels'] = ins:n_audio()
	self:table ():set (tbl);
end

-------------------------------------------------------------------------------
function dsp_runmap (bufs, in_map, out_map, n_samples, offset)
	-- passthrough all data
	ARDOUR.DSP.process_map (bufs, in_map, out_map, n_samples, offset, ARDOUR.DataType ("audio"))
	ARDOUR.DSP.process_map (bufs, in_map, out_map, n_samples, offset, ARDOUR.DataType ("midi"))

	local ctrl = CtrlPorts:array()
	local tbl = self:table ():get ()

	tbl['samplerate'] = Session:nominal_frame_rate ()
	tbl['frames_since_start'] = tbl['frames_since_start'] + n_samples

	-- startup condition
	if tbl['frames_since_start'] == n_samples then
		ctrl[5]=0
		ctrl[6]=0
		tbl['last_change_frames']=tbl['frames_since_start']
		tbl['last_change_confirmed_frames']=tbl['frames_since_start']
		self:table ():set (tbl)
	end

	if not(math.floor(ctrl[4]) == 2) then
		ctrl[6]=ctrl[4] --locked to 0 or 1
		self:queue_draw ()
		return --already done
	end

	local threshold = 10 ^ (.05 * ctrl[1]) -- dBFS to coefficient
	local n_channels=tbl['n_channels']

	for c = 1,n_channels do
		local b = in_map:get(ARDOUR.DataType("audio"), c - 1) -- get id of audio-buffer for the given channel
		if b ~= ARDOUR.ChanMapping.Invalid then -- check if channel is mapped
			local a = ARDOUR.DSP.compute_peak(bufs:get_audio(b):data(offset), n_samples, 0) -- compute digital peak

			if a < threshold then
				tbl['under_range_count']=tbl['under_range_count']+1
				if not(ctrl[5] == 0) then --if previous cycle wasn't the same
					tbl['last_change_frames']=tbl['frames_since_start'] --reset timer
					ctrl[5]=0
				end

				if not (ctrl[6] == 0) and tbl['frames_since_start'] - tbl['last_change_frames'] > ctrl[2] * tbl['samplerate'] then
					ctrl[6] = 0
					tbl['last_change_confirmed_frames']=tbl['frames_since_start']
					print("under TRIGGER " .. tbl['frames_since_start'] .. " " .. tbl['last_change_frames'])
				end

			else
				tbl['over_range_count']=tbl['over_range_count']+1
				if not(ctrl[5] == 1) then
					tbl['last_change_frames']=tbl['frames_since_start']
					ctrl[5]=1
				end

				if not (ctrl[6] == 1) and tbl['frames_since_start'] - tbl['last_change_frames'] > ctrl[3] * tbl['samplerate'] then
					ctrl[6] = 1
					tbl['last_change_confirmed_frames']=tbl['frames_since_start']
					print("over TRIGGER " .. tbl['frames_since_start'] .. " " .. tbl['last_change_frames'])
				end
			end
		end -- valid channel mapping
	end -- for channels

	self:table ():set (tbl)
	-- request redraw 
	self:queue_draw ()
end -- dsp_runmap()

local txt = nil -- cache font description (in GUI context)
-------------------------------------------------------------------------------
function render_inline (ctx, w, max_h)
	h=0
	return {w, h}
end -- render_inline()
-- EOF

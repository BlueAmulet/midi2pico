#!/usr/bin/env lua
local parse = require("argparse")

local args, opts = parse(...)

local function print(...)
	local args=table.pack(...)
	for i=1, args.n do
		args[i]=tostring(args[i])
	end
	io.stderr:write(table.concat(args, "\t").."\n")
end

function math.round(n)
	return math.floor(n+0.5)
end

if #args < 1 then
	print([[
Usage: ]] .. (arg and arg[0] or "midi2pico") .. [[ midi-file [p8-data]

Options:
	--maxvol  Maximum volume (0-7, 5)
	--drumvol Drum volume, (0-7, 2)
	--chvol   Per channel volume (Comma separated, ch:vol format)
	--div     Time division slices (Auto)
	--level   Logging level
	--speed   Music speed (0-255)
	--mute    Mute channels (Comma separated, 0=All)
	--mutet   Mute tracks (Comma separated)
	--mode    Arragement mode (blob/channel/track)
	--shift   Pitch shift, instruments (0)
	--dshift  Pitch shift, drums (0)

	All options above take the form: --name=value

	--no2ndpass Skip second corrective pass
	--nopwheel  Ignore pitch wheel data
	--novol     Ignore volume data
	--notrunc   Keep going despite no more sfx

	All options above take the form: --name
]])
	return
end

local function arg2num(name)
	val = tonumber(tostring(opts[name]), 10)
	if not val then
		error("Invalid value for option '" .. name .. "': " .. tostring(opts[name]), 0)
	end
	return val
end

-- Instrument to PICO-8 Map
local picoinstr={}
for i=0, 127 do
	picoinstr[i]={1, 0, 0, 5}
end
picoinstr[71]={5, 4, 0, 5} -- Clarinet
picoinstr[81]={2, 0, 0, 0} -- SawLd

-- Drums to PICO-8 Map
local picodrum={}
for i=35, 82 do
	picodrum[i]={6, 0, 0, 5}
end
-- TODO: I'm getting weird instrument numbers for drums.
for i=0, 127 do
	picodrum[i]={6, 0, 0, 5}
end

-- Allowed Channels
local chlisten={}
for i=0, 15 do
	chlisten[i]=true
end

-- Allowed Tracks
trlisten_mt={__index=function(t,k)
	t[k]=t.default
	return t.default
end}
local trlisten=setmetatable({default=true},trlisten_mt)

-- Drum Channels
local drumch={}
for i=0, 15 do
	drumch[i]=false
end
drumch[9]=true

-- Per Channel Volume
local chvol={}
for i=0, 15 do
	chvol[i]=5
end

local maxlevel = math.huge
if opts.level then
	maxlevel = arg2num("level")
end

local function log(level, ...)
	if level <= maxlevel then
		print(...)
	end
end

local function logf(level, ...)
	if level <= maxlevel then
		print(string.format(...))
	end
end

if opts.maxvol then
	local maxvol = tonumber(tostring(opts.maxvol))
	if not maxvol then
		error("Invalid value for option 'maxvol': " .. tostring(opts.maxvol), 0)
	elseif maxvol < 0 or maxvol > 7 then
		error("Invalid range for option 'maxvol': " .. maxvol, 0)
	end
	for i=0, 15 do
		chvol[i]=maxvol
	end
end

local drumvol = 2
if opts.drumvol then
	drumvol = tonumber(tostring(opts.drumvol))
	if not drumvol then
		error("Invalid value for option 'drumvol': " .. tostring(opts.drumvol), 0)
	elseif drumvol < 0 or drumvol > 7 then
		error("Invalid range for option 'drumvol': " .. drumvol, 0)
	end
end

if opts.mute then
	for part in (opts.mute .. ","):gmatch("(.-),") do
		local chmn=tonumber(part,10)
		if chmn == nil then
			error("Invalid channel for option 'mute': " .. part, 0)
		elseif chmn < -16 or chmn > 16 then
			error("Invalid channel for option 'mute': " .. math.abs(chmn), 0)
		elseif chmn == 0 then
			local all=(part:sub(1, 1) == "-")
			for i=0,15 do
				chlisten[i]=all
			end
		else
			chlisten[math.abs(chmn)-1]=chmn < 0
		end
	end
end

if opts.mutet then
	for part in (opts.mutet .. ","):gmatch("(.-),") do
		local trmn=tonumber(part,10)
		if trmn == nil then
			error("Invalid track for option 'mutet': " .. part, 0)
		elseif trmn < -65536 or trmn > 65536 then
			error("Invalid track for option 'mutet': " .. math.abs(trmn), 0)
		elseif trmn == 0 then
			trlisten=setmetatable({default=(part:sub(1, 1) == "-")},trlisten_mt)
		else
			trlisten[math.abs(trmn)-1]=trmn < 0
		end
	end
end

local speed
if opts.speed then
	speed = tonumber(tostring(opts.speed))
	if not speed then
		error("Invalid value for option 'speed': " .. tostring(opts.speed), 0)
	elseif speed < 0 or speed > 255 then
		error("Invalid range for option 'speed': " .. speed, 0)
	end
end

if opts.chvol then
	for part in (opts.chvol .. ","):gmatch("(.-),") do
		local ch, vol=part:match("(.*):(.+)")
		ch=tonumber(ch,10)
		vol=tonumber(vol,10)
		if ch == nil or vol == nil then
			error("Invalid value for option 'chvol': " .. part, 0)
		elseif ch < 1 or ch > 16 then
			error("Invalid channel for option 'chvol': " .. ch, 0)
		elseif vol < 0 or vol > 7 then
			error("Invalid volume for option 'chvol': " .. vol, 0)
		else
			chvol[ch-1]=vol
		end
	end
end

local amodes={
blob=true,
channel=true,
track=true
}
local mode="channel"
if opts.mode then
	if not amodes[opts.mode] then
		error("Invalid value for option 'mode': " .. opts.mode, 0)
	end
	mode=opts.mode
end

local skip=0
if opts.skip then
	skip=arg2num("skip")
end

local div
if opts.div then
	div=arg2num("div")
end

local shift=0
if opts.shift then
	shift=arg2num("shift")
end

local dshift=0
if opts.dshift then
	dshift=arg2num("dshift")
end

local text_events={
text_event=true,
copyright_text_event=true,
track_name=true,
instrument_name=true,
lyric=true,
marker=true,
cue_point=true,
text_event_08=true,
text_event_09=true,
text_event_0a=true,
text_event_0b=true,
text_event_0c=true,
text_event_0d=true,
text_event_0e=true,
text_event_0f=true,
}
local function score2note(score)
	local note = {score[1]}
	local trackpos={}
	local nscore = #score
	for i = 2, nscore do
		trackpos[i]=1
	end
	while true do
		local ltime, tpos=math.huge
		for i = 2, nscore do
			local event = score[i][trackpos[i]]
			if event then
				local ttime = event[2]
				if ttime < ltime then
					ltime, tpos = ttime, i
				end
			end
		end
		if not tpos then break end
		local event = score[tpos][trackpos[tpos]]
		score[tpos][trackpos[tpos]] = nil
		trackpos[tpos] = trackpos[tpos] + 1
		table.insert(event, 3, tpos-2)
		-- Merge text events into one event type
		local kind=event[1]
		if text_events[kind] then
			kind=kind:gsub("_event",""):gsub("_text","")
			table.insert(event, 4, kind)
			event[1]="text"
		end
		note[#note+1] = event
	end
	return note
end

log(1, "Info: Loading and parsing midi file ...")
local file, err=io.open(args[1], "rb")
if not file then
	print(err)
	os.exit(1)
end
local data=file:read("*a")
file:close()

local midi = require("MIDI")

local mididata = score2note(midi.midi2score(data))

local function gcd(m, n)
	while m ~= 0 do
		m, n = n%m, m
	end
	return n
end

if not div then
	log(1, "Info: Attempting to detect time division ...")
	for i=2, #mididata do
		local event=mididata[i]
		if event[1] == "note" and chlisten[event[5]] and trlisten[event[3]] then
			local time = event[2]-skip
			if time>0 then
				if not div then
					div = time
				else
					div = math.min(div, gcd(div, time))
					if div == 1 then
						error("Failed to detect time division!", 0)
					end
				end
			end
		end
	end
	if not div then
		error("Failed to detect time division!", 0)
	end
	log(1, "Info: Detected: " .. div)
end

if not speed then
	local ppq=mididata[1]
	log(1, "Info: Attempting to detect speed ...")
	local tempo
	local warned=false
	for i=2, #mididata do
		local event=mididata[i]
		if event[1] == "set_tempo" then
			if not tempo then
				tempo=event[4]
			elseif not warned then
				log(1, "Info: midi changes tempo mid song, this is currently not supported.")
				warned=true
			end
		end
	end
	if not tempo then
		log(1, "Info: No tempo events, using default of 500000")
		tempo=500000
	end
	local fspeed=div*(tempo/1000/ppq)/(1220/147)
	speed=math.max(math.round(fspeed), 1)
	logf(1, "Info: Detected: %s (%d)", fspeed, speed)
end

local function note2pico(note, drum)
	local val = (note-36)+(drum and dshift or shift)
	local msg = (drum and "Drum note" or "Note")
	if val > 63 then
		logf(2, "Warning: %s too high, truncating: %d, %+d", msg, val, val-63)
		val = 63
	end
	if val < 0 then
		logf(2, "Warning: %s too low, truncating: %d", msg, val)
		val = 0
	end
	return val
end

local bit = require("bit32")

local slice={}
local function getChunk(i)
	if not slice[i] then
		slice[i]={}
	end
	return slice[i]
end

-- Configured Midi Information
local vol={}
local prgm={}
local pwheel={}
local nrpn={}
local rpn={}
local nrpns={}
local rpns={}
local lrpn
local function resetmidi()
	for i=0, 15 do
		vol[i]=127
		prgm[i]=0
		pwheel[i]=0
		nrpn[i]={[0]=2}
		rpn[i]={[0]=2}
		nrpns[i]=0
		rpns[i]=0
	end
	lrpn=nil
end
resetmidi()

local die = false
local mtime=-math.huge
local stime=math.huge

local function parseevent(event)
	if event[1] == "note" and chlisten[event[5]] and trlisten[event[3]] and event[2]-skip >= 0 then
		event[2]=event[2]-skip
		if event[2]/div ~= math.floor(event[2]/div) then
			print("Invalid division: " .. event[2] .. " -> " .. event[2]/div)
			die = true
		end
		local time=math.floor(event[2]/div)
		mtime=math.max(mtime, time)
		stime=math.min(stime, time)
		local chunk=getChunk(time)
		local chunkdata={note=event[6], vol=vol[event[5]], vel=event[7], prgm=prgm[event[5]], pwheel=pwheel[event[5]]/8192*rpn[event[5]][0], ch=event[5], durat=event[4]}
		local placed=false
		if mode == "blob" then
			if #chunk < 4 then
				chunk[#chunk+1]=chunkdata
				placed=true
			end
		elseif mode == "channel" then
			local cpos=(event[5]%4)+1
			if chunk[cpos] == nil then
				chunk[cpos]=chunkdata
				placed=true
			end
		elseif mode == "track" then
			local tpos=((event[3]-1)%4)+1
			if chunk[tpos] == nil then
				chunk[tpos]=chunkdata
				placed=true
			end
		end
		if not placed and mode ~= "blob" then
			for i=1, 4 do
				if chunk[i] == nil then
					chunk[i]=chunkdata
					placed = true
					break
				end
			end
		end
		if not placed then
			log(2, "Warning: Overran " .. time)
			local kill
			local note=event[6]
			for i=1, 4 do
				if event[6]>chunk[i].note then
					kill = i
				end
			end
			if kill then
				chunk[kill]=chunkdata
			end
		end
	elseif event[1] == "text" then
		log(1, "Info: (Text) " .. event[4] .. ": " .. event[5])
	elseif event[1] == "control_change" then
		if event[5] == 1 then
			-- No Banks.
		elseif event[5] == 6 then
			if lrpn==true then
				rpn[event[4]][rpns[event[4]]]=event[6]
			elseif lrpn==false then
				nrpn[event[4]][nrpns[event[4]]]=event[6]
			end
			lrpn=nil
		elseif event[5] == 7 then
			vol[event[4]]=event[6]
		elseif event[5] == 10 then
			-- No Panning.
		elseif event[5] == 98 then
			nrpns[event[4]] = bit.bor(bit.band(nrpns[event[4]], 0x3f80), event[6])
			lrpn=false
		elseif event[5] == 99 then
			nrpns[event[4]] = bit.bor(bit.band(nrpns[event[4]], 0x7f), bit.lshift(event[6], 7))
			lrpn=false
		elseif event[5] == 100 then
			rpns[event[4]] = bit.bor(bit.band(rpns[event[4]], 0x3f80), event[6])
			lrpn=true
		elseif event[5] == 101 then
			rpns[event[4]] = bit.bor(bit.band(rpns[event[4]], 0x7f), bit.lshift(event[6], 7))
			lrpn=true
		else
			--log(2, "Warning: Unknown Control Parameter: " .. table.concat(event, ", "))
			local time, track, channel, control, value=table.unpack(event, 2)
			channel=channel+1
			logf(2, "Warning: Unknown Control Parameter: {%d, T%d, CH%d, C%d, V%d}", time, track, channel, control, value)
		end
	elseif event[1] == "patch_change" then
		prgm[event[4]]=event[5]
	elseif event[1] == "pitch_wheel_change" then
		pwheel[event[4]]=event[5]
		local time=math.floor(event[2]/div)
		local chunk=getChunk(time)

	else

	end
end
for i=2, #mididata do
	local event = mididata[i]
	local ok, err = pcall(parseevent, event)
	if not ok then
		io.stderr:write("Crashed parsing event : {" .. table.concat(event, ", ") .. "}\n\n" .. err .. "\n")
		os.exit(1)
	end
end

if die then
	--os.exit(1)
end
log(1, "Info: Extending notes ...")
local cpparm={"note", "vol", "vel", "prgm", "pwheel", "ch"}
local lostnotes=0
for i=0, mtime do
	if slice[i] then
		local chunk=slice[i]
		for j=1, 4 do
			if chunk[j] and chunk[j].durat then
				local kstop = math.ceil(chunk[j].durat/div)-1
				for k=1, kstop do
					mtime = math.max(mtime, i+k)
					local chunk2=getChunk(i+k)
					if not chunk2[j] then
						chunk2[j]={}
					end
					if not chunk2[j].note then
						for i=1,#cpparm do
							chunk2[j][cpparm[i]]=chunk[j][cpparm[i]]
						end
						chunk2[j].pos=((k == kstop) and "E" or "M")
					else
						local lost=kstop - k + 1
						local lchunk=slice[i+k-1][j]
						if k > 1 then
							lchunk.pos="E"
						end
						logf(2, "Warning: Note blocking Note, lost %d", lost)
						lchunk.lost=lost
						lostnotes=lostnotes+lost
						break
					end
				end
				chunk[j].durat=nil
				chunk[j].pos="S"
			end
		end
	end
end
if lostnotes>0 then
	logf(1, "Info: Lost %d notes", lostnotes)
end
if lostnotes>0 and not opts.noregain then
	local regained=0
	log(1, "Info: Attempting to regain notes ...")
	for i=0, mtime do
		if slice[i] then
			local chunk=slice[i]
			for j=1, 4 do
				local schunk=chunk[j]
				if schunk and schunk.lost then
					local chunk2=getChunk(i+1)
					local tj
					for k=1, 4 do
						if not chunk2[k] or not chunk2[k].note then
							tj=k
							break
						end
					end
					if tj then
						for k=1, schunk.lost do
							mtime = math.max(mtime, i+k)
							local chunk2=getChunk(i+k)
							if not chunk2[tj] then
								chunk2[tj]={}
							end
							if not chunk2[tj].note then
								for i=1,#cpparm do
									chunk2[tj][cpparm[i]]=schunk[cpparm[i]]
								end
								chunk2[tj].pos=((k == schunk.lost) and "E" or "M")
								if k == schunk.lost then
									logf(2, "Warning: Regained %d notes", schunk.lost)
									regained=regained+schunk.lost
								end
							else
								local lost=schunk.lost - k + 1
								local lchunk=slice[i+k-1][tj]
								if k > 1 then
									lchunk.pos="E"
								end
								logf(2, "Warning: Regained %d notes", k-1)
								lchunk.lost=lost
								regained=regained+k-1
								break
							end
						end
						schunk.lost=nil
						schunk.pos="M"
					end
				end
			end
		end
	end
	logf(1, "Info: Regained %d notes", regained)
end
if not opts.no2ndpass then
	log(1, "Info: Performing second corrective pass ...")
	resetmidi()
	local pass2nd={}
	local function parseevent2(event)
		if event[1] == "control_change" then
			if event[5] == 6 then
				if lrpn==true then
					rpn[event[4]][rpns[event[4]]]=event[6]
					if rpns[event[4]]==0 then
						local time=math.floor(event[2]/div)
						if not pass2nd[time] then
							pass2nd[time]={}
						end
						local chunk=pass2nd[time]
						if not chunk.pwheel then
							chunk.pwheel={}
						end
						chunk.pwheel[event[4]]=pwheel[event[4]]/8192*event[6]
					end
				elseif lrpn==false then
					nrpn[event[4]][nrpns[event[4]]]=event[6]
				end
				lrpn=nil
			elseif event[5] == 7 then
				local time=math.floor(event[2]/div)
				if not pass2nd[time] then
					pass2nd[time]={}
				end
				local chunk=pass2nd[time]
				if not chunk.vol then
					chunk.vol={}
				end
				chunk.vol[event[4]]=event[6]
			elseif event[5] == 98 then
				nrpns[event[4]] = bit.bor(bit.band(nrpns[event[4]], 0x3f80), event[6])
				lrpn=false
			elseif event[5] == 99 then
				nrpns[event[4]] = bit.bor(bit.band(nrpns[event[4]], 0x7f), bit.lshift(event[6], 7))
				lrpn=false
			elseif event[5] == 100 then
				rpns[event[4]] = bit.bor(bit.band(rpns[event[4]], 0x3f80), event[6])
				lrpn=true
			elseif event[5] == 101 then
				rpns[event[4]] = bit.bor(bit.band(rpns[event[4]], 0x7f), bit.lshift(event[6], 7))
				lrpn=true
			end
		elseif event[1] == "patch_change" then
			prgm[event[4]]=event[5]
		elseif event[1] == "pitch_wheel_change" then
			pwheel[event[4]]=event[5]
			local time=math.floor(event[2]/div)
			if not pass2nd[time] then
				pass2nd[time]={}
			end
			local chunk=pass2nd[time]
			if not chunk.pwheel then
				chunk.pwheel={}
			end
			chunk.pwheel[event[4]]=event[5]/8192*rpn[event[4]][0]
		end
	end
	for i=2, #mididata do
		local event = mididata[i]
		local ok, err = pcall(parseevent2, event)
		if not ok then
			io.stderr:write("Crashed parsing event : {" .. table.concat(event, ", ") .. "}\n\n" .. err .. "\n")
			os.exit(1)
		end
	end
	do
		local vol={}
		local pwheel={}
		for i=0,15 do
			vol[i]=127
			pwheel[i]=0
		end
		for i=0, mtime do
			if pass2nd[i] then
				local vold=pass2nd[i].vol
				local pwheeld=pass2nd[i].pwheel
				if vold then
					for i=0, 15 do
						if vold[i] then vol[i]=vold[i] end
					end
				end
				if pwheeld then
					for i=0, 15 do
						if pwheeld[i] then pwheel[i]=pwheeld[i] end
					end
				end
			end
			local chunk=slice[i]
			if chunk then
				for j=1, 4 do
					if chunk[j] then
						local schunk=chunk[j]
						if vol[schunk.ch] ~= schunk.vol and not opts.novol then
							logf(2, "Warning: Corrected volume from %s to %s", schunk.vol, vol[schunk.ch])
						end
						schunk.vol=vol[schunk.ch]
						if pwheel[schunk.ch] ~= schunk.pwheel and not opts.nopwheel then
							logf(2, "Warning: Corrected pitch wheel from %s to %s", schunk.pwheel, pwheel[schunk.ch])
						end
						schunk.pwheel=pwheel[schunk.ch]
					end
				end
			end
		end
	end
end
if stime ~= 0 then
	log(1, "Info: Trimming " .. stime .. " slices  ...")
	for i=stime, mtime+stime do
		slice[i-stime]=slice[i]
	end
	mtime=mtime-stime
	stime=0
end
local pats=math.ceil(mtime/32)-1
log(1, "Info: " .. pats+1 .. " patterns")
for block=0, pats*32, 32 do
	local top=0
	for i = 0, 31 do
		local chunk=getChunk(i+block)
		for j=1, 4 do
			if chunk[j] then
				top=math.max(top, j)
			end
		end
	end
	if top<4 then
		log(1, "Info: Saved " .. 4-top .. " in pattern " .. block/32)
	end
end
--Diagnostics only, needs fixing.
--[[
local patmap={}
for block=0, pats*32, 32 do
	for block2=block+32, pats*32, 32 do
		local same=true
		for i = 0, 31 do
			local chunk=slice[i+block]
			local chunk2=slice[i+block2]
			for j=1, 4 do
				if chunk[j]~=chunk2[j] then
					same=false
					break
				end
			end
			if not same then
				break
			end
		end
		if same and not patmap[block2/32] then
			log(1, "Info: pattern " .. block/32 .. " is the same as " .. block2/32)
		end
	end
end
--]]
local outfile, err
if args[2] then
	log(1, "Info: Writing to '" .. args[2] .. "'")
	outfile, err = io.open(args[2], "wb")
	if not outfile then
		error(err, 0)
	end
else
	log(1, "Info: Writing to stdout")
	outfile=io.stdout
end
outfile:write("__sfx__\n")
local base=0
local patsel={}
local linemap={}
local kill={}
local count=0
linemap[string.format("01%02x0000", tonumber(speed))..string.rep("0",32*5)]=-1 -- don't emit empty pattern.
for block=0, pats*32, 32 do
	local top=0
	for i = 0, 31 do
		local chunk=getChunk(i+block)
		for j=1, 4 do
			if chunk[j] and chunk[j].note then
				top=math.max(top, j)
			end
		end
		if top==4 then
			break
		end
	end
	for j=1, top do
		local line = string.format("01%02x0000", tonumber(speed))
		for i = 0, 31 do
			local chunk=getChunk(i+block)
			if chunk[j] and chunk[j].note then
				local info = chunk[j]
				if opts.nopwheel then
					info.pwheel=0
				end
				if opts.novol then
					info.vol=127
					info.vel=127
				end
				local instr = info.prgm
				local drum = drumch[info.ch]
				local val = note2pico(math.floor(info.note+info.pwheel+0.5), drum)
				if val <= 63 then
					local place=3
					if info.pos=="S" then
						place=2
					elseif info.pos=="E" then
						place=4
					end
					line = line .. string.format("%02x%x%s%x", val, drum and picodrum[instr][1] or picoinstr[instr][1], drum and drumvol or math.floor((info.vol/127)*(info.vel/127)*(chvol[info.ch]-1)+1.5), drum and picodrum[instr][place] or picoinstr[instr][place])
				else
					log(2, "Dropping high pitched note.")
					line = line .. "00000"
				end
			else
				line = line .. "00000"
			end
		end
		if not linemap[line] then
			linemap[line]=base+j-1
			if count >= 64 and not opts.notrunc then
				outfile:close()
				error("Midi is too long or time division is too short.\nUse --notrunc to continue writing.", 0)
			end
			outfile:write(line.." "..string.format("%02x", count).."\n")
			count=count+1
		else
			linemap[base+j-1]=linemap[line]
			kill[#kill+1]=base+j-1
		end
	end
	local patblock={}
	for i = 0, top-1 do
		patblock[#patblock+1]=linemap[base+i] or base+i
	end
	base=base+top
	patsel[block/32]=patblock
end
for block=0, pats do
	local patblock = patsel[block]
	for i=1, #patblock do
		local val=patblock[i]
		local subtract=0
		for i=1, #kill do
			if kill[i]<=val then
				subtract=subtract+1
			else
				break
			end
		end
		patblock[i]=val-subtract
	end
end
outfile:write("__music__\n")
local first=true
for block=0, pats do
	local line
	if first then
		line = "01 "
	elseif block == pats then
		line = "02 "
	else
		line = "00 "
	end
	local patblock = patsel[block]
	for i=1, 4 do
		if patblock[i] and patblock[i] >= 0x40 then
			if opts.notrunc then
				logf(2, "Warning: Ran out of sfx: %d, (%02x)", patblock[i], patblock[i])
			else
				outfile:close()
				error("Midi is too long or time division is too short.\nUse --notrunc to continue writing.", 0)
			end
		end
		if not patblock[i] or patblock[i] == -1 then
			patblock[i]=0x40
		elseif patblock[i] >= 0x40 then
			patblock[i]=0x40
		end
		patblock[i]=string.format("%02x", patblock[i])
	end
	local pats = table.concat(patblock, "")
	if not first or pats ~= "40404040" then
		first=false
		outfile:write(line .. table.concat(patblock, "").."\n")
	end
end
if args[2] then
	outfile:close()
end
log(1, "Info: Finished!")

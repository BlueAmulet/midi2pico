#!/usr/bin/env lua

local function print(...)
	local args=table.pack(...)
	for i=1, args.n do
		args[i]=tostring(args[i])
	end
	io.stderr:write(table.concat(args, "\t").."\n")
end

-- LuaJIT and Lua5.1 compatibility
if not table.pack then
	function table.pack(...) return {n=select("#", ...), ...} end
end
if not table.unpack then
	table.unpack = unpack
end

local bit=bit
if not bit then
	local ok
	ok, bit=pcall(require, "bit32")
	if not ok then
		print(bit)
		print("bit32 api is missing, please install via: luarocks install bit32")
		os.exit(1)
	end
end

local ok, midi=pcall(require, "MIDI")
if not ok then
	print(midi)
	print("MIDI api is missing, please install via: luarocks install midi")
	os.exit(1)
end

local parse=require("argparse")

local args, opts=parse(...)

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

	--clean     Don't output sfx and pattern info at end of lines
	--musichax  Write a special program to stream additional audio from gfx
	--no2ndpass Skip second corrective pass
	--nopwheel  Ignore pitch wheel data
	--novol     Ignore volume data
	--noexpr    Ignore expression data
	--notrunc   Keep going despite no more sfx
	--stub      Write a lua stub to automatically play the generated music

	--ignorediv Ignore bad time divisions
	--fixdivone Correct time divisions off by one
	--analysis  Analyse and report on time information

	All options above take the form: --name

MusicHAX:
	MusicHAX is a system to store more audio data than pico-8 normally allows,
	audio data is stored in gfx areas and copied into sfx as needed. Enabling
	this option will use this system and also output a lua stub to process and
	play the music.
]])
	return
end

local function arg2num(name)
	val=tonumber(tostring(opts[name]), 10)
	if not val then
		error("Invalid value for option '" .. name .. "': " .. tostring(opts[name]), 0)
	end
	return val
end

-- Instrument to PICO-8 Map
local picoinstr={
	[0]={1, 0, 0, 5},
	[1]={1, 0, 0, 5},
	[3]={1, 2, 2, 5},
	[4]={0, 0, 0, 5},
	[5]={5, 0, 0, 5},
	[7]={4, 0, 0, 5},
	[11]={1, 0, 0, 5},
	[16]={5, 0, 0, 5},
	[17]={0, 0, 0, 5},
	[18]={5, 2, 2, 5},
	[19]={5, 4, 0, 5},
	[20]={5, 4, 0, 5},
	[30]={4, 0, 0, 5},
	[33]={1, 0, 0, 5},
	[38]={1, 0, 0, 5},
	[42]={5, 4, 0, 5},
	[71]={5, 4, 0, 5},
	[72]={1, 4, 0, 5},
	[73]={5, 4, 2, 5},
	[74]={5, 4, 0, 5},
	[78]={0, 4, 0, 5},
	[79]={0, 4, 0, 5},
	[81]={2, 0, 0, 0},
	[89]={1, 4, 0, 5},
	[97]={4, 4, 0, 5},
	[100]={5, 0, 0, 5},
	[101]={0, 4, 0, 5},
	[105]={4, 0, 0, 5},
}
for i=0, 127 do
	if picoinstr[i] == nil then
		picoinstr[i]={3, 0, 0, 5}
	end
end

-- Drums to PICO-8 Map
local picodrum={
	[35]={2, 0, 0, 5, 42},
	[37]={6, 5,-1,-1, 64},
	[40]={6, 0, 0, 5, 64},
	[42]={6, 5,-1,-1, 90},
	[53]={5, 0, 0, 5, 90},
}
for i=0, 127 do
	if picodrum[i] == nil then
		picodrum[i]={6, 5,-1,-1, 84}
	end
end

-- Allowed Channels
local chlisten={}
for i=0, 15 do
	chlisten[i]=true
end

-- Allowed Tracks
trlisten_mt={__index=function(t, k)
	t[k]=t.default
	return t.default
end}
local trlisten=setmetatable({default=true}, trlisten_mt)

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
chvol[9]=2

local maxlevel=math.huge
if opts.level then
	maxlevel=arg2num("level")
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
	local maxvol=tonumber(tostring(opts.maxvol))
	if not maxvol then
		error("Invalid value for option 'maxvol': " .. tostring(opts.maxvol), 0)
	elseif maxvol < 0 or maxvol > 7 then
		error("Invalid range for option 'maxvol': " .. maxvol, 0)
	end
	for i=0, 15 do
		if not drumch[i] then
			chvol[i]=maxvol
		end
	end
end

if opts.drumvol then
	local drumvol=tonumber(tostring(opts.drumvol))
	if not drumvol then
		error("Invalid value for option 'drumvol': " .. tostring(opts.drumvol), 0)
	elseif drumvol < 0 or drumvol > 7 then
		error("Invalid range for option 'drumvol': " .. drumvol, 0)
	end
	for i=0, 15 do
		if drumch[i] then
			chvol[i]=drumvol
		end
	end
end

if opts.mute then
	for part in (opts.mute .. ","):gmatch("(.-),") do
		local chmn=tonumber(part, 10)
		if chmn == nil then
			error("Invalid channel for option 'mute': " .. part, 0)
		elseif chmn < -16 or chmn > 16 then
			error("Invalid channel for option 'mute': " .. math.abs(chmn), 0)
		elseif chmn == 0 then
			local all=(part:sub(1, 1) == "-")
			for i=0, 15 do
				chlisten[i]=all
			end
		else
			chlisten[math.abs(chmn)-1]=chmn < 0
		end
	end
end

if opts.mutet then
	for part in (opts.mutet .. ","):gmatch("(.-),") do
		local trmn=tonumber(part, 10)
		if trmn == nil then
			error("Invalid track for option 'mutet': " .. part, 0)
		elseif trmn < -65536 or trmn > 65536 then
			error("Invalid track for option 'mutet': " .. math.abs(trmn), 0)
		elseif trmn == 0 then
			trlisten=setmetatable({default=(part:sub(1, 1) == "-")}, trlisten_mt)
		else
			trlisten[math.abs(trmn)-1]=trmn < 0
		end
	end
end

local speed
if opts.speed then
	speed=tonumber(tostring(opts.speed))
	if not speed then
		error("Invalid value for option 'speed': " .. tostring(opts.speed), 0)
	elseif speed < 0 or speed > 255 then
		error("Invalid range for option 'speed': " .. speed, 0)
	end
end

if opts.chvol then
	for part in (opts.chvol .. ","):gmatch("(.-),") do
		local ch, vol=part:match("(.*):(.+)")
		ch=tonumber(ch, 10)
		vol=tonumber(vol, 10)
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
	local note={score[1]}
	local trackpos={}
	local nscore=#score
	for i=2, nscore do
		trackpos[i]=1
	end
	while true do
		local ltime, tpos=math.huge
		for i=2, nscore do
			local event=score[i][trackpos[i]]
			if event then
				local ttime=event[2]
				if ttime < ltime then
					ltime, tpos=ttime, i
				end
			end
		end
		if not tpos then break end
		local event=score[tpos][trackpos[tpos]]
		score[tpos][trackpos[tpos]]=nil
		trackpos[tpos]=trackpos[tpos] + 1
		table.insert(event, 3, tpos-2)
		-- Merge text events into one event type
		local kind=event[1]
		if text_events[kind] then
			kind=kind:gsub("_event", ""):gsub("_text", "")
			table.insert(event, 4, kind)
			event[1]="text"
		end
		note[#note+1]=event
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

if data == nil then
	print("Received no data from file?")
	os.exit(1)
end

if data:sub(1, 4) ~= "MThd" then
	print("MIDI header missing from file")
	os.exit(1)
end

local mididata=score2note(midi.midi2score(data))

local function gcd(m, n)
	while m ~= 0 do
		m, n=n%m, m
	end
	return n
end

-- MIDI timing analytics
local commondiv={}
for i=1, 30 do
	commondiv[i*5]=0
	commondiv[i*6]=0
end

local timediff={}
local lnote=0

if opts.analysis and not opts.ignorediv then
	log(2, "Warning: --analysis implies --ignorediv")
	opts.ignorediv=true
end

if not div then
	log(1, "Info: Attempting to detect time division ...")
	for i=2, #mididata do
		local event=mididata[i]
		if event[1] == "note" and chlisten[event[5]] and trlisten[event[3]] then
			local time=event[2]-skip
			if time > 0 then
				if opts.analysis and time-lnote > 0 then
					timediff[time-lnote]=(timediff[time-lnote] or 0)+1
					lnote=time
				end
				if not div then
					div=time
					commondiv[div]=1
					if div == 1 then
						print("\nError: Failed to detect time division! First note starts at 1")
						os.exit(1)
					end
				else
					local ldiv=div
					div=math.min(div, gcd(div, time))
					if opts.analysis then
						if not commondiv[div] then
							commondiv[div]=1
						else
							local highest=-math.huge
							for k, v in pairs(commondiv) do
								if time/k == math.floor(time/k) or (opts.fixdivone and ((time-1)/k == math.floor((time-1)/k) or (time+1)/k == math.floor((time+1)/k))) then
									highest=math.max(highest, k)
								end
							end
							commondiv[highest]=commondiv[highest]+1
						end
					end
					if ldiv ~= div and opts.fixdivone then
						if math.min(ldiv, gcd(ldiv, time-1)) == ldiv then
							div=ldiv
							logf(2, "Warning: Corrected off by one error at %d/%d (-1)", time, div)
						elseif math.min(ldiv, gcd(ldiv, time+1)) == ldiv then
							div=ldiv
							logf(2, "Warning: Corrected off by one error at %d/%d (+1)", time, div)
						end
					end
					if div == 1 then
						local bad=time/ldiv
						if not opts.ignorediv then
							print("\nError: Failed to detect time division!")
							print("Last good division was "..ldiv)
							print("Bad note at "..time.."/"..ldiv.." = "..bad.." ("..math.floor(bad).." + "..time-math.floor(bad)*ldiv.."/"..ldiv..")")
							print("\nTry using --analysis for suggestions")
							print("--ignorediv and --fixdivone may help correct errors")
							os.exit(1)
						else
							log(2, "Warning: Ignoring bad time division of "..time.."/"..ldiv.." = "..bad)
							div=ldiv
						end
					end
				end
			end
		end
	end
	if not div then
		print("\nError: Failed to detect time division! No notes?", 0)
		os.exit(1)
	end
	log(1, "Info: Detected: " .. div)
end

local function process(tbl, message)
	print(message)
	local high=-math.huge
	local highk=-math.huge
	local sorttbl={}
	for k, v in pairs(tbl) do
		if v > high then
			highk, high=k, v
		elseif v == high then
			highk=math.max(highk, k)
		end
		sorttbl[#sorttbl+1]={k, v}
	end
	table.sort(sorttbl, function(a, b) return a[2]<b[2] end)
	for i=1, #sorttbl do
		local k, v=sorttbl[i][1], sorttbl[i][2]
		if v ~= 0 then
			if v == high then
				k="["..k.."]"
			end
			print(k..") "..v)
		end
	end
	return high, highk
end

if opts.analysis then
	local cdhigh, cdhighk=process(commondiv, "\nInfo: Common div usage:")
	local cthigh, cthighk=process(timediff, "\nInfo: Common time difference:")

	local factor=math.min(cdhighk, cthighk, gcd(cdhighk, cthighk))
	print("\nInfo: Greatest common factor: "..factor)

	if factor ~= 1 then
		print("Try with --div="..factor)
	else
		print("Error: Analysis resulted in div of 1.")
	end
	local cdlowest=cdhighk
	while commondiv[cdlowest/2] do
		cdlowest=cdlowest/2
	end
	local ctlowest=cthighk
	while timediff[ctlowest/2] do
		ctlowest=ctlowest/2
	end

	local try={}
	if cdhighk ~= 1 then
		try[#try+1]=cdhighk
	end
	if cthighk ~= 1 and cthighk ~= cdhighk then
		try[#try+1]=cthighk
	end
	if cdlowest ~= 1 and cdlowest ~= cdhighk then
		try[#try+1]=cdlowest
	end
	if ctlowest ~= 1 and ctlowest ~= cthighk then
		try[#try+1]=ctlowest
	end
	if #try > 0 then
		local msg=(factor ~= 1) and "Other choices" or "Possibly try"
		print(msg..": "..table.concat(try, ", "))
	else
		print("No suggestions available, look at above lists")
	end

	os.exit(1)
end

if not speed then
	local ppq=mididata[1]
	log(1, "Info: Attempting to detect speed ...")
	local tempo
	local warned=false
	local notes=false
	for i=2, #mididata do
		local event=mididata[i]
		if event[1] == "set_tempo" then
			if not tempo or event[2] == 0 or not notes then
				tempo=event[4]
			elseif tempo ~= event[4] and not warned then
				log(1, "Info: midi changes tempo mid song, this is currently not supported.")
				warned=true
			end
		elseif event[1] == "note" then
			notes=true
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
	local val=(note-36)+(drum and dshift or shift)
	local msg=(drum and "Drum note" or "Note")
	if val > 63 then
		logf(2, "Warning: %s too high, truncating: %d, %+d", msg, val, val-63)
		val=63
	end
	if val < 0 then
		logf(2, "Warning: %s too low, truncating: %d", msg, val)
		val=0
	end
	return val
end

local slice={}
local function getChunk(i)
	if not slice[i] then
		slice[i]={}
	end
	return slice[i]
end

-- Configured Midi Information
local vol={}
local expr={}
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
		expr[i]=127
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

local mtime=-math.huge
local stime=math.huge

local function parseevent(event)
	if event[1] == "note" and chlisten[event[5]] and trlisten[event[3]] and event[2]-skip >= 0 then
		event[2]=event[2]-skip
		if event[2]/div ~= math.floor(event[2]/div) then
			print("Invalid division: " .. event[2] .. " -> " .. event[2]/div)
		end
		local time=math.floor(event[2]/div)
		mtime=math.max(mtime, time)
		stime=math.min(stime, time)
		local chunk=getChunk(time)
		local chunkdata={note=event[6], vol=vol[event[5]], expr=expr[event[5]], vel=event[7], prgm=prgm[event[5]], pwheel=pwheel[event[5]]/8192*rpn[event[5]][0], ch=event[5], durat=event[4]}
		if drumch[event[5]] then
			chunkdata.prgm=chunkdata.note
			chunkdata.note=picodrum[chunkdata.prgm][5]
		end
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
					placed=true
					break
				end
			end
		end
		if not placed then
			log(2, "Warning: Overran " .. time)
			local kill
			local note=event[6]
			for i=1, 4 do
				if event[6] > chunk[i].note then
					kill=i
				end
			end
			if kill then
				chunk[kill]=chunkdata
			end
		end
	elseif event[1] == "text" then
		log(1, "Info: (Text) " .. event[4] .. ": " .. event[5])
	elseif event[1] == "control_change" then
		if event[5] == 0 then
			-- No Banks.
		elseif event[5] == 6 then
			if lrpn == true then
				rpn[event[4]][rpns[event[4]]]=event[6]
			elseif lrpn == false then
				nrpn[event[4]][nrpns[event[4]]]=event[6]
			end
			lrpn=nil
		elseif event[5] == 7 then
			vol[event[4]]=event[6]
		elseif event[5] == 8 or event[5] == 10 then
			-- No Balance/Panning.
			if event[6] ~= 64 then
				logf(2, "Warning: " .. (event[5] == 8 and "balance" or "panning") .. " (ch:" .. event[4] .. "=" .. (event[6]-64) .. ") is not supported.")
			end
		elseif event[5] == 11 then
			expr[event[4]]=event[6]
		elseif event[5] == 98 then
			nrpns[event[4]]=bit.bor(bit.band(nrpns[event[4]], 0x3f80), event[6])
			lrpn=false
		elseif event[5] == 99 then
			nrpns[event[4]]=bit.bor(bit.band(nrpns[event[4]], 0x7f), bit.lshift(event[6], 7))
			lrpn=false
		elseif event[5] == 100 then
			rpns[event[4]]=bit.bor(bit.band(rpns[event[4]], 0x3f80), event[6])
			lrpn=true
		elseif event[5] == 101 then
			rpns[event[4]]=bit.bor(bit.band(rpns[event[4]], 0x7f), bit.lshift(event[6], 7))
			lrpn=true
		else
			local time, track, channel, control, value=table.unpack(event, 2)
			channel=channel+1
			logf(2, "Warning: Unknown Controller: {%d, T%d, CH%d, CC%d, V%d}", time, track, channel, control, value)
		end
	elseif event[1] == "patch_change" then
		prgm[event[4]]=event[5]
	elseif event[1] == "pitch_wheel_change" then
		if not drumch[event[4]] then
			pwheel[event[4]]=event[5]
		else
			logf(2, "Warning: Ignoring pitch wheel event on drum channel: " .. event[4])
		end
	else

	end
end
for i=2, #mididata do
	local event=mididata[i]
	local ok, err=pcall(parseevent, event)
	if not ok then
		io.stderr:write("Crashed parsing event : {" .. table.concat(event, ", ") .. "}\n\n" .. err .. "\n")
		os.exit(1)
	end
end

log(1, "Info: Extending notes ...")
local cpparm={"note", "vol", "expr", "vel", "prgm", "pwheel", "ch"}
local lostnotes=0
for i=0, mtime do
	if slice[i] then
		local chunk=slice[i]
		for j=1, 4 do
			if chunk[j] and chunk[j].durat then
				local kstop=math.ceil(chunk[j].durat/div)-1
				for k=1, kstop do
					mtime=math.max(mtime, i+k)
					local chunk2=getChunk(i+k)
					if not chunk2[j] then
						chunk2[j]={}
					end
					if not chunk2[j].note then
						for i=1, #cpparm do
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
if lostnotes > 0 then
	logf(1, "Info: Lost %d notes", lostnotes)
end
if lostnotes > 0 and not opts.noregain then
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
							mtime=math.max(mtime, i+k)
							local chunk2=getChunk(i+k)
							if not chunk2[tj] then
								chunk2[tj]={}
							end
							if not chunk2[tj].note then
								for i=1, #cpparm do
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
	if lostnotes == regained then
		logf(1, "Info: Regained all notes back!")
	end
end
if not opts.no2ndpass then
	log(1, "Info: Performing second corrective pass ...")
	resetmidi()
	local pass2nd={}
	local function parseevent2(event)
		if event[1] == "control_change" then
			if event[5] == 6 then
				if lrpn == true then
					rpn[event[4]][rpns[event[4]]]=event[6]
					if rpns[event[4]] == 0 then
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
				elseif lrpn == false then
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
			elseif event[5] == 11 then
				local time=math.floor(event[2]/div)
				if not pass2nd[time] then
					pass2nd[time]={}
				end
				local chunk=pass2nd[time]
				if not chunk.expr then
					chunk.expr={}
				end
				chunk.expr[event[4]]=event[6]
			elseif event[5] == 98 then
				nrpns[event[4]]=bit.bor(bit.band(nrpns[event[4]], 0x3f80), event[6])
				lrpn=false
			elseif event[5] == 99 then
				nrpns[event[4]]=bit.bor(bit.band(nrpns[event[4]], 0x7f), bit.lshift(event[6], 7))
				lrpn=false
			elseif event[5] == 100 then
				rpns[event[4]]=bit.bor(bit.band(rpns[event[4]], 0x3f80), event[6])
				lrpn=true
			elseif event[5] == 101 then
				rpns[event[4]]=bit.bor(bit.band(rpns[event[4]], 0x7f), bit.lshift(event[6], 7))
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
		local event=mididata[i]
		local ok, err=pcall(parseevent2, event)
		if not ok then
			io.stderr:write("Crashed parsing event : {" .. table.concat(event, ", ") .. "}\n\n" .. err .. "\n")
			os.exit(1)
		end
	end
	do
		local vol={}
		local expr={}
		local pwheel={}
		for i=0, 15 do
			vol[i]=127
			expr[i]=127
			pwheel[i]=0
		end
		for i=0, mtime do
			if pass2nd[i] then
				local vold=pass2nd[i].vol
				local exprd=pass2nd[i].expr
				local pwheeld=pass2nd[i].pwheel
				if vold then
					for i=0, 15 do
						if vold[i] then vol[i]=vold[i] end
					end
				end
				if exprd then
					for i=0, 15 do
						if exprd[i] then expr[i]=exprd[i] end
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
						if expr[schunk.ch] ~= schunk.expr and not opts.noexpr then
							logf(2, "Warning: Corrected expression from %s to %s", schunk.expr, expr[schunk.ch])
						end
						schunk.expr=expr[schunk.ch]
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
	log(1, "Info: Trimming " .. stime .. " slices ...")
	for i=stime, mtime+stime do
		slice[i-stime]=slice[i]
	end
	mtime=mtime-stime
	stime=0
end
local pats=math.ceil(mtime/32)-1
log(1, "Info: " .. pats+1 .. " patterns")
local outfile, err
if args[2] then
	log(1, "Info: Writing to '" .. args[2] .. "'")
	outfile, err=io.open(args[2], "wb")
	if not outfile then
		error(err, 0)
	end
else
	log(1, "Info: Writing to stdout")
	outfile=io.stdout
end
if not opts.musichax then
	if opts.stub then
	outfile:write([[pico-8 cartridge // http://www.pico-8.com
version 8
__lua__
music(0)
function _update() end
]])
	end
	outfile:write("__sfx__\n")
end
local base=0
local patsel={}
local linemap={}
local kill={}
local count=0

-- for musichax
local sfxdata
local cartdata
if not opts.musichax then
	linemap[string.format("01%02x0000", tonumber(speed))..string.rep("0", 32*5)]=-1 -- don't emit empty pattern.
else
	linemap[string.rep("\0", 64)]=-1 -- don't emit empty pattern.
	sfxdata=""
end
for block=0, pats*32, 32 do
	local top=0
	for i=0, 31 do
		local chunk=getChunk(i+block)
		for j=1, 4 do
			if chunk[j] and chunk[j].note then
				top=math.max(top, j)
			end
		end
		if top == 4 then
			break
		end
	end
	for j=1, top do
		local line, empty
		if not opts.musichax then
			line=string.format("01%02x0000", tonumber(speed))
			empty="00000"
		else
			line=""
			empty="\0\0"
		end
		for i=0, 31 do
			local chunk=getChunk(i+block)
			if chunk[j] and chunk[j].note then
				local info=chunk[j]
				if opts.nopwheel then
					info.pwheel=0
				end
				if opts.noexpr then
					info.expr=127
				end
				if opts.novol then
					info.vol=127
					info.vel=127
					info.expr=127
				end
				local instr=info.prgm
				local drum=drumch[info.ch]
				local val=note2pico(math.floor(info.note+info.pwheel+0.5), drum)
				if val <= 63 then
					local place=3
					if info.pos == "S" then
						place=2
					elseif info.pos == "E" then
						place=4
					end
					local instrdata=drum and picodrum[instr] or picoinstr[instr]
					if instrdata[place] ~= -1 then
						local note, instr, vol, fx=val, instrdata[1], math.floor((info.vol/127)*(info.vel/127)*(info.expr/127)*(chvol[info.ch]-1)+1.5), instrdata[place]
						if not opts.musichax then
							line=line .. string.format("%02x%x%s%x", note, instr, vol, fx)
						else
							local combo=(note*(2^0))+(instr*(2^6))+(vol*(2^9))+(fx*(2^12))
							line=line .. string.char(combo%256, math.floor(combo/256))
						end
					else
						line=line .. empty
					end
				else
					log(2, "Dropping high pitched note.")
					line=line .. empty
				end
			else
				line=line .. empty
			end
		end
		if not linemap[line] then
			linemap[line]=base+j-1
			if not opts.musichax then
				if count >= 64 and not opts.notrunc then
					outfile:close()
					error("Midi is too long or time division is too short.\nUse --notrunc to continue writing.", 0)
				end
				outfile:write(line..(not opts.clean and string.format(" %02x", count) or "").."\n")
			else
				sfxdata=sfxdata..line
				if #sfxdata/64 >= 256 then
					error("Too much sfx data", 0)
				end
			end
			count=count+1
		else
			linemap[base+j-1]=linemap[line]
			kill[#kill+1]=base+j-1
		end
	end
	local patblock={}
	for i=0, top-1 do
		patblock[#patblock+1]=linemap[base+i] or base+i
	end
	base=base+top
	patsel[block/32]=patblock
end
for block=0, pats do
	local patblock=patsel[block]
	for i=1, #patblock do
		local val=patblock[i]
		local subtract=0
		for i=1, #kill do
			if kill[i] <= val then
				subtract=subtract+1
			else
				break
			end
		end
		patblock[i]=val-subtract
	end
end
if not opts.musichax then
	outfile:write("__music__\n")
end
local first=true
local firstpat
for block=0, pats do
	local line
	if opts.musichax then
		line=""
	elseif first then
		line="01 "
	elseif block == pats then
		line="02 "
	else
		line="00 "
	end
	local patblock=patsel[block]
	if not opts.musichax then
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
		local pattern=table.concat(patblock, "")
		if not first or pattern ~= "40404040" then
			first=false
			outfile:write(line .. table.concat(patblock, "")..(not opts.clean and " "..block or "").."\n")
		end
	else
		for i=1, 4 do
			if not patblock[i] or patblock[i] == -1 then
				patblock[i]=0xFF
			end
		end
		local pattern=string.char(patblock[1], patblock[2], patblock[3], patblock[4])
		if not first or pattern ~= "\255\255\255\255" then
			if first then
				if pats-block >= 256 then
					error("Too many patterns", 0)
				end
				cartdata=string.char(pats-block, #sfxdata/64-1, 0, pats-block) -- number of patterns, number of sfx, loop start, loop end
				firstpat=block
			end
			first=false
			cartdata=cartdata..pattern
		end
	end
end
if opts.musichax then
	cartdata=cartdata..sfxdata
	local padding=0x4300-4-((pats-firstpat+1)*4)-#sfxdata-(68*4)
	if padding < 0 then
		error("too much data for MusicHAX")
	end
	cartdata=cartdata..string.rep("\0", padding)
	for i=1, 4 do
		cartdata=cartdata..string.rep("\0", 64).."\1"..string.char(speed).."\0\32"
	end
	local mhsfile, err=io.open("musichax-stub.lua", "rb")
	if not mhsfile then
		error(err, 0)
	end
	local code=mhsfile:read("*a")
	mhsfile:close()

	-- write cart
	local bin2hex=function(a) return ("%02x"):format(a:byte()) end
	outfile:write([[pico-8 cartridge // http://www.pico-8.com
version 8
__lua__
]]..code.."\n__gfx__\n")
	for i=0, 0x1fff, 64 do
		outfile:write(cartdata:sub(i+1, i+64):gsub(".", function(a) a=a:byte() return string.format("%02x", bit.bor(bit.lshift(bit.band(a, 0x0f), 4), bit.rshift(bit.band(a, 0xf0), 4))) end).."\n")
	end
	outfile:write("__gff__\n")
	for i=0x3000, 0x30ff, 128 do
		outfile:write(cartdata:sub(i+1, i+128):gsub(".", bin2hex).."\n")
	end
	outfile:write("__map__\n")
	for i=0x2000, 0x2fff, 128 do
		outfile:write(cartdata:sub(i+1, i+128):gsub(".", bin2hex).."\n")
	end
	outfile:write("__sfx__\n")
	for i=0x3200, 0x42ff, 68 do
		local sfx=cartdata:sub(i+65, i+68):gsub(".", bin2hex)
		local notes=cartdata:sub(i+1, i+64):gsub("..", function(a)
			local l, h=a:byte(1, -1)
			a=bit.bor(bit.lshift(h, 8), l)
			local note=bit.band(a, 0x003f)
			local instr=bit.rshift(bit.band(a, 0x01c0), 6)
			local vol=bit.rshift(bit.band(a, 0x0e00), 9)
			local fx=bit.rshift(bit.band(a, 0x7000), 12)
			return string.format("%02x%x%s%x", note, instr, vol, fx)
		end)
		outfile:write(sfx..notes.."\n")
	end
	outfile:write("__music__\n")
	for i=0x3100, 0x31ff, 4 do
		local loop=0
		local chn={cartdata:byte(i+1, i+4)}
		for j=0, 3 do
			loop=bit.bor(loop, bit.lshift(bit.band(chn[j+1], 0x80) ~= 0 and 1 or 0, j))
			chn[j+1]=bit.band(chn[j+1], 0x7f)
		end
		outfile:write(("%02x %02x%02x%02x%02x\n"):format(loop, chn[1], chn[2], chn[3], chn[4]))
	end
	outfile:write("\n")
end
if args[2] then
	outfile:close()
end
log(1, "Info: Finished!")

#!/usr/bin/env lua
local parse=require("argparse")

local args, opts=parse(...)

local function print(...)
	local args=table.pack(...)
	for i=1, args.n do
		args[i]=tostring(args[i])
	end
	io.stderr:write(table.concat(args, "\t").."\n")
end

if #args < 1 then
	print("Usage: " .. (arg and arg[0] or "midi2note") .. " midifile [notefile]")
	return 0
end

local file, err=io.open(args[1], "rb")
if not file then
	print(err)
	os.exit(1)
end
local data=file:read("*a")
file:close()

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

local midi=require("MIDI")

local note=score2note(midi.midi2score(data))

local outfile, err
if args[2] then
	print("Writing to '" .. args[2] .. "'")
	outfile, err=io.open(args[2], "wb")
	if not outfile then
		error(err, 0)
	end
else
	print("Writing to stdout")
	outfile=io.stdout
end
outfile:write("Ticks per beat: " .. note[1].."\n")
for i=2, #note do
	outfile:write(table.concat(note[i], ", ").."\n")
end
if args[2] then
	outfile:close()
end

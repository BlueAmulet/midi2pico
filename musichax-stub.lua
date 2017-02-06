local npat=peek(0)+1
local nsfx=peek(1)+1
local lstr=peek(2)+1
local lend=peek(3)+1
local base=4+npat*4
local pats={}
local lpos=0
local cpat=1
local function cpdata(i, len)
	local pat=peek(i+cpat*4)
	local addr=0x41f0+i*68+lpos*2
	if pat ~= 255 then
		memcpy(addr, pat*64+base+lpos*2, len)
	else
		memset(addr, 0, len)
	end
	return pat
end
for i=0,3 do
	pats[i]=cpdata(i, 64)
	if (pats[i] == 255) pats[i]=-1
end
cpat=2
local lcpt=1
sfx(60, 0)
sfx(61, 1)
sfx(62, 2)
sfx(63, 3)

local function updmusic()
	local pos=stat(20)
	if pos < lpos then
		for i=0, 3 do
			local pat=cpdata(i, 64-lpos*2)
			if (pat == 255) pat=-1
			pats[i]=pat
		end
		lcpt=cpat
		if cpat==lend then
			cpat=lstr
		else
			cpat+=1
		end
		lpos=0
		for i=0, 3 do
			cpdata(i, pos*2)
		end
	else
		for i=0, 3 do
			cpdata(i, (pos-lpos)*2)
		end
	end
	lpos=pos
end

function _init()
	cls()
	print(npat.." patterns")
	print(nsfx.." sfx data")
	print("loop start: "..(lstr-1))
	print("loop end: "..(lend-1))
	print("")
	print("streaming music ...")
end

function _update60()
	updmusic()
end

function _draw()
	rectfill(0, 42, 35, 47, 0)
	print("["..(lcpt-1).."/"..(npat-1).."]", 0, 42, 6)
	rectfill(0, 54, 23, 107, 0)
	for i=0, 3 do
		local val=pats[i]
		color(val ~= -1 and 6 or 5)
		print(i..") "..pats[i], 0, (i+9)*6)
	end
	for i=20, 23 do
		local val=stat(i)
		color(val ~= -1 and 6 or 5)
		print((i-20)..") "..val, 0, (i-6)*6)
	end
end

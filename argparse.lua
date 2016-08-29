-- Simple argument parser borrowed from OpenComputers
return function(...)
	local params = table.pack(...)
	local args = {}
	local options = {}
	local doneWithOptions = false
	for i = 1, params.n do
		local param = params[i]
		if not doneWithOptions and type(param) == "string" then
			if param == "--" then
				doneWithOptions = true
			elseif param:sub(1, 2) == "--" then
				if param:match("%-%-(.-)=") ~= nil then
					options[param:match("%-%-(.-)=")] = param:match("=(.*)")
				else
					options[param:sub(3)] = true
				end
			elseif param:sub(1, 1) == "-" and param ~= "-" then
				for j = 2, #param do
					options[param:sub(j, j)] = true
				end
			else
				table.insert(args, param)
			end
		else
			table.insert(args, param)
		end
	end
	return args, options
end

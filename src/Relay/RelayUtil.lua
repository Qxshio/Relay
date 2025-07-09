export type RelayModule = { any: (any) -> any }

export type RelayWhitelist = { any: (any) -> any }

export type PlayerGroup = { Player } | Player

--[=[
Includes useful shared resources

@class RelayUtil
]=]
local RelayUtil = { TAG_SET = "__SET" }

--[=[
Traverses a nested module/table structure using a dot-separated string path.

Given a string like `"Player.Inventory.Weapons"` and a root module table,
this function walks the path and returns the final table before the last key, along with the last key as a string.

Useful for dynamically accessing nested module properties based on a string input.

@within RelayUtil
@param stringPath string -- A dot-separated string representing the path to traverse (e.g., `"A.B.C"`)
@param module {} -- The root module or table to start the traversal from
@return  {}? -- The index at the end of the stringPath
]=]
function RelayUtil:getIndexValueFromString(stringPath: string, module: {})
	if not (typeof(stringPath) == "string") then
		warn(`Invalid string path ({stringPath})`)
		return
	end

	local current = module
	local path = string.split(stringPath, ".")

	for i = 1, #path - 1 do
		local key = path[i]

		if typeof(current) ~= "table" or current[key] == nil then
			warn(`Invalid path segment "{key}" at position {i} in path "{stringPath}"`)
			return
		end
		current = current[key]
	end

	return current[path[#path]]
end

return RelayUtil

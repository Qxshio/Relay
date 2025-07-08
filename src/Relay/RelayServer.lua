local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local remotesContainer: Folder
if RunService:IsRunning() and RunService:IsServer() then
	remotesContainer = Instance.new("Folder")
	remotesContainer.Name = "_comm"
	remotesContainer.Parent = script.Parent
end

local RelayUtil = require(script.Parent.RelayUtil)
local Sift = require(script.Parent.Packages.Sift)

type RelayModule = RelayUtil.RelayModule
type RelayWhitelist = RelayUtil.RelayWhitelist
type PlayerGroup = RelayUtil.PlayerGroup

--[=[
	RelayServer simplifies the usage of server-sided communication via establishing networking requests in service/module format.
    Inspired by leifstout

    @author Qxshio
	@class RelayServer  
]=]
local RelayServer = {}
RelayServer.__index = RelayServer

export type RelayServer = typeof(setmetatable(
	{} :: {
		GUID: string,
		_event: RemoteEvent,
		_func: RemoteFunction,
		_networkingTag: string,
		_instanceConn: RBXScriptSignal | nil,

		_referentialIntegrityFlag: (Player) -> (),

		remotes: Folder,
		instance: Instance | nil,
	},
	RelayServer
))

--[=[
	Constructs a new RelayServer instance

	@param GUID string | Instance -- The unique identifier for the RelayServer instance
	@param Module RelayModule -- The table of functions the client will be communicating with
	@param Whitelist RelayWhitelist? -- The methods that the client is allowed to call
	@return RelayServer  
]=]
function RelayServer.new(GUID: string | Instance, Module: RelayModule, Whitelist: RelayWhitelist?): RelayServer
	assert(
		GUID and (typeof(GUID) == "string" or typeof(GUID) == "Instance"),
		`Failed to create RelayServer as provided GUID ("{GUID}") is nil or not a valid GUID type (string | Instance)`
	)
	local self = setmetatable({ GUID = GUID }, RelayServer)

	assert(RunService:IsServer(), `RelayServer should only be ran on the server`)

	if not RunService:IsRunning() then
		return self
	end

	Whitelist = Whitelist or {}

	local remotes = Instance.new("Folder")
	local event = Instance.new("RemoteEvent")
	local func = Instance.new("RemoteFunction")
	event.Parent = remotes
	func.Parent = remotes

	self.remotes = remotes
	self._event = event
	self._func = func

	if typeof(self.GUID) == "Instance" then
		self.GUID = GUID.Name
		self.instance = GUID

		self._instanceConn = self.instance.Destroying:Once(function()
			self:Destroy()
		end)
	end

	assert(not remotesContainer:FindFirstChild(self.GUID), `GUID {GUID} already exists as a container`)
	remotes.Name = self.GUID
	remotes.Parent = remotesContainer

	local function eventCallback(player: Player, method: string, ...: any?): any?
		if method == RelayUtil.TAG_SET then
			self:setValueFromStringIndex(player, Module, Whitelist, ...)
			return
		end

		local moduleFunc = Module[method]
		if not moduleFunc then
			moduleFunc = method
		end

		if not moduleFunc then
			warn(`Method {method} does not exist in requested module: !({self.GUID})`)
			return
		end

		if
			not (
				typeof(moduleFunc) == "function" and table.find(Whitelist, moduleFunc)
				or self:propertyChangeAllowed(moduleFunc, Whitelist)
			)
		then
			warn(`Requested method {method} is not whitelisted on the server`)
			return
		end

		if typeof(moduleFunc) == "function" then
			return moduleFunc(player, ...)
		else
			local tree, lastKey = self:getModuleTreeFromString(moduleFunc, Module)
			return tree[lastKey]
		end
	end

	event.OnServerEvent:Connect(eventCallback)
	func.OnServerInvoke = eventCallback

	return self :: RelayServer
end

function RelayServer:propertyChangeAllowed(stringPath: string, Whitelist: {})
	local allowed = false

	for _, pattern in ipairs(Whitelist) do
		if not (typeof(pattern) == "string") then
			continue
		end

		local filteredPattern = "^" .. pattern:gsub("%.", "%%."):gsub("%*", ".*") .. "$"

		if string.match(stringPath, filteredPattern) then
			allowed = true
			break
		end
	end
	return Whitelist and allowed
end

function RelayServer:getModuleTreeFromString(stringPath: string, module: {})
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

	return current, path[#path]
end

--[=[
	Sets a value in a nested table structure using a dot-separated string path.

	This function navigates through the given `module` table according to `stringPath`,
	and sets the specified `value` at the targeted key. It optionally checks against
	a `Whitelist` of allowed path patterns to restrict which paths can be modified.
	
	If `RelayServer._referentialIntegrityFlag` is defined, it performs a type check to
	ensure the new value matches the existing value’s type, and triggers the flag function
	with the `Player` as argument if the types differ.

	@param Player Player -- The player attempting to set the value (used for integrity flagging)
	@param module table -- The root table to navigate and update
	@param Whitelist table? -- Optional list of allowed path patterns to restrict access
	@param ... any -- Additional arguments where the first is `stringPath` (dot-separated string path), and second is `value` to set
]=]
function RelayServer:setValueFromStringIndex(Player: Player, module: {}, Whitelist: {}?, ...)
	local args = { ... }
	local stringPath = args[1]
	local value = args[2]

	if not self:propertyChangeAllowed(stringPath, Whitelist) then
		warn(`Blocked unauthorized path: "{stringPath}"`)
		return
	end

	local path, lastKey = self:getModuleTreeFromString(stringPath, module)

	if typeof(path) == "table" then
		local old = path[lastKey]
		local flagFunc = self._referentialIntegrityFlag

		if flagFunc and old then
			local correctType = typeof(old)
			local newType = typeof(value)

			if not (newType == correctType) then
				task.spawn(flagFunc, Player)
				return
			end

			if correctType == "table" then
				local function map(t)
					return Sift.Dictionary.map(t, function(val)
						return typeof(val)
					end)
				end

				local t1 = map(old)
				local t2 = map(table.clone(path[lastKey]))

				if not (Sift.Dictionary.equals(t1, t2)) then
					task.spawn(flagFunc, Player)
					return
				end
				path = value
				return
			end
		end

		path[lastKey] = value
	else
		warn(`Cannot set value at path "{stringPath}", parent is not a table`)
	end
end

--[=[
	Sets a callback function to enforce referential integrity during value assignment.

	When a value is set via `setValueFromStringIndex`, this callback is invoked if the
	new value's type does not match the existing value's type at the target path.

	@param Callback (Player) -> () -- A function called with the Player when a type mismatch occurs
]=]
function RelayServer:enforceReferentialIntegrity(Callback: any?)
	self._referentialIntegrityFlag = Callback
		or function(Player: Player)
			warn(`Blocked type mismatch for {Player.UserId}`)
		end
end

--[=[
	Communicates to the provided client(s) using the given method and parameters (...)
    @param players PlayerGroup -- The players to include in the setting
    @param method string -- The method to call
    @param ... any? -- The parameters to call the method with

	@return ()  
]=]
function RelayServer:fire(players: PlayerGroup, method: string, ...: any?): ()
	if typeof(players) == "Instance" then
		self._event:FireClient(players, method, ...)
		return
	end

	for _, Player in players do
		self._event:FireClient(Player, method, ...)
	end
end

--[=[
	Communicates to all clients using the given method and parameters (...)
    @param method string -- The method to call
    @param ... any? -- The parameters to call the method with

	@return ()  
]=]
function RelayServer:fireAll(method: string, ...: any?): ()
	self._event:FireAllClients(method, ...)
end

--[=[
	Communicates to all clients except the players provided using the given method and parameters (...)
    @param players PlayerGroup -- The players to exclude in the setting
    @param method string -- The method to call
    @param ... any? -- The parameters to call the method with

	@return ()  
]=]
function RelayServer:fireAllExcept(players: PlayerGroup, method: string, ...: any?): ()
	for _, Player in Players:GetChildren() do
		if not table.find(players, Player) then
			self._event:FireClient(Player, method, ...)
		end
	end
end

--[=[
	Sets a value for all provided players
    @param players PlayerGroup -- The players to include in the setting
    @param index string -- The name of the value that will be set
    @param value any? -- The value to set index to

	@return ()  
]=]
function RelayServer:set(players: PlayerGroup, index: string, value: any)
	self:fire(players, RelayUtil.TAG_SET, index, value)
end

--[=[
	Sets a value for all players
    @param index string -- The name of the value that will be set
    @param value any? -- The value to set index to

	@return ()  
]=]
function RelayServer:setAll(index: string, value: any)
	self:fireAll(RelayUtil.TAG_SET, index, value)
end

--[=[
	Sets a value for all players except the provided players
    @param players PlayerGroup -- The players to exclude from the setting
    @param index string -- The name of the value that will be set
    @param value any? -- The value to set index to

	@return ()  
]=]
function RelayServer:setAllExcept(players: PlayerGroup, index: string, value: any)
	self:fireAllExcept(players, RelayUtil.TAG_SET, index, value)
end

--[=[
	Destroys the RelayServer  
	@return ()  
]=]
function RelayServer:destroy(): ()
	if self._instanceConn then
		self._instanceConn:Disconnect()
	end
	if self.instance then
		self.instance = nil
	end
	self.remotes:Destroy()
end

return RelayServer

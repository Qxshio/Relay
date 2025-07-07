local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local remotesContainer: Folder
if RunService:IsRunning() and RunService:IsServer() then
	remotesContainer = Instance.new("Folder")
	remotesContainer.Name = "_comm"
	remotesContainer.Parent = script.Parent
end

local RelayUtil = require(script.Parent.RelayUtil)

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
			warn(`Method {method} does not exist in requested module: !({self.GUID})`)
			return
		end

		if not table.find(Whitelist, moduleFunc) then
			warn(`Requested method {method} is not whitelisted on the server`)
			return
		end

		return moduleFunc(player, ...)
	end

	event.OnServerEvent:Connect(eventCallback)
	func.OnServerInvoke = eventCallback

	return self :: RelayServer
end

--[=[
	Sets a value in a nested table structure using a dot-separated string path.
	
	This function navigates through the given `module` table using the `stringPath`,
	and sets the specified `value` at the targeted key. It performs optional referential
	integrity checks to ensure that the type of the new value matches the existing one,
	if `RelayServer._referentialIntegrityFlag` is defined.

	@param Player Player -- The player attempting to set the value (used for integrity flagging)
	@param module table -- The root table to navigate and update
	@param stringPath string -- The dot-separated path indicating where to set the value
	@param value any -- The new value to assign at the specified path
]=]
function RelayServer:setValueFromStringIndex(Player: Player, module: {}, Whitelist: {}?, ...)
	local args = { ... }
	local stringPath = args[1]
	local value = args[2]

	if not (typeof(stringPath) == "string") then
		warn(`Invalid string path ({stringPath})`)
		return
	end

	if Whitelist then
		local allowed = false

		for _, pattern in ipairs(Whitelist) do
			local filteredPattern = "^"
				.. pattern:gsub("%%", "%%%%"):gsub("%.", "%%."):gsub("%*%*", ".+"):gsub("%*", "[^%.]+")
				.. "$"
			if string.match(stringPath, filteredPattern) then
				allowed = true
				break
			end
		end

		if not allowed then
			warn(`Blocked unauthorized path: "{stringPath}"`)
			return
		end
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

	local lastKey = path[#path]
	if typeof(current) == "table" then
		local old = current[lastKey]
		local flagFunc = self._referentialIntegrityFlag
		if flagFunc and old then
			local correctType = typeof(old)
			local newType = typeof(value)

			if not (correctType == newType) then
				task.spawn(flagFunc, Player)
				return
			end
		end

		current[lastKey] = value
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
function RelayServer:enforceReferentialIntegrity(Callback)
	self._referencialIntegrityFlag = Callback
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

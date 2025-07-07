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
		local moduleFunc = Module[method]

		if not moduleFunc then
			warn(`Method {method} does not exist in requested module: !({self._networkingTag})`)
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

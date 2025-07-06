local RunService = game:GetService("RunService")

local Packages = script.Parent.Packages
local Signal = require(Packages.Signal)

local RelayUtil = require(script.Parent.RelayUtil)

--[=[
	RelayClient simplifies the usage of client-sided communication via establishing networking requests in service/module format.
    Inspired by leifstout

    @author Qxshio
	@class RelayClient  
]=]
local RelayClient = { _changedSignals = {} }
RelayClient.__index = RelayClient

export type RelayClient = typeof(setmetatable(
	{} :: {
		_changedSignals: { [string]: Signal.Signal<any> },
		remotes: Folder,
		GUID: string,
	},
	RelayClient
))

--[=[
	Constructs a new RelayClient instance

	@param GUID string | Instance -- The unique identifier for the RelayClient instance
	@param Module RelayModule -- The table of functions the server will be communicating with
	@return RelayClient  
]=]
function RelayClient.new(GUID: string | Instance, module: {})
	assert(
		GUID and (typeof(GUID) == "string" or typeof(GUID) == "Instance"),
		`Failed to create RelayClient as provided GUID ("{GUID}") is nil or not a valid GUID type (string | Instance)`
	)
	assert(RunService:IsClient(), `RelayClient should only be ran on the client`)

	local self = setmetatable({
		GUID = GUID,
	}, RelayClient)

	if not RunService:IsRunning() then
		return self
	end

	if typeof(GUID) == "Instance" then
		self.GUID = GUID.Name
	end

	local remotes = script.Parent._comm:WaitForChild(self.GUID)
	self.remotes = remotes

	local remoteEvent = remotes.RemoteEvent

	remotes.Destroying:Once(function()
		self:destroy()
	end)

	remoteEvent.OnClientEvent:Connect(function(method: string, key: string, ...: any?)
		if method == RelayUtil.TAG_SET then
			local old = module[key]
			module[key] = ...
			if self._changedSignals[key] then
				self._changedSignals[key]:Fire(old, module[key])
			end
			return
		end

		assert(module[method], `Method "{method}" does not exist on GUID {remotes.Name}`)
		module[method](key, ...)
	end)
	return self
end

--[=[
	Retrieves and/or creates a Signal that is fired whenever the server changes any values on the client
    @param key string -- The value to listen to, should it be changed by the server

	@return Signal.Signal<any>
]=]
function RelayClient:getServerChangedSignal<T>(key: string): Signal.Signal<T>
	if not self._changedSignals[key] then
		self._changedSignals[key] = Signal.new()
	end

	return self._changedSignals[key]
end

--[=[
	Communicates to the server using the given method and parameters (...)
    @param method string -- The method to call
    @param ... any? -- The parameters to call the method with

	@return ()  
]=]
function RelayClient:fire(method: string, ...: any?): ()
	self.remotes.RemoteEvent:FireServer(method, ...)
end

--[=[
	Fetches the returned server method function value with the given parameters
    @param method string The method to call
    @param ... any? The parameters to call the method with

	@return ()  
]=]
function RelayClient:fetchAsync(method: string, ...: any?)
	return self.remotes.RemoteFunction:InvokeServer(method, ...)
end

--[=[
	Destoys the RelayClient

	@return ()  
]=]
function RelayClient:destroy()
	if self.remotes then
		self.remotes:Destroy()
	end
	for _, signal in self._changedSignals do
		signal:Destroy()
	end
end

return RelayClient

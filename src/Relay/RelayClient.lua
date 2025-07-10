local RunService = game:GetService("RunService")

local Packages = script.Parent.Packages
local Signal = require(Packages.Signal)

local RelayUtil = require(script.Parent.RelayUtil)

--[=[
RelayClient simplifies the usage of client-sided communication via establishing networking requests in service/module format.
Inspired by leifstout

@class RelayClient
]=]
local RelayClient = { _changedSignals = {}, RelayUtil = RelayUtil }
RelayClient.__index = RelayClient

export type RelayClient = typeof(setmetatable(
	{} :: {
		_changedSignals: { [string]: typeof(Signal) },
		remotes: Folder,
		GUID: string,
	},
	RelayClient
))

--[=[
Constructs a new RelayClient instance

@within RelayClient
@param GUID string | Instance -- The unique identifier for the RelayClient instance
@param module RelayModule -- The table of functions the server will be communicating with

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

	self.Module = module

	local remotes = script.Parent._comm:WaitForChild(self.GUID)
	self.remotes = remotes

	local remoteEvent = remotes.RemoteEvent

	remotes.Destroying:Once(function()
		self:destroy()
	end)

	remoteEvent.OnClientEvent:Connect(function(method: string, key: string, ...: any?)
		if method == RelayUtil.TAG_SET then
			local path, lastKey = RelayUtil:getIndexValueFromString(key, self.Module)
			local old = path[lastKey]
			path[lastKey] = ...

			if self._changedSignals[key] then
				self._changedSignals[key]:Fire(old, path[lastKey])
			end
			return
		end

		assert(self.Module[method], `Method "{method}" does not exist on GUID {remotes.Name}`)
		self.Module[method](self.Module, key, ...)
	end)
	return self
end

--[=[
Retrieves and/or creates a Signal that is fired whenever the server changes any values on the client
@param key string -- The value to listen to, should it be changed by the server

@within RelayClient
@return Signal
]=]
function RelayClient:getServerChangedSignal<T>(key: string)
	if not self._changedSignals[key] then
		self._changedSignals[key] = Signal.new()
	end

	return self._changedSignals[key] :: Signal.Signal<T>
end

--[=[
Communicates to the server using the given method and parameters (...)
@param method string -- The method to call
@param ... any? -- The parameters to call the method with

@within RelayClient
@return ()  
]=]
function RelayClient:fire(method: string, ...: any?): ()
	self.remotes.RemoteEvent:FireServer(method, ...)
end

--[=[
Fetches the returned server method function value with the given parameters
@param method string The method to call
@param ... any? The parameters to call the method with

@within RelayClient
@return ()  
]=]
function RelayClient:fetchAsync(method: string, ...: any?)
	return self.remotes.RemoteFunction:InvokeServer(method, ...)
end

--[=[
Sends a request to the server to update a value at a specified path.

@within RelayClient
@param path string -- The dot-separated path indicating where to set the value on the server
@param value any -- The new value to assign at the specified path
]=]
function RelayClient:postDataAsync(path: string, value: any)
	assert(path and value, `Path or value missing for setServerData`)
	assert(typeof(path) == "string", `Path "{path}" must be a string, e.g: Settings.MaxVolume`)
	self.remotes.RemoteFunction:InvokeServer(RelayUtil.TAG_SET, path, value)
end

--[=[
Sets a value in a nested table structure using a dot-separated string path.

This function navigates through the given `module` table according to `stringPath`,
and sets the specified `value` at the targeted key.

@within RelayClient
@param stringPath string -- The stringPath of the data you want to set
@param value any -- The new value to set the index
]=]
function RelayClient:setValueFromStringIndex(stringPath: string, value: any)
	local module = self.Module
	local path, lastKey = RelayUtil:getIndexValueFromString(stringPath, module)

	path[lastKey] = value
end

--[=[
Destoys the RelayClient

@within RelayClient
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

return RelayClient :: RelayClient

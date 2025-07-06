# Relay
### Last updated 06/07/2025
Simplifies the usage of server-to-client communication via establishing networking requests in service/module format. (similar to Knit)

## Installation

### Client
```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Relay = require(ReplicatedStorage.Relay)

local TestService = {Cash = 0}
TestService.__index = TestService

-- Creates TestService on the client
TestService.Relay = Relay.new("TestService", TestService)
```

### Server
```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Relay = require(ReplicatedStorage.Relay)

local TestService = {Cash = 500}
TestService.__index = TestService

function TestService:init()
     -- Creates "TestService" with the only whitelisted function being TestService:getCash()
     self.Relay = Relay.new("TestService", self, {self.getCash})
end
```

## Example
Retrieve cash from the server and store it on the client service

### Client
```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Relay = require(ReplicatedStorage.Relay)

local TestService = {Cash = 0}
TestService.__index = TestService

TestService._Relay = Relay.new("TestService", TestService)

function TestService:_init()
     self.Cash = self_Relay:fetchAsync("getCash") -- $500
end
```

### Server
```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Relay = require(ReplicatedStorage.Relay)

local TestService = {Cash = 500}
TestService.__index = TestService

function TestService:init()
     -- Creates "TestService" with the only whitelisted function being TestService:getCash()
     self.Relay = Relay.new("TestService", self, {self.getCash})
end

function TestService:getCash()
     return self.Cash
end
```

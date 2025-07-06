--[[

                              
--!  @                  @                                 Relay
   @@  @              @  @@                             06/07/2025
   @  @  @@        @@  @  @@                            By Qxshio
  @  @  @    @@@@    @  @  @     Simplifies the usage of server-to-client communication via
  @  @  @   @@@@@@   @  @  @     establishing networking requests in service/module format.
  @  @  @   @@@@@@   @  @  @  
  @  @  @            @  @  @                     https://github.com/Qxshio
   @  @  @    @@    @  @  @   
    @  @     @@@@     @  @    
     @      @@  @@      @     
            @@  @@            
           @@@  @@@           
           @@@  @@@@          
          @@@@  @@@@          
         @@        @@         
         @   @@@@   @         
        @@@@      @@@@        
       @@            @@ 

]]

local RunService = game:GetService("RunService")

local relayServer = require(script.RelayServer)
local relayClient = require(script.RelayClient)

return RunService:IsServer() and relayServer or relayClient

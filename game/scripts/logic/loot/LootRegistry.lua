--
-- Copyright (c) Uladzislau Nikalayevich <thenormalnij@gmail.com>. All rights reserved.
-- Licensed under the MIT license. See LICENSE file in the project root for details.
--

---@type CoopPlayers
local CoopPlayers = ModRequire "../CoopPlayers.lua"
---@type LootQuery
local LootQuery = ModRequire "LootQuery.lua"
---@type Log
local Log = ModRequire "../../utils/Log.lua"

---@alias LootRegistryState "pending" | "active" | "consumed" | "cancelled"
---@alias LootRegistrySource "room_reward" | "store" | "hermes_followup" | "bonus"

---@class LootRegistryEntry
---@field playerId number
---@field clickedByPlayer number|nil
---@field state LootRegistryState
---@field source LootRegistrySource
---@field rewardType string|nil

---@class LootRegistry
local LootRegistry = {}

---@return table<number, LootRegistryEntry>
local function getRegistry()
    local room = CurrentRun and CurrentRun.CurrentRoom
    if not room then
        return {}
    end
    if room.CoopLootRegistry == nil then
        room.CoopLootRegistry = {}
    end
    return room.CoopLootRegistry
end

---@return table<number, boolean>
local function getRoomClaims()
    local room = CurrentRun and CurrentRun.CurrentRoom
    if not room then
        return {}
    end
    if room.CoopLootClaims == nil then
        room.CoopLootClaims = {}
    end
    return room.CoopLootClaims
end

---@param objectId number
---@param playerId number
---@param source LootRegistrySource
---@param rewardType string|nil
---@param clickedByPlayer number|nil
function LootRegistry.Register(objectId, playerId, source, rewardType, clickedByPlayer)
    local registry = getRegistry()
    registry[objectId] = {
        playerId = playerId,
        clickedByPlayer = clickedByPlayer,
        state = "pending",
        source = source,
        rewardType = rewardType,
    }
end

---@param objectId number
---@return LootRegistryEntry | nil
function LootRegistry.Get(objectId)
    return getRegistry()[objectId]
end

---@param objectId number
function LootRegistry.Activate(objectId)
    local entry = getRegistry()[objectId]
    if entry then
        entry.state = "active"
    end
end

---@param objectId number
function LootRegistry.Consume(objectId)
    local entry = getRegistry()[objectId]
    if entry and (entry.state == "pending" or entry.state == "active") then
        entry.state = "consumed"
        if entry.source == "room_reward" then
            getRoomClaims()[entry.playerId] = true
            Log.Write(string.format(
                "TN_Coop:Registry CONSUME objectId=%s Assigned=%s ClickedBy=%s source=%s roomClaimSet=true counter=%s",
                tostring(objectId),
                tostring(entry.playerId),
                tostring(entry.clickedByPlayer),
                tostring(entry.source),
                tostring(CurrentRun and CurrentRun.CoopLootCounter)
            ))
        end
        LootQuery.CommitCounter(entry.playerId)
    else
        Log.Write(string.format(
            "TN_Coop:Registry CONSUME SKIP objectId=%s entry=%s state=%s",
            tostring(objectId),
            tostring(entry ~= nil),
            tostring(entry and entry.state)
        ))
    end
end

---@param objectId number
function LootRegistry.Cancel(objectId)
    local entry = getRegistry()[objectId]
    if entry and (entry.state == "pending" or entry.state == "active") then
        entry.state = "cancelled"
    end
end

---@param objectId number
function LootRegistry.Remove(objectId)
    getRegistry()[objectId] = nil
end

---@param objectId number
---@return table | nil
function LootRegistry.GetHero(objectId)
    local entry = getRegistry()[objectId]
    if entry then
        return CoopPlayers.GetHero(entry.playerId)
    end
    return nil
end

---@param objectId number
---@return number | nil
function LootRegistry.GetPlayerId(objectId)
    local entry = getRegistry()[objectId]
    if entry then
        return entry.playerId
    end
    return nil
end

---@return number
function LootRegistry.PendingCount()
    local count = 0
    for _, entry in pairs(getRegistry()) do
        if entry.state == "pending" or entry.state == "active" then
            count = count + 1
        end
    end
    return count
end

---@param playerId number
---@return boolean
function LootRegistry.HasRoomRewardClaim(playerId)
    -- Treat an active room reward as locked so the same player cannot re-enter
    -- the pickup flow before resolving or cancelling the open menu.
    if getRoomClaims()[playerId] == true then
        Log.Write(string.format(
            "TN_Coop:Registry HasClaim player=%s claimFromRoomClaims=true",
            tostring(playerId)
        ))
        return true
    end

    for _, entry in pairs(getRegistry()) do
        if entry.playerId == playerId and entry.source == "room_reward" and entry.state == "active" then
            Log.Write(string.format(
                "TN_Coop:Registry HasClaim player=%s claimFromActiveEntry=true",
                tostring(playerId)
            ))
            return true
        end
    end

    return false
end

function LootRegistry.SetClickedBy(objectId, clickedByPlayer)
    local entry = getRegistry()[objectId]
    if entry then
        entry.clickedByPlayer = clickedByPlayer
    end
end

function LootRegistry.CancelAllPending()
    for _, entry in pairs(getRegistry()) do
        if entry.state == "pending" or entry.state == "active" then
            entry.state = "cancelled"
        end
    end
end

function LootRegistry.ResetActiveToPending()
    for _, entry in pairs(getRegistry()) do
        if entry.state == "active" then
            entry.state = "pending"
        end
    end
end

function LootRegistry.RemoveAll()
    local room = CurrentRun and CurrentRun.CurrentRoom
    if room then
        room.CoopLootRegistry = {}
        room.CoopLootClaims = {}
    end
end

function LootRegistry.DebugPrint()
    local registry = getRegistry()
    local parts = {}
    for id, entry in pairs(registry) do
        table.insert(parts, string.format("[%s] id=%s player=%s state=%s source=%s",
            tostring(entry.rewardType or "?"), tostring(id),
            tostring(entry.playerId), entry.state, entry.source))
    end
    if #parts > 0 then
        Log.Write("CoopLootRegistry: " .. table.concat(parts, " | "))
    else
        Log.Write("CoopLootRegistry: (empty)")
    end
end

return LootRegistry

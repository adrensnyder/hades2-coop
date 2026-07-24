--
-- Copyright (c) Uladzislau Nikalayevich <thenormalnij@gmail.com>. All rights reserved.
-- Licensed under the MIT license. See LICENSE file in the project root for details.
--

---@type HeroContext
local HeroContext = ModRequire "../HeroContext.lua"
---@type CoopPlayers
local CoopPlayers = ModRequire "../CoopPlayers.lua"
---@type HeroContextProxyStore
local HeroContextProxyStore = ModRequire "../HeroContextProxyStore.lua"
---@type Events
local Events = ModRequire "../Events.lua"
---@type LootDeliveryCommon
local LootDeliveryCommon = ModRequire "LootDeliveryCommon.lua"
---@type LootQuery
local LootQuery = ModRequire "LootQuery.lua"
---@type LootRegistry
local LootRegistry = ModRequire "LootRegistry.lua"

---@class LootShared : ILootDelivery
local LootShared = {}

function LootShared.InitHooks()
    Events.run:on("newRunStarted", LootShared.Reset)
    Events.run:on("roomPreLeave", LootShared.OnRoomPreLeave)
    Events.run:on("mapLoaded", LootShared.OnMapLoaded)
end

---@param baseFun fun(run: table, room: table)
---@param run table
---@param room table
function LootShared.OnUnlockedRewardedRoom(baseFun, run, room)
    baseFun(run, room)
end

---@param baseFun fun(eventSource: table, args: table)
---@param eventSource table
---@param args table
function LootShared.SpawnRoomReward(baseFun, eventSource, args)
    local hero, ownerIndex = LootDeliveryCommon.SelectRewardHero()
    if not hero then
        return baseFun(eventSource, args)
    end
    return LootDeliveryCommon.SpawnRewardForHero(baseFun, eventSource, args, hero, ownerIndex)
end

function LootShared.Reset()
    HeroContextProxyStore.GetOrCreate(CurrentRun, "LootTypeHistory"):Reset()
    LootQuery.Reset()
    LootRegistry.RemoveAll()
end

---@param currentRun table
---@param door table
function LootShared.OnRoomPreLeave(currentRun, door)
    LootRegistry.CancelAllPending()
end

function LootShared.OnMapLoaded()
    LootRegistry.ResetActiveToPending()
end

---@param baseFun fun(args: table): table
---@param hero table
---@param args table
---@return table
function LootShared.GiveBlindLoot(baseFun, hero, args)
    return HeroContext.RunWithHeroContextReturn(hero, baseFun, args)
end

---@param baseFun fun(args: table): table
---@param args table
---@return table
function LootShared.GiveLoot(baseFun, args)
    return baseFun(args)
end

---@param loot table
---@param hero table
function LootShared.CanUseHeroLoot(loot, hero)
    if not loot or not hero then
        return false
    end

    local lootId = loot.ObjectId or loot.ObjectID or loot.Id
    if not lootId then
        return true
    end

    local entry = LootRegistry.Get(lootId)
    if not entry then
        return true
    end

    local playerId = CoopPlayers.GetPlayerByHero(hero)
    if not playerId then
        return false
    end

    return entry.playerId == playerId and entry.state ~= "consumed" and entry.state ~= "cancelled"
end

return LootShared

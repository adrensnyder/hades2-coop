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
---@type LootQuery
local LootQuery = ModRequire "LootQuery.lua"
---@type LootRegistry
local LootRegistry = ModRequire "LootRegistry.lua"
---@type CoopModConfig
local Config = ModRequire "../../config.lua"

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
    local room = CurrentRun.CurrentRoom

    local playerIndex = LootQuery.PeekNextHeroForLoot()
    local hero
    if playerIndex then
        hero = CoopPlayers.GetHero(playerIndex)
    else
        hero = CoopPlayers.GetAliveHeroes()[1] or CurrentRun.Hero
    end

    if hero.IsDead then
        local altIndex = LootQuery.PeekNextHeroForLoot()
        if altIndex then
            hero = CoopPlayers.GetHero(altIndex)
        else
            hero = CoopPlayers.GetAliveHeroes()[1]
            if not hero then
                DebugPrint { Text = "Cannot spawn a loot for a player. All players are dead" }
                return baseFun(eventSource, args)
            end
        end
    end

    local result = HeroContext.RunWithHeroContextAwait(hero, baseFun, eventSource, args)

    if result and result.ObjectId then
        local ownerIndex = playerIndex or CoopPlayers.GetPlayerByHero(hero) or 1
        LootRegistry.Register(result.ObjectId, ownerIndex, "room_reward", result.Name)
    end

    if Config.RewardMode == "Independent" then
        local firstOwnerIndex = playerIndex or CoopPlayers.GetPlayerByHero(hero) or 1
        local otherIndex = LootQuery.GetOtherPlayerIndex(firstOwnerIndex)
        if otherIndex and CoopPlayers.GetPlayersCount() >= 2 then
            local otherHero = CoopPlayers.GetHero(otherIndex)
            if otherHero and not otherHero.IsDead then
                local offsetArgs = MergeTables(args, { OffsetX = (args.OffsetX or 0) + 100 })
                local result2 = HeroContext.RunWithHeroContextAwait(otherHero, baseFun, eventSource, offsetArgs)
                if result2 and result2.ObjectId then
                    LootRegistry.Register(result2.ObjectId, otherIndex, "room_reward", result2.Name)
                end
            end
        end
    end

    return result
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

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

    local pendingRewards = CurrentRun.CoopPendingRoomRewards
    local pendingOwner
    if pendingRewards then
        for playerId in pairs(pendingRewards) do
            if not pendingOwner then
                pendingOwner = playerId
            end
        end
    end

    local playerIndex = pendingOwner or LootQuery.PeekNextHeroForLoot()
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

    local rewardDescriptor = pendingRewards and pendingRewards[playerIndex]
    local spawnArgs = args or {}
    if rewardDescriptor and rewardDescriptor.ChosenRewardType then
        spawnArgs = MergeTables(spawnArgs, {
            RewardOverride = rewardDescriptor.ChosenRewardType,
            LootName = rewardDescriptor.ForceLootName,
        })
    end
    local result = HeroContext.RunWithHeroContextAwait(hero, baseFun, eventSource, spawnArgs)
    if rewardDescriptor then
        DebugPrint { Text = string.format(
            "LootDelivery: player=%s reward=%s object=%s",
            tostring(playerIndex), tostring(rewardDescriptor.ChosenRewardType),
            tostring(result and result.ObjectId)
        ) }
    end

    if result and result.ObjectId then
        local ownerIndex = playerIndex or CoopPlayers.GetPlayerByHero(hero) or 1
        LootRegistry.Register(result.ObjectId, ownerIndex, "room_reward", result.Name)
    end

    if Config.RewardMode == "Independent" then
        local firstOwnerIndex = playerIndex or CoopPlayers.GetPlayerByHero(hero) or 1
        local otherIndex = LootQuery.GetOtherPlayerIndex(firstOwnerIndex)
        if pendingRewards then
            otherIndex = nil
            for candidateId in pairs(pendingRewards) do
                if candidateId ~= firstOwnerIndex then
                    otherIndex = candidateId
                    break
                end
            end
        end
        if otherIndex and CoopPlayers.GetPlayersCount() >= 2 then
            local otherHero = CoopPlayers.GetHero(otherIndex)
            if otherHero and not otherHero.IsDead then
                local offset = { X = 100, Y = 0 }
                if result and result.ObjectId and otherHero.ObjectId then
                    local angle = GetAngleBetween({
                        Id = result.ObjectId,
                        DestinationId = otherHero.ObjectId,
                    })
                    offset = CalcOffset(math.rad(angle + 180), 110)
                end

                local offsetArgs = MergeTables(spawnArgs, {
                    SpawnRewardOnId = result and result.ObjectId,
                    OffsetX = offset.X,
                    OffsetY = offset.Y,
                })
                local otherDescriptor = pendingRewards and pendingRewards[otherIndex]
                if otherDescriptor and otherDescriptor.ChosenRewardType then
                    offsetArgs = MergeTables(offsetArgs, {
                        RewardOverride = otherDescriptor.ChosenRewardType,
                        LootName = otherDescriptor.ForceLootName,
                    })
                end
                local result2 = HeroContext.RunWithHeroContextAwait(otherHero, baseFun, eventSource, offsetArgs)
                if otherDescriptor then
                    DebugPrint { Text = string.format(
                        "LootDelivery: player=%s reward=%s object=%s",
                        tostring(otherIndex), tostring(otherDescriptor.ChosenRewardType),
                        tostring(result2 and result2.ObjectId)
                    ) }
                end
                if result2 and result2.ObjectId then
                    LootRegistry.Register(result2.ObjectId, otherIndex, "room_reward", result2.Name)
                end
            end
        end
    end

    if pendingRewards then
        CurrentRun.CoopPendingRoomRewards = nil
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
    return true
end

return LootShared

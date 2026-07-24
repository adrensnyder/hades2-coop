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

local function copyTable(source)
    local result = {}
    if source then
        for key, value in pairs(source) do
            result[key] = value
        end
    end
    return result
end

---@param baseFun fun(eventSource: table, args: table)
---@param eventSource table
---@param hero table
---@param ownerIndex number|nil
---@param spawnArgs table
---@param rewardDescriptor table|nil
---@param anchorObjectId number|nil
---@return table|nil
local function spawnRewardForHero(baseFun, eventSource, hero, ownerIndex, spawnArgs, rewardDescriptor, anchorObjectId)
    local resolvedOwnerIndex = ownerIndex or CoopPlayers.GetPlayerByHero(hero) or 1
    local heroArgs = copyTable(spawnArgs)
    if anchorObjectId then
        heroArgs.SpawnRewardOnId = anchorObjectId
    end
    if rewardDescriptor and rewardDescriptor.ChosenRewardType then
        heroArgs.RewardOverride = rewardDescriptor.ChosenRewardType
        heroArgs.LootName = rewardDescriptor.ForceLootName
    end

    local result = HeroContext.RunWithHeroContextAwait(hero, baseFun, eventSource, heroArgs)
    if result and result.ObjectId then
        LootRegistry.Register(result.ObjectId, resolvedOwnerIndex, "room_reward", result.Name)
    end
    return result
end

---@param baseFun fun(eventSource: table, args: table)
---@param eventSource table
---@param hero table
---@param ownerIndex number|nil
---@param templateArgs table
---@param rewardDescriptor table|nil
---@param templateResult table|nil
---@return table|nil
local function duplicateRewardForHero(baseFun, eventSource, hero, ownerIndex, templateArgs, rewardDescriptor, templateResult)
    if not hero then
        return nil
    end

    local resolvedOwnerIndex = ownerIndex or CoopPlayers.GetPlayerByHero(hero) or 1
    local duplicateArgs = copyTable(templateArgs)
    if templateResult and templateResult.ObjectId and hero.ObjectId then
        local angle = GetAngleBetween({
            Id = templateResult.ObjectId,
            DestinationId = hero.ObjectId,
        })
        local offset = CalcOffset(math.rad(angle + 180), 110)
        duplicateArgs.SpawnRewardOnId = templateResult.ObjectId
        duplicateArgs.OffsetX = offset.X
        duplicateArgs.OffsetY = offset.Y
    end

    local result = spawnRewardForHero(
        baseFun,
        eventSource,
        hero,
        resolvedOwnerIndex,
        duplicateArgs,
        rewardDescriptor,
        duplicateArgs.SpawnRewardOnId
    )
    if result and result.ObjectId then
        DebugPrint { Text = string.format(
            "LootDelivery: duplicated fallback reward for player=%s object=%s",
            tostring(resolvedOwnerIndex), tostring(result.ObjectId)
        ) }
    end
    return result
end

function LootShared.InitHooks()
    Events.run:on("newRunStarted", LootShared.Reset)
    Events.run:on("roomPreLeave", LootShared.OnRoomPreLeave)
    Events.run:on("mapLoaded", LootShared.OnMapLoaded)
end

---@param baseFun fun(run: table, room: table)
---@param run table
---@param room table
function LootShared.OnUnlockedRewardedRoom(baseFun, run, room)
    DebugPrint { Text = string.format(
        "TN_Coop:Loot OnUnlockedRewardedRoom room=%s",
        tostring(room and (room.GenusName or room.Name))
    ) }
    baseFun(run, room)
end

---@param baseFun fun(eventSource: table, args: table)
---@param eventSource table
---@param args table
function LootShared.SpawnRoomReward(baseFun, eventSource, args)
    local pendingRewards = CurrentRun.CoopPendingRoomRewards
    local pendingCount = 0
    local pendingOwner
    if pendingRewards then
        for playerId in pairs(pendingRewards) do
            pendingCount = pendingCount + 1
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

    DebugPrint { Text = string.format(
        "LootDelivery: spawn start mode=%s player=%s pending=%s players=%s",
        tostring(Config.RewardMode),
        tostring(playerIndex),
        tostring(pendingCount),
        tostring(CoopPlayers.GetPlayersCount())
    ) }

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
    local primarySpawnArgs = args or {}
    local result = spawnRewardForHero(
        baseFun,
        eventSource,
        hero,
        playerIndex,
        primarySpawnArgs,
        rewardDescriptor,
        nil
    )
    if rewardDescriptor then
        DebugPrint { Text = string.format(
            "LootDelivery: player=%s reward=%s object=%s",
            tostring(playerIndex), tostring(rewardDescriptor.ChosenRewardType),
            tostring(result and result.ObjectId)
        ) }
    end

    local finalResult = result
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
                local otherDescriptor = pendingRewards and pendingRewards[otherIndex]
                DebugPrint { Text = string.format(
                    "LootDelivery: spawn second candidate player=%s hero=%s descriptor=%s",
                    tostring(otherIndex),
                    tostring(otherHero.ObjectId),
                    tostring(otherDescriptor and otherDescriptor.ChosenRewardType)
                ) }
                local otherSpawnArgs = copyTable(primarySpawnArgs)
                if result and result.ObjectId and otherHero.ObjectId then
                    local angle = GetAngleBetween({
                        Id = result.ObjectId,
                        DestinationId = otherHero.ObjectId,
                    })
                    local offset = CalcOffset(math.rad(angle + 180), 110)
                    otherSpawnArgs.SpawnRewardOnId = result.ObjectId
                    otherSpawnArgs.OffsetX = offset.X
                    otherSpawnArgs.OffsetY = offset.Y
                end
                local otherResult = spawnRewardForHero(
                    baseFun,
                    eventSource,
                    otherHero,
                    otherIndex,
                    otherSpawnArgs,
                    otherDescriptor,
                    otherSpawnArgs.SpawnRewardOnId
                )
                if otherDescriptor then
                    DebugPrint { Text = string.format(
                        "LootDelivery: player=%s reward=%s object=%s",
                        tostring(otherIndex), tostring(otherDescriptor.ChosenRewardType),
                        tostring(otherResult and otherResult.ObjectId)
                    ) }
                end
                if result and result.ObjectId and (not otherResult or not otherResult.ObjectId) then
                    DebugPrint { Text = string.format(
                        "LootDelivery: second reward missing, duplicating primary for player=%s",
                        tostring(otherIndex)
                    ) }
                    local duplicateResult = duplicateRewardForHero(
                        baseFun,
                        eventSource,
                        otherHero,
                        otherIndex,
                        primarySpawnArgs,
                        rewardDescriptor,
                        result
                    )
                    if not duplicateResult or not duplicateResult.ObjectId then
                        DebugPrint { Text = string.format(
                            "LootDelivery: fallback duplication failed for player=%s",
                            tostring(otherIndex)
                        ) }
                    end
                elseif (not result or not result.ObjectId) and otherResult and otherResult.ObjectId then
                    finalResult = otherResult
                    DebugPrint { Text = string.format(
                        "LootDelivery: first reward missing, duplicating secondary for player=%s",
                        tostring(playerIndex or firstOwnerIndex)
                    ) }
                    local duplicateResult = duplicateRewardForHero(
                        baseFun,
                        eventSource,
                        hero,
                        playerIndex or firstOwnerIndex,
                        otherSpawnArgs,
                        otherDescriptor,
                        otherResult
                    )
                    if not duplicateResult or not duplicateResult.ObjectId then
                        DebugPrint { Text = string.format(
                            "LootDelivery: fallback duplication failed for player=%s",
                            tostring(playerIndex or firstOwnerIndex)
                        ) }
                    end
                end
            end
        end
    end

    if pendingRewards then
        CurrentRun.CoopPendingRoomRewards = nil
    end

    return finalResult
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
    if not loot or not loot.ObjectId then
        return true
    end
    if not hero then
        return false
    end

    local ownerPlayerId = LootRegistry.GetPlayerId(loot.ObjectId)
    if not ownerPlayerId then
        return true
    end

    return CoopPlayers.GetPlayerByHero(hero) == ownerPlayerId
end

return LootShared

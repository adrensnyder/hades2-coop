--
-- Copyright (c) Uladzislau Nikalayevich <thenormalnij@gmail.com>. All rights reserved.
-- Licensed under the MIT license. See LICENSE file in the project root for details.
--

---@type SimpleHook
local SimpleHook = ModRequire "../utils/SimpleHook.lua"
---@type HeroContextProxy
local HeroContextProxy = ModRequire "../logic/HeroContextProxy.lua"
---@type HeroContextProxyStore
local HeroContextProxyStore = ModRequire "../logic/HeroContextProxyStore.lua"
---@type Events
local Events = ModRequire "../logic/Events.lua"
---@type CoopPlayers
local CoopPlayers = ModRequire "../logic/CoopPlayers.lua"
---@type HeroContext
local HeroContext = ModRequire "../logic/HeroContext.lua"
---@type HookUtils
local HookUtils = ModRequire "../utils/HookUtils.lua"
---@type RunEx
local RunEx = ModRequire "../logic/RunEx.lua"

---@type ILootDelivery
local LootDelivery = ModRequire "../logic/loot/LootInterface.lua"
---@type LootRegistry
local LootRegistry = ModRequire "../logic/loot/LootRegistry.lua"

---@class LootHooks : SimpleHook
local LootHooks = SimpleHook.New()

function LootHooks.wrap.UnwrapRandomLoot(baseFun, ...)
    local hero = CurrentRun.Hero
    local playerId = CoopPlayers.GetPlayerByHero(hero)

    DebugPrint { Text = string.format(
        "TN_Coop:Loot UnwrapRandomLoot player=%s hero=%s",
        tostring(playerId),
        tostring(hero and hero.ObjectId)
    ) }

    baseFun(...)

    for lootId, lootData in pairs(LootObjects) do
        if not lootData.Cost then
            if playerId then
                LootRegistry.Register(lootId, playerId, "store", lootData.Name)
            end
            DebugPrint { Text = string.format(
                "TN_Coop:Loot UnwrapRandomLoot lootId=%s reward=%s",
                tostring(lootId),
                tostring(lootData.Name)
            ) }
            CoopUseItem(hero.ObjectId, lootId)
            break
        end
    end
end

function LootHooks.InitEngineHooks()
    Events.run:on("newRunStarted", LootHooks.InitLootHistoryProxy)

    if CurrentRun then
        LootHooks.InitLootHistoryProxy()
    end
end

---@private
function LootHooks.InitLootHistoryProxy()
    local proxyHandler = HeroContextProxy.New(CurrentRun, "LootTypeHistory")
    HeroContextProxyStore.Set("LootTypeHistory", proxyHandler)
end

---@private
function LootHooks.wrap.GiveLoot(baseFun, args)
    local hero = nil

    if args and args.SpawnPoint then
        hero = LootRegistry.GetHero(args.SpawnPoint)
    end

    if hero then
        return HeroContext.RunWithHeroContextReturn(hero, baseFun, args)
    else
        return baseFun(args)
    end
end

---@private
-- Select a player for room reward
function LootHooks.wrap.DoUnlockRoomExits(baseFun, run, room)
    local needsRewards = LootHooks.NeedsCurrentRoomExitRewards(run)
    DebugPrint { Text = string.format(
        "TN_Coop:Loot DoUnlockRoomExits room=%s needsRewards=%s",
        tostring(room and (room.GenusName or room.Name)),
        tostring(needsRewards)
    ) }

    if not needsRewards then
        return baseFun(run, room)
    end

    LootDelivery.OnUnlockedRewardedRoom(baseFun, run, room)
end

---@private
function LootHooks.wrap.SpawnRoomReward(baseFun, ...)
    -- Fix #16
    CurrentRun.CurrentRoom.DisableRewardMagnetisim = true

    DebugPrint { Text = string.format(
        "TN_Coop:Loot SpawnRoomReward room=%s",
        tostring(CurrentRun and CurrentRun.CurrentRoom and (CurrentRun.CurrentRoom.GenusName or CurrentRun.CurrentRoom.Name))
    ) }

    local result = LootDelivery.SpawnRoomReward(baseFun, ...)
    DebugPrint { Text = string.format(
        "TN_Coop:Loot SpawnRoomReward result=%s object=%s",
        tostring(result and result.Name),
        tostring(result and result.ObjectId)
    ) }
    return result
end

---@private
function LootHooks.InitGameHooks()
    HookUtils.wrap("HandleUpgradeChoiceSelection", function(baseFun, screen, button, args)
        local source = screen and screen.Source
        local entry = source and source.ObjectId and LootRegistry.Get(source.ObjectId)
        if source and source.ObjectId then
            LootRegistry.Activate(source.ObjectId)
        end
        DebugPrint { Text = string.format(
            "TN_Coop:Loot HandleUpgradeChoiceSelection start object=%s entrySource=%s pending=%s",
            tostring(source and source.ObjectId),
            tostring(entry and entry.source),
            tostring(LootRegistry.PendingCount())
        ) }
        local ok, result = pcall(baseFun, screen, button, args)
        if ok then
            if source and source.ObjectId then
                LootRegistry.Consume(source.ObjectId)
                DebugPrint { Text = string.format(
                    "TN_Coop:Loot HandleUpgradeChoiceSelection consumed object=%s pending=%s",
                    tostring(source.ObjectId),
                    tostring(LootRegistry.PendingCount())
                ) }
                if entry and entry.source == "room_reward" and LootRegistry.PendingCount() == 0 then
                    DebugPrint { Text = string.format(
                        "TN_Coop:Loot HandleUpgradeChoiceSelection remove default door rewards object=%s",
                        tostring(source.ObjectId)
                    ) }
                    DebugPrint { Text = string.format(
                        "TN_Coop:Loot default door rewards before clear room=%s",
                        tostring(CurrentRun and CurrentRun.CurrentRoom and (CurrentRun.CurrentRoom.GenusName or CurrentRun.CurrentRoom.Name))
                    ) }
                    RunEx.RemoveRewardFromAllDefaultDoors()
                    DebugPrint { Text = string.format(
                        "TN_Coop:Loot default door rewards after clear room=%s",
                        tostring(CurrentRun and CurrentRun.CurrentRoom and (CurrentRun.CurrentRoom.GenusName or CurrentRun.CurrentRoom.Name))
                    ) }
                end
            end
        else
            DebugPrint { Text = "HandleUpgradeChoiceSelection error: " .. tostring(result) }
            if source and source.ObjectId then
                LootRegistry.Cancel(source.ObjectId)
            end
        end
        return result
    end)

    HookUtils.wrap("CloseUpgradeChoiceScreen", function(baseFun, screen, button)
        local source = screen and screen.Source
        if source and source.ObjectId then
            local entry = LootRegistry.Get(source.ObjectId)
            if entry and entry.state == "active" then
                LootRegistry.Cancel(source.ObjectId)
            end
        end
        return baseFun(screen, button)
    end)
end

--- Warning: this function mutates the game state in ChooseNextRoomData
---@private
---@param run table
function LootHooks.NeedsCurrentRoomExitRewards(run)
    local roomData = ChooseNextRoomData(run)

    DebugPrint { Text = string.format(
        "TN_Coop:Loot NeedsCurrentRoomExitRewards roomData=%s noReward=%s noReroll=%s",
        tostring(roomData and (roomData.GenusName or roomData.Name)),
        tostring(roomData and roomData.NoReward),
        tostring(roomData and roomData.NoReroll)
    ) }

    if roomData == nil then
        return false
    end

    if roomData.NoReward then
        return false
    end

    if roomData.NoReroll then
        return false
    end

    return true
end

return LootHooks

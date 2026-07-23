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

---@type ILootDelivery
local LootDelivery = ModRequire "../logic/loot/LootInterface.lua"
---@type LootRegistry
local LootRegistry = ModRequire "../logic/loot/LootRegistry.lua"

---@class LootHooks : SimpleHook
local LootHooks = SimpleHook.New()

function LootHooks.wrap.UnwrapRandomLoot(baseFun, ...)
    local hero = CurrentRun.Hero
    local playerId = CoopPlayers.GetPlayerByHero(hero)

    baseFun(...)

    for lootId, lootData in pairs(LootObjects) do
        if not lootData.Cost then
            if playerId then
                LootRegistry.Register(lootId, playerId, "store", lootData.Name)
            end
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
    if not LootHooks.NeedsCurrentRoomExitRewards(run) then
        return baseFun(run, room)
    end

    LootDelivery.OnUnlockedRewardedRoom(baseFun, run, room)
end

---@private
function LootHooks.wrap.SpawnRoomReward(baseFun, ...)
    -- Fix #16
    CurrentRun.CurrentRoom.DisableRewardMagnetisim = true

    return LootDelivery.SpawnRoomReward(baseFun, ...)
end

---@private
function LootHooks.InitGameHooks()
    HookUtils.wrap("HandleUpgradeChoiceSelection", function(baseFun, screen, button, args)
        local source = screen and screen.Source
        if source and source.ObjectId then
            LootRegistry.Consume(source.ObjectId)
        end
        local ok, result = pcall(baseFun, screen, button, args)
        if not ok then
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

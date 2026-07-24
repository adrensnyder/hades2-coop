--
-- Copyright (c) Uladzislau Nikalayevich <thenormalnij@gmail.com>. All rights reserved.
-- Licensed under the MIT license. See LICENSE file in the project root for details.
--

---@type HeroContext
local HeroContext = ModRequire "../HeroContext.lua"
---@type CoopPlayers
local CoopPlayers = ModRequire "../CoopPlayers.lua"
---@type LootQuery
local LootQuery = ModRequire "LootQuery.lua"
---@type LootRegistry
local LootRegistry = ModRequire "LootRegistry.lua"
---@type Log
local Log = ModRequire "../../utils/Log.lua"

---@class LootDeliveryCommon
local LootDeliveryCommon = {}

---@param ownerIndex number
---@param preSnapshot table<number, boolean>
local function RegisterNewLoots(ownerIndex, preSnapshot)
    local hero = CoopPlayers.GetHero(ownerIndex)
    for lootId, lootData in pairs(LootObjects) do
        if not preSnapshot[lootId] and not LootRegistry.Get(lootId) then
            if lootData and lootData.ObjectId and lootData.OnUsedFunctionName == "UseLoot" then
                if hero then
                    lootData.UsedByHero = hero
                end
                LootRegistry.Register(lootData.ObjectId, ownerIndex, "room_reward", lootData.Name, lootData.CoopClickedByPlayer)
                Log.Write(string.format(
                    "TN_Coop:SpawnRoomReward registered bonus loot objectId=%s name=%s player=%s",
                    tostring(lootData.ObjectId),
                    tostring(lootData.Name),
                    tostring(ownerIndex)
                ))
            end
        end
    end
end

---@return table | nil hero
---@return number | nil ownerIndex
function LootDeliveryCommon.SelectRewardHero()
    local playerIndex = LootQuery.PeekNextHeroForLoot()
    local hero
    if playerIndex then
        hero = CoopPlayers.GetHero(playerIndex)
    else
        hero = CoopPlayers.GetAliveHeroes()[1] or CurrentRun.Hero
    end

    if hero and hero.IsDead then
        local altIndex = LootQuery.PeekNextHeroForLoot()
        if altIndex then
            hero = CoopPlayers.GetHero(altIndex)
        else
            hero = CoopPlayers.GetAliveHeroes()[1]
            if not hero then
                DebugPrint { Text = "Cannot spawn a loot for a player. All players are dead" }
                return nil
            end
        end
    end

    local ownerIndex = playerIndex or CoopPlayers.GetPlayerByHero(hero) or 1
    return hero, ownerIndex
end

---@param baseFun fun(eventSource: table, args: table)
---@param eventSource table
---@param args table
---@param hero table
---@param ownerIndex number
---@return table
function LootDeliveryCommon.SpawnRewardForHero(baseFun, eventSource, args, hero, ownerIndex)
    local preSnapshot = {}
    for id in pairs(LootObjects) do
        preSnapshot[id] = true
    end

    local room = CurrentRun and CurrentRun.CurrentRoom
    local previousOwner = room and room.CoopPendingRewardOwner
    if room then
        room.CoopPendingRewardOwner = ownerIndex
        room.CoopPendingRewardClickedBy = nil
    end

    local ok, result = pcall(HeroContext.RunWithHeroContextAwait, hero, baseFun, eventSource, args)

    if room then
        room.CoopPendingRewardOwner = previousOwner
    end

    if ok and result and result.ObjectId then
        local clickedByPlayer = room and room.CoopPendingRewardClickedBy or result.CoopClickedByPlayer
        Log.Write(string.format(
            "TN_Coop:SpawnRoomReward objectId=%s owner=%s hero=%s user=%s",
            tostring(result.ObjectId),
            tostring(ownerIndex),
            tostring(hero and hero.ObjectId),
            tostring(clickedByPlayer)
        ))
        result.UsedByHero = hero
        LootRegistry.Register(result.ObjectId, ownerIndex, "room_reward", result.Name, clickedByPlayer)
    end

    if not ok then
        error(result, 0)
    end

    RegisterNewLoots(ownerIndex, preSnapshot)

    return result
end

return LootDeliveryCommon

--
-- Copyright (c) Uladzislau Nikalayevich <thenormalnij@gmail.com>. All rights reserved.
-- Licensed under the MIT license. See LICENSE file in the project root for details.
--

---@type LootShared
local LootShared = ModRequire "LootShared.lua"
---@type LootDeliveryCommon
local LootDeliveryCommon = ModRequire "LootDeliveryCommon.lua"
---@type CoopPlayers
local CoopPlayers = ModRequire "../CoopPlayers.lua"
---@type LootQuery
local LootQuery = ModRequire "LootQuery.lua"

---@class LootIndependent : ILootDelivery
local LootIndependent = setmetatable({}, { __index = LootShared })

---@param baseFun fun(eventSource: table, args: table)
---@param eventSource table
---@param args table
function LootIndependent.SpawnRoomReward(baseFun, eventSource, args)
    local hero, ownerIndex = LootDeliveryCommon.SelectRewardHero()
    if not hero then
        return baseFun(eventSource, args)
    end

    local result = LootDeliveryCommon.SpawnRewardForHero(baseFun, eventSource, args, hero, ownerIndex)

    local otherIndex = LootQuery.GetOtherPlayerIndex(ownerIndex)
    if otherIndex and CoopPlayers.GetPlayersCount() >= 2 then
        local otherHero = CoopPlayers.GetHero(otherIndex)
        if otherHero and not otherHero.IsDead then
            local offsetArgs = MergeTables(args or {}, { OffsetX = ((args and args.OffsetX) or 0) + 100 })
            LootDeliveryCommon.SpawnRewardForHero(baseFun, eventSource, offsetArgs, otherHero, otherIndex)
        end
    end

    return result
end

return LootIndependent

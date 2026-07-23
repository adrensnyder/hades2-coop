--
-- Copyright (c) Uladzislau Nikalayevich <thenormalnij@gmail.com>. All rights reserved.
-- Licensed under the MIT license. See LICENSE file in the project root for details.
--

---@type CoopPlayers
local CoopPlayers = ModRequire "../CoopPlayers.lua"

---@class LootQuery
local LootQuery = {}

function LootQuery.Reset()
    CurrentRun.CoopLootCounter = CurrentRun.CoopLootCounter or RandomInt(1, CoopPlayers.GetPlayersCount())
end

--- Peek at the next hero without advancing the counter.
---@return number | nil
function LootQuery.PeekNextHeroForLoot()
    local playersCount = CoopPlayers.GetPlayersCount()
    if playersCount <= 1 then
        return
    end

    local startPos = CurrentRun.CoopLootCounter
    local playerIndex = startPos + 1
    while true do
        if playerIndex > playersCount then
            playerIndex = 1
        end

        if playerIndex == startPos then
            return
        end

        local hero = CoopPlayers.GetHero(playerIndex)
        if not hero.IsDead then
            return playerIndex
        end

        playerIndex = playerIndex + 1
    end
end

--- Advance the counter after a reward is committed (consumed or granted).
---@param playerId number
function LootQuery.CommitCounter(playerId)
    CurrentRun.CoopLootCounter = playerId
end

--- Get an alive player other than the excluded player.
---@param excludedPlayerId number|nil
---@return number | nil
function LootQuery.GetOtherPlayerIndex(excludedPlayerId)
    local playersCount = CoopPlayers.GetPlayersCount()
    if playersCount <= 1 then
        return
    end

    local current = CurrentRun.CoopLootCounter
    for offset = 1, playersCount do
        local playerId = current + offset
        if playerId > playersCount then
            playerId = playerId - playersCount
        end

        local hero = CoopPlayers.GetHero(playerId)
        if playerId ~= excludedPlayerId and hero and not hero.IsDead then
            return playerId
        end
    end

    return nil
end

--- Legacy: peek + commit in one call. Kept for backward compatibility.
---@return number | nil
function LootQuery.UseNextHeroForLoot()
    local playerIndex = LootQuery.PeekNextHeroForLoot()
    if playerIndex then
        CurrentRun.CoopLootCounter = playerIndex
    end
    return playerIndex
end

return LootQuery

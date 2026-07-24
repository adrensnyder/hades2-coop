--
-- Copyright (c) Uladzislau Nikalayevich <thenormalnij@gmail.com>. All rights reserved.
-- Licensed under the MIT license. See LICENSE file in the project root for details.
--

---@type CoopPlayers
local CoopPlayers = ModRequire "../logic/CoopPlayers.lua"
---@type HeroContext
local HeroContext = ModRequire "../logic/HeroContext.lua"
---@type SimpleHook
local SimpleHook = ModRequire "../utils/SimpleHook.lua"
---@type Events
local Events = ModRequire "../logic/Events.lua"
---@type LootRegistry
local LootRegistry = ModRequire "../logic/loot/LootRegistry.lua"
---@type Log
local Log = ModRequire "../utils/Log.lua"

local InteractLogicHooks = SimpleHook.New()

---@param item table
---@param fallbackHero table
---@return table
local function resolveHero(item, fallbackHero)
    if item and item.ObjectId then
        local hero = LootRegistry.GetHero(item.ObjectId)
        if hero then
            return hero
        end
    end
    return fallbackHero
end

function InteractLogicHooks.wrap.UseLoot(baseFun, usee, args, user)
    if usee and usee.ObjectId then
        local entry = LootRegistry.Get(usee.ObjectId)
        local userIsHero = type(user) == "table"
        local playerId = userIsHero and CoopPlayers.GetPlayerByHero(user) or nil
        local room = CurrentRun and CurrentRun.CurrentRoom

        if not playerId and userIsHero then
            for pid = 1, CoopPlayers.GetPlayersCount() do
                if CoopPlayers.GetHero(pid) == user then
                    playerId = pid
                    break
                end
            end
        end

        if not playerId then
            playerId = CoopPlayers.GetCurrentPlayerId()
        end

        usee.CoopClickedByPlayer = playerId
        if room then
            room.CoopPendingRewardClickedBy = playerId
        end

        local assignedPlayer = entry and entry.playerId or (room and room.CoopPendingRewardOwner)

        if userIsHero and usee.UsedByHero and usee.UsedByHero ~= user then
            Log.Write(string.format(
                "TN_Coop:UseLoot BLOCKED ownerMismatch objectId=%s userPlayer=%s",
                tostring(usee.ObjectId),
                tostring(playerId)
            ))
            return false
        end

        if entry then
            Log.Write(string.format(
                "TN_Coop:UseLoot objectId=%s source=%s state=%s entryPlayer=%s userPlayer=%s userIsHero=%s",
                tostring(usee.ObjectId),
                tostring(entry.source),
                tostring(entry.state),
                tostring(entry.playerId),
                tostring(playerId),
                tostring(userIsHero)
            ))
            if entry.source == "room_reward" then
                if playerId and assignedPlayer and playerId ~= assignedPlayer then
                    Log.Write(string.format(
                        "TN_Coop:UseLoot BLOCKED objectId=%s Assigned=%s ClickedBy=%s",
                        tostring(usee.ObjectId),
                        tostring(assignedPlayer),
                        tostring(playerId)
                    ))
                    return false
                end
                if playerId and LootRegistry.HasRoomRewardClaim(playerId) then
                    Log.Write(string.format(
                        "TN_Coop:UseLoot BLOCKED objectId=%s userPlayer=%s",
                        tostring(usee.ObjectId),
                        tostring(playerId)
                    ))
                    return false
                end
            end
        elseif usee.OnUsedFunctionName == "UseLoot" then
            if playerId and assignedPlayer and playerId ~= assignedPlayer then
                Log.Write(string.format(
                    "TN_Coop:UseLoot BLOCKED objectId=%s Assigned=%s ClickedBy=%s",
                    tostring(usee.ObjectId),
                    tostring(assignedPlayer),
                    tostring(playerId)
                ))
                return false
            end
            if playerId and LootRegistry.HasRoomRewardClaim(playerId) then
                Log.Write(string.format(
                    "TN_Coop:UseLoot BLOCKED unregistered objectId=%s name=%s userPlayer=%s",
                    tostring(usee.ObjectId),
                    tostring(usee.Name),
                    tostring(playerId)
                ))
                return false
            end
            Log.Write(string.format(
                "TN_Coop:UseLoot NO REGISTRY objectId=%s name=%s userIsHero=%s userPlayer=%s",
                tostring(usee.ObjectId),
                tostring(usee.Name),
                tostring(userIsHero),
                tostring(playerId)
            ))
        end
    end

    return baseFun(usee, args, user)
end

function InteractLogicHooks.wrap.OnUsed(_OnUsed, args)
    if type(args[1]) == "function" then
        _OnUsed { function(triggerArgs)
            local item = triggerArgs.TriggeredByTable
            if item == nil then
                return
            end

            local interactingHero = CoopPlayers.GetHeroByUnit(triggerArgs.UserId)
            if item.UsedByHero and item.UsedByHero ~= interactingHero then
                return
            end

            local hero = resolveHero(item, interactingHero)

            local functionName = triggerArgs.AttachedTable and triggerArgs.AttachedTable.OnUsedFunctionName
            if functionName == "UseEscapeDoor" and hero ~= HeroContext.GetDefaultHero() then
                return;
            else
                HeroContext.RunWithHeroContext(
                    hero,
                    args[1],
                    triggerArgs
                )
            end
        end
        }
    else
        _OnUsed({
            args[1],
            function(triggerArgs)
                local item = triggerArgs.TriggeredByTable
                local interactingHero = CoopPlayers.GetHeroByUnit(triggerArgs.UserId)
                local hero = resolveHero(item, interactingHero)
                HeroContext.RunWithHeroContext(
                    hero,
                    args[2],
                    triggerArgs
                )
            end
        })
    end
end

function InteractLogicHooks.wrap.OnActiveUseTarget(baseFun, args)
    if type(args[1]) == "function" then
        baseFun {
            function(triggerArgs)
                local item = triggerArgs.TriggeredByTable
                local interactingHero = CoopPlayers.GetHeroByUnit(triggerArgs.UserId)
                local hero = resolveHero(item, interactingHero)
                local functionName = triggerArgs.AttachedTable and triggerArgs.AttachedTable.OnUsedFunctionName
                if functionName == "UseEscapeDoor" and hero ~= HeroContext.GetDefaultHero() then
                    return;
                end

                HeroContext.RunWithHeroContext(
                    hero,
                    args[1],
                    triggerArgs
                )
            end
        }
    else
        baseFun(args)
    end
end

function InteractLogicHooks.wrap.OnActiveUseTargetLost(baseFun, args)
    if type(args[1]) == "function" then
        baseFun {
            function(triggerArgs)
                local item = triggerArgs.TriggeredByTable
                local interactingHero = CoopPlayers.GetHeroByUnit(triggerArgs.UserId)
                local hero = resolveHero(item, interactingHero)
                local functionName = triggerArgs.AttachedTable and triggerArgs.AttachedTable.OnUsedFunctionName
                if functionName == "UseEscapeDoor" and hero ~= HeroContext.GetDefaultHero() then
                    return;
                end

                HeroContext.RunWithHeroContext(
                    hero,
                    args[1],
                    triggerArgs
                )
            end
        }
    else
        baseFun(args)
    end
end

function InteractLogicHooks.post.UseConsumableItem(consumableItem, args, user)
    if consumableItem.AddAmmo then
        Events.game:trigger("comsumeAmmoItem", consumableItem)
    end
end

return InteractLogicHooks

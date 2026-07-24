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
        if entry and entry.source == "room_reward" then
            local playerId = CoopPlayers.GetPlayerByHero(user)
            if playerId and LootRegistry.HasRoomRewardClaim(playerId) then
                return false
            end
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

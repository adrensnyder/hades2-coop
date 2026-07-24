--
-- Copyright (c) Uladzislau Nikalayevich <thenormalnij@gmail.com>. All rights reserved.
-- Licensed under the MIT license. See LICENSE file in the project root for details.
--

---@type CoopPlayers
local CoopPlayers = ModRequire "CoopPlayers.lua"
---@type Events
local Events = ModRequire "Events.lua"
---@type HeroContext
local HeroContext = ModRequire "HeroContext.lua"

---@class RoomExitSelection
local RoomExitSelection = {}
local pendingInteractions = {}
local authorizedTransition = false

function RoomExitSelection.InitHooks()
    Events.run:on("newRunStarted", RoomExitSelection.Reset)
    Events.run:on("mapLoaded", RoomExitSelection.Reset)
    Events.run:on("roomPreLeave", RoomExitSelection.Cancel)
    Events.engine:on("presave", RoomExitSelection.Cancel)
end

local function getRoom()
    return CurrentRun and CurrentRun.CurrentRoom
end

local function getState()
    local room = getRoom()
    if not room then
        return nil
    end
    return room.CoopRoomExitSelection
end

local function describeSelection(selection)
    if not selection then
        return "nil"
    end

    return string.format(
        "{DoorId=%s Reward=%s Confirmed=%s PresentationComplete=%s}",
        tostring(selection.DoorId),
        tostring(selection.RewardDescriptor and selection.RewardDescriptor.ChosenRewardType),
        tostring(selection.Confirmed),
        tostring(selection.PresentationComplete)
    )
end

local function describeReadyState(state)
    if not state then
        return "state=nil"
    end

    local parts = {}
    for _, playerId in ipairs(state.EligiblePlayerIds or {}) do
        local selection = state.PlayerSelections and state.PlayerSelections[playerId]
        table.insert(parts, string.format("P%s=%s", tostring(playerId), describeSelection(selection)))
    end
    return table.concat(parts, " | ")
end

---@return table
function RoomExitSelection.Begin()
    local room = getRoom()
    if not room then
        return nil
    end

    local existing = room.CoopRoomExitSelection
    if existing and existing.Phase == "Collecting" then
        return existing
    end

    local eligible = {}
    for playerId, hero in CoopPlayers.PlayersIterator() do
        if hero and not hero.IsDead then
            table.insert(eligible, playerId)
        end
    end

    local selections = {}
    for _, playerId in ipairs(eligible) do
        selections[playerId] = {
            DoorId = nil,
            RewardDescriptor = nil,
            Confirmed = false,
            PresentationComplete = false,
        }
    end

    room.CoopRoomExitSelection = {
        Phase = "Collecting",
        AuthoritativePlayerId = 1,
        AuthoritativeDoorId = nil,
        AuthoritativeNextRoom = nil,
        EligiblePlayerIds = eligible,
        PlayerSelections = selections,
        LeaveRoomCalled = false,
    }
    pendingInteractions = {}
    return room.CoopRoomExitSelection
end

---@param playerId number
---@return boolean
function RoomExitSelection.IsEligible(playerId)
    local state = getState()
    if not state then
        return false
    end
    for _, eligibleId in ipairs(state.EligiblePlayerIds) do
        if eligibleId == playerId then
            return true
        end
    end
    return false
end

---@param playerId number
---@param doorId number|string
---@param rewardDescriptor table|nil
---@param nextRoom table|nil
---@return boolean
function RoomExitSelection.RecordSelection(playerId, doorId, rewardDescriptor, nextRoom)
    local state = getState()
    if not state or state.Phase ~= "Collecting" or not RoomExitSelection.IsEligible(playerId) then
        return false
    end

    local selection = state.PlayerSelections[playerId]
    if selection.Confirmed then
        return false
    end

    selection.DoorId = doorId
    selection.RewardDescriptor = rewardDescriptor
    selection.Confirmed = true
    if playerId == state.AuthoritativePlayerId then
        state.AuthoritativeDoorId = doorId
        state.AuthoritativeNextRoom = nextRoom and (nextRoom.GenusName or nextRoom.Name)
    end
    DebugPrint { Text = string.format(
        "RoomExitSelection: player=%s door=%s room=%s confirmed=true",
        tostring(playerId), tostring(doorId), tostring(state.AuthoritativeNextRoom)
    ) }
    DebugPrint { Text = "RoomExitSelection: selections " .. describeReadyState(state) }
    return true
end

---@return boolean
function RoomExitSelection.IsReady()
    local state = getState()
    if not state or state.Phase ~= "Collecting" then
        return false
    end
    for _, playerId in ipairs(state.EligiblePlayerIds) do
        if not state.PlayerSelections[playerId].Confirmed then
            return false
        end
    end
    return true
end

---@return boolean
function RoomExitSelection.BeginTransition()
    local state = getState()
    if not RoomExitSelection.IsReady() or state.LeaveRoomCalled then
        return false
    end
    state.Phase = "Transitioning"
    state.LeaveRoomCalled = true
    DebugPrint { Text = "RoomExitSelection: all eligible players confirmed; committing one transition" }
    DebugPrint { Text = "RoomExitSelection: transition snapshot " .. describeReadyState(state) }
    return true
end

function RoomExitSelection.Cancel()
    local state = getState()
    if state and state.Phase ~= "Completed" then
        state.Phase = "Cancelled"
    end
    pendingInteractions = {}
    authorizedTransition = false
end

function RoomExitSelection.Complete()
    local state = getState()
    if state then
        state.Phase = "Completed"
    end
    pendingInteractions = {}
    authorizedTransition = false
end

---@return boolean
function RoomExitSelection.IsTransitionAuthorized()
    return authorizedTransition
end

function RoomExitSelection.Reset()
    local room = getRoom()
    if room then
        room.CoopRoomExitSelection = nil
    end
    pendingInteractions = {}
    authorizedTransition = false
end

---@param door table
---@return table
local function getRewardDescriptor(door)
    local room = door and door.Room
    return {
        RewardStoreName = room and room.RewardStoreName,
        ChosenRewardType = room and room.ChosenRewardType,
        ForceLootName = room and room.ForceLootName,
        RewardOverrides = room and room.RewardOverrides,
        RoomName = room and (room.GenusName or room.Name),
    }
end

function RoomExitSelection.PrepareRewardDelivery()
    local state = getState()
    if not state or state.Phase ~= "Transitioning" then
        return
    end

    local pending = {}
    local pendingCount = 0
    for _, playerId in ipairs(state.EligiblePlayerIds) do
        local selection = state.PlayerSelections[playerId]
        if selection and selection.RewardDescriptor then
            pending[playerId] = selection.RewardDescriptor
            pendingCount = pendingCount + 1
        end
    end
    CurrentRun.CoopPendingRoomRewards = pending
    DebugPrint { Text = string.format(
        "TN_Coop:RoomExitSelection prepared reward descriptors count=%s",
        tostring(pendingCount)
    ) }
end

local function isSupportedDoor(door)
    return door and door.ObjectId and door.Room and door.ReadyToUse and
        door.EncounterCost == nil and door.HealthCost == nil and
        door.ReturnToPreviousRoom == nil and door.ReturnToPreviousRoomName == nil
end

local function runDoorPresentation(door)
    if door.OnUsedPresentationFunctionName then
        CallFunctionName(
            door.OnUsedPresentationFunctionName,
            door,
            door.OnUsedPresentationFunctionArgs
        )
    end
end

---@param baseFun fun(door: table, args: table)
---@param door table
---@param args table|nil
---@return boolean
function RoomExitSelection.HandleAttemptUseDoor(baseFun, door, args)
    local state = getState()
    if not state or state.Phase ~= "Collecting" then
        return false
    end

    local playerId = CoopPlayers.GetCurrentPlayerId()
    if not RoomExitSelection.IsEligible(playerId) or not isSupportedDoor(door) then
        return false
    end

    DebugPrint { Text = string.format(
        "RoomExitSelection: attempt player=%s ready=%s selections=%s",
        tostring(playerId),
        tostring(RoomExitSelection.IsReady()),
        describeReadyState(state)
    ) }

    local selection = state.PlayerSelections[playerId]
    if selection.Confirmed then
        DebugPrint { Text = string.format(
            "RoomExitSelection: player=%s already confirmed",
            tostring(playerId)
        ) }
        return true
    end

    RoomExitSelection.RecordSelection(
        playerId,
        door.ObjectId,
        getRewardDescriptor(door),
        door.Room
    )
    pendingInteractions[playerId] = {
        Door = door,
        Args = args or {},
        BaseFun = baseFun,
    }
    runDoorPresentation(door)
    selection.PresentationComplete = true
    DebugPrint { Text = string.format(
        "RoomExitSelection: player=%s presentation complete",
        tostring(playerId)
    ) }
    DebugPrint { Text = string.format(
        "RoomExitSelection: post-presentation ready=%s selections=%s",
        tostring(RoomExitSelection.IsReady()),
        describeReadyState(state)
    ) }

    if not RoomExitSelection.IsReady() then
        return true
    end

    if not RoomExitSelection.BeginTransition() then
        return true
    end

    local authoritative = pendingInteractions[state.AuthoritativePlayerId]
    if not authoritative then
        RoomExitSelection.Cancel()
        return true
    end

    RoomExitSelection.PrepareRewardDelivery()
    authorizedTransition = true
    HeroContext.RunWithHeroContext(
        CoopPlayers.GetHero(state.AuthoritativePlayerId),
        authoritative.BaseFun,
        authoritative.Door,
        authoritative.Args
    )
    return true
end

---@return table|nil
function RoomExitSelection.Get()
    return getState()
end

return RoomExitSelection

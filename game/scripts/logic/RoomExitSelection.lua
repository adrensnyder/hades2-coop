--
-- Copyright (c) Uladzislau Nikalayevich <thenormalnij@gmail.com>. All rights reserved.
-- Licensed under the MIT license. See LICENSE file in the project root for details.
--

---@type CoopPlayers
local CoopPlayers = ModRequire "CoopPlayers.lua"

---@class RoomExitSelection
local RoomExitSelection = {}
local pendingInteractions = {}

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
    return true
end

function RoomExitSelection.Cancel()
    local state = getState()
    if state and state.Phase ~= "Completed" then
        state.Phase = "Cancelled"
    end
    pendingInteractions = {}
end

function RoomExitSelection.Complete()
    local state = getState()
    if state then
        state.Phase = "Completed"
    end
    pendingInteractions = {}
end

function RoomExitSelection.Reset()
    local room = getRoom()
    if room then
        room.CoopRoomExitSelection = nil
    end
    pendingInteractions = {}
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
    for _, playerId in ipairs(state.EligiblePlayerIds) do
        local selection = state.PlayerSelections[playerId]
        if selection and selection.RewardDescriptor then
            pending[playerId] = selection.RewardDescriptor
        end
    end
    CurrentRun.CoopPendingRoomRewards = pending
end

---@param playerId number
---@param door table
---@param triggerArgs table
---@param useDoor fun(triggerArgs: table)
---@return boolean, boolean
function RoomExitSelection.RecordDoorInteraction(playerId, door, triggerArgs, useDoor)
    local state = getState()
    if not state or state.Phase ~= "Collecting" or not RoomExitSelection.IsEligible(playerId) then
        return false, false
    end
    if not door or not door.ObjectId or not door.Room then
        return false, false
    end

    local selection = state.PlayerSelections[playerId]
    if selection.Confirmed then
        return true, false
    end

    RoomExitSelection.RecordSelection(
        playerId,
        door.ObjectId,
        getRewardDescriptor(door),
        door.Room
    )
    pendingInteractions[playerId] = {
        TriggerArgs = triggerArgs,
        UseDoor = useDoor,
    }

    if not RoomExitSelection.IsReady() then
        return true, false
    end

    if not RoomExitSelection.BeginTransition() then
        return true, false
    end

    local authoritative = pendingInteractions[state.AuthoritativePlayerId]
    if authoritative and authoritative.UseDoor then
        RoomExitSelection.PrepareRewardDelivery()
        authoritative.UseDoor(authoritative.TriggerArgs)
        pendingInteractions = {}
    else
        RoomExitSelection.Cancel()
    end
    return true, true
end

---@return table|nil
function RoomExitSelection.Get()
    return getState()
end

return RoomExitSelection

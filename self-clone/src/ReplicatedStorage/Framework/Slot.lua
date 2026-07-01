--!strict
-- Slot.lua
-- Pure data. One Slot = one position in a Formation. Slots are pooled and
-- reused by FormationComponent (see its free-list) so a minion joining or
-- leaving an army never allocates a new table once the formation has
-- reached its high-water mark of concurrently-occupied slots.
--
-- DesiredPosition is the AUTHORITATIVE, STABLE navigation target -- see
-- the design note at the top of FormationComponent.lua. It is written in
-- exactly one place (FormationComponent) and read in exactly one place
-- (FormationSystem). There is no separate "interpolated" position and no
-- per-slot jitter offset anymore: navigation always targets Offset alone,
-- never Offset + some idle wobble. If minions should look alive while
-- holding formation, animate the model (breathing/sway), don't perturb
-- the nav target -- that's what caused the permanent orbiting.
--
-- Movement bookkeeping (_movement / _lastDirection / Moving / Reached)
-- lives here rather than back on the minion, because FormationSystem
-- iterates SLOTS (flat, cache-friendly array), not minions scattered
-- across armies. This mirrors the FollowComponent/FollowSystem split
-- already in the codebase: Slot = state, FormationSystem = work.

export type Slot = {
	SlotId: number,
	Offset: Vector3,            -- local-space offset from the formation anchor
	DesiredPosition: Vector3,   -- stable world-space nav target; only FormationComponent writes this
	AssignedMinion: any?,       -- MinionEntity occupying this slot, or nil
	Occupied: boolean,

	-- Movement state owned by FormationSystem. Reset on every Reset() call.
	Reached: boolean,            -- arrived (or confirmed unreachable) -- skip re-evaluation until DesiredPosition changes
	Moving: boolean,              -- are we currently telling the humanoid to move

	_occupiedIndex: number?,    -- this slot's index inside FormationComponent's flat _occupied array (O(1) unregister)
	_movement: any?,            -- cached MovementComponent reference for AssignedMinion
	_lastDirection: Vector3?,
}

local Slot = {}
Slot.__index = Slot

local function new(slotId: number): Slot
	return setmetatable({
		SlotId = slotId,
		Offset = Vector3.zero,
		DesiredPosition = Vector3.zero,
		AssignedMinion = nil,
		Occupied = false,

		Reached = false,
		Moving = false,

		_occupiedIndex = nil,
		_movement = nil,
		_lastDirection = nil,
	}, Slot) :: any
end

-- Reset+reuse instead of allocating a new table. Called whenever a slot is
-- pulled out of the free-list to be handed to a newly-joining minion.
-- Offset/DesiredPosition are computed by the caller (FormationComponent),
-- everything else is wiped.
function Slot.Reset(slot: Slot, offset: Vector3, desiredPosition: Vector3)
	slot.Offset = offset
	slot.DesiredPosition = desiredPosition
	slot.AssignedMinion = nil
	slot.Occupied = false
	slot.Reached = false
	slot.Moving = false
	slot._occupiedIndex = nil
	slot._movement = nil
	slot._lastDirection = nil
end

return {
	new = new,
	Reset = Slot.Reset,
}
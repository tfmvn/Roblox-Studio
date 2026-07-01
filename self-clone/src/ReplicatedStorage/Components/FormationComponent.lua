--!strict
-- FormationComponent.lua
-- Owns one Army's slots. Minions never compute their own position; they
-- are assigned a Slot once and FormationSystem walks them toward
-- slot.DesiredPosition. This module only does the bookkeeping: allocate/
-- free slots, recompute offsets on shape/spacing change, and recompute
-- desired world positions when the anchor has actually moved enough to
-- matter. It does NOT call MoveTo/SetDirection -- that's FormationSystem's
-- job (registry of work), this is state.
--
-- DESIGN RULE (read before touching this file):
-- Slot.DesiredPosition is the AUTHORITATIVE, STABLE navigation target.
-- It is NOT recomputed every frame. It only changes when:
--   1. the anchor has moved further than RECOMPUTE_THRESHOLD studs since
--      the last recompute (ArmyService calls SetAnchor every Heartbeat,
--      but most of those calls are cheap no-ops here because the player
--      hasn't moved far enough to matter),
--   2. the formation's Shape or Spacing changes, or
--   3. a minion joins (its own slot is computed once, immediately,
--      against the current anchor).
-- Anything that continuously re-derives DesiredPosition (a per-frame
-- Lerp, permanent per-slot jitter, etc.) turns the humanoid into a dog
-- chasing a target that itself keeps moving -- that's what caused the
-- orbiting/circling/drifting bugs this file used to have. If idle "life"
-- is wanted, animate the model (breathing/sway) -- never the nav target.
--
-- Slot pooling: _slots is a dense array, indexed 1.._slotCapacity, that
-- only ever GROWS (new Slot tables are appended, never removed) -- it is
-- the formation's all-time high-water mark of concurrently-used slots.
-- _freeStack is a stack of currently-unused slots pulled from that array.
-- Joining pops a free slot (or appends a brand-new one if the stack is
-- empty); leaving pushes the slot back. Steady-state armies (the common
-- case: minions die and get replaced) do ZERO table allocation after the
-- army's first trip to its peak size.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FormationGenerator = require(ReplicatedStorage.Framework.FormationGenerator)
local Slot = require(ReplicatedStorage.Framework.Slot)

-- Anchor has to move (studs, straight-line) more than this before slot
-- DesiredPositions are recomputed. Below this, ArmyService's per-frame
-- SetAnchor calls are cheap no-ops (one Vector3 subtract + compare).
-- Small enough that walking still tracks in smooth-feeling discrete
-- steps; large enough that a stationary player's tiny physics jitter
-- (R15 HumanoidRootPart micro-movement while idle) never triggers a
-- recompute -- so idle minions actually go still instead of endlessly
-- re-aiming at a target that moved a hundredth of a stud.
local RECOMPUTE_THRESHOLD = 1.5

export type FormationConfig = {
	Shape: FormationGenerator.ShapeName?,
	Spacing: number?,
}

export type FormationComponent = {
	Shape: FormationGenerator.ShapeName,
	Spacing: number,
	AnchorCFrame: CFrame,

	AddMinion: (self: FormationComponent, minion: any) -> Slot.Slot,
	RemoveMinion: (self: FormationComponent, minion: any) -> (),
	GetSlot: (self: FormationComponent, minion: any) -> Slot.Slot?,
	SetShape: (self: FormationComponent, shape: FormationGenerator.ShapeName) -> (),
	SetSpacing: (self: FormationComponent, spacing: number) -> (),
	SetAnchor: (self: FormationComponent, cframe: CFrame) -> (),
	OccupiedCount: (self: FormationComponent) -> number,
	Destroy: (self: FormationComponent) -> (),

	_slots: { Slot.Slot },          -- dense, index = SlotId, only ever grows
	_freeStack: { Slot.Slot },      -- pooled, currently-unused slots
	_occupied: { Slot.Slot },       -- flat array of currently-occupied slots (cache-friendly iteration)
	_minionToSlot: { [any]: Slot.Slot },
	_lastRecomputeAnchor: CFrame,
}

local FormationComponent = {}
FormationComponent.__index = FormationComponent

-- O(1): pop a free slot or append a new one. Computes that single slot's
-- offset AND its DesiredPosition against the CURRENT anchor -- a joining
-- minion should walk straight to its final spot, not to some stale
-- position left over from before it existed.
local function acquireSlot(self: FormationComponent): Slot.Slot
	local slot = table.remove(self._freeStack)
	if slot then
		local offset = FormationGenerator.GetOffset(self.Shape, slot.SlotId, self.Spacing)
		Slot.Reset(slot, offset, self.AnchorCFrame:PointToWorldSpace(offset))
		return slot
	end

	local slotId = #self._slots + 1
	local newSlot = Slot.new(slotId)
	local offset = FormationGenerator.GetOffset(self.Shape, slotId, self.Spacing)
	Slot.Reset(newSlot, offset, self.AnchorCFrame:PointToWorldSpace(offset))
	self._slots[slotId] = newSlot
	return newSlot
end

-- O(n) over occupied slots only. The ONE place that writes
-- Slot.DesiredPosition. Called from SetAnchor (gated by
-- RECOMPUTE_THRESHOLD), SetShape, and SetSpacing -- never from a
-- per-frame system tick.
local function recomputeDesiredPositions(self: FormationComponent)
	local anchor = self.AnchorCFrame
	for _, slot in ipairs(self._occupied) do
		slot.DesiredPosition = anchor:PointToWorldSpace(slot.Offset)
		slot.Reached = false
	end
end

-- O(1): minion already has a cached MovementComponent reference; this is
-- just dictionary lookup + array swap-remove, no scanning.
function FormationComponent:AddMinion(minion: any): Slot.Slot
	local existing = self._minionToSlot[minion]
	if existing then
		return existing
	end

	local slot = acquireSlot(self)
	slot.Occupied = true
	slot.AssignedMinion = minion
	slot._movement = minion.GetComponent and minion:GetComponent("Movement") or nil

	table.insert(self._occupied, slot)
	slot._occupiedIndex = #self._occupied
	self._minionToSlot[minion] = slot

	return slot
end

function FormationComponent:RemoveMinion(minion: any)
	local slot = self._minionToSlot[minion]
	if not slot then
		return
	end
	self._minionToSlot[minion] = nil

	-- O(1) swap-remove from the occupied array using the slot's cached index
	local occupied = self._occupied
	local idx = slot._occupiedIndex
	local lastIdx = #occupied
	if idx and idx ~= lastIdx then
		local lastSlot = occupied[lastIdx]
		occupied[idx] = lastSlot
		lastSlot._occupiedIndex = idx
	end
	occupied[lastIdx] = nil

	slot.Occupied = false
	slot.AssignedMinion = nil
	slot._movement = nil
	slot._lastDirection = nil
	slot.Moving = false
	slot.Reached = false
	slot._occupiedIndex = nil

	table.insert(self._freeStack, slot)
end

function FormationComponent:GetSlot(minion: any): Slot.Slot?
	return self._minionToSlot[minion]
end

-- O(n) in THIS army's occupied minions only (spec-allowed "Formation
-- rebuild O(n)"). Reuses every existing slot table -- only Offset is
-- recomputed, no slot is freed or reallocated -- then DesiredPosition is
-- rebuilt against the current anchor so a shape change mid-fight doesn't
-- cause pool churn OR leave a stale desired position around.
function FormationComponent:SetShape(shape: FormationGenerator.ShapeName)
	if shape == self.Shape then
		return
	end
	self.Shape = shape
	for _, slot in ipairs(self._occupied) do
		slot.Offset = FormationGenerator.GetOffset(shape, slot.SlotId, self.Spacing)
	end
	recomputeDesiredPositions(self)
end

function FormationComponent:SetSpacing(spacing: number)
	if spacing == self.Spacing then
		return
	end
	self.Spacing = spacing
	for _, slot in ipairs(self._occupied) do
		slot.Offset = FormationGenerator.GetOffset(self.Shape, slot.SlotId, spacing)
	end
	recomputeDesiredPositions(self)
end

-- Called every frame by ArmyService's anchor-follow Heartbeat. Deliberately
-- CHEAP when nothing meaningful happened: store the new anchor, compare it
-- against the anchor last used to compute DesiredPositions, and only pay
-- for the O(occupied) recompute if the player has actually moved far
-- enough to matter. A stationary player (or one whose HumanoidRootPart is
-- only jittering a fraction of a stud from physics) causes zero slot
-- recomputation -- which is what lets idle minions come to a genuine,
-- permanent stop instead of endlessly re-aiming at a target that never
-- quite finishes moving.
function FormationComponent:SetAnchor(cframe: CFrame)
	self.AnchorCFrame = cframe

	local delta = (cframe.Position - self._lastRecomputeAnchor.Position).Magnitude
	if delta >= RECOMPUTE_THRESHOLD then
		self._lastRecomputeAnchor = cframe
		recomputeDesiredPositions(self)
	end
end

function FormationComponent:OccupiedCount(): number
	return #self._occupied
end

function FormationComponent:Destroy()
	table.clear(self._slots)
	table.clear(self._freeStack)
	table.clear(self._occupied)
	table.clear(self._minionToSlot)
end

local function new(config: FormationConfig?): FormationComponent
	config = config or {}
	local self = setmetatable({
		Shape = config.Shape or "Circle",
		Spacing = config.Spacing or 5,
		AnchorCFrame = CFrame.new(),

		_slots = {},
		_freeStack = {},
		_occupied = {},
		_minionToSlot = {},
		_lastRecomputeAnchor = CFrame.new(),
	}, FormationComponent)

	return (self :: any) :: FormationComponent
end

return {
	new = new,
}
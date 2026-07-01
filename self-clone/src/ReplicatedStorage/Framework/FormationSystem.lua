--!strict
-- FormationSystem.lua
-- The ONE system (registered once with Scheduler, same pattern as
-- FollowSystem) that drives every Army's formation in the game.
--
-- There is only ONE pass now: a bucketed movement re-aim pass over every
-- occupied slot. The old "interpolate slot.WorldPosition every frame"
-- pass is GONE -- FormationComponent.DesiredPosition is now the
-- authoritative, stable nav target (see FormationComponent.lua's design
-- note), so there's nothing left here to interpolate. Humanoids walk
-- straight at a fixed point and stop; they don't chase a target that's
-- still drifting toward its own final spot.
--
-- Iterates FLAT arrays (formations list, each formation's own _occupied
-- array) -- never nested "for every army, for every OTHER army's
-- minions" loops, so this stays O(n) total across the whole game, never
-- O(n^2).

local BUCKET_COUNT = 8
local DIRECTION_EPSILON = 0.12  -- skip re-aiming for ~7 degree direction changes
local ARRIVE_DISTANCE = 1.5     -- stop walking once this close (horizontally) to the slot
local MAX_VERTICAL_REACH = 6    -- beyond this Y difference, treat the slot as unreachable

local FormationSystem = {}
FormationSystem.__index = FormationSystem
FormationSystem.Name = "FormationSystem"

-- Flat list of every live FormationComponent (one per Army).
local formations: { any } = {}
local frameCounter = 0

function FormationSystem.RegisterFormation(formation: any)
	table.insert(formations, formation)
end

function FormationSystem.UnregisterFormation(formation: any)
	for i, f in ipairs(formations) do
		if f == formation then
			table.remove(formations, i)
			return
		end
	end
end

-- Slot.DesiredPosition is fixed until FormationComponent says otherwise
-- (anchor moved enough / shape changed / spacing changed / joined). So
-- once a minion reaches it (or the slot is confirmed unreachable) and
-- Reached is set, this function does NOTHING on every subsequent
-- evaluation until DesiredPosition actually changes -- no repeated
-- Stop() calls, no re-aiming, no drift.
local function evaluateSlotMovement(slot: any)
	if not slot.Occupied then
		return
	end
	local minion = slot.AssignedMinion
	if not minion or minion.Destroyed then
		return
	end
	if slot.Reached then
		return
	end

	local movement = slot._movement
	if not movement then
		return
	end

	local model = minion.Model
	local rootPart = model and model:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end

	local myPos = (rootPart :: BasePart).Position
	local desired = slot.DesiredPosition
	local offset = desired - myPos
	local horizontal = Vector3.new(offset.X, 0, offset.Z)
	local distance = horizontal.Magnitude

	if distance <= ARRIVE_DISTANCE then
		if slot.Moving then
			slot.Moving = false
			slot._lastDirection = nil
			movement:Stop()
		end
		slot.Reached = true
		return
	end

	if math.abs(offset.Y) > MAX_VERTICAL_REACH then
		-- Different level / unreachable for now. Stop AND mark Reached so
		-- we stop re-evaluating a spot we can't get to every bucket cycle
		-- -- the formation waits at the last reachable position instead
		-- of jittering. FormationComponent clears Reached the moment the
		-- anchor/shape actually changes again, which is the only thing
		-- that can make this slot reachable. A future pathfinding-aware
		-- system can hook in here without this file needing to change.
		if slot.Moving then
			movement:Stop()
			slot.Moving = false
		end
		slot.Reached = true
		return
	end

	local direction = horizontal.Unit
	local lastDir = slot._lastDirection
	if lastDir and slot.Moving and lastDir:Dot(direction) > (1 - DIRECTION_EPSILON) then
		return
	end

	slot._lastDirection = direction
	slot.Moving = true
	movement:SetDirection(direction)
end

function FormationSystem:Update(_dt: number)
	frameCounter += 1
	local bucket = frameCounter % BUCKET_COUNT

	local globalIndex = 0
	for _, formation in ipairs(formations) do
		local occupied = formation._occupied
		for i = 1, #occupied do
			globalIndex += 1
			if (globalIndex % BUCKET_COUNT) == bucket then
				local slot = occupied[i]
				local ok = pcall(evaluateSlotMovement, slot)
				if not ok then
					-- A single bad slot/minion should never stall every
					-- other army's movement update.
					formation:RemoveMinion(slot.AssignedMinion)
				end
			end
		end
	end
end

return FormationSystem
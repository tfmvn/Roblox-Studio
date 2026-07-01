--!strict
-- FormationGenerator.lua
-- Pure, stateless math: GetOffset(shape, slotId, spacing) -> Vector3 offset
--
-- The critical property: every shape here is a CLOSED-FORM function of
-- slotId alone (plus spacing). Computing slot #501's offset never requires
-- knowing about slots #1-500, and never requires iterating or regenerating
-- the rest of the formation. This is what lets FormationComponent allocate
-- exactly one slot on join and free exactly one slot on leave, instead of
-- rebuilding the whole formation array (the spec's "never regenerate the
-- entire formation" requirement).
--
-- Changing formation SHAPE is still O(n) -- every existing slot's offset
-- has to be recomputed because the shape function changed -- but that is
-- the one explicitly-allowed O(n) "Formation rebuild" in the spec, and it
-- reuses the existing slot tables (FormationComponent:SetShape), it does
-- not reallocate them.
--
-- NOTE: this module used to also hand back a per-slot "jitter" offset for
-- idle wobble. That's gone -- jitter applied to the NAVIGATION target is
-- exactly what caused minions to permanently orbit their slot instead of
-- coming to rest (see FormationComponent.lua's design note). If idle
-- motion is wanted later, it belongs entirely in the model/animation
-- layer, never mixed into the value FormationSystem tells a Humanoid to
-- walk toward.

export type ShapeName = "Circle" | "Ring" | "Square" | "Triangle" | "Grid"

local FormationGenerator = {}

-- ---------------------------------------------------------------------
-- Concentric "ring layer" math shared by Circle/Ring/Square.
--
-- DELIBERATELY NO CENTER SLOT. An earlier version put slot #1 at
-- Vector3.zero -- i.e. dead center of the formation, which is the
-- anchor position, which for an Army formation IS the player's own
-- standing position. That minion could never "arrive" because the
-- player's own hitbox physically shoves it away every time it gets
-- close, so it kept re-aiming in a new direction every bucket cycle --
-- which is exactly what "a few minions walking randomly / spinning"
-- looks like (it's specifically the center occupant and whichever
-- neighbors get jostled into it). Layer 1 (k=1) is now the innermost
-- ring, `spacing` studs out from the anchor, which is enough to clear a
-- standing player.
--
-- Layer k (k>=1) holds 6k slots, so point density per ring stays
-- constant as the formation grows instead of one ring getting more and
-- more crowded. Closed-form (sqrt + a couple of corrective steps for
-- float rounding) -- O(1), not a search loop.
-- ---------------------------------------------------------------------
local function ringLayerOf(slotId: number): (number, number, number)
	local index = slotId - 1 -- 0-based position among ALL slots (no center slot)

	local k = math.floor((-1 + math.sqrt(1 + (4 * index) / 3)) / 2) + 1
	if k < 1 then
		k = 1
	end
	-- at most a couple of nudges to correct float rounding at the boundary
	while 3 * k * (k + 1) <= index do
		k += 1
	end
	while k > 1 and 3 * (k - 1) * k > index do
		k -= 1
	end

	local cumulativeBeforeLayer = 3 * (k - 1) * k
	local posInLayer = index - cumulativeBeforeLayer
	local capacity = 6 * k
	return k, posInLayer, capacity
end

local function circleOffset(slotId: number, spacing: number): Vector3
	local layer, posInLayer, capacity = ringLayerOf(slotId)
	-- stagger alternating layers by half a slot-width so minions don't
	-- line up radially in dead-straight spokes
	local stagger = if layer % 2 == 0 then 0 else (math.pi / capacity)
	local angle = (posInLayer / capacity) * (2 * math.pi) + stagger
	local radius = layer * spacing
	return Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
end

local function squareOffset(slotId: number, spacing: number): Vector3
	local layer, posInLayer, _capacity = ringLayerOf(slotId)
	-- walk the perimeter of an (2*layer)x(2*layer) square, 8*layer points
	-- evenly spaced, starting at the top-left corner and going clockwise
	local side = layer * 2
	local perim = 8 * layer
	local t = (posInLayer / perim) * (4 * side) -- distance traveled along perimeter, 0..4*side
	local half = layer * spacing
	local seg = 2 * half
	local d = t * (seg / side) -- map back into world units along one side

	if t < side then
		return Vector3.new(-half + d, 0, -half)
	elseif t < side * 2 then
		return Vector3.new(half, 0, -half + (d - seg))
	elseif t < side * 3 then
		return Vector3.new(half - (d - seg * 2), 0, half)
	else
		return Vector3.new(-half, 0, half - (d - seg * 3))
	end
end

-- Triangle / phalanx wedge: row r (0-based) holds (r+1) slots, centered.
-- Row of slotId found via the inverse triangular-number formula, closed
-- form, no search. Row 0 is pushed one spacing unit forward (z = (row+1)
-- * spacing, not row * spacing) so the single front-row slot never sits
-- at (0,0,0) -- i.e. never coincides with the anchor / player position,
-- for the same reason the center slot was removed from the ring shapes
-- above.
local function triangleOffset(slotId: number, spacing: number): Vector3
	local index = slotId - 1 -- 0-based
	local row = math.floor((-1 + math.sqrt(1 + 8 * index)) / 2)
	local rowStart = (row * (row + 1)) // 2
	local posInRow = index - rowStart
	local rowWidth = row + 1
	local x = (posInRow - (rowWidth - 1) / 2) * spacing
	local z = (row + 1) * spacing
	return Vector3.new(x, 0, z)
end

-- Grid: simple row-major layout, fixed column count derived from spacing
-- alone (not from total population), so slot #N's column/row is O(1).
local GRID_WIDTH = 12
local function gridOffset(slotId: number, spacing: number): Vector3
	local index = slotId - 1 -- 0-based
	local col = index % GRID_WIDTH
	local row = index // GRID_WIDTH
	local x = (col - (GRID_WIDTH - 1) / 2) * spacing
	local z = row * spacing
	return Vector3.new(x, 0, z)
end

local SHAPES: { [ShapeName]: (number, number) -> Vector3 } = {
	Circle = circleOffset,
	Ring = circleOffset, -- alias: same concentric-ring math
	Square = squareOffset,
	Triangle = triangleOffset,
	Grid = gridOffset,
}

function FormationGenerator.GetOffset(shape: ShapeName, slotId: number, spacing: number): Vector3
	local fn = SHAPES[shape] or circleOffset
	return fn(slotId, spacing)
end

function FormationGenerator.IsValidShape(shape: string): boolean
	return SHAPES[shape :: ShapeName] ~= nil
end

return FormationGenerator
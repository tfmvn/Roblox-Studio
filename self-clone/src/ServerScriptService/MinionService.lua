-- ServerScriptService/MinionService.lua
-- Spawns plain minion objects (NOT an entity/component framework).
-- A minion is just: { Model, Humanoid, Animator, Movement, Animation }.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local MovementComponent = require(ReplicatedStorage.Components.MovementComponent)
local AnimationComponent = require(ReplicatedStorage.Components.AnimationComponent)

local MinionService = {}
MinionService._minionsByArmy = {} -- [army] = { minion, minion, ... }

-- REQUIRED SETUP (not code, just Studio setup):
--   ServerStorage
--     └── Assets
--          └── MinionTemplate   (Model, PrimaryPart set, contains Humanoid)
--
-- The Humanoid needs an Animator (Roblox adds one automatically at runtime
-- if missing, but it's cleaner to have it baked into the template).
local ASSETS_FOLDER = ServerStorage:WaitForChild("Assets")
local MINION_TEMPLATE = ASSETS_FOLDER:WaitForChild("MinionTemplate")

-- Swap these for your real animation asset ids.
local IDLE_ANIMATION_ID = "rbxassetid://0000000000"
local WALK_ANIMATION_ID = "rbxassetid://0000000000"

local function buildMinion(spawnCFrame)
	local model = MINION_TEMPLATE:Clone()
	model:PivotTo(spawnCFrame)
	model.Parent = workspace

	local humanoid = model:WaitForChild("Humanoid")
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)

	local idleAnim = Instance.new("Animation")
	idleAnim.AnimationId = IDLE_ANIMATION_ID

	local walkAnim = Instance.new("Animation")
	walkAnim.AnimationId = WALK_ANIMATION_ID

	local minion = {
		Model = model,
		Humanoid = humanoid,
		Animator = animator,

		Movement = MovementComponent.new(humanoid),
		Animation = AnimationComponent.new(animator, idleAnim, walkAnim),
	}

	function minion:Destroy()
		self.Movement:Destroy()
		self.Animation:Destroy()
		if self.Model then
			self.Model:Destroy()
		end
	end

	return minion
end

function MinionService.Spawn(army, spawnCFrame)
	spawnCFrame = spawnCFrame or army.Anchor

	local minion = buildMinion(spawnCFrame)
	army:AddMinion(minion)

	MinionService._minionsByArmy[army] = MinionService._minionsByArmy[army] or {}
	table.insert(MinionService._minionsByArmy[army], minion)

	return minion
end

function MinionService.Destroy(army, minion)
	army:RemoveMinion(minion)

	local list = MinionService._minionsByArmy[army]
	if list then
		local index = table.find(list, minion)
		if index then
			table.remove(list, index)
		end
	end

	minion:Destroy()
end

function MinionService.GetArmyMinions(army)
	return MinionService._minionsByArmy[army] or {}
end

return MinionService

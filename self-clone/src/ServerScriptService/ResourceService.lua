local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Signal = require(ReplicatedStorage.Framework.Signal)
local ResourceNode = require(script.Parent.ResourceNode)

local ResourceService = {}


ResourceService.NodeClicked = Signal.new()

local _nodesByModel = {}

local NODES_FOLDER_NAME = "ResourceNodes"
local RESPAWN_TIME = 20

local PICKUP_COUNT = 6
local PICKUP_POP_TIME = 0.15
local PICKUP_FLY_TIME = 0.5

local function wrapNode(model)
	local node = ResourceNode.new(model)
	_nodesByModel[model] = node

	local clickDetector = model:FindFirstChildWhichIsA("ClickDetector", true)
	if not clickDetector then
		clickDetector = Instance.new("ClickDetector")
		clickDetector.MaxActivationDistance = 32
		clickDetector.Parent = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	end

	clickDetector.MouseClick:Connect(function(player)
		if node._destroyed then
			return
		end
		ResourceService.NodeClicked:Fire(player, node)
	end)

	return node
end


function ResourceService.Init()
	local folder = workspace:FindFirstChild(NODES_FOLDER_NAME)
	if not folder then
		warn(("[ResourceService] No '%s' folder found in workspace"):format(NODES_FOLDER_NAME))
		return
	end

	for _, model in ipairs(folder:GetChildren()) do
		if model:IsA("Model") then
			wrapNode(model)
		end
	end
end

function ResourceService.GetNode(model)
	return _nodesByModel[model]
end


function ResourceService.SpawnPickups(node, owner)
	local character = owner.Character
	if not character then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end

	local originCFrame = node.Model:GetPivot()

	for _ = 1, PICKUP_COUNT do
		local pickup = Instance.new("Part")
		pickup.Shape = Enum.PartType.Ball
		pickup.Size = Vector3.new(1, 1, 1)
		pickup.Color = Color3.fromRGB(255, 220, 90)
		pickup.Material = Enum.Material.Neon
		pickup.CanCollide = false
		pickup.Anchored = true
		pickup.CFrame = originCFrame * CFrame.new(
			math.random(-3, 3), math.random(2, 4), math.random(-3, 3)
		)
		pickup.Parent = workspace

		local popTarget = pickup.CFrame * CFrame.new(0, 2, 0)
		local popTween = TweenService:Create(
			pickup,
			TweenInfo.new(PICKUP_POP_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = popTarget }
		)

		popTween.Completed:Connect(function()
			
			local flyTween = TweenService:Create(
				pickup,
				TweenInfo.new(PICKUP_FLY_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ CFrame = CFrame.new(rootPart.Position), Size = Vector3.new(0.2, 0.2, 0.2) }
			)

			flyTween.Completed:Connect(function()
				pickup:Destroy()
			end)

			flyTween:Play()
		end)

		popTween:Play()
	end
end

function ResourceService.ScheduleRespawn(node)
	task.delay(RESPAWN_TIME, function()
		node:Respawn()
	end)
end

return ResourceService

local ResourceNode = {}
ResourceNode.__index = ResourceNode

function ResourceNode.new(model)
	local maxHealth = model:GetAttribute("Health") or 1000
	local resourceType = model:GetAttribute("ResourceType") or "Wood"

	local self = setmetatable({
		Model = model,
		MaxHealth = maxHealth,
		Health = maxHealth,
		ResourceType = resourceType,
		Army = nil,

		_originalParent = model.Parent,
		_originalCFrame = model:GetPivot(),
		_destroyed = false,
	}, ResourceNode)

	return self
end

function ResourceNode:AssignArmy(army)
	self.Army = army
end


function ResourceNode:Harvest(amount)
	if self._destroyed then
		return false
	end

	local wasAlive = self.Health > 0
	self.Health = math.max(0, self.Health - amount)

	return wasAlive and self.Health <= 0
end

function ResourceNode:Destroy()
	if self._destroyed then
		return
	end

	self._destroyed = true
	self.Army = nil
	self.Model.Parent = nil
end

function ResourceNode:Respawn()
	self._destroyed = false
	self.Health = self.MaxHealth
	self.Army = nil

	self.Model:PivotTo(self._originalCFrame)
	self.Model.Parent = self._originalParent
end

return ResourceNode

local AnimationComponent = {}
AnimationComponent.__index = AnimationComponent

function AnimationComponent.new(animator, idleAnimation, walkAnimation)
	local self = setmetatable({
		Animator = animator,
		IdleTrack = animator:LoadAnimation(idleAnimation),
		WalkTrack = animator:LoadAnimation(walkAnimation),
		_moving = false,
	}, AnimationComponent)

	self.IdleTrack.Priority = Enum.AnimationPriority.Idle
	self.WalkTrack.Priority = Enum.AnimationPriority.Movement

	self.IdleTrack:Play()

	return self
end

function AnimationComponent:SetMoving(isMoving)
	if isMoving == self._moving then
		return 
	end

	self._moving = isMoving

	if isMoving then
		self.IdleTrack:Stop(0.15)
		self.WalkTrack:Play(0.15)
	else
		self.WalkTrack:Stop(0.15)
		self.IdleTrack:Play(0.15)
	end
end

function AnimationComponent:Destroy()
	if self.IdleTrack then
		self.IdleTrack:Stop(0)
		self.IdleTrack:Destroy()
	end
	if self.WalkTrack then
		self.WalkTrack:Stop(0)
		self.WalkTrack:Destroy()
	end
end

return AnimationComponent

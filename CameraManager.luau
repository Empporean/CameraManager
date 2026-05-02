local CameraService = {}
CameraService.__index = CameraService

-- Services
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService('ContextActionService')
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Janitor = require(ReplicatedStorage.Janitor)

-- Constants
local DEFAULT_CONFIG: Config = {
	Offset = Vector3.new(2.5, 2, 8),
	Smoothness = 0.15,
	FOV = 70,
	BobbingIntensity = 0.1,
	TiltIntensity = 1.5,
	SensitivyMultiplier = 1
}

local AIM_CONFIG: Config = {
	Offset = Vector3.new(1.8, 1.5, 4),
	Smoothness = 0.3,
	FOV = 50,
	BobbingIntensity = 0.05,
	TiltIntensity = 0.5,
	SensitivyMultiplier = 0.5
}

function CameraService.new()
	local self = setmetatable({}, CameraService)

	self.Camera = Workspace.CurrentCamera
	self.Player = game.Players.LocalPlayer :: Player
	
	self.Obliterator = Janitor.new()

	self.Config = table.clone(DEFAULT_CONFIG)
	self.TargetConfig = DEFAULT_CONFIG

	self.CurrentRotationX = 0
	self.CurrentRotationY = 0

	self.ShakeIntensity = 0
	self.TiltAngle = 0
	self.IsAiming = false
	
	self.CameraWeight = 0
	
	self:SetupCharacter()

	return self
end

function CameraService:SetupCharacter()
	self.Character = self.Player.Character or self.Player.CharacterAdded:Wait()
	self.RootPart = self.Character:WaitForChild("HumanoidRootPart") :: BasePart
	self.Humanoid = self.Character:WaitForChild("Humanoid") :: Humanoid
	self.Head = self.Character:WaitForChild('Head') :: BasePart
	
	-- Death + Leave
	self.Obliterator:Add(self.Character:GetPropertyChangedSignal("Parent"):Connect(function()
		self:Stop()
	end))
end

function CameraService:ApplyShake(intensity: number)
	self.ShakeIntensity = intensity
end

local function getOcclusionOffset(origin: Vector3, targetOffset: Vector3, ignoreList: {Instance}): Vector3
	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = ignoreList
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	local result = Workspace:Raycast(origin, targetOffset, rayParams)

	if result then
		return targetOffset.Unit * (result.Distance - 0.5)
	end

	return targetOffset
end

function CameraService:UpdateTilt(dt: number)
	local moveDirection = self.RootPart.CFrame:VectorToObjectSpace(self.Humanoid.MoveDirection)
	local targetTilt = -moveDirection.X * self.Config.TiltIntensity
	self.TiltAngle = math.lerp(self.TiltAngle, targetTilt, 0.1)
end

function CameraService:GetBobbing(): Vector3
	local speed = self.Humanoid.MoveDirection.Magnitude > 0 and self.Humanoid.WalkSpeed or 0
	local timer = tick() * (speed * 0.75)

	if speed > 0 then
		return Vector3.new(
			math.cos(timer) * self.Config.BobbingIntensity,
			math.sin(timer * 2) * self.Config.BobbingIntensity,
			0
		)
	end
	return Vector3.new(0, 0, 0)
end

function CameraService:SetAiming(isAiming: boolean)
	self.IsAiming = isAiming
	self.TargetConfig = isAiming and AIM_CONFIG or DEFAULT_CONFIG
end

function CameraService:Start()
	self.Camera.CameraType = Enum.CameraType.Scriptable
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	
	ContextActionService:BindAction('Aim', function(actionName: string, UserInputState: Enum.UserInputState, _inputObject)
		if UserInputState == Enum.UserInputState.Begin then
			self:SetAiming(true)
		elseif UserInputState == Enum.UserInputState.End then
			self:SetAiming(false)
		end
	end, false, Enum.UserInputType.MouseButton2)

	RunService:BindToRenderStep("CameraUpdate", Enum.RenderPriority.Camera.Value, function(dt: number)
		if not self.RootPart or not self.Humanoid then return end
		
		self.Config.FOV = math.lerp(self.Config.FOV, self.TargetConfig.FOV, 0.1)
		self.Config.Offset = self.Config.Offset:Lerp(self.TargetConfig.Offset, 0.1)

		local mouseDelta = UserInputService:GetMouseDelta()
		local sensitivy = 0.2 * self.TargetConfig.SensitivyMultiplier
		self.CurrentRotationX -= mouseDelta.X * sensitivy
		self.CurrentRotationY = math.clamp(self.CurrentRotationY - mouseDelta.Y * sensitivy, -75, 75)

		self:UpdateTilt(dt)
		local rotationCFrame = CFrame.Angles(0, math.rad(self.CurrentRotationX), 0) 
			* CFrame.Angles(math.rad(self.CurrentRotationY), 0, math.rad(self.TiltAngle))

		local rawOffset = rotationCFrame:VectorToWorldSpace(self.Config.Offset)
		local safeOffset = getOcclusionOffset(self.RootPart.Position, rawOffset, {self.Character})

		local shake = Vector3.new(
			math.noise(tick() * 20) * self.ShakeIntensity,
			math.noise(tick() * 20 + 1) * self.ShakeIntensity,
			0
		)
		self.ShakeIntensity = math.lerp(self.ShakeIntensity, 0, 0.1)

		local bobbing = self:GetBobbing()
		
		local targetWeight = self.Humanoid.MoveDirection.Magnitude > 0 and 0 or 0.5
		self.CameraWeight = math.lerp(self.CameraWeight, targetWeight, 0.1)

		local headLocalOffset = self.RootPart.CFrame:ToObjectSpace(self.Head.CFrame).Position
		local animationJitter = (headLocalOffset - Vector3.new(0, 1.5, 0)) * self.CameraWeight

		local targetPosition = self.RootPart.Position + safeOffset + bobbing + shake + animationJitter

		local lookAt = self.RootPart.Position + rotationCFrame.LookVector * 100
		local finalCFrame = CFrame.new(targetPosition, lookAt) * CFrame.Angles(0, 0, math.rad(self.TiltAngle))

		self.Camera.CFrame = self.Camera.CFrame:Lerp(finalCFrame, self.Config.Smoothness)
		self.Camera.FieldOfView = self.Config.FOV

		self.RootPart.CFrame = CFrame.new(self.RootPart.Position) * CFrame.Angles(0, math.rad(self.CurrentRotationX), 0)
	end)
end

function CameraService:Stop()
	RunService:UnbindFromRenderStep('CameraUpdate')
	ContextActionService:UnbindAction('Aim')
	
	self.Obliterator:Destroy()
	
	self.Camera.CameraType = Enum.CameraType.Custom
end

-- Types
type Config = {
	Offset: Vector3,
	Smoothness: number,
	FOV: number,
	BobbingIntensity: number,
	TiltIntensity: number,
	SensitivyMultiplier: number,
}

return CameraService

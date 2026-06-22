-- 1111alesai113 (roblox)
-- teve_ee (discord)

--[=[
    @class CameraService
    Provides a high-level API for a custom scripted third-person camera.
    Features: Smooth interpolation, Aiming states, Camera Bobbing, Tilt, and Occlusion.
]=]

local CameraService = {}
CameraService.__index = CameraService

-- Services
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService('ContextActionService')
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Dependencies
local Janitor = require(ReplicatedStorage.Janitor)
local Signal = require(ReplicatedStorage.Signal)

-- Types
type Config = {
	Offset: Vector3,
	Smoothness: number,
	FOV: number,
	BobbingIntensity: number,
	TiltIntensity: number,
	SensitivyMultiplier: number,
}

export type Camera = {
	Camera: Camera,
	Player: Player,
	
	Obliterator: Janitor.Janitor,
	
	Config: Config,
	TargetConfig: Config,
	
	CurrentRotationX: number,
	CurrentRotationY: number,
	
	ShakeIntensity: number,
	TiltAngle: number,
	IsAiming: boolean,
	
	CameraWeight: number,
	
	-- no types for these :(
	ShakeApplied: any,
	TiltApplied: any,
	AimingChanged: any,
} & typeof(CameraService)

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

local DEBUG_ENABLED = false

--[=[
    @description Creates a new instance of the CameraService.
    @return CameraService
]=]
function CameraService.new()
	local self = setmetatable({}, CameraService) :: Camera

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
	
	-- Signals
	self.ShakeApplied = Signal.new()
	
	if DEBUG_ENABLED then
		self.ShakeApplied:Connect(function(shakeIntensity: number)
			if DEBUG_ENABLED then
				print("Shake Applied:", shakeIntensity)
			end
		end)
	end
	
	self.TiltApplied = Signal.new()
	
	if DEBUG_ENABLED then
		self.TiltApplied:Connect(function(tiltAngle: number)
			if DEBUG_ENABLED then
				print("Tilt Applied:", tiltAngle)
			end
		end)
	end
	
	self.AimingChanged = Signal.new()
	
	if DEBUG_ENABLED then
		self.AimingChanged:Connect(function(state: boolean)
			if DEBUG_ENABLED then
				print("Aiming State Changed:", state)
			end
		end)
	end

	self:SetupCharacter()

	return self
end

--[=[
    @description Initializes character references and sets up cleanup connections.
    @private
]=]
function CameraService:SetupCharacter()
	self.Character = self.Player.Character or self.Player.CharacterAdded:Wait()
	self.RootPart = self.Character:WaitForChild("HumanoidRootPart") :: BasePart
	self.Humanoid = self.Character:WaitForChild("Humanoid") :: Humanoid
	self.Head = self.Character:WaitForChild('Head') :: BasePart

	-- Cleanup on Character removal or death
	self.Obliterator:Add(self.Character:GetPropertyChangedSignal("Parent"):Connect(function()
		if not self.Character.Parent then
			self:Stop()
		end
	end))
end

--[=[
    @description Adds a camera shake effect.
    @param intensity number -- The magnitude of the shake.
]=]
function CameraService:ApplyShake(intensity: number)
	self.ShakeIntensity = intensity
	self.ShakeApplied:Fire(intensity)
end

--[=[
    @description Calculates camera offset to prevent clipping through geometry.
    @param origin Vector3 -- The starting position of the check (usually RootPart).
    @param targetOffset Vector3 -- The desired relative offset.
    @param ignoreList {Instance} -- Instances for the raycast to ignore.
    @return Vector3 -- The safe offset after collision checks.
]=]
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

--[=[
    @description Updates the camera tilt based on lateral movement.
    @param dt number -- DeltaTime from RenderStep.
]=]
function CameraService:UpdateTilt(dt: number)
	local moveDirection = self.RootPart.CFrame:VectorToObjectSpace(self.Humanoid.MoveDirection)
	local targetTilt = -moveDirection.X * self.Config.TiltIntensity
	self.TiltAngle = math.lerp(self.TiltAngle, targetTilt, 0.1)
	self.TiltApplied:Fire(self.TiltAngle)
end

--[=[
    @description Calculates a procedural bobbing Vector3 based on movement speed.
    @return Vector3
]=]
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

--[=[
    @description Switches camera profile between Aiming and Default.
    @param isAiming boolean
]=]
function CameraService:SetAiming(isAiming: boolean)
	self.IsAiming = isAiming
	self.TargetConfig = isAiming and AIM_CONFIG or DEFAULT_CONFIG
	self.AimingChanged:Fire(isAiming)
end

--[=[
    @description Returns the current camera offset.
    @return Vector3
]=]
function CameraService:GetOffset(): Vector3
	return self.Config.Offset
end

--[=[
    @description Returns the current smoothness value.
    @return number
]=]
function CameraService:GetSmoothness(): number
	return self.Config.Smoothness
end

--[=[
    @description Returns the current FOV.
    @return number
]=]
function CameraService:GetFOV(): number
	return self.Config.FOV
end

--[=[
    @description Returns the current bobbing intensity.
    @return number
]=]
function CameraService:GetBobbingIntensity(): number
	return self.Config.BobbingIntensity
end

--[=[
    @description Returns the current tilt intensity.
    @return number
]=]
function CameraService:GetTiltIntensity(): number
	return self.Config.TiltIntensity
end

--[=[
    @description Returns the current sensitivity multiplier.
    @return number
]=]
function CameraService:GetSensitivityMultiplier(): number
	return self.Config.SensitivyMultiplier
end

--[=[
    @description Returns the current rotation X angle.
    @return number
]=]
function CameraService:GetRotationX(): number
	return self.CurrentRotationX
end

--[=[
    @description Returns the current rotation Y angle.
    @return number
]=]
function CameraService:GetRotationY(): number
	return self.CurrentRotationY
end

--[=[
    @description Returns the current shake intensity.
    @return number
]=]
function CameraService:GetShakeIntensity(): number
	return self.ShakeIntensity
end

--[=[
    @description Returns the current tilt angle.
    @return number
]=]
function CameraService:GetTiltAngle(): number
	return self.TiltAngle
end

--[=[
    @description Returns whether the camera is in aiming mode.
    @return boolean
]=]
function CameraService:IsAiming(): boolean
	return self.IsAiming
end

--[=[
    @description Returns the current camera weight (for head jitter).
    @return number
]=]
function CameraService:GetCameraWeight(): number
	return self.CameraWeight
end

--[=[
    @description Returns the current character instance.
    @return Model?
]=]
function CameraService:GetCharacter(): Model?
	return self.Character
end

--[=[
    @description Returns the current root part.
    @return BasePart?
]=]
function CameraService:GetRootPart(): BasePart?
	return self.RootPart
end

--[=[
    @description Returns the current humanoid.
    @return Humanoid?
]=]
function CameraService:GetHumanoid(): Humanoid?
	return self.Humanoid
end

--[=[
    @description Returns the current head part.
    @return BasePart?
]=]
function CameraService:GetHead(): BasePart?
	return self.Head
end

--[=[
    @description Returns the target config (aiming or default).
    @return Config
]=]
function CameraService:GetTargetConfig(): Config
	return self.TargetConfig
end

--[=[
    @description Returns whether debug mode is enabled.
    @return boolean
]=]
function CameraService:IsDebugEnabled(): boolean
	return DEBUG_ENABLED
end

--[=[
    @description Starts the camera loop, locks the mouse, and binds input actions.
]=]

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

	-- Main Render
	RunService:BindToRenderStep("CameraUpdate", Enum.RenderPriority.Camera.Value, function(dt: number)
		if not self.RootPart or not self.Humanoid then return end

		-- Smooth Config Transitions
		self.Config.FOV = math.lerp(self.Config.FOV, self.TargetConfig.FOV, 0.1)
		self.Config.Offset = self.Config.Offset:Lerp(self.TargetConfig.Offset, 0.1)

		-- Mouse Input Handling
		local mouseDelta = UserInputService:GetMouseDelta()
		local sensitivy = 0.2 * self.TargetConfig.SensitivyMultiplier
		self.CurrentRotationX -= mouseDelta.X * sensitivy
		self.CurrentRotationY = math.clamp(self.CurrentRotationY - mouseDelta.Y * sensitivy, -75, 75)

		self:UpdateTilt(dt)

		-- Rotation Calculation
		local rotationCFrame = CFrame.Angles(0, math.rad(self.CurrentRotationX), 0) 
			* CFrame.Angles(math.rad(self.CurrentRotationY), 0, math.rad(self.TiltAngle))

		-- Collision Check
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

		-- Final CFrame
		local targetPosition = self.RootPart.Position + safeOffset + bobbing + shake + animationJitter
		local lookAt = self.RootPart.Position + rotationCFrame.LookVector * 100
		local finalCFrame = CFrame.new(targetPosition, lookAt) * CFrame.Angles(0, 0, math.rad(self.TiltAngle))

		-- Update Camera
		self.Camera.CFrame = self.Camera.CFrame:Lerp(finalCFrame, self.Config.Smoothness)
		self.Camera.FieldOfView = self.Config.FOV

		-- Rotate Character to match Camera
		self.RootPart.CFrame = CFrame.new(self.RootPart.Position) * CFrame.Angles(0, math.rad(self.CurrentRotationX), 0)
	end)
end

--[=[
    @description Stops the camera loop, unbinds actions, and cleans up memory.
]=]
function CameraService:Stop()
	RunService:UnbindFromRenderStep('CameraUpdate')
	ContextActionService:UnbindAction('Aim')

	self.Obliterator:Destroy()

	self.Camera.CameraType = Enum.CameraType.Custom
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
end

return CameraService

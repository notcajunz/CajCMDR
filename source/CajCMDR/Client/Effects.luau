--[[
	Client-side effects that the server asks for with Admin.Fx(player, "name", ...).
	Only the server can trigger these, so other players cannot use them on you.
]]

const Lighting = game:GetService("Lighting")
const Players = game:GetService("Players")
const RunService = game:GetService("RunService")
const StarterGui = game:GetService("StarterGui")
const TweenService = game:GetService("TweenService")
const UserInputService = game:GetService("UserInputService")

const Notifications = require(script.Parent.Notifications)

const player = Players.LocalPlayer

const Effects = {}
const handlers: { [string]: (...any) -> () } = {}

-- state
local flyConnection: RBXScriptConnection? = nil
local flyObjects: { Instance } = {}
local noclipConnection: RBXScriptConnection? = nil
local infJumpConnection: RBXScriptConnection? = nil
local viewConnection: RBXScriptConnection? = nil
local espConnections: { RBXScriptConnection } = {}
local xrayConnection: RBXScriptConnection? = nil
local xrayParts: { [BasePart]: boolean } = {}
local savedLighting: { [string]: any }? = nil
local hiddenGuis: { [ScreenGui]: boolean } = {}
local shakeCounter = 0

const function camera(): Camera
	return workspace.CurrentCamera
end

const function getHumanoid(): Humanoid?
	const character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

const function getRoot(): BasePart?
	const character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

const function overlay(name: string, color: Color3): Frame
	const screen = Instance.new("ScreenGui")
	screen.Name = name
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 500
	screen.Parent = player:WaitForChild("PlayerGui")

	const frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	frame.Parent = screen
	return frame
end

----------------------------------------------------------------------------------------------------
-- Flight
----------------------------------------------------------------------------------------------------

handlers.unfly = function()
	if flyConnection then
		flyConnection:Disconnect()
		flyConnection = nil
	end

	for _, object in ipairs(flyObjects) do
		object:Destroy()
	end
	table.clear(flyObjects)

	const humanoid = getHumanoid()
	if humanoid then
		humanoid.PlatformStand = false
	end
end

handlers.fly = function(speed: number?)
	handlers.unfly()

	const root = getRoot()
	const humanoid = getHumanoid()
	if not root or not humanoid then
		return
	end

	const flySpeed = speed or 60

	const attachment = Instance.new("Attachment")
	attachment.Name = "CajFlyA"
	attachment.Parent = root

	const velocity = Instance.new("LinearVelocity")
	velocity.Name = "CajFly"
	velocity.Attachment0 = attachment
	velocity.MaxForce = math.huge
	velocity.VectorVelocity = Vector3.zero
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.Parent = root

	flyObjects = { attachment, velocity }
	humanoid.PlatformStand = true

	flyConnection = RunService.RenderStepped:Connect(function()
		const currentRoot = getRoot()
		const currentHumanoid = getHumanoid()
		if not currentRoot or not currentHumanoid or currentRoot ~= root then
			handlers.unfly()
			return
		end

		currentHumanoid.PlatformStand = true

		const cam = camera().CFrame
		local direction = currentHumanoid.MoveDirection
		-- Moving toward where the camera looks also moves up/down.
		const flatLook = Vector3.new(cam.LookVector.X, 0, cam.LookVector.Z)
		if direction.Magnitude > 0 and flatLook.Magnitude > 0.001 then
			const forwardAmount = direction:Dot(flatLook.Unit)
			direction += Vector3.new(0, cam.LookVector.Y * math.max(forwardAmount, 0), 0)
		end

		if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
			direction += Vector3.new(0, 1, 0)
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.Q) then
			direction -= Vector3.new(0, 1, 0)
		end

		velocity.VectorVelocity = if direction.Magnitude > 0.05 then direction.Unit * flySpeed else Vector3.zero

		if flatLook.Magnitude > 0.001 then
			currentRoot.CFrame = CFrame.lookAt(currentRoot.Position, currentRoot.Position + flatLook)
		end
	end)
end

----------------------------------------------------------------------------------------------------
-- Noclip / infinite jump
----------------------------------------------------------------------------------------------------

handlers.clip = function()
	if noclipConnection then
		noclipConnection:Disconnect()
		noclipConnection = nil
	end
end

handlers.noclip = function()
	handlers.clip()
	noclipConnection = RunService.Stepped:Connect(function()
		const character = player.Character
		if not character then
			return
		end

		for _, part in ipairs(character:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CanCollide = false
			end
		end
	end)
end

handlers.uninfjump = function()
	if infJumpConnection then
		infJumpConnection:Disconnect()
		infJumpConnection = nil
	end
end

handlers.infjump = function()
	handlers.uninfjump()
	infJumpConnection = UserInputService.JumpRequest:Connect(function()
		const humanoid = getHumanoid()
		if humanoid then
			humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		end
	end)
end

----------------------------------------------------------------------------------------------------
-- Camera
----------------------------------------------------------------------------------------------------

handlers.fov = function(degrees: number)
	TweenService:Create(camera(), TweenInfo.new(0.4), { FieldOfView = math.clamp(degrees, 1, 120) }):Play()
end

handlers.firstperson = function()
	player.CameraMode = Enum.CameraMode.LockFirstPerson
end

handlers.thirdperson = function()
	player.CameraMode = Enum.CameraMode.Classic
	player.CameraMaxZoomDistance = 128
end

handlers.zoom = function(distance: number)
	player.CameraMaxZoomDistance = math.max(distance, 0.5)
end

handlers.unview = function()
	if viewConnection then
		viewConnection:Disconnect()
		viewConnection = nil
	end

	const humanoid = getHumanoid()
	if humanoid then
		camera().CameraSubject = humanoid
	end
end

handlers.view = function(userId: number)
	handlers.unview()

	const target = Players:GetPlayerByUserId(userId)
	if not target then
		return
	end

	viewConnection = RunService.RenderStepped:Connect(function()
		const character = target.Character
		const humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and camera().CameraSubject ~= humanoid then
			camera().CameraSubject = humanoid
		end

		if not target.Parent then
			handlers.unview()
		end
	end)
end

handlers.shake = function(seconds: number?, intensity: number?)
	shakeCounter += 1
	const id = shakeCounter
	const duration = seconds or 3
	const strength = (intensity or 1) * 0.35
	const started = os.clock()
	const name = "CajShake"

	pcall(RunService.UnbindFromRenderStep, RunService, name)
	RunService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value + 1, function()
		const elapsed = os.clock() - started
		if id ~= shakeCounter or elapsed >= duration then
			RunService:UnbindFromRenderStep(name)
			return
		end

		const fade = 1 - elapsed / duration
		const offset = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * strength * fade
		camera().CFrame *= CFrame.new(offset) * CFrame.Angles(0, 0, (math.random() - 0.5) * 0.05 * strength * fade)
	end)
end

----------------------------------------------------------------------------------------------------
-- Screen effects
----------------------------------------------------------------------------------------------------

handlers.unblind = function()
	const gui = player:WaitForChild("PlayerGui"):FindFirstChild("CajBlind")
	if gui then
		gui:Destroy()
	end
end

handlers.blind = function()
	handlers.unblind()
	overlay("CajBlind", Color3.new(0, 0, 0))
end

handlers.flash = function()
	const frame = overlay("CajFlash", Color3.new(1, 1, 1))
	const tween = TweenService:Create(frame, TweenInfo.new(1.6), { BackgroundTransparency = 1 })
	tween:Play()
	tween.Completed:Connect(function()
		if frame.Parent then
			frame.Parent:Destroy()
		end
	end)
end

handlers.unblur = function()
	const blur = Lighting:FindFirstChild("CajBlur")
	if blur then
		blur:Destroy()
	end
end

handlers.blur = function(size: number?)
	handlers.unblur()
	const blur = Instance.new("BlurEffect")
	blur.Name = "CajBlur"
	blur.Size = 0
	blur.Parent = Lighting
	TweenService:Create(blur, TweenInfo.new(0.5), { Size = math.clamp(size or 20, 1, 56) }):Play()
end

handlers.unfullbright = function()
	if savedLighting then
		for property, value in pairs(savedLighting) do
			(Lighting :: any)[property] = value
		end
		savedLighting = nil
	end
end

handlers.fullbright = function()
	if not savedLighting then
		savedLighting = {
			Brightness = Lighting.Brightness,
			Ambient = Lighting.Ambient,
			OutdoorAmbient = Lighting.OutdoorAmbient,
			FogEnd = Lighting.FogEnd,
			GlobalShadows = Lighting.GlobalShadows,
		}
	end

	Lighting.Brightness = 2
	Lighting.Ambient = Color3.new(1, 1, 1)
	Lighting.OutdoorAmbient = Color3.new(1, 1, 1)
	Lighting.FogEnd = 1e6
	Lighting.GlobalShadows = false
end

handlers.unxray = function()
	if xrayConnection then
		xrayConnection:Disconnect()
		xrayConnection = nil
	end

	for part in pairs(xrayParts) do
		part.LocalTransparencyModifier = 0
	end
	table.clear(xrayParts)
end

handlers.xray = function()
	handlers.unxray()

	const function apply(part: Instance)
		if part:IsA("BasePart") and part.Transparency < 0.9 and not (player.Character and part:IsDescendantOf(player.Character)) then
			if not part.Parent or not part.Parent:FindFirstChildOfClass("Humanoid") then
				xrayParts[part] = true
				part.LocalTransparencyModifier = 0.7
			end
		end
	end

	xrayConnection = workspace.DescendantAdded:Connect(apply)

	task.spawn(function()
		local processed = 0
		for _, descendant in ipairs(workspace:GetDescendants()) do
			apply(descendant)
			processed += 1
			if processed % 400 == 0 then
				task.wait()
			end
		end
	end)
end

handlers.unesp = function()
	for _, connection in ipairs(espConnections) do
		connection:Disconnect()
	end
	table.clear(espConnections)

	for _, other in ipairs(Players:GetPlayers()) do
		const character = other.Character
		const highlight = character and character:FindFirstChild("CajESP")
		if highlight then
			highlight:Destroy()
		end
	end
end

handlers.esp = function()
	handlers.unesp()

	const function mark(other: Player, character: Model)
		if other == player then
			return
		end

		const old = character:FindFirstChild("CajESP")
		if old then
			old:Destroy()
		end

		const highlight = Instance.new("Highlight")
		highlight.Name = "CajESP"
		highlight.FillTransparency = 0.6
		highlight.OutlineTransparency = 0
		highlight.FillColor = other.TeamColor.Color
		highlight.OutlineColor = Color3.new(1, 1, 1)
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.Parent = character
	end

	const function track(other: Player)
		if other.Character then
			mark(other, other.Character)
		end
		table.insert(
			espConnections,
			other.CharacterAdded:Connect(function(character)
				mark(other, character)
			end)
		)
	end

	for _, other in ipairs(Players:GetPlayers()) do
		track(other)
	end
	table.insert(espConnections, Players.PlayerAdded:Connect(track))
end

handlers.showgui = function()
	for gui in pairs(hiddenGuis) do
		gui.Enabled = true
	end
	table.clear(hiddenGuis)

	pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.All, true)
end

handlers.hidegui = function()
	handlers.showgui()

	for _, gui in ipairs(player:WaitForChild("PlayerGui"):GetChildren()) do
		if gui:IsA("ScreenGui") and gui.Enabled and not gui.Name:find("Caj") and gui.Name ~= "Cmdr" then
			hiddenGuis[gui] = true
			gui.Enabled = false
		end
	end

	pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.All, false)
end

handlers.countdown = function(seconds: number, caption: string?)
	Notifications.Countdown(seconds, caption)
end

handlers.reset = function()
	for _, name in ipairs({ "unfly", "clip", "uninfjump", "unview", "unblind", "unblur", "unfullbright", "unxray", "unesp", "showgui", "thirdperson" }) do
		handlers[name]()
	end

	camera().FieldOfView = 70
end

----------------------------------------------------------------------------------------------------

function Effects.Run(effect: string, ...: any)
	const handler = handlers[effect]
	if not handler then
		warn(`[CajAdmin] Unknown client effect "{effect}"`)
		return
	end

	const arguments = table.pack(...)
	task.spawn(function()
		const ok, err = pcall(handler, table.unpack(arguments, 1, arguments.n))
		if not ok then
			warn(`[CajAdmin] Client effect "{effect}" failed: {err}`)
		end
	end)
end

-- Flight stops when the character respawns.
player.CharacterAdded:Connect(function()
	handlers.unfly()
end)

return Effects

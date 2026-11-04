--[[
	Fun: effects, explosions, emotes and silly avatar changes.
]]

const Debris = game:GetService("Debris")
const RunService = game:GetService("RunService")
const TweenService = game:GetService("TweenService")

const EMOTE_IDS = {
	wave = 507770239,
	point = 507770453,
	dance = 507771019,
	dance2 = 507776043,
	dance3 = 507777268,
	laugh = 507770818,
	cheer = 507770677,
}
const DANCES = { "dance", "dance2", "dance3" }

return function(Admin)
	const rainbowPlayers: { [Player]: boolean } = {}
	local rainbowConnection: RBXScriptConnection? = nil

	----------------------------------------------------------------------------------------------------
	-- helpers
	----------------------------------------------------------------------------------------------------

	const function describe(count: number, verb: string): string
		return Admin.Result(verb, count)
	end

	const function bodyParts(character: Model): { BasePart }
		const parts = {}
		for _, child in ipairs(character:GetChildren()) do
			if child:IsA("BasePart") and child.Name ~= "HumanoidRootPart" then
				table.insert(parts, child)
			end
		end

		return parts
	end

	const function visualExplosion(position: Vector3, radius: number)
		const explosion = Instance.new("Explosion")
		explosion.Position = position
		explosion.BlastRadius = radius
		explosion.BlastPressure = 0
		explosion.DestroyJointRadiusPercent = 0
		explosion.ExplosionType = Enum.ExplosionType.NoCraters
		explosion.Parent = workspace
	end

	const function deadlyExplosion(position: Vector3, radius: number, pressure: number?)
		const explosion = Instance.new("Explosion")
		explosion.Position = position
		explosion.BlastRadius = radius
		explosion.BlastPressure = pressure or 500000
		explosion.DestroyJointRadiusPercent = 1
		explosion.ExplosionType = Enum.ExplosionType.NoCraters
		explosion.Parent = workspace
	end

	const function playEmote(humanoid: Humanoid, emote: string): boolean
		const id = EMOTE_IDS[emote]
		const animator = humanoid:FindFirstChildOfClass("Animator")
		if not id or not animator or humanoid.RigType ~= Enum.HumanoidRigType.R15 then
			return false
		end

		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			if track.Name == "CajEmote" then
				track:Stop()
			end
		end

		const animation = Instance.new("Animation")
		animation.Name = "CajEmote"
		animation.AnimationId = `rbxassetid://{id}`

		const track = animator:LoadAnimation(animation)
		track.Priority = Enum.AnimationPriority.Action
		track.Looped = emote:find("dance") ~= nil
		track:Play()
		return true
	end

	const function stopEmotes(humanoid: Humanoid)
		const animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then
			for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
				if track.Name == "CajEmote" then
					track:Stop()
				end
			end
		end
	end

	const function stepRainbow()
		const hue = (os.clock() * 0.4) % 1
		const color = Color3.fromHSV(hue, 1, 1)
		local active = false

		for player in pairs(rainbowPlayers) do
			const character = player.Character
			if player.Parent and character then
				active = true
				for _, part in ipairs(bodyParts(character)) do
					part.Color = color
				end
			else
				rainbowPlayers[player] = nil
			end
		end

		if not active and rainbowConnection then
			rainbowConnection:Disconnect()
			rainbowConnection = nil
		end
	end

	const function firework(position: Vector3)
		const anchor = Instance.new("Part")
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.Transparency = 1
		anchor.Size = Vector3.one
		anchor.Position = position
		anchor.Parent = Admin.GetObjectsFolder()

		const emitter = Instance.new("ParticleEmitter")
		emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		emitter.Color = ColorSequence.new(Color3.fromHSV(math.random(), 1, 1))
		emitter.Lifetime = NumberRange.new(1, 2)
		emitter.Speed = NumberRange.new(30, 50)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Acceleration = Vector3.new(0, -20, 0)
		emitter.Size = NumberSequence.new(1.5, 0)
		emitter.LightEmission = 1
		emitter.Rate = 0
		emitter.Enabled = false
		emitter.Parent = anchor
		emitter:Emit(150)

		visualExplosion(position, 1)
		Debris:AddItem(anchor, 3)
	end

	--[[ Builds the on/off pair for a simple attached effect (fire, smoke, ...). ]]
	const function effectPair(
		name: string,
		offName: string,
		aliasesOn: { string }?,
		description: string,
		className: string,
		effectName: string,
		configure: (Instance, Color3?) -> (),
		colorOptional: boolean
	)
		const args = { { Type = "targets", Name = "players", Description = "The players." } }
		if colorOptional then
			table.insert(args, { Type = "color3", Name = "color", Description = "Optional color.", Optional = true })
		end

		return {
			Name = name,
			Aliases = aliasesOn,
			Role = "Moderator",
			Description = description,
			Args = args,
			Run = function(_, players: { Player }, color: Color3?)
				return describe(
					Admin.Each(players, function(_player, character)
						const instance = Admin.AddEffect(character, className, effectName, nil, "HumanoidRootPart")
						if instance then
							configure(instance, color)
						end
					end),
					"Applied the effect to"
				)
			end,
		},
			{
				Name = offName,
				Role = "Moderator",
				Description = `Removes the {name} effect.`,
				Args = { { Type = "players", Name = "players", Description = "The players." } },
				Run = function(_, players: { Player })
					return describe(
						Admin.Each(players, function(_player, character)
							Admin.RemoveEffect(character, effectName)
						end),
						"Cleared"
					)
				end,
			}
	end

	const function materialLook(name: string, description: string, apply: (Model) -> ())
		return {
			Name = name,
			Role = "Moderator",
			Description = description,
			Args = { { Type = "targets", Name = "players", Description = "The players." } },
			Run = function(_, players: { Player })
				return describe(Admin.Each(players, function(_player, character)
					apply(character)
				end), "Transformed")
			end,
		}
	end

	const function scaleLook(name: string, aliases: { string }?, description: string, height: number?, width: number?, head: number?)
		return {
			Name = name,
			Aliases = aliases,
			Role = "Moderator",
			Description = description,
			Args = { { Type = "targets", Name = "players", Description = "The players." } },
			Run = function(_, players: { Player })
				const count = Admin.Each(players, function(_player, _character, humanoid)
					return Admin.SetScale(humanoid, height, width, head)
				end)

				if count == 0 then
					return "Nobody was changed (this only works on R15 avatars)."
				end

				return describe(count, "Transformed")
			end,
		}
	end

	----------------------------------------------------------------------------------------------------
	-- commands
	----------------------------------------------------------------------------------------------------

	const commands = {}

	const function add(...: any)
		for _, spec in ipairs({ ... }) do
			table.insert(commands, spec)
		end
	end

	add(effectPair("fire", "unfire", { "burn" }, "Sets players on fire (harmless).", "Fire", "CajFire", function(instance, color)
		const fire = instance :: Fire
		fire.Size = 8
		fire.Heat = 10
		if color then
			fire.Color = color
			fire.SecondaryColor = color
		end
	end, true))

	add(effectPair("smoke", "unsmoke", nil, "Surrounds players with smoke.", "Smoke", "CajSmoke", function(instance, color)
		const smoke = instance :: Smoke
		smoke.Size = 10
		smoke.RiseVelocity = 8
		smoke.Opacity = 0.5
		if color then
			smoke.Color = color
		end
	end, true))

	add(effectPair("sparkles", "unsparkles", { "sparkle" }, "Makes players sparkle.", "Sparkles", "CajSparkles", function(instance, color)
		if color then
			(instance :: Sparkles).SparkleColor = color
		end
	end, true))

	add(effectPair("light", "unlight", { "glow" }, "Makes players glow.", "PointLight", "CajLight", function(instance, color)
		const light = instance :: PointLight
		light.Range = 24
		light.Brightness = 3
		if color then
			light.Color = color
		end
	end, true))

	add({
		Name = "trail",
		Role = "Moderator",
		Description = "Gives players a colored trail.",
		Args = {
			{ Type = "targets", Name = "players", Description = "The players." },
			{ Type = "color3", Name = "color", Description = "Trail color.", Optional = true },
		},
		Run = function(_, players: { Player }, color: Color3?)
			return describe(
				Admin.Each(players, function(_player, character, _humanoid, root)
					Admin.RemoveEffect(character, "CajTrail")
					Admin.RemoveEffect(character, "CajTrailA")
					Admin.RemoveEffect(character, "CajTrailB")

					const top = Instance.new("Attachment")
					top.Name = "CajTrailA"
					top.Position = Vector3.new(0, 1, 0)
					top.Parent = root

					const bottom = Instance.new("Attachment")
					bottom.Name = "CajTrailB"
					bottom.Position = Vector3.new(0, -1, 0)
					bottom.Parent = root

					const trail = Instance.new("Trail")
					trail.Name = "CajTrail"
					trail.Attachment0 = top
					trail.Attachment1 = bottom
					trail.Lifetime = 0.9
					trail.LightEmission = 1
					trail.Color = ColorSequence.new(color or Color3.fromHSV(math.random(), 1, 1))
					trail.Transparency = NumberSequence.new(0, 1)
					trail.Parent = root
				end),
				"Gave a trail to"
			)
		end,
	}, {
		Name = "untrail",
		Role = "Moderator",
		Description = "Removes trails.",
		Args = { { Type = "players", Name = "players", Description = "The players." } },
		Run = function(_, players: { Player })
			return describe(
				Admin.Each(players, function(_player, character)
					Admin.RemoveEffect(character, "CajTrail")
					Admin.RemoveEffect(character, "CajTrailA")
					Admin.RemoveEffect(character, "CajTrailB")
				end),
				"Cleared"
			)
		end,
	})

	add({
		Name = "explode",
		Role = "Admin",
		Description = "Blows players up (also hurts people standing next to them).",
		Args = { { Type = "targets", Name = "players", Description = "The players." } },
		Run = function(_, players: { Player })
			return describe(
				Admin.Each(players, function(_player, _character, _humanoid, root)
					deadlyExplosion(root.Position, 8)
				end),
				"Exploded"
			)
		end,
	}, {
		Name = "nuke",
		Role = "Admin",
		Description = "Drops a huge explosion on players. Everyone nearby will die.",
		Args = { { Type = "targets", Name = "players", Description = "The players." } },
		Run = function(_, players: { Player })
			return describe(
				Admin.Each(players, function(_player, _character, _humanoid, root)
					const position = root.Position

					const sphere = Instance.new("Part")
					sphere.Shape = Enum.PartType.Ball
					sphere.Anchored = true
					sphere.CanCollide = false
					sphere.Material = Enum.Material.Neon
					sphere.Color = Color3.fromRGB(255, 170, 40)
					sphere.Size = Vector3.one * 4
					sphere.Position = position
					sphere.Parent = Admin.GetObjectsFolder()

					TweenService:Create(sphere, TweenInfo.new(1.2), { Size = Vector3.one * 90, Transparency = 1 }):Play()
					Debris:AddItem(sphere, 1.4)

					deadlyExplosion(position, 60, 800000)
				end),
				"Nuked"
			)
		end,
	}, {
		Name = "lightning",
		Aliases = { "smite", "strike" },
		Role = "Moderator",
		Description = "Strikes players with a bolt of lightning (25 damage).",
		Args = { { Type = "targets", Name = "players", Description = "The players." } },
		Run = function(_, players: { Player })
			return describe(
				Admin.Each(players, function(_player, _character, humanoid, root)
					const position = root.Position

					const bolt = Instance.new("Part")
					bolt.Anchored = true
					bolt.CanCollide = false
					bolt.CanQuery = false
					bolt.Material = Enum.Material.Neon
					bolt.Color = Color3.fromRGB(190, 220, 255)
					bolt.Size = Vector3.new(1.2, 300, 1.2)
					bolt.Position = position + Vector3.new(0, 150, 0)
					bolt.Parent = Admin.GetObjectsFolder()
					Debris:AddItem(bolt, 0.25)

					visualExplosion(position, 6)
					humanoid:TakeDamage(25)
				end),
				"Struck"
			)
		end,
	}, {
		Name = "meteor",
		Role = "Admin",
		Description = "Drops a flaming meteor on players.",
		Args = { { Type = "targets", Name = "players", Description = "The players." } },
		Run = function(_, players: { Player })
			return describe(
				Admin.Each(players, function(_player, _character, _humanoid, root)
					const rock = Instance.new("Part")
					rock.Shape = Enum.PartType.Ball
					rock.Size = Vector3.one * 10
					rock.Material = Enum.Material.Slate
					rock.Color = Color3.fromRGB(70, 40, 30)
					rock.Position = root.Position + Vector3.new(0, 200, 0)
					rock.Parent = Admin.GetObjectsFolder()
					rock:SetNetworkOwner(nil)
					rock.AssemblyLinearVelocity = Vector3.new(0, -220, 0)

					const fire = Instance.new("Fire")
					fire.Size = 18
					fire.Parent = rock

					local landed = false
					rock.Touched:Connect(function(other)
						if landed or other:IsDescendantOf(Admin.GetObjectsFolder()) then
							return
						end

						landed = true
						deadlyExplosion(rock.Position, 18, 300000)
						rock:Destroy()
					end)

					Debris:AddItem(rock, 12)
				end),
				"Sent a meteor at"
			)
		end,
	}, {
		Name = "fireworks",
		Role = "Moderator",
		Description = "Shoots a fireworks show above players.",
		Args = { { Type = "players", Name = "players", Description = "The players." } },
		Run = function(_, players: { Player })
			return describe(
				Admin.Each(players, function(_player, _character, _humanoid, root)
					const origin = root.Position
					for index = 1, 7 do
						task.delay(index * 0.45, function()
							firework(origin + Vector3.new(math.random(-14, 14), math.random(24, 38), math.random(-14, 14)))
						end)
					end
				end),
				"Launched fireworks for"
			)
		end,
	})

	add({
		Name = "fling",
		Role = "Moderator",
		Description = "Flings players across the map.",
		Args = {
			{ Type = "targets", Name = "players", Description = "The players." },
			{ Type = "positiveNumber", Name = "power", Description = "Default 150.", Optional = true },
		},
		Run = function(_, players: { Player }, power: number?)
			const strength = math.min(power or 150, 1000)
			return describe(
				Admin.Each(players, function(_player, _character, humanoid, root)
					const direction = Vector3.new(math.random() - 0.5, 0.6, math.random() - 0.5).Unit
					humanoid.PlatformStand = true
					root.AssemblyLinearVelocity = direction * strength
					root.AssemblyAngularVelocity = Vector3.new(math.random(-20, 20), math.random(-20, 20), math.random(-20, 20))

					task.delay(2, function()
						if humanoid.Parent then
							humanoid.PlatformStand = false
						end
					end)
				end),
				"Flung"
			)
		end,
	}, {
		Name = "launch",
		Role = "Moderator",
		Description = "Launches players straight up.",
		Args = {
			{ Type = "targets", Name = "players", Description = "The players." },
			{ Type = "positiveNumber", Name = "power", Description = "Default 120.", Optional = true },
		},
		Run = function(_, players: { Player }, power: number?)
			return describe(
				Admin.Each(players, function(_player, _character, _humanoid, root)
					root.AssemblyLinearVelocity = Vector3.new(0, math.min(power or 120, 1000), 0)
				end),
				"Launched"
			)
		end,
	}, {
		Name = "rocket",
		Role = "Admin",
		Description = "Straps a rocket to players: up they go, then boom.",
		Args = { { Type = "targets", Name = "players", Description = "The players." } },
		Run = function(_, players: { Player })
			return describe(
				Admin.Each(players, function(_player, character, humanoid, root)
					Admin.AddEffect(character, "Fire", "CajFire", { Size = 14 }, "HumanoidRootPart")
					root.AssemblyLinearVelocity = Vector3.new(0, 260, 0)

					task.delay(2, function()
						if character.Parent and humanoid.Parent then
							const top = character:FindFirstChild("HumanoidRootPart")
							if top and top:IsA("BasePart") then
								deadlyExplosion(top.Position, 8)
							end
							humanoid.Health = 0
						end
					end)
				end),
				"Launched a rocket with"
			)
		end,
	}, {
		Name = "slap",
		Role = "Moderator",
		Description = "Slaps players (10 damage and a shove).",
		Args = { { Type = "targets", Name = "players", Description = "The players." } },
		Run = function(_, players: { Player })
			return describe(
				Admin.Each(players, function(_player, _character, humanoid, root)
					humanoid:TakeDamage(10)
					root.AssemblyLinearVelocity = Vector3.new(math.random(-60, 60), 70, math.random(-60, 60))
				end),
				"Slapped"
			)
		end,
	}, {
		Name = "spin",
		Role = "Moderator",
		Description = "Spins players around.",
		Args = {
			{ Type = "targets", Name = "players", Description = "The players." },
			{ Type = "number", Name = "speed", Description = "Radians per second (default 12).", Optional = true },
		},
		Run = function(_, players: { Player }, speed: number?)
			return describe(
				Admin.Each(players, function(_player, character, humanoid, root)
					Admin.RemoveEffect(character, "CajSpin")
					Admin.RemoveEffect(character, "CajSpinA")

					const attachment = Instance.new("Attachment")
					attachment.Name = "CajSpinA"
					attachment.Parent = root

					const spinner = Instance.new("AngularVelocity")
					spinner.Name = "CajSpin"
					spinner.Attachment0 = attachment
					spinner.MaxTorque = math.huge
					spinner.AngularVelocity = Vector3.new(0, math.clamp(speed or 12, -100, 100), 0)
					spinner.RelativeTo = Enum.ActuatorRelativeTo.World
					spinner.Parent = root

					humanoid.PlatformStand = true
				end),
				"Spun"
			)
		end,
	}, {
		Name = "unspin",
		Role = "Moderator",
		Description = "Stops players from spinning.",
		Args = { { Type = "players", Name = "players", Description = "The players." } },
		Run = function(_, players: { Player })
			return describe(
				Admin.Each(players, function(_player, character, humanoid)
					Admin.RemoveEffect(character, "CajSpin")
					Admin.RemoveEffect(character, "CajSpinA")
					humanoid.PlatformStand = false
				end),
				"Stopped"
			)
		end,
	}, {
		Name = "trip",
		Role = "Moderator",
		Description = "Makes players trip and fall over for a few seconds.",
		Args = { { Type = "targets", Name = "players", Description = "The players." } },
		Run = function(_, players: { Player })
			return describe(
				Admin.Each(players, function(_player, _character, humanoid, root)
					humanoid:ChangeState(Enum.HumanoidStateType.Ragdoll)
					root.AssemblyLinearVelocity = root.CFrame.LookVector * 30 + Vector3.new(0, 12, 0)

					task.delay(3, function()
						if humanoid.Parent then
							humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
						end
					end)
				end),
				"Tripped"
			)
		end,
	})

	add({
		Name = "rainbow",
		Role = "Moderator",
		Description = "Cycles players' body color through the rainbow.",
		Args = { { Type = "targets", Name = "players", Description = "The players." } },
		Run = function(_, players: { Player })
			const count = Admin.EachPlayer(players, function(player)
				rainbowPlayers[player] = true
			end)

			if not rainbowConnection and count > 0 then
				rainbowConnection = RunService.Heartbeat:Connect(stepRainbow)
			end

			return describe(count, "Made rainbow:")
		end,
	}, {
		Name = "unrainbow",
		Role = "Moderator",
		Description = "Stops the rainbow effect.",
		Args = { { Type = "players", Name = "players", Description = "The players." } },
		Run = function(_, players: { Player })
			return describe(
				Admin.EachPlayer(players, function(player)
					rainbowPlayers[player] = nil
				end),
				"Stopped the rainbow for"
			)
		end,
	})

	add(
		materialLook("neon", "Turns players into glowing neon.", function(character)
			for _, part in ipairs(bodyParts(character)) do
				part.Material = Enum.Material.Neon
			end
		end),
		materialLook("glass", "Turns players into glass.", function(character)
			for _, part in ipairs(bodyParts(character)) do
				part.Material = Enum.Material.Glass
				part.Transparency = 0.4
				part.Reflectance = 0.2
			end
		end),
		materialLook("gold", "Turns players into shiny gold statues.", function(character)
			for _, part in ipairs(bodyParts(character)) do
				part.Material = Enum.Material.Metal
				part.Color = Color3.fromRGB(255, 200, 40)
				part.Reflectance = 0.3
			end
		end),
		materialLook("ghost", "Turns players into see-through ghosts.", function(character)
			Admin.SetTransparency(character, 0.6)
			for _, part in ipairs(bodyParts(character)) do
				part.Material = Enum.Material.ForceField
			end
		end),
		materialLook("ice", "Freezes players solid in a block of ice.", function(character)
			for _, part in ipairs(bodyParts(character)) do
				part.Material = Enum.Material.Ice
				part.Color = Color3.fromRGB(170, 220, 255)
			end

			const root = character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				root.Anchored = true
			end

			Admin.RemoveEffect(character, "CajIce")
			const marker = Instance.new("BoolValue")
			marker.Name = "CajIce"
			marker.Parent = character
		end),
		scaleLook("bighead", { "megahead" }, "Gives players a giant head.", nil, nil, 3),
		scaleLook("giant", { "huge" }, "Makes players 3x bigger.", 3, 3, 3),
		scaleLook("tiny", { "small", "mini" }, "Makes players tiny.", 0.4, 0.4, 0.4)
	)

	add({
		Name = "emote",
		Role = "Moderator",
		Description = "Makes players play an emote (R15 only).",
		Args = {
			{ Type = "targets", Name = "players", Description = "The players." },
			{ Type = "emote", Name = "emote", Description = "wave, point, dance, dance2, dance3, laugh, cheer." },
		},
		Run = function(_, players: { Player }, emote: string)
			const count = Admin.Each(players, function(_player, _character, humanoid)
				return playEmote(humanoid, emote)
			end)

			if count == 0 then
				return "Nobody could play the emote (it only works on R15 avatars)."
			end

			return describe(count, "Made emote:")
		end,
	}, {
		Name = "dance",
		Role = "Moderator",
		Description = "Makes players dance (R15 only).",
		Args = { { Type = "targets", Name = "players", Description = "The players." } },
		Run = function(_, players: { Player })
			const count = Admin.Each(players, function(_player, _character, humanoid)
				return playEmote(humanoid, DANCES[math.random(1, #DANCES)])
			end)

			if count == 0 then
				return "Nobody could dance (it only works on R15 avatars)."
			end

			return describe(count, "Made dance:")
		end,
	}, {
		Name = "stopemote",
		Aliases = { "undance" },
		Role = "Moderator",
		Description = "Stops emotes started by commands.",
		Args = { { Type = "players", Name = "players", Description = "The players." } },
		Run = function(_, players: { Player })
			return describe(
				Admin.Each(players, function(_player, _character, humanoid)
					stopEmotes(humanoid)
				end),
				"Stopped the emote of"
			)
		end,
	}, {
		Name = "clone",
		Role = "Moderator",
		Description = "Creates a statue-like copy of players next to them.",
		Args = { { Type = "players", Name = "players", Description = "The players." } },
		Run = function(_, players: { Player })
			return describe(
				Admin.Each(players, function(player, character, _humanoid, root)
					character.Archivable = true
					const copy = character:Clone()
					if not copy then
						return false
					end

					copy.Name = `{player.Name} (clone)`
					copy:SetAttribute("CajClone", true)
					for _, descendant in ipairs(copy:GetDescendants()) do
						if descendant:IsA("Script") or descendant:IsA("LocalScript") then
							descendant:Destroy()
						end
					end

					copy:PivotTo(root.CFrame * CFrame.new(5, 0, 0))
					copy.Parent = Admin.GetObjectsFolder()
				end),
				"Cloned"
			)
		end,
	}, {
		Name = "clearclones",
		Role = "Moderator",
		Description = "Removes every clone made with the clone command.",
		Args = {},
		Run = function()
			local count = 0
			for _, child in ipairs(Admin.GetObjectsFolder():GetChildren()) do
				if child:GetAttribute("CajClone") then
					child:Destroy()
					count += 1
				end
			end

			return `Removed {Admin.Plural(count, "clone")}.`
		end,
	})

	return commands
end

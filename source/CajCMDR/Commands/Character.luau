--[[
	Character: health, movement, appearance, tools, teams and teleporting.
]]

const InsertService = game:GetService("InsertService")
const Players = game:GetService("Players")
const Teams = game:GetService("Teams")

return function(Admin)
	----------------------------------------------------------------------------------------------------
	-- helpers
	----------------------------------------------------------------------------------------------------

	const function applyInvisible(_player: Player, character: Model, humanoid: Humanoid)
		Admin.SetTransparency(character, 1)
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

		-- Accessories can finish loading a moment later.
		task.delay(1.5, function()
			if character.Parent then
				Admin.SetTransparency(character, 1)
			end
		end)
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

	--[[ Places players on a ring around a point, looking at it. Returns how many were moved. ]]
	const function teleportAround(players: { Player }, origin: Vector3, skip: Player?): number
		local index = 0
		const total = #players
		const radius = 5 + math.floor(total / 8) * 2

		return Admin.Each(players, function(player, character)
			if player == skip then
				return false
			end

			index += 1
			const angle = (index / math.max(total, 1)) * math.pi * 2
			const position = origin + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
			Admin.Teleport(character, CFrame.lookAt(position, origin))
		end)
	end

	const function describe(count: number, verb: string): string
		return Admin.Result(verb, count)
	end

	const function giveDefaults(player: Player, character: Model, humanoid: Humanoid)
		humanoid.MaxHealth = 100
		humanoid.Health = math.min(humanoid.Health, 100)
		humanoid.WalkSpeed = 16
		humanoid.UseJumpPower = true
		humanoid.JumpPower = 50
		humanoid.PlatformStand = false
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
		humanoid.DisplayName = player.DisplayName
		Admin.SetScale(humanoid, 1, 1, 1)
		Admin.SetTransparency(character, nil)

		const root = character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			root.Anchored = false
		end

		Admin.RemoveEffect(character, "CajFF")
	end

	const function scaleCommand(name: string, aliases: { string }?, description: string, argName: string, apply: (Humanoid, number) -> ())
		return {
			Name = name,
			Aliases = aliases,
			Role = "Moderator",
			Description = description,
			Args = {
				{ Type = "targets", Name = "players", Description = "The players to resize." },
				{ Type = "positiveNumber", Name = argName, Description = "Scale (1 = normal, 0.1 - 12)." },
			},
			Run = function(_, players: { Player }, value: number)
				const count = Admin.Each(players, function(_player, _character, humanoid)
					if not humanoid:FindFirstChild("BodyHeightScale") then
						return false
					end

					apply(humanoid, value)
				end)

				if count == 0 then
					return "Nobody was resized (resizing only works on R15 avatars)."
				end

				return describe(count, "Resized")
			end,
		}
	end

	----------------------------------------------------------------------------------------------------
	-- commands
	----------------------------------------------------------------------------------------------------

	return {
		-- Health -------------------------------------------------------------------------------------
		{
			Name = "kill",
			Aliases = { "slay" },
			Role = "Moderator",
			Description = "Kills players.",
			Args = { { Type = "targets", Name = "players", Description = "The players to kill." } },
			Run = function(_, players: { Player })
				return describe(
					Admin.Each(players, function(_player, _character, humanoid)
						humanoid.Health = 0
					end),
					"Killed"
				)
			end,
		},
		{
			Name = "respawn",
			Aliases = { "re" },
			Role = "Helper",
			Description = "Respawns players at their spawn point.",
			Args = { { Type = "players", Name = "players", Description = "The players to respawn." } },
			Run = function(_, players: { Player })
				return describe(
					Admin.EachPlayer(players, function(player)
						player:LoadCharacter()
					end),
					"Respawned"
				)
			end,
		},
		{
			Name = "refresh",
			Aliases = { "ref" },
			Role = "Helper",
			Description = "Respawns players and puts them back where they were standing.",
			Args = { { Type = "players", Name = "players", Description = "The players to refresh." } },
			Run = function(_, players: { Player })
				return describe(
					Admin.Each(players, function(player, _character, _humanoid, root)
						const spot = root.CFrame
						player:LoadCharacter()

						const character = player.Character
						if character and character:WaitForChild("HumanoidRootPart", 5) then
							task.wait()
							character:PivotTo(spot)
						end
					end),
					"Refreshed"
				)
			end,
		},
		{
			Name = "heal",
			Role = "Helper",
			Description = "Restores players to full health.",
			Args = { { Type = "players", Name = "players", Description = "The players to heal." } },
			Run = function(_, players: { Player })
				return describe(
					Admin.Each(players, function(_player, _character, humanoid)
						humanoid.Health = humanoid.MaxHealth
					end),
					"Healed"
				)
			end,
		},
		{
			Name = "damage",
			Aliases = { "hurt" },
			Role = "Moderator",
			Description = "Deals damage to players (force fields protect).",
			Args = {
				{ Type = "targets", Name = "players", Description = "The players to damage." },
				{ Type = "positiveNumber", Name = "amount", Description = "How much damage." },
			},
			Run = function(_, players: { Player }, amount: number)
				return describe(
					Admin.Each(players, function(_player, _character, humanoid)
						humanoid:TakeDamage(amount)
					end),
					"Damaged"
				)
			end,
		},
		{
			Name = "sethealth",
			Aliases = { "hp" },
			Role = "Moderator",
			Description = "Sets the current health of players.",
			Args = {
				{ Type = "targets", Name = "players", Description = "The players." },
				{ Type = "number", Name = "health", Description = "New health." },
			},
			Run = function(_, players: { Player }, health: number)
				return describe(
					Admin.Each(players, function(_player, _character, humanoid)
						humanoid.Health = math.clamp(health, 0, humanoid.MaxHealth)
					end),
					"Updated"
				)
			end,
		},
		{
			Name = "maxhealth",
			Aliases = { "maxhp" },
			Role = "Admin",
			Description = "Sets the maximum (and current) health of players.",
			Args = {
				{ Type = "targets", Name = "players", Description = "The players." },
				{ Type = "positiveNumber", Name = "health", Description = "New maximum health." },
			},
			Run = function(_, players: { Player }, health: number)
				return describe(
					Admin.Each(players, function(_player, _character, humanoid)
						humanoid.MaxHealth = health
						humanoid.Health = health
					end),
					"Updated"
				)
			end,
		},
		{
			Name = "god",
			Aliases = { "godmode" },
			Role = "Admin",
			Description = "Gives players infinite health (kept after respawning).",
			Args = { { Type = "targets", Name = "players", Description = "The players." } },
			Run = function(_, players: { Player })
				return describe(
					Admin.EachPlayer(players, function(player)
						Admin.SetState(player, "god", function(_, _character, humanoid)
							humanoid.MaxHealth = math.huge
							humanoid.Health = math.huge
						end)
					end),
					"Made invincible"
				)
			end,
		},
		{
			Name = "ungod",
			Role = "Admin",
			Description = "Removes god mode.",
			Args = { { Type = "players", Name = "players", Description = "The players." } },
			Run = function(_, players: { Player })
				return describe(
					Admin.EachPlayer(players, function(player)
						Admin.ClearState(player, "god")
						const humanoid = Admin.GetHumanoid(player)
						if humanoid then
							humanoid.MaxHealth = 100
							humanoid.Health = 100
						end
					end),
					"Updated"
				)
			end,
		},
		{
			Name = "ff",
			Aliases = { "forcefield" },
			Role = "Moderator",
			Description = "Gives players a force field.",
			Args = { { Type = "targets", Name = "players", Description = "The players." } },
			Run = function(_, players: { Player })
				return describe(
					Admin.Each(players, function(_player, character)
						Admin.RemoveEffect(character, "CajFF")
						const field = Instance.new("ForceField")
						field.Name = "CajFF"
						field.Parent = character
					end),
					"Protected"
				)
			end,
		},
		{
			Name = "unff",
			Aliases = { "unforcefield" },
			Role = "Moderator",
			Description = "Removes force fields.",
			Args = { { Type = "players", Name = "players", Description = "The players." } },
			Run = function(_, players: { Player })
				return describe(
					Admin.Each(players, function(_player, character)
						for _, child in ipairs(character:GetChildren()) do
							if child:IsA("ForceField") then
								child:Destroy()
							end
						end
					end),
					"Updated"
				)
			end,
		},

		-- Movement stats -------------------------------------------------------------------------------
		{
			Name = "speed",
			Aliases = { "ws", "walkspeed" },
			Role = "Moderator",
			Description = "Sets walk speed (default 16, kept after respawning).",
			Args = {
				{ Type = "targets", Name = "players", Description = "The players." },
				{ Type = "number", Name = "speed", Description = "Studs per second (0-500)." },
			},
			Run = function(_, players: { Player }, speed: number)
				const value = math.clamp(speed, 0, 500)
				return describe(
					Admin.EachPlayer(players, function(player)
						Admin.SetState(player, "speed", function(_, _character, humanoid)
							humanoid.WalkSpeed = value
						end)
					end),
					"Updated"
				)
			end,
		},
		{
			Name = "jumppower",
			Aliases = { "jp" },
			Role = "Moderator",
			Description = "Sets jump power (default 50, kept after respawning).",
			Args = {
				{ Type = "targets", Name = "players", Description = "The players." },
				{ Type = "number", Name = "power", Description = "Jump power (0-1000)." },
			},
			Run = function(_, players: { Player }, power: number)
				const value = math.clamp(power, 0, 1000)
				return describe(
					Admin.EachPlayer(players, function(player)
						Admin.SetState(player, "jump", function(_, _character, humanoid)
							humanoid.UseJumpPower = true
							humanoid.JumpPower = value
						end)
					end),
					"Updated"
				)
			end,
		},
		{
			Name = "jumpheight",
			Aliases = { "jh" },
			Role = "Moderator",
			Description = "Sets jump height in studs (default 7.2, kept after respawning).",
			Args = {
				{ Type = "targets", Name = "players", Description = "The players." },
				{ Type = "number", Name = "height", Description = "Jump height in studs (0-500)." },
			},
			Run = function(_, players: { Player }, height: number)
				const value = math.clamp(height, 0, 500)
				return describe(
					Admin.EachPlayer(players, function(player)
						Admin.SetState(player, "jump", function(_, _character, humanoid)
							humanoid.UseJumpPower = false
							humanoid.JumpHeight = value
						end)
					end),
					"Updated"
				)
			end,
		},
		{
			Name = "hipheight",
			Role = "Admin",
			Description = "Sets how high the avatar floats above the ground.",
			Args = {
				{ Type = "targets", Name = "players", Description = "The players." },
				{ Type = "number", Name = "height", Description = "Hip height in studs (0-100)." },
			},
			Run = function(_, players: { Player }, height: number)
				return describe(
					Admin.Each(players, function(_player, _character, humanoid)
						humanoid.HipHeight = math.clamp(height, 0, 100)
					end),
					"Updated"
				)
			end,
		},
		{
			Name = "sit",
			Role = "Moderator",
			Description = "Makes players sit down.",
			Args = { { Type = "targets", Name = "players", Description = "The players." } },
			Run = function(_, players: { Player })
				return describe(
					Admin.Each(players, function(_player, _character, humanoid)
						humanoid.Sit = true
					end),
					"Seated"
				)
			end,
		},
		{
			Name = "stand",
			Aliases = { "unsit" },
			Role = "Moderator",
			Description = "Makes players stand up.",
			Args = { { Type = "players", Name = "players", Description = "The players." } },
			Run = function(_, players: { Player })
				return describe(
					Admin.Each(players, function(_player, _character, humanoid)
						humanoid.Sit = false
					end),
					"Stood up"
				)
			end,
		},
		{
			Name = "jump",
			Role = "Moderator",
			Description = "Makes players jump.",
			Args = { { Type = "targets", Name = "players", Description = "The players." } },
			Run = function(_, players: { Player })
				return describe(
					Admin.Each(players, function(_player, _character, humanoid)
						humanoid.Jump = true
					end),
					"Made jump"
				)
			end,
		},
		{
			Name = "freeze",
			Role = "Moderator",
			Description = "Freezes players in place.",
			Args = { { Type = "targets", Name = "players", Description = "The players." } },
			Run = function(_, players: { Player })
				return describe(
					Admin.Each(players, function(_player, _character, _humanoid, root)
						root.Anchored = true
					end),
					"Froze"
				)
			end,
		},
		{
			Name = "thaw",
			Aliases = { "unfreeze" },
			Role = "Moderator",
			Description = "Unfreezes players.",
			Args = { { Type = "players", Name = "players", Description = "The players." } },
			Run = function(_, players: { Player })
				return describe(
					Admin.Each(players, function(_player, character, _humanoid, root)
						root.Anchored = false
						Admin.RemoveEffect(character, "CajIce")
					end),
					"Thawed"
				)
			end,
		},
		{
			Name = "stun",
			Role = "Moderator",
			Description = "Makes players unable to move (platform stand).",
			Args = { { Type = "targets", Name = "players", Description = "The players." } },
			Run = function(_, players: { Player })
				return describe(
					Admin.Each(players, function(_player, _character, humanoid)
						humanoid.PlatformStand = true
					end),
					"Stunned"
				)
			end,
		},
		{
			Name = "unstun",
			Role = "Moderator",
			Description = "Lets stunned players move again.",
			Args = { { Type = "players", Name = "players", Description = "The players." } },
			Run = function(_, players: { Player })
				return describe(
					Admin.Each(players, function(_player, _character, humanoid)
						humanoid.PlatformStand = false
					end),
					"Released"
				)
			end,
		},
		{
			Name = "ragdoll",
			Role = "Moderator",
			Description = "Turns players into ragdolls.",
			Args = { { Type = "targets", Name = "players", Description = "The players." } },
			Run = function(_, players: { Player })
				return describe(
					Admin.Each(players, function(_player, _character, humanoid)
						humanoid:ChangeState(Enum.HumanoidStateType.Ragdoll)
					end),
					"Ragdolled"
				)
			end,
		},
		{
			Name = "unragdoll",
			Role = "Moderator",
			Description = "Gets ragdolled players back on their feet.",
			Args = { { Type = "players", Name = "players", Description = "The players." } },
			Run = function(_, players: { Player })
				return describe(
					Admin.Each(players, function(_player, _character, humanoid)
						humanoid.PlatformStand = false
						humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
					end),
					"Recovered"
				)
			end,
		},

		-- Size -----------------------------------------------------------------------------------------
		scaleCommand("size", { "scale" }, "Resizes the whole avatar (R15 only).", "scale", function(humanoid, value)
			Admin.SetScale(humanoid, value, value, value)
		end),
		scaleCommand("height", nil, "Changes the avatar height (R15 only).", "scale", function(humanoid, value)
			Admin.SetScale(humanoid, value, nil, nil)
		end),
		scaleCommand("width", nil, "Changes the avatar width and depth (R15 only).", "scale", function(humanoid, value)
			Admin.SetScale(humanoid, nil, value, nil)
		end),
		scaleCommand("headsize", { "head" }, "Changes the head size (R15 only).", "scale", function(humanoid, value)
			Admin.SetScale(humanoid, nil, nil, value)
		end),
		{
			Name = "resetsize",
			Aliases = { "normalsize" },
			Role = "Moderator",
			Description = "Returns players to their normal size.",
			Args = { { Type = "players", Name = "players", Description = "The players." } },
			Run = function(_, players: { Player })
				return describe(
					Admin.Each(players, function(_player, _character, humanoid)
						return Admin.SetScale(humanoid, 1, 1, 1)
					end),
					"Reset the size of"
				)
			end,
		},

		-- Appearance -----------------------------------------------------------------------------------
		{
			Name = "char",
			Aliases = { "morph", "disguise" },
			Role = "Admin",
			Description = "Makes players look like another Roblox user.",
			Args = {
				{ Type = "targets", Name = "players", Description = "The players to change." },
				{ Type = "playerId", Name = "user", Description = "Player or UserId (#123) to copy." },
			},
			Run = function(_, players: { Player }, userId: number)
				const ok, description = pcall(Players.GetHumanoidDescriptionFromUserId, Players, userId)
				if not ok then
					return `Could not load that user's appearance: {description}`
				end

				return describe(
					Admin.Each(players, function(_player, _character, humanoid)
						humanoid:ApplyDescription(description)
					end),
					"Changed the appearance of"
				)
			end,
		},
		{
			Name = "resetchar",
			Aliases = { "unchar" },
			Role = "Admin",
			Description = "Restores players' real avatars.",
			Args = { { Type = "players", Name = "players", Description = "The players." } },
			Run = function(_, players: { Player })
				return describe(
					Admin.Each(players, function(player, _character, humanoid)
						const ok, description = pcall(Players.GetHumanoidDescriptionFromUserId, Players, player.UserId)
						if not ok then
							return false
						end

						humanoid:ApplyDescription(description)
					end),
					"Restored"
				)
			end,
		},
		{
			Name = "color",
			Aliases = { "paint", "skin" },
			Role = "Moderator",
			Description = "Paints the whole body one color.",
			Args = {
				{ Type = "targets", Name = "players", Description = "The players." },
				{ Type = "color3", Name = "color", Description = "e.g. 255,0,0 or #ff0000." },
			},
			Run = function(_, players: { Player }, color: Color3)
				return describe(
					Admin.Each(players, function(_player, character)
						const bodyColors = character:FindFirstChildOfClass("BodyColors")
						if bodyColors then
							bodyColors.HeadColor3 = color
							bodyColors.TorsoColor3 = color
							bodyColors.LeftArmColor3 = color
							bodyColors.RightArmColor3 = color
							bodyColors.LeftLegColor3 = color
							bodyColors.RightLegColor3 = color
						end

						for _, part in ipairs(bodyParts(character)) do
							part.Color = color
						end
					end),
					"Painted"
				)
			end,
		},
		{
			Name = "material",
			Role = "Moderator",
			Description = "Changes the material of the body (Neon, Glass, Gold, ...).",
			Args = {
				{ Type = "targets", Name = "players", Description = "The players." },
				{ Type = "material", Name = "material", Description = "A Roblox material." },
			},
			Run = function(_, players: { Player }, material: Enum.Material)
				return describe(
					Admin.Each(players, function(_player, character)
						for _, part in ipairs(bodyParts(character)) do
							part.Material = material
						end
					end),
					"Updated"
				)
			end,
		},
		{
			Name = "transparency",
			Aliases = { "trans" },
			Role = "Moderator",
			Description = "Sets how see-through players are (0 = normal, 1 = invisible).",
			Args = {
				{ Type = "targets", Name = "players", Description = "The players." },
				{ Type = "number", Name = "amount", Description = "0 to 1." },
			},
			Run = function(_, players: { Player }, amount: number)
				return describe(
					Admin.Each(players, function(_player, character)
						Admin.SetTransparency(character, if amount <= 0 then nil else math.clamp(amount, 0, 1))
					end),
					"Updated"
				)
			end,
		},
		{
			Name = "invisible",
			Aliases = { "invis" },
			Role = "Moderator",
			Description = "Makes players invisible (kept after respawning).",
			Args = { { Type = "targets", Name = "players", Description = "The players." } },
			Run = function(_, players: { Player })
				return describe(
					Admin.EachPlayer(players, function(player)
						Admin.SetState(player, "invisible", applyInvisible)
					end),
					"Hid"
				)
			end,
		},
		{
			Name = "visible",
			Aliases = { "vis" },
			Role = "Moderator",
			Description = "Makes invisible players visible again.",
			Args = { { Type = "players", Name = "players", Description = "The players." } },
			Run = function(_, players: { Player })
				return describe(
					Admin.EachPlayer(players, function(player)
						Admin.ClearState(player, "invisible")
						const character = player.Character
						const humanoid = Admin.GetHumanoid(player)
						if character then
							Admin.SetTransparency(character, nil)
						end
						if humanoid then
							humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
						end
					end),
					"Revealed"
				)
			end,
		},
		{
			Name = "name",
			Aliases = { "displayname" },
			Role = "Admin",
			Description = "Changes the name shown above players' heads.",
			Args = {
				{ Type = "targets", Name = "players", Description = "The players." },
				{ Type = "string", Name = "name", Description = "The new display name." },
			},
			Run = function(_, players: { Player }, text: string)
				return describe(
					Admin.Each(players, function(_player, _character, humanoid)
						humanoid.DisplayName = Admin.Truncate(text, 50)
					end),
					"Renamed"
				)
			end,
		},
		{
			Name = "unname",
			Role = "Admin",
			Description = "Restores the real display name.",
			Args = { { Type = "players", Name = "players", Description = "The players." } },
			Run = function(_, players: { Player })
				return describe(
					Admin.Each(players, function(player, _character, humanoid)
						humanoid.DisplayName = player.DisplayName
					end),
					"Restored"
				)
			end,
		},
		{
			Name = "hidename",
			Aliases = { "hidenames" },
			Role = "Moderator",
			Description = "Hides the name above players' heads.",
			Args = { { Type = "targets", Name = "players", Description = "The players." } },
			Run = function(_, players: { Player })
				return describe(
					Admin.Each(players, function(_player, _character, humanoid)
						humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
					end),
					"Updated"
				)
			end,
		},
		{
			Name = "showname",
			Role = "Moderator",
			Description = "Shows the name above players' heads again.",
			Args = { { Type = "players", Name = "players", Description = "The players." } },
			Run = function(_, players: { Player })
				return describe(
					Admin.Each(players, function(_player, _character, humanoid)
						humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
					end),
					"Updated"
				)
			end,
		},
		{
			Name = "hat",
			Aliases = { "accessory" },
			Role = "Admin",
			Description = "Gives players an accessory from the catalog (by asset id).",
			Args = {
				{ Type = "targets", Name = "players", Description = "The players." },
				{ Type = "positiveInteger", Name = "assetId", Description = "Catalog asset id of the accessory." },
			},
			Run = function(_, players: { Player }, assetId: number)
				const ok, model = pcall(InsertService.LoadAsset, InsertService, assetId)
				if not ok then
					return `Could not load that asset: {model}`
				end

				const accessory = model:FindFirstChildWhichIsA("Accessory", true)
				if not accessory then
					model:Destroy()
					return "That asset is not an accessory."
				end

				const count = Admin.Each(players, function(_player, _character, humanoid)
					humanoid:AddAccessory(accessory:Clone())
				end)

				model:Destroy()
				return describe(count, "Equipped")
			end,
		},
		{
			Name = "removehats",
			Aliases = { "nohats" },
			Role = "Admin",
			Description = "Removes all accessories from players.",
			Args = { { Type = "targets", Name = "players", Description = "The players." } },
			Run = function(_, players: { Player })
				return describe(
					Admin.Each(players, function(_player, _character, humanoid)
						humanoid:RemoveAccessories()
					end),
					"Cleared"
				)
			end,
		},

		-- Tools ----------------------------------------------------------------------------------------
		{
			Name = "tools",
			Role = "Helper",
			Description = "Lists the tools that can be given with the give command.",
			Args = {},
			Run = function(context)
				const lines = {}
				for _, tool in ipairs(Admin.ListTools()) do
					table.insert(lines, tool.Name)
				end

				if not Admin.GetToolsFolder() then
					table.insert(lines, `Create a folder named "{Admin.Config.ToolsFolder}" in ServerStorage and put Tools in it.`)
				end

				return Admin.Output(context, "Available tools", lines)
			end,
		},
		{
			Name = "give",
			Aliases = { "tool" },
			Role = "Moderator",
			Description = "Gives players a tool from ServerStorage > AdminTools.",
			Args = {
				{ Type = "players", Name = "players", Description = "The players." },
				{ Type = "string", Name = "tool", Description = "Name of the tool (see the tools command)." },
			},
			Run = function(_, players: { Player }, toolName: string)
				const tool = Admin.FindTool(toolName)
				if not tool then
					return `No tool called "{toolName}". Use the tools command to see the list.`
				end

				return describe(
					Admin.EachPlayer(players, function(player)
						const backpack = player:FindFirstChildOfClass("Backpack")
						if not backpack then
							return false
						end

						tool:Clone().Parent = backpack
					end),
					`Gave {tool.Name} to`
				)
			end,
		},
		{
			Name = "ungive",
			Aliases = { "untool" },
			Role = "Moderator",
			Description = "Takes a tool away from players.",
			Args = {
				{ Type = "players", Name = "players", Description = "The players." },
				{ Type = "string", Name = "tool", Description = "Name (or part of the name) of the tool." },
			},
			Run = function(_, players: { Player }, toolName: string)
				const needle = toolName:lower()
				return describe(
					Admin.EachPlayer(players, function(player)
						local removed = false
						const containers = { player:FindFirstChildOfClass("Backpack"), player.Character }
						for _, container in pairs(containers) do
							for _, child in ipairs(container:GetChildren()) do
								if child:IsA("Tool") and child.Name:lower():find(needle, 1, true) then
									child:Destroy()
									removed = true
								end
							end
						end

						return removed
					end),
					"Took a tool from"
				)
			end,
		},
		{
			Name = "strip",
			Aliases = { "removetools", "striptools" },
			Role = "Moderator",
			Description = "Removes every tool from players.",
			Args = { { Type = "targets", Name = "players", Description = "The players." } },
			Run = function(_, players: { Player })
				return describe(
					Admin.EachPlayer(players, function(player)
						const backpack = player:FindFirstChildOfClass("Backpack")
						if backpack then
							backpack:ClearAllChildren()
						end

						const character = player.Character
						if character then
							for _, child in ipairs(character:GetChildren()) do
								if child:IsA("Tool") then
									child:Destroy()
								end
							end
						end
					end),
					"Stripped"
				)
			end,
		},

		-- Teams ----------------------------------------------------------------------------------------
		{
			Name = "team",
			Role = "Moderator",
			Description = "Moves players to a team.",
			Args = {
				{ Type = "targets", Name = "players", Description = "The players." },
				{ Type = "team", Name = "team", Description = "The team." },
			},
			Run = function(_, players: { Player }, team: Team)
				return describe(
					Admin.EachPlayer(players, function(player)
						player.Team = team
					end),
					`Moved to {team.Name}:`
				)
			end,
		},
		{
			Name = "neutral",
			Role = "Moderator",
			Description = "Removes players from their team.",
			Args = { { Type = "players", Name = "players", Description = "The players." } },
			Run = function(_, players: { Player })
				return describe(
					Admin.EachPlayer(players, function(player)
						player.Team = nil
					end),
					"Made neutral:"
				)
			end,
		},
		{
			Name = "newteam",
			Aliases = { "createteam" },
			Role = "Admin",
			Description = "Creates a new team.",
			Args = {
				{ Type = "string", Name = "name", Description = "Team name." },
				{ Type = "brickColor", Name = "color", Description = "Team color.", Optional = true },
			},
			Run = function(_, name: string, color: BrickColor?)
				if Teams:FindFirstChild(name) then
					return `A team called "{name}" already exists.`
				end

				const team = Instance.new("Team")
				team.Name = name
				team.TeamColor = color or BrickColor.Random()
				team.AutoAssignable = false
				team.Parent = Teams
				return `Created team {name}.`
			end,
		},
		{
			Name = "delteam",
			Aliases = { "removeteam" },
			Role = "Admin",
			Description = "Deletes a team.",
			Args = { { Type = "team", Name = "team", Description = "The team to delete." } },
			Run = function(_, team: Team)
				const name = team.Name
				team:Destroy()
				return `Deleted team {name}.`
			end,
		},

		-- Teleporting ----------------------------------------------------------------------------------
		{
			Name = "bring",
			Role = "Moderator",
			Description = "Teleports players to you.",
			Args = { { Type = "targets", Name = "players", Description = "The players to bring." } },
			Run = function(context, players: { Player })
				const root = Admin.GetRoot(context.Executor)
				if not root then
					return "You need a character to bring players."
				end

				return describe(teleportAround(players, root.Position, context.Executor), "Brought")
			end,
		},
		{
			Name = "goto",
			Aliases = { "to", "tpto" },
			Role = "Helper",
			Description = "Teleports you to a player.",
			Args = { { Type = "player", Name = "player", Description = "The player to go to." } },
			Run = function(context, target: Player)
				const targetRoot = Admin.GetRoot(target)
				const character = context.Executor.Character
				if not (targetRoot and character) then
					return "Both of you need a character."
				end

				Admin.Teleport(character, CFrame.lookAt(targetRoot.Position + targetRoot.CFrame.LookVector * 5, targetRoot.Position))
				return `Teleported to {target.Name}.`
			end,
		},
		{
			Name = "tp",
			Aliases = { "teleport" },
			Role = "Moderator",
			Description = "Teleports players to another player.",
			Args = {
				{ Type = "targets", Name = "players", Description = "The players to move." },
				{ Type = "player", Name = "destination", Description = "The player to teleport them to." },
			},
			Run = function(_, players: { Player }, destination: Player)
				const root = Admin.GetRoot(destination)
				if not root then
					return `{destination.Name} has no character.`
				end

				return describe(teleportAround(players, root.Position, destination), "Teleported")
			end,
		},
		{
			Name = "tppos",
			Aliases = { "tpxyz" },
			Role = "Moderator",
			Description = "Teleports players to coordinates (use ~ for relative: ~ ~10 ~).",
			Args = {
				{ Type = "targets", Name = "players", Description = "The players to move." },
				{ Type = "positionVector3", Name = "position", Description = "X, Y, Z." },
			},
			Run = function(_, players: { Player }, position: Vector3)
				return describe(
					Admin.Each(players, function(_player, character)
						Admin.Teleport(character, CFrame.new(position))
					end),
					"Teleported"
				)
			end,
		},
		{
			Name = "swap",
			Role = "Moderator",
			Description = "Swaps the positions of two players.",
			Args = {
				{ Type = "target", Name = "first", Description = "First player." },
				{ Type = "target", Name = "second", Description = "Second player." },
			},
			Run = function(_, first: Player, second: Player)
				const characterA = first.Character
				const characterB = second.Character
				if not (characterA and characterB) then
					return "Both players need a character."
				end

				const pivotA = characterA:GetPivot()
				const pivotB = characterB:GetPivot()
				Admin.Teleport(characterA, pivotB)
				Admin.Teleport(characterB, pivotA)
				return `Swapped {first.Name} and {second.Name}.`
			end,
		},
		{
			Name = "up",
			Aliases = { "rise" },
			Role = "Moderator",
			Description = "Moves players up.",
			Args = {
				{ Type = "targets", Name = "players", Description = "The players." },
				{ Type = "number", Name = "studs", Description = "How far." },
			},
			Run = function(_, players: { Player }, studs: number)
				return describe(
					Admin.Each(players, function(_player, character)
						character:PivotTo(character:GetPivot() + Vector3.new(0, studs, 0))
					end),
					"Moved"
				)
			end,
		},
		{
			Name = "down",
			Role = "Moderator",
			Description = "Moves players down.",
			Args = {
				{ Type = "targets", Name = "players", Description = "The players." },
				{ Type = "number", Name = "studs", Description = "How far." },
			},
			Run = function(_, players: { Player }, studs: number)
				return describe(
					Admin.Each(players, function(_player, character)
						character:PivotTo(character:GetPivot() - Vector3.new(0, studs, 0))
					end),
					"Moved"
				)
			end,
		},
		{
			Name = "forward",
			Aliases = { "fwd" },
			Role = "Moderator",
			Description = "Moves players forward (negative = backward).",
			Args = {
				{ Type = "targets", Name = "players", Description = "The players." },
				{ Type = "number", Name = "studs", Description = "How far." },
			},
			Run = function(_, players: { Player }, studs: number)
				return describe(
					Admin.Each(players, function(_player, character, _humanoid, root)
						character:PivotTo(character:GetPivot() + root.CFrame.LookVector * studs)
					end),
					"Moved"
				)
			end,
		},
		{
			Name = "resetstats",
			Aliases = { "defaults" },
			Role = "Moderator",
			Description = "Resets health, speed, jump, size, visibility and other changes to normal.",
			Args = { { Type = "players", Name = "players", Description = "The players." } },
			Run = function(_, players: { Player })
				return describe(
					Admin.EachPlayer(players, function(player)
						Admin.ClearStates(player)
						const character = player.Character
						const humanoid = Admin.GetHumanoid(player)
						if character and humanoid then
							giveDefaults(player, character, humanoid)
						end
					end),
					"Reset"
				)
			end,
		},
	}
end

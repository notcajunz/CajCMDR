--[[
	World: messages, lighting, gravity, music, loops and small utilities.
]]

const InsertService = game:GetService("InsertService")
const Lighting = game:GetService("Lighting")
const RunService = game:GetService("RunService")

const MAX_LOOP_RUNS = 100

return function(Admin)
	----------------------------------------------------------------------------------------------------
	-- state
	----------------------------------------------------------------------------------------------------

	const originals = {
		Brightness = Lighting.Brightness,
		ClockTime = Lighting.ClockTime,
		Ambient = Lighting.Ambient,
		OutdoorAmbient = Lighting.OutdoorAmbient,
		FogEnd = Lighting.FogEnd,
		FogStart = Lighting.FogStart,
		FogColor = Lighting.FogColor,
		GlobalShadows = Lighting.GlobalShadows,
		Gravity = workspace.Gravity,
		FallenPartsDestroyHeight = workspace.FallenPartsDestroyHeight,
	}

	const loopKill: { [Player]: boolean } = {}
	const loopHeal: { [Player]: boolean } = {}
	local playerLoopRunning = false
	local timelapseConnection: RBXScriptConnection? = nil
	const activeLoops: { [number]: { Cancelled: boolean } } = {}
	local nextLoopId = 0

	----------------------------------------------------------------------------------------------------
	-- helpers
	----------------------------------------------------------------------------------------------------

	const function describe(count: number, verb: string): string
		return Admin.Result(verb, count)
	end

	const function getSound(): Sound
		local sound = workspace:FindFirstChild("CajMusic")
		if not sound or not sound:IsA("Sound") then
			sound = Instance.new("Sound")
			sound.Name = "CajMusic"
			sound.Looped = true
			sound.Volume = 1
			sound.Parent = workspace
		end

		return sound :: Sound
	end

	const function runPlayerLoop()
		if playerLoopRunning then
			return
		end

		playerLoopRunning = true
		task.spawn(function()
			while next(loopKill) ~= nil or next(loopHeal) ~= nil do
				for player in pairs(loopKill) do
					const humanoid = if player.Parent then Admin.GetHumanoid(player) else nil
					if not player.Parent then
						loopKill[player] = nil
					elseif humanoid and humanoid.Health > 0 then
						humanoid.Health = 0
					end
				end

				for player in pairs(loopHeal) do
					const humanoid = if player.Parent then Admin.GetHumanoid(player) else nil
					if not player.Parent then
						loopHeal[player] = nil
					elseif humanoid and humanoid.Health > 0 then
						humanoid.Health = humanoid.MaxHealth
					end
				end

				task.wait(0.5)
			end

			playerLoopRunning = false
		end)
	end

	const function firstWord(text: string): string
		return (text:match("^%s*(%S+)") or ""):lower()
	end

	const function roll(context: any, text: string): string
		const ready, wait = Admin.Cooldown(`roll{context.Executor.UserId}`, 3)
		if not ready then
			return `Please wait {math.ceil(wait)}s.`
		end

		Admin.NotifyAll(`{context.Executor.Name} {text}`, "info")
		return ""
	end

	Admin.OnGlobal("announce", function(data)
		Admin.Announce(tostring(data.Title or "Announcement"), tostring(data.Text or ""), 10)
	end)

	----------------------------------------------------------------------------------------------------
	-- commands
	----------------------------------------------------------------------------------------------------

	const commands = {}

	const function add(...: any)
		for _, spec in ipairs({ ... }) do
			table.insert(commands, spec)
		end
	end

	-- Messages -------------------------------------------------------------------------------------
	add({
		Name = "announce",
		Aliases = { "m", "message", "shout" },
		Role = "Moderator",
		Description = "Shows a big announcement banner to every player.",
		Args = { { Type = "string", Name = "message", Description = "The announcement." } },
		Run = function(context, message: string)
			Admin.Announce(`Announcement from {context.Executor.DisplayName}`, message, 10)
			return "Announcement sent."
		end,
	}, {
		Name = "globalannounce",
		Aliases = { "gannounce", "gm" },
		Role = "Admin",
		Description = "Shows an announcement banner in EVERY server of this experience.",
		Args = { { Type = "string", Name = "message", Description = "The announcement." } },
		Run = function(context, message: string)
			const data = { Title = `Global announcement from {context.Executor.DisplayName}`, Text = message }
			const ok, err = Admin.PublishGlobal("announce", data)
			if not ok then
				Admin.RunGlobalLocally("announce", data)
				return `Could not reach other servers ({err}). Announced in this server only.`
			end

			return "Announcement sent to all servers."
		end,
	}, {
		Name = "hint",
		Aliases = { "h", "broadcast" },
		Role = "Moderator",
		Description = "Shows a small notification to every player.",
		Args = { { Type = "string", Name = "message", Description = "The message." } },
		Run = function(context, message: string)
			Admin.NotifyAll(`{context.Executor.DisplayName}: {message}`, "info")
			return "Hint sent."
		end,
	}, {
		Name = "notify",
		Role = "Helper",
		Description = "Sends a notification to specific players.",
		Args = {
			{ Type = "players", Name = "players", Description = "Who gets it." },
			{ Type = "string", Name = "message", Description = "The message." },
		},
		Run = function(_, players: { Player }, message: string)
			return describe(
				Admin.EachPlayer(players, function(player)
					Admin.Notify(player, message, "info")
				end),
				"Notified"
			)
		end,
	}, {
		Name = "pm",
		Aliases = { "whisper" },
		Role = "Helper",
		Description = "Sends a private message to players.",
		Args = {
			{ Type = "players", Name = "players", Description = "Who gets it." },
			{ Type = "string", Name = "message", Description = "The message." },
		},
		Run = function(context, players: { Player }, message: string)
			return describe(
				Admin.EachPlayer(players, function(player)
					Admin.Notify(player, `[PM from {context.Executor.DisplayName}] {message}`, "success")
				end),
				"Messaged"
			)
		end,
	}, {
		Name = "countdown",
		Aliases = { "timer" },
		Role = "Moderator",
		Description = "Shows a big countdown to every player.",
		Args = {
			{ Type = "integer", Name = "seconds", Description = "1 to 300." },
			{ Type = "string", Name = "label", Description = "Text shown under the number.", Optional = true },
		},
		Run = function(_, seconds: number, label: string?)
			Admin.FxAll("countdown", math.clamp(seconds, 1, 300), label or "")
			return `Countdown started ({seconds}s).`
		end,
	})

	-- Time and lighting ----------------------------------------------------------------------------
	const function timeCommand(name: string, aliases: { string }?, description: string, hour: number)
		return {
			Name = name,
			Aliases = aliases,
			Role = "Moderator",
			Description = description,
			Args = {},
			Run = function()
				Lighting.ClockTime = hour
				return `Time set to {hour}:00.`
			end,
		}
	end

	add({
		Name = "settime",
		Aliases = { "clocktime" },
		Role = "Moderator",
		Description = "Sets the time of day (0-24).",
		Args = { { Type = "number", Name = "hour", Description = "0-24, e.g. 14.5 = 2:30 PM." } },
		Run = function(_, hour: number)
			Lighting.ClockTime = hour % 24
			return `Time set to {string.format("%.1f", hour % 24)}.`
		end,
	}, timeCommand("day", nil, "Sets the time to 2 PM.", 14), timeCommand("night", nil, "Sets the time to midnight.", 0), timeCommand(
		"dawn",
		{ "sunrise" },
		"Sets the time to 6 AM.",
		6
	), timeCommand("dusk", { "sunset" }, "Sets the time to 6 PM.", 18), {
		Name = "timelapse",
		Role = "Moderator",
		Description = "Makes time pass faster (game hours per second, 0 = stop).",
		Args = { { Type = "number", Name = "speed", Description = "0 to 24." } },
		Run = function(_, speed: number)
			if timelapseConnection then
				timelapseConnection:Disconnect()
				timelapseConnection = nil
			end

			const rate = math.clamp(speed, 0, 24)
			if rate == 0 then
				return "Time lapse stopped."
			end

			timelapseConnection = RunService.Heartbeat:Connect(function(dt)
				Lighting.ClockTime = (Lighting.ClockTime + dt * rate) % 24
			end)

			return `Time is passing at {rate} hours per second.`
		end,
	}, {
		Name = "brightness",
		Role = "Moderator",
		Description = "Sets the brightness of the world.",
		Args = { { Type = "number", Name = "brightness", Description = "0 to 10 (default 2)." } },
		Run = function(_, value: number)
			Lighting.Brightness = math.clamp(value, 0, 10)
			return "Brightness updated."
		end,
	}, {
		Name = "ambient",
		Role = "Moderator",
		Description = "Sets the ambient light color.",
		Args = { { Type = "color3", Name = "color", Description = "e.g. 80,80,255." } },
		Run = function(_, color: Color3)
			Lighting.Ambient = color
			return "Ambient color updated."
		end,
	}, {
		Name = "outdoorambient",
		Role = "Moderator",
		Description = "Sets the outdoor ambient light color.",
		Args = { { Type = "color3", Name = "color", Description = "e.g. 80,80,255." } },
		Run = function(_, color: Color3)
			Lighting.OutdoorAmbient = color
			return "Outdoor ambient color updated."
		end,
	}, {
		Name = "fog",
		Role = "Moderator",
		Description = "Adds fog that fades out at the given distance.",
		Args = {
			{ Type = "positiveNumber", Name = "end", Description = "Where the fog is fully thick." },
			{ Type = "number", Name = "start", Description = "Where the fog begins (default 0).", Optional = true },
		},
		Run = function(_, fogEnd: number, fogStart: number?)
			Lighting.FogEnd = fogEnd
			Lighting.FogStart = math.clamp(fogStart or 0, 0, fogEnd)
			return "Fog enabled."
		end,
	}, {
		Name = "nofog",
		Role = "Moderator",
		Description = "Removes the fog.",
		Args = {},
		Run = function()
			Lighting.FogEnd = 100000
			Lighting.FogStart = 0
			return "Fog removed."
		end,
	}, {
		Name = "fogcolor",
		Role = "Moderator",
		Description = "Sets the fog color.",
		Args = { { Type = "color3", Name = "color", Description = "e.g. 200,200,220." } },
		Run = function(_, color: Color3)
			Lighting.FogColor = color
			return "Fog color updated."
		end,
	}, {
		Name = "shadows",
		Role = "Moderator",
		Description = "Turns global shadows on or off.",
		Args = { { Type = "boolean", Name = "enabled", Description = "true or false." } },
		Run = function(_, enabled: boolean)
			Lighting.GlobalShadows = enabled
			return `Shadows {if enabled then "enabled" else "disabled"}.`
		end,
	}, {
		Name = "resetlighting",
		Aliases = { "resetworld" },
		Role = "Moderator",
		Description = "Restores the lighting, gravity and fall height from when the server started.",
		Args = {},
		Run = function()
			if timelapseConnection then
				timelapseConnection:Disconnect()
				timelapseConnection = nil
			end

			for property, value in pairs(originals) do
				if property == "Gravity" or property == "FallenPartsDestroyHeight" then
					(workspace :: any)[property] = value
				else
					(Lighting :: any)[property] = value
				end
			end

			return "Lighting and physics restored."
		end,
	}, {
		Name = "gravity",
		Role = "Admin",
		Description = "Sets the world gravity (default 196.2).",
		Args = { { Type = "number", Name = "gravity", Description = "0 = floaty, 196.2 = normal." } },
		Run = function(_, value: number)
			workspace.Gravity = math.clamp(value, 0, 1000)
			return `Gravity set to {workspace.Gravity}.`
		end,
	}, {
		Name = "fallheight",
		Role = "Admin",
		Description = "Sets the height below which things are destroyed (void kill height).",
		Args = { { Type = "number", Name = "height", Description = "Y position, e.g. -500." } },
		Run = function(_, value: number)
			workspace.FallenPartsDestroyHeight = value
			return `Fall height set to {value}.`
		end,
	})

	-- Music ----------------------------------------------------------------------------------------
	add({
		Name = "music",
		Aliases = { "play" },
		Role = "Moderator",
		Description = "Plays a sound or song for everyone (audio asset id).",
		Args = { { Type = "positiveInteger", Name = "assetId", Description = "Audio asset id." } },
		Run = function(_, assetId: number)
			const sound = getSound()
			sound:Stop()
			sound.SoundId = `rbxassetid://{assetId}`
			sound:Play()
			return `Playing {assetId}.`
		end,
	}, {
		Name = "stopmusic",
		Aliases = { "stop" },
		Role = "Moderator",
		Description = "Stops the music.",
		Args = {},
		Run = function()
			getSound():Stop()
			return "Music stopped."
		end,
	}, {
		Name = "pausemusic",
		Aliases = { "pause" },
		Role = "Moderator",
		Description = "Pauses the music.",
		Args = {},
		Run = function()
			getSound():Pause()
			return "Music paused."
		end,
	}, {
		Name = "resumemusic",
		Aliases = { "resume" },
		Role = "Moderator",
		Description = "Resumes the music.",
		Args = {},
		Run = function()
			getSound():Resume()
			return "Music resumed."
		end,
	}, {
		Name = "volume",
		Role = "Moderator",
		Description = "Sets the music volume.",
		Args = { { Type = "number", Name = "volume", Description = "0 to 10 (default 1)." } },
		Run = function(_, value: number)
			getSound().Volume = math.clamp(value, 0, 10)
			return "Volume updated."
		end,
	}, {
		Name = "pitch",
		Aliases = { "musicspeed" },
		Role = "Moderator",
		Description = "Changes how fast the music plays.",
		Args = { { Type = "positiveNumber", Name = "speed", Description = "0.1 to 5 (default 1)." } },
		Run = function(_, value: number)
			getSound().PlaybackSpeed = math.clamp(value, 0.1, 5)
			return "Playback speed updated."
		end,
	})

	-- Cleanup and loading --------------------------------------------------------------------------
	add({
		Name = "cleanup",
		Aliases = { "clean" },
		Role = "Moderator",
		Description = "Removes dropped tools, hats and everything spawned by commands (cages, clones, ...).",
		Args = {},
		Run = function()
			local count = 0
			for _, child in ipairs(workspace:GetChildren()) do
				if child:IsA("Tool") or child:IsA("Accessory") or child:IsA("Hat") then
					child:Destroy()
					count += 1
				end
			end

			const objects = Admin.GetObjectsFolder()
			count += #objects:GetChildren()
			objects:ClearAllChildren()

			return `Removed {count} objects.`
		end,
	}, {
		Name = "insert",
		Role = "Owner",
		Description = "Loads a model from the catalog next to you. Disabled by default (see Config).",
		Args = { { Type = "positiveInteger", Name = "assetId", Description = "Model asset id." } },
		Run = function(context, assetId: number)
			const ok, model = pcall(InsertService.LoadAsset, InsertService, assetId)
			if not ok then
				return `Could not load that asset: {model}`
			end

			const root = Admin.GetRoot(context.Executor)
			model.Name = `Inserted {assetId}`
			if root then
				model:PivotTo(root.CFrame * CFrame.new(0, 0, -12))
			end
			model.Parent = Admin.GetObjectsFolder()

			Admin.Audit(context, `inserted asset {assetId}`)
			return `Inserted asset {assetId}.`
		end,
	})

	-- Loops ----------------------------------------------------------------------------------------
	add({
		Name = "loopkill",
		Role = "Admin",
		Description = "Kills players over and over (until unloopkill).",
		Args = { { Type = "targets", Name = "players", Description = "The players." } },
		Run = function(_, players: { Player })
			const count = Admin.EachPlayer(players, function(player)
				loopKill[player] = true
			end)
			runPlayerLoop()
			return describe(count, "Loop-killing")
		end,
	}, {
		Name = "unloopkill",
		Role = "Admin",
		Description = "Stops loop-killing players.",
		Args = { { Type = "players", Name = "players", Description = "The players." } },
		Run = function(_, players: { Player })
			return describe(
				Admin.EachPlayer(players, function(player)
					loopKill[player] = nil
				end),
				"Stopped loop-killing"
			)
		end,
	}, {
		Name = "loopheal",
		Role = "Moderator",
		Description = "Keeps players at full health (until unloopheal).",
		Args = { { Type = "players", Name = "players", Description = "The players." } },
		Run = function(_, players: { Player })
			const count = Admin.EachPlayer(players, function(player)
				loopHeal[player] = true
			end)
			runPlayerLoop()
			return describe(count, "Loop-healing")
		end,
	}, {
		Name = "unloopheal",
		Role = "Moderator",
		Description = "Stops loop-healing players.",
		Args = { { Type = "players", Name = "players", Description = "The players." } },
		Run = function(_, players: { Player })
			return describe(
				Admin.EachPlayer(players, function(player)
					loopHeal[player] = nil
				end),
				"Stopped loop-healing"
			)
		end,
	}, {
		Name = "loop",
		Aliases = { "repeat" },
		Role = "Admin",
		Description = "Runs a command several times, e.g.  loop 5 2 announce hello",
		Args = {
			{ Type = "integer", Name = "times", Description = `1 to {MAX_LOOP_RUNS}.` },
			{ Type = "number", Name = "delay", Description = "Seconds between runs (min 0.1)." },
			{ Type = "string", Name = "command", Description = "The command to repeat." },
		},
		Run = function(context, times: number, delay: number, commandText: string)
			if firstWord(commandText) == "loop" or firstWord(commandText) == "repeat" or firstWord(commandText) == "delay" then
				return "You cannot nest loops."
			end

			const runs = math.clamp(times, 1, MAX_LOOP_RUNS)
			const wait = math.max(delay, 0.1)
			const executor = context.Executor

			nextLoopId += 1
			const id = nextLoopId
			const token = { Cancelled = false }
			activeLoops[id] = token

			task.spawn(function()
				for _ = 1, runs do
					if token.Cancelled or not executor.Parent then
						break
					end

					Admin.Run(commandText, executor)
					task.wait(wait)
				end

				activeLoops[id] = nil
			end)

			return `Running "{commandText}" {runs} times. Use stoploops to cancel.`
		end,
	}, {
		Name = "delay",
		Aliases = { "later" },
		Role = "Admin",
		Description = "Runs a command after a delay, e.g.  delay 30 shutdown",
		Args = {
			{ Type = "number", Name = "seconds", Description = "Up to 3600." },
			{ Type = "string", Name = "command", Description = "The command to run later." },
		},
		Run = function(context, seconds: number, commandText: string)
			if firstWord(commandText) == "loop" or firstWord(commandText) == "repeat" or firstWord(commandText) == "delay" then
				return "You cannot nest delayed commands."
			end

			const executor = context.Executor
			nextLoopId += 1
			const id = nextLoopId
			const token = { Cancelled = false }
			activeLoops[id] = token

			task.delay(math.clamp(seconds, 0, 3600), function()
				activeLoops[id] = nil
				if not token.Cancelled and executor.Parent then
					Admin.Run(commandText, executor)
				end
			end)

			return `Will run "{commandText}" in {Admin.FormatDuration(seconds)}. Use stoploops to cancel.`
		end,
	}, {
		Name = "stoploops",
		Aliases = { "cancelloops" },
		Role = "Admin",
		Description = "Cancels every running loop and delayed command (including loopkill/loopheal).",
		Args = {},
		Run = function()
			local count = 0
			for id, token in pairs(activeLoops) do
				token.Cancelled = true
				activeLoops[id] = nil
				count += 1
			end

			table.clear(loopKill)
			table.clear(loopHeal)
			return `Cancelled {count} loops.`
		end,
	})

	-- Randomizers (open to everyone) ---------------------------------------------------------------
	add({
		Name = "random",
		Aliases = { "rng" },
		Role = "Player",
		Description = "Picks a random number and shows it to everyone.",
		Args = {
			{ Type = "integer", Name = "min", Description = "Lowest number." },
			{ Type = "integer", Name = "max", Description = "Highest number." },
		},
		Run = function(context, minimum: number, maximum: number)
			if maximum < minimum then
				minimum, maximum = maximum, minimum
			end

			return roll(context, `picked {math.random(minimum, maximum)} (random {minimum}-{maximum})`)
		end,
	}, {
		Name = "roll",
		Aliases = { "dice" },
		Role = "Player",
		Description = "Rolls a dice and shows the result to everyone.",
		Args = { { Type = "integer", Name = "sides", Description = "Default 6.", Optional = true } },
		Run = function(context, sides: number?)
			const count = math.clamp(sides or 6, 2, 1000000)
			return roll(context, `rolled a {math.random(1, count)} (d{count})`)
		end,
	}, {
		Name = "coinflip",
		Aliases = { "flip" },
		Role = "Player",
		Description = "Flips a coin and shows the result to everyone.",
		Args = {},
		Run = function(context)
			return roll(context, `flipped a coin: {if math.random(1, 2) == 1 then "heads" else "tails"}`)
		end,
	})

	return commands
end

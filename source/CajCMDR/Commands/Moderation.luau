--[[
	Moderation: kicks, bans, warnings, mutes, jails, server lock, reports.
	Bans use Roblox's official Players:BanAsync, so they persist across servers and cover alt accounts.
]]

const Players = game:GetService("Players")
const ServerStorage = game:GetService("ServerStorage")

const DEFAULT_REASON = "No reason given"
const JAIL_SIZE = 12

return function(Admin)
	const Roles = Admin.Roles
	const Chat = Admin.Chat
	const Store = Admin.Store
	const Config = Admin.Config

	const jails: { [Player]: { Cage: Model, Center: CFrame, Connection: RBXScriptConnection } } = {}
	const punished: { [Player]: Model } = {}

	----------------------------------------------------------------------------------------------------
	-- helpers
	----------------------------------------------------------------------------------------------------

	const function levelForRoleName(roleName: string?, fallbackIndex: number): number
		const role = Roles.Get(roleName)
		if role then
			return role.Level
		end

		const list = Roles.List()
		return list[math.min(fallbackIndex, #list)].Level
	end

	--[[ Splits user ids into the ones the executor may act on and a list of names that are protected. ]]
	const function filterUserIds(executor: Player, userIds: { number }): ({ number }, { string })
		const allowed = {}
		const blocked = {}
		for _, userId in ipairs(userIds) do
			if Admin.CanAffectUserId(executor, userId) then
				table.insert(allowed, userId)
			else
				table.insert(blocked, Admin.NameFromUserId(userId))
			end
		end

		return allowed, blocked
	end

	const function namesOf(userIds: { number }): string
		const names = {}
		for index, userId in ipairs(userIds) do
			if index > 5 then
				table.insert(names, `+{#userIds - 5} more`)
				break
			end
			table.insert(names, Admin.NameFromUserId(userId))
		end

		return table.concat(names, ", ")
	end

	const function protectedMessage(blocked: { string }): string
		return `You cannot act on {table.concat(blocked, ", ")} (equal or higher role).`
	end

	const function banUsers(context: any, userIds: { number }, duration: number, reason: string): string
		const executor = context.Executor
		const allowed, blocked = filterUserIds(executor, userIds)
		if #allowed == 0 then
			return protectedMessage(blocked)
		end

		const displayReason = Admin.Truncate(reason, 380)
		const ok, err = pcall(Players.BanAsync, Players, {
			UserIds = allowed,
			Duration = duration,
			DisplayReason = displayReason,
			PrivateReason = Admin.Truncate(`{executor.Name}: {reason}`, 950),
			ExcludeAltAccounts = Config.Bans.ExcludeAltAccounts == true,
			ApplyToUniverse = Config.Bans.ApplyToUniverse ~= false,
		})

		local note = ""
		if not ok then
			-- BanAsync is unavailable (for example in Studio): fall back to banning for this server only.
			for _, userId in ipairs(allowed) do
				Admin.ServerBans[userId] = reason
				const online = Players:GetPlayerByUserId(userId)
				if online then
					online:Kick(`Banned: {reason}`)
				end
			end
			note = ` (BanAsync failed: {err}. Applied as a server ban instead.)`
		end

		const length = if duration < 0 then "permanently" else `for {Admin.FormatDuration(duration)}`
		Admin.Audit(context, `banned {namesOf(allowed)} {length}: {reason}`)

		local message = `Banned {namesOf(allowed)} {length}.{note}`
		if #blocked > 0 then
			message ..= ` Skipped: {table.concat(blocked, ", ")}.`
		end

		return message
	end

	const function addEntry(storeName: string, userId: number, entry: any): number
		local total = 0
		Store.Update(storeName, tostring(userId), function(old)
			const list = if type(old) == "table" then old else {}
			table.insert(list, entry)
			total = #list
			return list
		end)

		return total
	end

	const function listEntries(context: any, storeName: string, title: string, userId: number): string
		const entries = Store.Get(storeName, tostring(userId), {})
		const lines = {}
		for index, entry in ipairs(entries) do
			table.insert(lines, `#{index} [{Admin.Timestamp(entry.Time)}] {entry.By}: {entry.Text}`)
		end

		return Admin.Output(context, `{title} for {Admin.NameFromUserId(userId)}`, lines)
	end

	const function shutdownServer(reason: string)
		Admin.ServerLock.Level = Roles.MaxLevel + 1
		Admin.ServerLock.Reason = `Server shut down: {reason}`

		Admin.Announce("Server shutting down", reason, 6)
		task.delay(4, function()
			for _, player in ipairs(Players:GetPlayers()) do
				player:Kick(`Server shut down: {reason}`)
			end
		end)
	end

	-- Cross-server actions
	Admin.OnGlobal("kick", function(data)
		const player = Players:GetPlayerByUserId(data.UserId)
		if player then
			player:Kick(data.Reason or DEFAULT_REASON)
		end
	end)

	Admin.OnGlobal("shutdown", function(data)
		shutdownServer(data.Reason or "Maintenance")
	end)

	----------------------------------------------------------------------------------------------------
	-- jail / punish
	----------------------------------------------------------------------------------------------------

	const function buildCage(center: Vector3): Model
		const model = Instance.new("Model")
		model.Name = "CajJail"

		const function wall(size: Vector3, offset: Vector3)
			const part = Instance.new("Part")
			part.Anchored = true
			part.Size = size
			part.Position = center + offset
			part.Material = Enum.Material.Metal
			part.Color = Color3.fromRGB(60, 60, 70)
			part.Transparency = 0.25
			part.Parent = model
		end

		const half = JAIL_SIZE / 2
		wall(Vector3.new(JAIL_SIZE, 1, JAIL_SIZE), Vector3.new(0, -3.5, 0))
		wall(Vector3.new(JAIL_SIZE, 1, JAIL_SIZE), Vector3.new(0, 8.5, 0))
		wall(Vector3.new(JAIL_SIZE, 12, 1), Vector3.new(0, 2.5, half))
		wall(Vector3.new(JAIL_SIZE, 12, 1), Vector3.new(0, 2.5, -half))
		wall(Vector3.new(1, 12, JAIL_SIZE), Vector3.new(half, 2.5, 0))
		wall(Vector3.new(1, 12, JAIL_SIZE), Vector3.new(-half, 2.5, 0))

		model.Parent = Admin.GetObjectsFolder()
		return model
	end

	const function unjailPlayer(player: Player): boolean
		const jail = jails[player]
		if not jail then
			return false
		end

		jail.Connection:Disconnect()
		jail.Cage:Destroy()
		jails[player] = nil
		return true
	end

	Players.PlayerRemoving:Connect(function(player)
		unjailPlayer(player)
		punished[player] = nil
	end)

	----------------------------------------------------------------------------------------------------
	-- commands
	----------------------------------------------------------------------------------------------------

	return {
		{
			Name = "kick",
			Aliases = { "boot" },
			Role = "Helper",
			Description = "Kicks players from the server.",
			Args = {
				{ Type = "targets", Name = "players", Description = "The players to kick." },
				{ Type = "string", Name = "reason", Description = "Shown to the player.", Optional = true },
			},
			Run = function(context, players: { Player }, reason: string?)
				const why = reason or DEFAULT_REASON
				const names = Admin.Names(players)
				const count = Admin.EachPlayer(players, function(player)
					player:Kick(`You were kicked. Reason: {why}`)
				end)

				Admin.Audit(context, `kicked {names}: {why}`)
				return Admin.Result("Kicked", count)
			end,
		},
		{
			Name = "kickall",
			Role = "Admin",
			Description = "Kicks every player with a lower role than you.",
			Args = {
				{ Type = "string", Name = "reason", Description = "Shown to the players.", Optional = true },
			},
			Run = function(context, reason: string?)
				const why = reason or "The server is being cleared"
				const executorLevel = Roles.GetLevel(context.Executor)
				local count = 0
				for _, player in ipairs(Players:GetPlayers()) do
					if player ~= context.Executor and Roles.GetLevel(player) < executorLevel then
						player:Kick(`You were kicked. Reason: {why}`)
						count += 1
					end
				end

				Admin.Audit(context, `kicked everyone below their rank ({count}): {why}`)
				return Admin.Result("Kicked", count)
			end,
		},
		{
			Name = "ban",
			Role = "Admin",
			Description = "Permanently bans players (works on offline users too).",
			Args = {
				{ Type = "playerIds", Name = "players", Description = "Players or UserIds (#123) to ban." },
				{ Type = "string", Name = "reason", Description = "Shown to the player.", Optional = true },
			},
			Run = function(context, userIds: { number }, reason: string?)
				return banUsers(context, userIds, -1, reason or DEFAULT_REASON)
			end,
		},
		{
			Name = "tempban",
			Aliases = { "tban" },
			Role = "Moderator",
			Description = "Bans players for a limited time, e.g. 1d12h.",
			Args = {
				{ Type = "playerIds", Name = "players", Description = "Players or UserIds (#123) to ban." },
				{ Type = "duration", Name = "duration", Description = "How long, e.g. 30m, 2h, 7d." },
				{ Type = "string", Name = "reason", Description = "Shown to the player.", Optional = true },
			},
			Run = function(context, userIds: { number }, duration: number, reason: string?)
				if duration <= 0 then
					return "The duration must be longer than zero. Use ban for permanent bans."
				end

				return banUsers(context, userIds, duration, reason or DEFAULT_REASON)
			end,
		},
		{
			Name = "unban",
			Role = "Admin",
			Description = "Removes bans (works on offline users).",
			Args = {
				{ Type = "playerIds", Name = "players", Description = "Players or UserIds (#123) to unban." },
			},
			Run = function(context, userIds: { number })
				const ok, err = pcall(Players.UnbanAsync, Players, {
					UserIds = userIds,
					ApplyToUniverse = Config.Bans.ApplyToUniverse ~= false,
				})

				for _, userId in ipairs(userIds) do
					Admin.ServerBans[userId] = nil
				end

				if not ok then
					return `Server bans were lifted, but UnbanAsync failed: {err}`
				end

				Admin.Audit(context, `unbanned {namesOf(userIds)}`)
				return `Unbanned {namesOf(userIds)}.`
			end,
		},
		{
			Name = "baninfo",
			Aliases = { "banhistory" },
			Role = "Moderator",
			Description = "Shows the ban history of a user.",
			Args = {
				{ Type = "playerId", Name = "player", Description = "Player or UserId (#123)." },
			},
			Run = function(context, userId: number)
				const ok, pages = pcall(Players.GetBanHistoryAsync, Players, userId)
				if not ok then
					return `Could not read the ban history: {pages}`
				end

				const lines = {}
				for _, item in ipairs(pages:GetCurrentPage()) do
					table.insert(
						lines,
						`{if item.Ban then "BAN" else "UNBAN"} {tostring(item.StartTime or "")} - {tostring(item.DurationSeconds or "?")}s - {tostring(item.DisplayReason or "")} | {tostring(item.PrivateReason or "")}`
					)
				end

				return Admin.Output(context, `Ban history of {Admin.NameFromUserId(userId)}`, lines)
			end,
		},
		{
			Name = "serverban",
			Aliases = { "sban" },
			Role = "Moderator",
			Description = "Bans players from this server only (until it closes).",
			Args = {
				{ Type = "playerIds", Name = "players", Description = "Players or UserIds (#123)." },
				{ Type = "string", Name = "reason", Description = "Shown to the player.", Optional = true },
			},
			Run = function(context, userIds: { number }, reason: string?)
				const why = reason or DEFAULT_REASON
				const allowed, blocked = filterUserIds(context.Executor, userIds)
				if #allowed == 0 then
					return protectedMessage(blocked)
				end

				for _, userId in ipairs(allowed) do
					Admin.ServerBans[userId] = why
					const online = Players:GetPlayerByUserId(userId)
					if online then
						online:Kick(`Banned from this server: {why}`)
					end
				end

				Admin.Audit(context, `server-banned {namesOf(allowed)}: {why}`)
				return `Server-banned {namesOf(allowed)}.`
			end,
		},
		{
			Name = "unserverban",
			Aliases = { "unsban" },
			Role = "Moderator",
			Description = "Lifts a server-only ban.",
			Args = {
				{ Type = "playerIds", Name = "players", Description = "Players or UserIds (#123)." },
			},
			Run = function(context, userIds: { number })
				local count = 0
				for _, userId in ipairs(userIds) do
					if Admin.ServerBans[userId] then
						Admin.ServerBans[userId] = nil
						count += 1
					end
				end

				Admin.Audit(context, `lifted server bans ({count})`)
				return `Lifted {count} server ban(s).`
			end,
		},
		{
			Name = "warn",
			Role = "Helper",
			Description = "Gives players a saved warning.",
			Args = {
				{ Type = "targets", Name = "players", Description = "The players to warn." },
				{ Type = "string", Name = "reason", Description = "Why they are being warned." },
			},
			Run = function(context, players: { Player }, reason: string)
				const limit = Config.Warnings.AutoKickAt or 0
				const count = Admin.EachPlayer(players, function(player)
					const total = addEntry("Warnings", player.UserId, {
						Time = os.time(),
						By = context.Executor.Name,
						Text = reason,
					})

					Admin.Notify(player, `Warning #{total}: {reason}`, "warn")
					if limit > 0 and total >= limit then
						player:Kick(`You reached {limit} warnings. Last reason: {reason}`)
					end
				end)

				Admin.Audit(context, `warned {Admin.Names(players)}: {reason}`)
				return Admin.Result("Warned", count)
			end,
		},
		{
			Name = "warnings",
			Aliases = { "warns" },
			Role = "Helper",
			Description = "Lists the saved warnings of a user.",
			Args = {
				{ Type = "playerId", Name = "player", Description = "Player or UserId (#123)." },
			},
			Run = function(context, userId: number)
				return listEntries(context, "Warnings", "Warnings", userId)
			end,
		},
		{
			Name = "clearwarnings",
			Aliases = { "clearwarns" },
			Role = "Moderator",
			Description = "Deletes every warning of a user.",
			Args = {
				{ Type = "playerId", Name = "player", Description = "Player or UserId (#123)." },
			},
			Run = function(context, userId: number)
				Store.Remove("Warnings", tostring(userId))
				Admin.Audit(context, `cleared the warnings of {Admin.NameFromUserId(userId)}`)
				return `Cleared the warnings of {Admin.NameFromUserId(userId)}.`
			end,
		},
		{
			Name = "note",
			Role = "Helper",
			Description = "Saves a private staff note about a user.",
			Args = {
				{ Type = "playerId", Name = "player", Description = "Player or UserId (#123)." },
				{ Type = "string", Name = "note", Description = "The note." },
			},
			Run = function(context, userId: number, text: string)
				const total = addEntry("Notes", userId, { Time = os.time(), By = context.Executor.Name, Text = text })
				return `Saved note #{total} for {Admin.NameFromUserId(userId)}.`
			end,
		},
		{
			Name = "notes",
			Role = "Helper",
			Description = "Lists the staff notes about a user.",
			Args = {
				{ Type = "playerId", Name = "player", Description = "Player or UserId (#123)." },
			},
			Run = function(context, userId: number)
				return listEntries(context, "Notes", "Notes", userId)
			end,
		},
		{
			Name = "clearnotes",
			Role = "Admin",
			Description = "Deletes every staff note about a user.",
			Args = {
				{ Type = "playerId", Name = "player", Description = "Player or UserId (#123)." },
			},
			Run = function(context, userId: number)
				Store.Remove("Notes", tostring(userId))
				Admin.Audit(context, `cleared the notes of {Admin.NameFromUserId(userId)}`)
				return `Cleared the notes of {Admin.NameFromUserId(userId)}.`
			end,
		},
		{
			Name = "mute",
			Role = "Helper",
			Description = "Stops players from using chat (optionally for a limited time).",
			Args = {
				{ Type = "targets", Name = "players", Description = "The players to mute." },
				{ Type = "duration", Name = "duration", Description = "How long, e.g. 10m. Default: until the server closes.", Optional = true },
				{ Type = "string", Name = "reason", Description = "Why they are muted.", Optional = true },
			},
			Run = function(context, players: { Player }, duration: number?, reason: string?)
				const why = reason or DEFAULT_REASON
				const count = Admin.EachPlayer(players, function(player)
					Chat.Mute(player.UserId, duration, why)
					Admin.Notify(player, `You were muted. Reason: {why}`, "warn")
				end)

				Admin.Audit(context, `muted {Admin.Names(players)}: {why}`)
				return Admin.Result("Muted", count)
			end,
		},
		{
			Name = "unmute",
			Role = "Helper",
			Description = "Lets muted players chat again.",
			Args = {
				{ Type = "players", Name = "players", Description = "The players to unmute." },
			},
			Run = function(context, players: { Player })
				const count = Admin.EachPlayer(players, function(player)
					if Chat.Unmute(player.UserId) then
						Admin.Notify(player, "You were unmuted.", "success")
						return true
					end

					return false
				end)

				Admin.Audit(context, `unmuted {Admin.Names(players)}`)
				return Admin.Result("Unmuted", count)
			end,
		},
		{
			Name = "muted",
			Role = "Helper",
			Description = "Lists the currently muted players.",
			Args = {},
			Run = function(context)
				const lines = {}
				for userId in pairs(Chat.Muted) do
					const muted, reason, remaining = Chat.IsMuted(userId)
					if muted then
						table.insert(lines, `{Admin.NameFromUserId(userId)} - {Admin.FormatDuration(remaining)} - {reason}`)
					end
				end

				return Admin.Output(context, "Muted players", lines)
			end,
		},
		{
			Name = "lockchat",
			Role = "Moderator",
			Description = "Only lets the given role (and above) chat. Default: Helper.",
			Args = {
				{ Type = "role", Name = "role", Description = "Minimum role allowed to chat.", Optional = true },
			},
			Run = function(context, roleName: string?)
				Chat.LockLevel = levelForRoleName(roleName or "Helper", 2)
				Admin.Audit(context, `locked chat for roles below {Roles.GetRoleForLevel(Chat.LockLevel).Name}`)
				return `Chat is now locked for roles below {Roles.GetRoleForLevel(Chat.LockLevel).Name}.`
			end,
		},
		{
			Name = "unlockchat",
			Role = "Moderator",
			Description = "Unlocks the chat again.",
			Args = {},
			Run = function(context)
				Chat.LockLevel = 0
				Admin.Audit(context, "unlocked chat")
				return "Chat unlocked."
			end,
		},
		{
			Name = "slowmode",
			Role = "Moderator",
			Description = "Limits how often normal players can chat (0 = off).",
			Args = {
				{ Type = "nonNegativeInteger", Name = "seconds", Description = "Seconds between messages." },
			},
			Run = function(context, seconds: number)
				Chat.SlowSeconds = seconds
				Admin.Audit(context, `set slow mode to {seconds}s`)
				return if seconds == 0 then "Slow mode disabled." else `Slow mode: one message every {seconds}s.`
			end,
		},
		{
			Name = "jail",
			Role = "Moderator",
			Description = "Locks players inside a cage.",
			Args = {
				{ Type = "targets", Name = "players", Description = "The players to jail." },
			},
			Run = function(context, players: { Player })
				const count = Admin.Each(players, function(player, _character, _humanoid, root)
					if jails[player] then
						return false
					end

					const center = root.Position + Vector3.new(0, 2, 0)
					const cage = buildCage(center)
					const spot = CFrame.new(center)

					jails[player] = {
						Cage = cage,
						Center = spot,
						Connection = player.CharacterAdded:Connect(function(character)
							const newRoot = character:WaitForChild("HumanoidRootPart", 10)
							if newRoot and jails[player] then
								task.wait()
								character:PivotTo(spot)
							end
						end),
					}
				end)

				Admin.Audit(context, `jailed {Admin.Names(players)}`)
				return Admin.Result("Jailed", count)
			end,
		},
		{
			Name = "unjail",
			Role = "Moderator",
			Description = "Releases players from jail.",
			Args = {
				{ Type = "players", Name = "players", Description = "The players to release." },
			},
			Run = function(context, players: { Player })
				const count = Admin.EachPlayer(players, unjailPlayer)
				Admin.Audit(context, `released {Admin.Names(players)} from jail`)
				return Admin.Result("Released", count)
			end,
		},
		{
			Name = "punish",
			Role = "Moderator",
			Description = "Removes players' characters from the world until unpunished.",
			Args = {
				{ Type = "targets", Name = "players", Description = "The players to punish." },
			},
			Run = function(context, players: { Player })
				const count = Admin.Each(players, function(player, character)
					punished[player] = character
					character.Parent = ServerStorage
				end)

				Admin.Audit(context, `punished {Admin.Names(players)}`)
				return Admin.Result("Punished", count)
			end,
		},
		{
			Name = "unpunish",
			Role = "Moderator",
			Description = "Puts punished players back into the world.",
			Args = {
				{ Type = "players", Name = "players", Description = "The players to restore." },
			},
			Run = function(_, players: { Player })
				const count = Admin.EachPlayer(players, function(player)
					const character = punished[player]
					punished[player] = nil
					if character and character.Parent == ServerStorage then
						character.Parent = workspace
						return true
					end

					return false
				end)

				return Admin.Result("Restored", count)
			end,
		},
		{
			Name = "slock",
			Aliases = { "serverlock" },
			Role = "Moderator",
			Description = "Stops players below a role from joining this server. Default: Helper.",
			Args = {
				{ Type = "role", Name = "role", Description = "Minimum role allowed to join.", Optional = true },
			},
			Run = function(context, roleName: string?)
				Admin.ServerLock.Level = levelForRoleName(roleName or "Helper", 2)
				Admin.ServerLock.Reason = "This server is locked."
				Admin.Audit(context, `locked the server for roles below {Roles.GetRoleForLevel(Admin.ServerLock.Level).Name}`)
				return `Server locked. Players below {Roles.GetRoleForLevel(Admin.ServerLock.Level).Name} can no longer join.`
			end,
		},
		{
			Name = "unslock",
			Aliases = { "unlockserver" },
			Role = "Moderator",
			Description = "Unlocks the server.",
			Args = {},
			Run = function(context)
				Admin.ServerLock.Level = 0
				Admin.ServerLock.Reason = ""
				Admin.Audit(context, "unlocked the server")
				return "Server unlocked."
			end,
		},
		{
			Name = "shutdown",
			Role = "Admin",
			Description = "Kicks everyone and locks this server.",
			Args = {
				{ Type = "string", Name = "reason", Description = "Shown to the players.", Optional = true },
			},
			Run = function(context, reason: string?)
				const why = reason or "Maintenance"
				Admin.Audit(context, `shut down the server: {why}`)
				shutdownServer(why)
				return "Shutting down in 4 seconds..."
			end,
		},
		{
			Name = "globalshutdown",
			Aliases = { "gshutdown" },
			Role = "Owner",
			Description = "Shuts down EVERY server of this experience.",
			Args = {
				{ Type = "string", Name = "reason", Description = "Shown to the players.", Optional = true },
			},
			Run = function(context, reason: string?)
				const why = reason or "Maintenance"
				Admin.Audit(context, `shut down all servers: {why}`)

				const ok, err = Admin.PublishGlobal("shutdown", { Reason = why })
				if not ok then
					Admin.RunGlobalLocally("shutdown", { Reason = why })
					return `Could not reach other servers ({err}). Shut down this server only.`
				end

				return "Shutdown sent to all servers."
			end,
		},
		{
			Name = "gkick",
			Aliases = { "globalkick" },
			Role = "Admin",
			Description = "Kicks a user from whichever server they are in.",
			Args = {
				{ Type = "playerId", Name = "player", Description = "Player or UserId (#123)." },
				{ Type = "string", Name = "reason", Description = "Shown to the player.", Optional = true },
			},
			Run = function(context, userId: number, reason: string?)
				if not Admin.CanAffectUserId(context.Executor, userId) then
					return "You cannot act on someone with an equal or higher role."
				end

				const data = { UserId = userId, Reason = `You were kicked. Reason: {reason or DEFAULT_REASON}` }
				const ok = Admin.PublishGlobal("kick", data)
				if not ok then
					Admin.RunGlobalLocally("kick", data)
				end

				Admin.Audit(context, `global-kicked {Admin.NameFromUserId(userId)}: {reason or DEFAULT_REASON}`)
				return `Sent a kick for {Admin.NameFromUserId(userId)} to all servers.`
			end,
		},
		{
			Name = "report",
			Aliases = { "callmod" },
			Role = "Player",
			Description = "Reports a player to the staff in this server.",
			Args = {
				{ Type = "player", Name = "player", Description = "The player you are reporting." },
				{ Type = "string", Name = "reason", Description = "What happened." },
			},
			Run = function(context, player: Player, reason: string)
				if player == context.Executor then
					return "You cannot report yourself."
				end

				const ready, wait = Admin.Cooldown(`report{context.Executor.UserId}`, Config.ReportCooldown or 60)
				if not ready then
					return `Please wait {math.ceil(wait)} more seconds before sending another report.`
				end

				const text = `REPORT: {context.Executor.Name} reported {player.Name}: {Admin.Truncate(reason, 200)}`
				Admin.Log.Audit({ Time = os.time(), Executor = context.Executor.Name, UserId = context.Executor.UserId, Text = text })
				Admin.NotifyStaff(text, "warn", 1)
				Admin.Log.Webhook(text)
				return "Your report was sent to the staff. Thank you!"
			end,
		},
	}
end

--[[
	Info: look things up. Mostly harmless, mostly available to everyone.
]]

const MarketplaceService = game:GetService("MarketplaceService")
const Players = game:GetService("Players")
const Stats = game:GetService("Stats")
const TextChatService = game:GetService("TextChatService")

return function(Admin)
	const Roles = Admin.Roles

	const function roleLine(player: Player): string
		const role = Roles.GetRole(player)
		return `{role.Name} ({role.Level})`
	end

	return {
		{
			Name = "whoami",
			Aliases = { "myrole" },
			Role = "Player",
			Description = "Shows your role and where it comes from.",
			Args = {},
			Run = function(context)
				const player = context.Executor
				const role = Roles.GetRole(player)
				return `You are {role.Name} (level {role.Level}). Source: {Roles.GetSource(player)}.`
			end,
		},
		{
			Name = "roles",
			Role = "Player",
			Description = "Lists every role and how many players have it.",
			Args = {},
			Run = function(context)
				const lines = {}
				const list = Roles.List()
				for index = #list, 1, -1 do
					const role = list[index]
					local online = 0
					for _, player in ipairs(Players:GetPlayers()) do
						if player:GetAttribute("CajRole") == role.Name then
							online += 1
						end
					end

					table.insert(lines, `{role.Name} - level {role.Level} - {online} online`)
				end

				return Admin.Output(context, "Roles", lines)
			end,
		},
		{
			Name = "getrole",
			Aliases = { "rolecheck" },
			Role = "Player",
			Description = "Shows the role of a player.",
			Args = {
				{ Type = "player", Name = "player", Description = "The player to check." },
			},
			Run = function(_, player: Player)
				const role = Roles.GetRole(player)
				return `{player.Name} is {role.Name} (level {role.Level}). Source: {Roles.GetSource(player)}.`
			end,
		},
		{
			Name = "admins",
			Aliases = { "staff", "mods" },
			Role = "Player",
			Description = "Lists staff members who are in this server.",
			Args = {},
			Run = function(context)
				const staff = {}
				for _, player in ipairs(Players:GetPlayers()) do
					if Roles.IsStaff(player) then
						table.insert(staff, player)
					end
				end

				table.sort(staff, function(a, b)
					return Roles.GetLevel(a) > Roles.GetLevel(b)
				end)

				const lines = {}
				for _, player in ipairs(staff) do
					table.insert(lines, `{player.Name} - {Roles.GetRole(player).Name}`)
				end

				return Admin.Output(context, "Staff online", lines)
			end,
		},
		{
			Name = "players",
			Aliases = { "plist" },
			Role = "Player",
			Description = "Lists every player in the server.",
			Args = {},
			Run = function(context)
				const lines = {}
				for _, player in ipairs(Players:GetPlayers()) do
					table.insert(
						lines,
						`{player.Name} (@{player.DisplayName}) - {roleLine(player)} - {if player.Team then player.Team.Name else "no team"}`
					)
				end

				return Admin.Output(context, `Players ({#lines})`, lines)
			end,
		},
		{
			Name = "count",
			Role = "Player",
			Description = "Shows how many players are in the server.",
			Args = {},
			Run = function()
				return `{#Players:GetPlayers()} / {Players.MaxPlayers} players.`
			end,
		},
		{
			Name = "whois",
			Aliases = { "pinfo", "playerinfo" },
			Role = "Helper",
			Description = "Shows detailed information about a player.",
			Args = {
				{ Type = "player", Name = "player", Description = "The player to inspect." },
			},
			Run = function(context, player: Player)
				const humanoid = Admin.GetHumanoid(player)
				const root = Admin.GetRoot(player)
				const muted, reason = Admin.Chat.IsMuted(player.UserId)

				local healthText = "no character"
				if humanoid then
					healthText = `{math.floor(humanoid.Health)} / {math.floor(humanoid.MaxHealth)}`
				end

				local positionText = "n/a"
				if root then
					const position = root.Position
					positionText = `{math.floor(position.X)}, {math.floor(position.Y)}, {math.floor(position.Z)}`
				end

				const mutedText = if muted then `yes ({reason})` else "no"

				const lines = {
					`Name: {player.Name} (@{player.DisplayName})`,
					`UserId: {player.UserId}`,
					`Account age: {player.AccountAge} days`,
					`Membership: {player.MembershipType.Name}`,
					`Role: {roleLine(player)} - {Roles.GetSource(player)}`,
					`Team: {if player.Team then player.Team.Name else "none"}`,
					`Health: {healthText}`,
					`Position: {positionText}`,
					`Ping: {math.floor(player:GetNetworkPing() * 1000)} ms`,
					`Locale: {player.LocaleId}`,
					`Muted: {mutedText}`,
				}

				return Admin.Output(context, `Who is {player.Name}`, lines)
			end,
		},
		{
			Name = "userid",
			Aliases = { "getid" },
			Role = "Player",
			Description = "Looks up the UserId of a Roblox username.",
			Args = {
				{ Type = "string", Name = "username", Description = "The Roblox username." },
			},
			Run = function(_, username: string)
				const ok, userId = pcall(Players.GetUserIdFromNameAsync, Players, username)
				if not ok then
					return `No Roblox user called "{username}" was found.`
				end

				return `{username} has the UserId {userId}.`
			end,
		},
		{
			Name = "username",
			Aliases = { "getname" },
			Role = "Player",
			Description = "Looks up the username that belongs to a UserId.",
			Args = {
				{ Type = "positiveInteger", Name = "userId", Description = "The UserId." },
			},
			Run = function(_, userId: number)
				const ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
				if not ok then
					return `No Roblox user with the UserId {userId} was found.`
				end

				return `UserId {userId} is {name}.`
			end,
		},
		{
			Name = "serverinfo",
			Aliases = { "sinfo" },
			Role = "Player",
			Description = "Shows information about this server.",
			Args = {},
			Run = function(context)
				const lock = Admin.ServerLock
				const lockText = if lock.Level > 0 then `yes (needs {Roles.GetRoleForLevel(lock.Level).Name}+)` else "no"
				const lines = {
					`Place: {game.PlaceId} (version {game.PlaceVersion})`,
					`Server id: {if game.JobId == "" then "Studio" else game.JobId}`,
					`Players: {#Players:GetPlayers()} / {Players.MaxPlayers}`,
					`Uptime: {Admin.FormatDuration(os.time() - Admin.StartTime)}`,
					`Private server: {if game.PrivateServerId ~= "" then "yes" else "no"}`,
					`Locked: {lockText}`,
					`Chat system: {TextChatService.ChatVersion.Name}`,
					`Saved data: {if Admin.Store.IsPersistent() then "DataStore" else "memory only"}`,
				}

				return Admin.Output(context, "Server", lines)
			end,
		},
		{
			Name = "uptime",
			Role = "Player",
			Description = "Shows how long this server has been running.",
			Args = {},
			Run = function()
				return `This server has been running for {Admin.FormatDuration(os.time() - Admin.StartTime)}.`
			end,
		},
		{
			Name = "servertime",
			Aliases = { "date" },
			Role = "Player",
			Description = "Shows the current server date and time (UTC).",
			Args = {},
			Run = function()
				return os.date("!%Y-%m-%d %H:%M:%S UTC") :: string
			end,
		},
		{
			Name = "ping",
			Role = "Player",
			Description = "Shows the network ping of a player (default: you).",
			Args = {
				{ Type = "player", Name = "player", Description = "The player to check.", Optional = true },
			},
			Run = function(context, player: Player?)
				const target = player or context.Executor
				return `{target.Name}'s ping is {math.floor(target:GetNetworkPing() * 1000)} ms.`
			end,
		},
		{
			Name = "position",
			Aliases = { "pos", "where" },
			Role = "Helper",
			Description = "Shows where a player is standing.",
			Args = {
				{ Type = "player", Name = "player", Description = "The player to locate." },
			},
			Run = function(_, player: Player)
				const root = Admin.GetRoot(player)
				if not root then
					return `{player.Name} has no character.`
				end

				const position = root.Position
				return `{player.Name} is at {math.floor(position.X)}, {math.floor(position.Y)}, {math.floor(position.Z)}.`
			end,
		},
		{
			Name = "teams",
			Role = "Player",
			Description = "Lists the teams in the game.",
			Args = {},
			Run = function(context)
				const lines = {}
				for _, team in ipairs(game:GetService("Teams"):GetTeams()) do
					table.insert(lines, `{team.Name} - {#team:GetPlayers()} players`)
				end

				return Admin.Output(context, "Teams", lines)
			end,
		},
		{
			Name = "prefix",
			Role = "Player",
			Description = "Shows how to open the console and the chat command prefix.",
			Args = {},
			Run = function()
				const chatConfig = Admin.Config.Chat
				const keys = table.concat(Admin.Config.ConsoleKeys or { "F2" }, " or ")
				if chatConfig and chatConfig.Enabled then
					return `Open the console with {keys}, or type {chatConfig.Prefix}command in chat.`
				end

				return `Open the console with {keys}.`
			end,
		},
		{
			Name = "about",
			Aliases = { "caj" },
			Role = "Player",
			Description = "Shows which admin system this is.",
			Args = {},
			Run = function()
				local count = 0
				for _ in pairs(Admin.Specs) do
					count += 1
				end

				return `CajCMDR {Admin.Version}, built on Cmdr. {count} commands loaded. Type help for the list.`
			end,
		},
		{
			Name = "perms",
			Aliases = { "access" },
			Role = "Player",
			Description = "Shows which role is needed for a command.",
			Args = {
				{ Type = "command", Name = "command", Description = "The command to check." },
			},
			Run = function(context, commandName: string)
				const key = commandName:lower()
				const level = Admin.CommandLevels[key]
				if level == nil then
					return `"{commandName}" is not managed by CajCMDR.`
				end

				if level < 0 then
					return `"{commandName}" is disabled.`
				end

				const role = Roles.GetRoleForLevel(level)
				const allowed = Roles.GetLevel(context.Executor) >= level
				return `"{commandName}" needs {role.Name} or higher. {if allowed then "You can use it." else "You cannot use it."}`
			end,
		},
		{
			Name = "gameinfo",
			Aliases = { "placeinfo" },
			Role = "Player",
			Description = "Shows the name and creator of this experience.",
			Args = {},
			Run = function(context)
				const ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, game.PlaceId)
				if not ok or type(info) ~= "table" then
					return "No published info available (is the place published?)."
				end

				return Admin.Output(context, info.Name or "Game", {
					`Creator: {if info.Creator then info.Creator.Name else "unknown"}`,
					`Updated: {tostring(info.Updated)}`,
					`Description: {Admin.Truncate(tostring(info.Description or ""), 160)}`,
				})
			end,
		},
		{
			Name = "serverstats",
			Aliases = { "perf" },
			Role = "Admin",
			Description = "Shows memory, physics and instance statistics of the server.",
			Args = {},
			Run = function(context)
				const lines = {}

				const okMemory, memory = pcall(function()
					return Stats:GetTotalMemoryUsageMb()
				end)
				if okMemory then
					table.insert(lines, `Memory: {math.floor(memory)} MB`)
				end

				const okInstances, instances = pcall(function()
					return Stats.InstanceCount
				end)
				if okInstances then
					table.insert(lines, `Instances: {instances}`)
				end

				const okHeartbeat, heartbeat = pcall(function()
					return Stats.HeartbeatTimeMs
				end)
				if okHeartbeat then
					table.insert(lines, `Heartbeat: {string.format("%.2f", heartbeat)} ms`)
				end

				table.insert(lines, `Physics FPS: {math.floor(workspace:GetRealPhysicsFPS())}`)
				table.insert(lines, `Players: {#Players:GetPlayers()}`)

				return Admin.Output(context, "Server stats", lines)
			end,
		},
		{
			Name = "logs",
			Aliases = { "cmdlogs" },
			Role = "Admin",
			Description = "Shows the most recent commands that were run in this server.",
			Args = {
				{ Type = "positiveInteger", Name = "count", Description = "How many entries (default 25).", Optional = true },
			},
			Run = function(context, count: number?)
				const lines = {}
				for _, entry in ipairs(Admin.Log.GetCommands(math.min(count or 25, 80))) do
					table.insert(lines, `[{os.date("!%H:%M:%S", entry.Time)}] {entry.Executor}: {entry.Text}`)
				end

				return Admin.Output(context, "Command log", lines)
			end,
		},
		{
			Name = "clearlogs",
			Role = "Admin",
			Description = "Clears the in-memory command log.",
			Args = {},
			Run = function()
				Admin.Log.ClearCommands()
				return "Command log cleared."
			end,
		},
		{
			Name = "chatlogs",
			Role = "Moderator",
			Description = "Shows the most recent chat messages.",
			Args = {
				{ Type = "positiveInteger", Name = "count", Description = "How many messages (default 25).", Optional = true },
			},
			Run = function(context, count: number?)
				const lines = {}
				for _, entry in ipairs(Admin.Log.GetChat(math.min(count or 25, 80))) do
					table.insert(lines, `[{os.date("!%H:%M:%S", entry.Time)}] {entry.Player}: {entry.Text}`)
				end

				return Admin.Output(context, "Chat log", lines)
			end,
		},
		{
			Name = "auditlog",
			Aliases = { "audit" },
			Role = "Moderator",
			Description = "Shows the saved moderation history (kicks, bans, warnings, ...).",
			Args = {
				{ Type = "positiveInteger", Name = "count", Description = "How many entries (default 20).", Optional = true },
			},
			Run = function(context, count: number?)
				const entries = Admin.Log.GetAudit()
				const lines = {}
				for index = math.max(1, #entries - (count or 20) + 1), #entries do
					const entry = entries[index]
					table.insert(lines, `[{Admin.Timestamp(entry.Time)}] {entry.Executor}: {entry.Text} -> {entry.Response or ""}`)
				end

				return Admin.Output(context, "Moderation history", lines)
			end,
		},
	}
end

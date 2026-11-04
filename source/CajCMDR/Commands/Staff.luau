--[[
	Staff: manage roles and command permissions while the game is running.
]]

const Players = game:GetService("Players")

-- These can never be disabled or re-ranked at runtime, so nobody can lock the owner out.
const PROTECTED_COMMANDS = { setcmdrole = true, disablecmd = true, enablecmd = true, resetcmdroles = true }

return function(Admin)
	const Roles = Admin.Roles

	--[[ Roles at or above the executor's own cannot be handed out (the top role may hand out anything). ]]
	const function canGrant(executor: Player, role: any): boolean
		const level = Roles.GetLevel(executor)
		return level >= Roles.MaxLevel or role.Level < level
	end

	return {
		{
			Name = "setrole",
			Aliases = { "giverole" },
			Role = "Admin",
			Description = "Gives players a role until this server closes.",
			Args = {
				{ Type = "targets", Name = "players", Description = "The players." },
				{ Type = "role", Name = "role", Description = "The role to give." },
			},
			Run = function(context, players: { Player }, roleName: string)
				const role = Roles.Get(roleName)
				if not role or not canGrant(context.Executor, role) then
					return "You can only hand out roles that are lower than your own."
				end

				const count = Admin.EachPlayer(players, function(player)
					Roles.SetTemp(player.UserId, role.Name)
					Admin.Notify(player, `You were given the {role.Name} role.`, "success")
				end)

				Admin.Audit(context, `gave {role.Name} to {Admin.Names(players)} (temporary)`)
				return Admin.Result(`Gave {role.Name} to`, count)
			end,
		},
		{
			Name = "saverole",
			Role = "HeadAdmin",
			Description = "Gives a user a role that is saved forever (works on offline users).",
			Args = {
				{ Type = "playerId", Name = "player", Description = "Player or UserId (#123)." },
				{ Type = "role", Name = "role", Description = "The role to give." },
			},
			Run = function(context, userId: number, roleName: string)
				const role = Roles.Get(roleName)
				if not role or not canGrant(context.Executor, role) then
					return "You can only hand out roles that are lower than your own."
				end

				if not Admin.CanAffectUserId(context.Executor, userId) then
					return "You cannot change the role of someone with an equal or higher role."
				end

				const name = Admin.NameFromUserId(userId)
				const saved = Roles.SetSaved(userId, role.Name)
				Admin.Audit(context, `saved the {role.Name} role for {name}`)

				if not saved then
					return `Gave {name} the {role.Name} role for now, but saving failed (check DataStore access).`
				end

				return `{name} now has the {role.Name} role permanently.`
			end,
		},
		{
			Name = "removerole",
			Aliases = { "unrole" },
			Role = "Admin",
			Description = "Removes temporary and saved roles from a user (community ranks still apply).",
			Args = {
				{ Type = "playerId", Name = "player", Description = "Player or UserId (#123)." },
			},
			Run = function(context, userId: number)
				if not Admin.CanAffectUserId(context.Executor, userId) then
					return "You cannot change the role of someone with an equal or higher role."
				end

				Roles.Clear(userId)
				Admin.Audit(context, `removed the custom roles of {Admin.NameFromUserId(userId)}`)
				return `Removed the custom roles of {Admin.NameFromUserId(userId)}.`
			end,
		},
		{
			Name = "refreshroles",
			Aliases = { "refreshranks" },
			Role = "Moderator",
			Description = "Re-checks community ranks right now (default: everyone).",
			Args = {
				{ Type = "players", Name = "players", Description = "The players (default: all).", Optional = true },
			},
			Run = function(_, players: { Player }?)
				const list = players or Players:GetPlayers()
				local count = 0
				for _, player in ipairs(list) do
					task.spawn(Roles.Resolve, player)
					count += 1
				end

				return `Refreshing the roles of {Admin.Plural(count, "player")}.`
			end,
		},
		{
			Name = "staffchat",
			Aliases = { "sc", "a" },
			Role = "Helper",
			Description = "Sends a message that only staff can see.",
			Args = { { Type = "string", Name = "message", Description = "The message." } },
			Run = function(context, message: string)
				Admin.NotifyStaff(`[Staff] {context.Executor.DisplayName}: {message}`, "info", 1)
				return ""
			end,
		},
		{
			Name = "setcmdrole",
			Aliases = { "cmdrole" },
			Role = "Owner",
			Description = "Changes which role is needed for a command until the server closes.",
			Args = {
				{ Type = "command", Name = "command", Description = "The command." },
				{ Type = "role", Name = "role", Description = "The minimum role." },
			},
			Run = function(context, commandName: string, roleName: string)
				const key = commandName:lower()
				const role = Roles.Get(roleName)
				if PROTECTED_COMMANDS[key] or not role or Admin.CommandLevels[key] == nil then
					return "That command cannot be changed."
				end

				Admin.CommandLevels[key] = role.Level
				Admin.PublishCommandLevels()
				Admin.Audit(context, `set {commandName} to {role.Name}`)
				return `{commandName} now needs {role.Name} or higher.`
			end,
		},
		{
			Name = "disablecmd",
			Aliases = { "disablecommand" },
			Role = "Owner",
			Description = "Turns a command off until the server closes.",
			Args = { { Type = "command", Name = "command", Description = "The command." } },
			Run = function(context, commandName: string)
				const key = commandName:lower()
				if PROTECTED_COMMANDS[key] or Admin.CommandLevels[key] == nil then
					return "That command cannot be disabled."
				end

				Admin.CommandLevels[key] = -1
				Admin.PublishCommandLevels()
				Admin.Audit(context, `disabled {commandName}`)
				return `{commandName} is now disabled.`
			end,
		},
		{
			Name = "enablecmd",
			Aliases = { "enablecommand" },
			Role = "Owner",
			Description = "Turns a disabled command back on with its normal role.",
			Args = { { Type = "command", Name = "command", Description = "The command." } },
			Run = function(context, commandName: string)
				const key = commandName:lower()
				const spec = Admin.Specs[key]
				if not spec then
					return "That command is not managed by CajCMDR."
				end

				Admin.CommandLevels[key] = spec.Level
				Admin.PublishCommandLevels()
				Admin.Audit(context, `enabled {commandName}`)
				return `{commandName} now needs {spec.Role} or higher.`
			end,
		},
		{
			Name = "resetcmdroles",
			Role = "Owner",
			Description = "Restores every command to the role from the Config.",
			Args = {},
			Run = function(context)
				for key, spec in pairs(Admin.Specs) do
					Admin.CommandLevels[key] = spec.Level
				end

				Admin.PublishCommandLevels()
				Admin.Audit(context, "reset all command roles")
				return "All command roles were reset."
			end,
		},
		{
			Name = "setprefix",
			Role = "Owner",
			Description = "Changes the chat command prefix until the server closes.",
			Args = { { Type = "string", Name = "prefix", Description = "One to three characters, e.g. !" } },
			Run = function(context, prefix: string)
				if #prefix < 1 or #prefix > 3 or prefix:find("%s") then
					return "The prefix must be 1 to 3 characters without spaces."
				end

				Admin.Config.Chat = Admin.Config.Chat or { Enabled = true, HideCommands = true }
				Admin.Config.Chat.Enabled = true
				Admin.Config.Chat.Prefix = prefix
				if Admin.DataFolder then
					Admin.DataFolder:SetAttribute("ChatPrefix", prefix)
				end

				Admin.Audit(context, `changed the chat prefix to {prefix}`)
				return `Chat commands now start with {prefix}`
			end,
		},
	}
end

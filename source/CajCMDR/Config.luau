--[[
	CajCMDR - CONFIG
	================
	This is the only file most developers ever need to touch.

	QUICK START
	  1. Put your Roblox community (group) id in the `Groups` table below and map your community's
	     rank ids to the roles you want them to receive (Owner, Admin, Moderator, ...).
	  2. Put your own UserId in `Users` if you want to be staff even when you are not in the community.
	  3. Publish and play. Press F2 (or the ` key) to open the console, or type ;cmds in chat.

	Find a community id:  roblox.com/communities/<THIS NUMBER>/name
	Find a rank id:       Community > Configure > Roles > the "Rank" number next to each role (1-255).
]]

return {
	----------------------------------------------------------------------------------------------------
	-- 1. ROLES
	-- Higher `Level` = more power. Anyone can use commands of their own level and below.
	-- You can rename roles, change levels/colours, add roles or remove roles. Keep one role at Level 0.
	-- Role names are used everywhere else in this file, so spell them exactly the same.
	----------------------------------------------------------------------------------------------------
	Roles = {
		{ Name = "Player", Level = 0, Color = Color3.fromRGB(190, 190, 190) },
		{ Name = "Helper", Level = 25, Color = Color3.fromRGB(110, 220, 140) },
		{ Name = "Moderator", Level = 50, Color = Color3.fromRGB(80, 170, 255) },
		{ Name = "Admin", Level = 75, Color = Color3.fromRGB(255, 170, 60) },
		{ Name = "HeadAdmin", Level = 90, Color = Color3.fromRGB(255, 100, 100) },
		{ Name = "Owner", Level = 100, Color = Color3.fromRGB(255, 215, 0) },
	},

	----------------------------------------------------------------------------------------------------
	-- 2. COMMUNITY (GROUP) BINDINGS   <-- the part you probably came here for
	--
	-- Format:   [communityId] = { [rankId] = "RoleName", ... }
	--
	-- * The key on the left is the rank id (0-255) from your community's role list.
	--   You can also use the exact role *name* in quotes instead:  ["Head Moderator"] = "Moderator"
	-- * With GroupRankMatching = "AtOrAbove" (default) a member whose rank is 150 or higher gets the
	--   role bound to 150 (as long as no higher binding also matches), so you only list the ranks
	--   that matter. Use "Exact" if only that exact rank should receive the role.
	-- * You can bind as many communities as you like. The highest role a player qualifies for wins.
	-- * Entries with community id 0 are ignored, so the example below does nothing until you edit it.
	----------------------------------------------------------------------------------------------------
	Groups = {
		[0] = { -- <-- replace 0 with your community id, e.g. [1234567] = { ... }
			[255] = "Owner",
			[254] = "HeadAdmin",
			[200] = "Admin",
			[150] = "Moderator",
			[100] = "Helper",
		},

		-- A second community, uncomment and edit to use:
		-- [7654321] = {
		-- 	[255] = "Owner",
		-- 	[50] = "Helper",
		-- },
	},
	GroupRankMatching = "AtOrAbove", -- "AtOrAbove" or "Exact"

	----------------------------------------------------------------------------------------------------
	-- 3. OTHER WAYS TO GET A ROLE
	----------------------------------------------------------------------------------------------------

	-- Specific people by UserId. Great for yourself and trusted friends.
	Users = {
		-- [123456789] = "Owner", -- YourUsername
	},

	-- Own a game pass -> get a role. [GamePassId] = "RoleName"
	GamePasses = {
		-- [11111111] = "Helper",
	},

	-- The experience creator (or the owner of the community that owns the experience) gets this role.
	-- Set to nil / false to turn it off.
	GameOwnerRole = "Owner",

	-- Everyone gets this role while testing in Roblox Studio so you can try every command.
	-- Set to nil / false before publishing if you want Studio to behave like a live server.
	StudioRole = "Owner",

	-- How often (in seconds) community ranks are re-checked for players already in the server.
	-- Players can also be refreshed instantly with the `refreshroles` command.
	RoleRefreshSeconds = 300,

	----------------------------------------------------------------------------------------------------
	-- 4. COMMAND PERMISSIONS
	-- Every command has a default role. Override them here: ["commandName"] = "RoleName".
	----------------------------------------------------------------------------------------------------
	CommandRoles = {
		-- kick = "Helper",
		-- fly = "Admin",
	},

	-- Commands that should not exist at all in your game.
	DisabledCommands = {
		"insert", -- loads free models from the catalog; enable only if you really want it
	},

	-- Whole categories you do not want: "Info", "Moderation", "Character", "Fun", "World", "Client",
	-- "Staff", "Utility"
	DisabledCategories = {},

	-- Roles for Cmdr's built-in command groups (help, alias, bind, ...).
	DefaultGroupRoles = {
		DefaultUtil = "Player",
		Help = "Player",
		UserAlias = "Player",
	},

	-- Players cannot use harmful commands on players of an equal or higher role (the top role may target anyone).
	ProtectHigherRanks = true,

	----------------------------------------------------------------------------------------------------
	-- 5. INTERFACE
	----------------------------------------------------------------------------------------------------
	PlaceName = "CajCMDR", -- shown in the console prompt
	ConsoleKeys = { "F2", "Backquote" }, -- Enum.KeyCode names that open the console

	Chat = {
		Enabled = true, -- allow running commands from chat, e.g.  ;kill me
		Prefix = ";",
		HideCommands = true, -- do not show staff command messages in the public chat
	},

	----------------------------------------------------------------------------------------------------
	-- 6. MODERATION
	----------------------------------------------------------------------------------------------------
	Bans = {
		ApplyToUniverse = true, -- ban from every place in the experience
		ExcludeAltAccounts = false, -- true = do not also ban alt accounts
	},

	Warnings = {
		AutoKickAt = 0, -- kick a player automatically when they reach this many warnings (0 = off)
	},

	ReportCooldown = 60, -- seconds between `report` uses per player

	----------------------------------------------------------------------------------------------------
	-- 7. TOOLS
	-- Put Tool objects in ServerStorage > AdminTools and staff can hand them out with `give`.
	----------------------------------------------------------------------------------------------------
	ToolsFolder = "AdminTools",

	----------------------------------------------------------------------------------------------------
	-- 8. LOGGING
	-- Optional webhook. Discord blocks Roblox servers, so use a relay/proxy url that forwards to Discord.
	----------------------------------------------------------------------------------------------------
	Webhook = {
		Enabled = false,
		Url = "",
		MinLevel = 25, -- only commands run by staff of this level or higher are sent
	},
}

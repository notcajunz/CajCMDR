--[[
	CajCMDR bootstrap.
	Builds on the Cmdr command framework: adds roles bound to Roblox communities (groups), a permission layer,
	chat commands, moderation tools and 200+ commands.  Configure everything in the `Config` module.
]]

const HttpService = game:GetService("HttpService")
const Players = game:GetService("Players")
const ReplicatedStorage = game:GetService("ReplicatedStorage")
const ServerScriptService = game:GetService("ServerScriptService")
const ServerStorage = game:GetService("ServerStorage")

const Config = require(script.Config)
const Store = require(script.Core.Store)
const Roles = require(script.Core.Roles)
const Log = require(script.Core.Log)
const Chat = require(script.Core.Chat)
const Admin = require(script.Core.Admin)

const PREFIX = "[CajAdmin]"

----------------------------------------------------------------------------------------------------
-- Find Cmdr
----------------------------------------------------------------------------------------------------

const function findCmdr(): ModuleScript?
	-- The drop-in package ships Cmdr as a child of this script; fall back to an existing install.
	const bundled = script:FindFirstChild("Cmdr")
	if bundled and bundled:IsA("ModuleScript") then
		return bundled
	end

	for _, container in ipairs({ ServerScriptService, ServerStorage }) do
		const found = container:FindFirstChild("Cmdr", true)
		if found and found:IsA("ModuleScript") then
			return found
		end
	end

	return nil
end

const cmdrModule = findCmdr()
if not cmdrModule then
	error(`{PREFIX} Could not find the Cmdr module. Re-insert the CajCMDR package (see README.md).`)
end

----------------------------------------------------------------------------------------------------
-- Roles and shared data
----------------------------------------------------------------------------------------------------

Roles.Init(Config)
Log.Init(Config)

const data = Instance.new("Folder")
data.Name = "CajAdminData"
data:SetAttribute("Roles", Roles.ToJson())
data:SetAttribute("MaxLevel", Roles.MaxLevel)
data:SetAttribute("Protect", Config.ProtectHigherRanks ~= false)
data:SetAttribute("PlaceName", Config.PlaceName or "CajCMDR")
data:SetAttribute("ConsoleKeys", HttpService:JSONEncode(Config.ConsoleKeys or { "F2" }))
data:SetAttribute("ChatPrefix", if Config.Chat and Config.Chat.Enabled then Config.Chat.Prefix or ";" else "")
data:SetAttribute("CommandLevels", "{}")

const groupLevels = {}
for groupName, roleName in pairs(Config.DefaultGroupRoles or {}) do
	const role = Roles.Get(roleName)
	if role then
		groupLevels[groupName] = role.Level
	end
end
data:SetAttribute("GroupLevels", HttpService:JSONEncode(groupLevels))
data.Parent = ReplicatedStorage

----------------------------------------------------------------------------------------------------
-- Cmdr
----------------------------------------------------------------------------------------------------

const Cmdr = require(cmdrModule)

Admin.Init({
	Cmdr = Cmdr,
	Config = Config,
	Roles = Roles,
	Store = Store,
	Log = Log,
	Chat = Chat,
	DataFolder = data,
})

Cmdr.Registry:RegisterDefaultCommands({ "DefaultUtil", "Help" })
Cmdr.Registry:RegisterTypesIn(script.Shared.Types)
Cmdr.Registry:RegisterHooksIn(script.Shared.Hooks)

-- Command logging (server only).
Cmdr.Registry:RegisterHook("AfterRun", function(context: any)
	const spec = Admin.Specs[context.Name:lower()]
	Log.Command({
		Time = os.time(),
		Executor = context.Executor.Name,
		UserId = context.Executor.UserId,
		Level = Roles.GetLevel(context.Executor),
		Text = context.RawText,
		Response = context.Response,
		Command = context.Name,
	})

	if spec and spec.Audit then
		Log.Audit({
			Time = os.time(),
			Executor = context.Executor.Name,
			UserId = context.Executor.UserId,
			Text = context.RawText,
			Response = context.Response,
		})
	end

	return nil
end, 100)

----------------------------------------------------------------------------------------------------
-- Command loading
----------------------------------------------------------------------------------------------------

const stubFolder = Instance.new("Folder")
stubFolder.Name = "Stubs"
stubFolder.Parent = script.Core

const function toSet(list: { string }?): { [string]: boolean }
	const set = {}
	for _, value in ipairs(list or {}) do
		set[value:lower()] = true
	end

	return set
end

const disabledCommands = toSet(Config.DisabledCommands)
const disabledCategories = toSet(Config.DisabledCategories)
const usedNames: { [string]: string } = {}
local commandCount = 0

const function registerSpec(spec: any, category: string)
	assert(type(spec) == "table", "command spec must be a table")
	assert(type(spec.Name) == "string" and spec.Name ~= "", "command spec needs a Name")
	assert(type(spec.Run) == "function", `command "{spec.Name}" needs a Run function`)

	const lowered = spec.Name:lower()
	if disabledCommands[lowered] then
		return
	end

	-- Name / alias collisions
	for _, name in ipairs({ spec.Name, table.unpack(spec.Aliases or {}) }) do
		const key = name:lower()
		if usedNames[key] then
			warn(`{PREFIX} "{name}" ({category}) is already used by "{usedNames[key]}"; skipping the duplicate.`)
			return
		end
	end

	const overrides = Config.CommandRoles or {}
	const roleName = overrides[spec.Name] or overrides[lowered] or spec.Role or "Admin"
	local role = Roles.Get(roleName)
	if not role then
		warn(`{PREFIX} Unknown role "{roleName}" for command "{spec.Name}"; only the top role can use it.`)
		role = Roles.GetRoleForLevel(Roles.MaxLevel)
	end

	usedNames[lowered] = spec.Name
	for _, alias in ipairs(spec.Aliases or {}) do
		usedNames[alias:lower()] = spec.Name
	end

	const definition = {
		Name = spec.Name,
		Aliases = spec.Aliases,
		Description = spec.Description or "No description.",
		Group = category,
		Args = spec.Args or {},
	}

	const stub = script.Core.CommandStub:Clone()
	stub.Name = spec.Name
	stub:SetAttribute("Def", HttpService:JSONEncode(definition))
	stub.Parent = stubFolder

	Cmdr.Registry:RegisterCommand(stub)

	const registered = Cmdr.Registry:GetCommand(spec.Name)
	if not registered then
		warn(`{PREFIX} Cmdr refused to register "{spec.Name}".`)
		stub:Destroy()
		return
	end

	registered.Run = spec.Run

	Admin.Specs[lowered] = { Name = spec.Name, Role = role.Name, Level = role.Level, Category = category, Audit = spec.Audit == true }
	Admin.CommandLevels[lowered] = role.Level
	commandCount += 1
end

local categoryCount = 0
for _, moduleScript in ipairs(script.Commands:GetChildren()) do
	if not moduleScript:IsA("ModuleScript") or disabledCategories[moduleScript.Name:lower()] then
		continue
	end

	const loaded, factory = pcall(require, moduleScript)
	if not loaded then
		warn(`{PREFIX} Failed to load command file {moduleScript.Name}: {factory}`)
		continue
	end

	const built, specs = pcall(factory, Admin)
	if not built then
		warn(`{PREFIX} Failed to build commands from {moduleScript.Name}: {specs}`)
		continue
	end

	categoryCount += 1
	for _, spec in ipairs(specs) do
		const registered, err = pcall(registerSpec, spec, moduleScript.Name)
		if not registered then
			warn(`{PREFIX} Skipped a command in {moduleScript.Name}: {err}`)
		end
	end
end

Admin.PublishCommandLevels()

----------------------------------------------------------------------------------------------------
-- Join gating: server bans and server lock
----------------------------------------------------------------------------------------------------

const function gate(player: Player)
	const banReason = Admin.ServerBans[player.UserId]
	if banReason then
		player:Kick(`You are banned from this server. Reason: {banReason}`)
		return
	end

	if Admin.ServerLock.Level > 0 and Roles.GetLevel(player) < Admin.ServerLock.Level then
		player:Kick(Admin.ServerLock.Reason ~= "" and Admin.ServerLock.Reason or "This server is locked.")
	end
end

Players.PlayerAdded:Connect(gate)
Roles.Resolved.Event:Connect(gate)

----------------------------------------------------------------------------------------------------
-- Start everything
----------------------------------------------------------------------------------------------------

-- The client script lives inside this package; hand a copy to every player (no StarterPlayerScripts setup needed).
const clientTemplate = script:FindFirstChild("Client")

const function giveClient(player: Player)
	if not clientTemplate then
		return
	end

	task.spawn(function()
		const gui = player:WaitForChild("PlayerGui", 30)
		if not gui or gui:FindFirstChild("CajAdminClient") then
			return
		end

		const client = clientTemplate:Clone()
		client.Name = "CajAdminClient"
		client.Parent = gui
	end)
end

Players.PlayerAdded:Connect(giveClient)
for _, player in ipairs(Players:GetPlayers()) do
	giveClient(player)
end

Roles.Start()
Admin.Start()
Chat.Start({ Cmdr = Cmdr, Config = Config, Roles = Roles, Admin = Admin, Log = Log })

print(`{PREFIX} Ready: {commandCount} commands in {categoryCount} categories. Press F2 to open the console.`)

--[[
	Turns Config bindings (communities, users, game passes, ...) into a role for every player.

	The result is stored on the Player as attributes so the client can read it too:
		CajRole  - role name
		CajLevel - role level (number)
]]

const GroupService = game:GetService("GroupService")
const HttpService = game:GetService("HttpService")
const MarketplaceService = game:GetService("MarketplaceService")
const Players = game:GetService("Players")
const RunService = game:GetService("RunService")

const Store = require(script.Parent.Store)

const GROUP_CACHE_SECONDS = 20
const OWNER_RANK = 255

type RoleDefinition = { Name: string, Level: number, Color: Color3 }

const Roles = {
	MaxLevel = 0,
	Resolved = Instance.new("BindableEvent"), -- (player, role) first time a player's role is known
	Changed = Instance.new("BindableEvent"), -- (player, role) whenever a player's role level changes
}

local config: any = nil
local roleList: { RoleDefinition } = {} -- ascending by level
const rolesByName: { [string]: RoleDefinition } = {} -- lower-case name
const tempRoles: { [number]: string } = {} -- UserId -> role name (this server only)
const savedRoleCache: { [number]: any } = {} -- role name, or false when the user has no saved role
const sources: { [Player]: string } = {}
const resolvedOnce: { [Player]: boolean } = {}
const groupCache: { [number]: { Time: number, Groups: { [number]: { Rank: number, Role: string } } } } = {}

const function warnOnce(message: string)
	warn(`[CajAdmin] Config: {message}`)
end

function Roles.Init(cfg: any)
	config = cfg

	table.clear(rolesByName)
	roleList = {}

	for _, definition in ipairs(cfg.Roles or {}) do
		if type(definition.Name) == "string" and type(definition.Level) == "number" then
			const lowered = definition.Name:lower()
			if rolesByName[lowered] then
				warnOnce(`role "{definition.Name}" is defined twice.`)
			else
				const role: RoleDefinition = {
					Name = definition.Name,
					Level = definition.Level,
					Color = definition.Color or Color3.fromRGB(200, 200, 200),
				}
				rolesByName[lowered] = role
				table.insert(roleList, role)
			end
		end
	end

	table.sort(roleList, function(a, b)
		return a.Level < b.Level
	end)

	if #roleList == 0 or roleList[1].Level > 0 then
		warnOnce('there is no Level 0 role, adding a default "Player" role.')
		const fallback: RoleDefinition = { Name = "Player", Level = 0, Color = Color3.fromRGB(190, 190, 190) }
		rolesByName["player"] = rolesByName["player"] or fallback
		table.insert(roleList, 1, fallback)
	end

	Roles.MaxLevel = roleList[#roleList].Level

	-- Check that every role name used in the config actually exists.
	const function check(name: any, where: string)
		if name and not rolesByName[tostring(name):lower()] then
			warnOnce(`unknown role "{tostring(name)}" in {where}.`)
		end
	end

	for groupId, bindings in pairs(cfg.Groups or {}) do
		for rank, roleName in pairs(bindings) do
			check(roleName, `Groups[{groupId}][{tostring(rank)}]`)
		end
	end
	for userId, roleName in pairs(cfg.Users or {}) do
		check(roleName, `Users[{userId}]`)
	end
	for passId, roleName in pairs(cfg.GamePasses or {}) do
		check(roleName, `GamePasses[{passId}]`)
	end
	check(cfg.GameOwnerRole, "GameOwnerRole")
	check(cfg.StudioRole, "StudioRole")
	for commandName, roleName in pairs(cfg.CommandRoles or {}) do
		check(roleName, `CommandRoles.{commandName}`)
	end
end

----------------------------------------------------------------------------------------------------
-- Lookups
----------------------------------------------------------------------------------------------------

function Roles.List(): { RoleDefinition }
	return roleList
end

function Roles.Get(name: string?): RoleDefinition?
	if not name then
		return nil
	end

	return rolesByName[tostring(name):lower()]
end

function Roles.GetBaseRole(): RoleDefinition
	return roleList[1]
end

--[[ Lowest role whose level is at least `level` (used for error messages). ]]
function Roles.GetRoleForLevel(level: number): RoleDefinition
	for _, role in ipairs(roleList) do
		if role.Level >= level then
			return role
		end
	end

	return roleList[#roleList]
end

function Roles.GetLevel(player: Player): number
	return player:GetAttribute("CajLevel") or 0
end

function Roles.GetRole(player: Player): RoleDefinition
	return Roles.Get(player:GetAttribute("CajRole")) or roleList[1]
end

function Roles.GetSource(player: Player): string
	return sources[player] or "Unknown"
end

function Roles.IsStaff(player: Player): boolean
	return Roles.GetLevel(player) > 0
end

function Roles.ToJson(): string
	const list = {}
	for _, role in ipairs(roleList) do
		table.insert(list, {
			Name = role.Name,
			Level = role.Level,
			Color = { math.floor(role.Color.R * 255 + 0.5), math.floor(role.Color.G * 255 + 0.5), math.floor(role.Color.B * 255 + 0.5) },
		})
	end

	return HttpService:JSONEncode(list)
end

----------------------------------------------------------------------------------------------------
-- Binding evaluation
----------------------------------------------------------------------------------------------------

const function fetchGroups(userId: number, player: Player?): { [number]: { Rank: number, Role: string } }
	const cached = groupCache[userId]
	if cached and os.clock() - cached.Time < GROUP_CACHE_SECONDS then
		return cached.Groups
	end

	const result = {}
	const ok, groups = pcall(GroupService.GetGroupsAsync, GroupService, userId)
	if ok and type(groups) == "table" then
		for _, group in ipairs(groups) do
			result[group.Id] = { Rank = group.Rank, Role = group.Role }
		end
	elseif player then
		-- Fallback: ask about each configured community one by one.
		for groupId in pairs(config.Groups or {}) do
			if type(groupId) == "number" and groupId > 0 then
				const okRank, rank = pcall(player.GetRankInGroup, player, groupId)
				if okRank and rank > 0 then
					const okRole, roleName = pcall(player.GetRoleInGroup, player, groupId)
					result[groupId] = { Rank = rank, Role = if okRole then roleName else "" }
				end
			end
		end
	end

	groupCache[userId] = { Time = os.clock(), Groups = result }
	return result
end

const function loadSavedRole(userId: number): string?
	if savedRoleCache[userId] == nil then
		const stored = Store.Get("Roles", tostring(userId), false)
		savedRoleCache[userId] = if type(stored) == "string" then stored else false
	end

	const value = savedRoleCache[userId]
	if value == false then
		return nil
	end

	return value
end

--[[
	Works out the role for any UserId (online or not).
	Returns the role and a human readable description of where it came from.
]]
function Roles.Compute(userId: number, player: Player?): (RoleDefinition, string)
	local best: RoleDefinition = roleList[1]
	local source = "Default"

	const function consider(roleName: any, description: string)
		const role = Roles.Get(roleName)
		if role and role.Level > best.Level then
			best = role
			source = description
		end
	end

	if RunService:IsStudio() and config.StudioRole then
		consider(config.StudioRole, "Roblox Studio")
	end

	consider((config.Users or {})[userId], "Users list")

	if game.CreatorId ~= 0 and game.CreatorType == Enum.CreatorType.User and game.CreatorId == userId then
		consider(config.GameOwnerRole, "Experience creator")
	end

	if player and next(config.GamePasses or {}) ~= nil then
		for passId, roleName in pairs(config.GamePasses) do
			const ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, userId, passId)
			if ok and owns then
				consider(roleName, `Game pass {passId}`)
			end
		end
	end

	const memberships = fetchGroups(userId, player)

	if game.CreatorId ~= 0 and game.CreatorType == Enum.CreatorType.Group then
		const membership = memberships[game.CreatorId]
		if membership and membership.Rank == OWNER_RANK then
			consider(config.GameOwnerRole, "Experience community owner")
		end
	end

	const atOrAbove = config.GroupRankMatching ~= "Exact"
	for groupId, bindings in pairs(config.Groups or {}) do
		const membership = if type(groupId) == "number" and groupId > 0 then memberships[groupId] else nil
		if not membership then
			continue
		end

		for key, roleName in pairs(bindings) do
			local matches = false
			if type(key) == "number" then
				matches = if atOrAbove then membership.Rank >= key else membership.Rank == key
			elseif type(key) == "string" then
				matches = membership.Role:lower() == key:lower()
			end

			if matches then
				consider(roleName, `Community {groupId} ({membership.Role}, rank {membership.Rank})`)
			end
		end
	end

	consider(tempRoles[userId], "Temporary role (setrole)")
	consider(loadSavedRole(userId), "Saved role (saverole)")

	return best, source
end

function Roles.GetLevelForUserId(userId: number): number
	const online = Players:GetPlayerByUserId(userId)
	if online then
		return Roles.GetLevel(online)
	end

	const role = Roles.Compute(userId, nil)
	return role.Level
end

--[[ Recomputes a player's role and updates their attributes. Yields. ]]
function Roles.Resolve(player: Player)
	const role, source = Roles.Compute(player.UserId, player)
	if not player.Parent then
		return
	end

	sources[player] = source

	const previousLevel = player:GetAttribute("CajLevel")
	player:SetAttribute("CajRole", role.Name)
	player:SetAttribute("CajLevel", role.Level)

	if not resolvedOnce[player] then
		resolvedOnce[player] = true
		Roles.Resolved:Fire(player, role)
	end

	if previousLevel ~= role.Level then
		Roles.Changed:Fire(player, role)
	end
end

function Roles.IsResolved(player: Player): boolean
	return resolvedOnce[player] == true
end

----------------------------------------------------------------------------------------------------
-- Overrides made by commands
----------------------------------------------------------------------------------------------------

--[[ Gives a role for the rest of this server's lifetime. Pass nil to remove it. ]]
function Roles.SetTemp(userId: number, roleName: string?)
	tempRoles[userId] = roleName

	const player = Players:GetPlayerByUserId(userId)
	if player then
		task.spawn(Roles.Resolve, player)
	end
end

--[[ Gives a role that is saved to the DataStore. Pass nil to remove it. ]]
function Roles.SetSaved(userId: number, roleName: string?): boolean
	const ok = if roleName then Store.Set("Roles", tostring(userId), roleName) else Store.Remove("Roles", tostring(userId))
	savedRoleCache[userId] = if roleName then roleName else false

	const player = Players:GetPlayerByUserId(userId)
	if player then
		task.spawn(Roles.Resolve, player)
	end

	return ok
end

function Roles.Clear(userId: number)
	tempRoles[userId] = nil
	Roles.SetSaved(userId, nil)
end

----------------------------------------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------------------------------------

function Roles.Start()
	const function track(player: Player)
		task.spawn(Roles.Resolve, player)
	end

	Players.PlayerAdded:Connect(track)
	for _, player in ipairs(Players:GetPlayers()) do
		track(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		sources[player] = nil
		resolvedOnce[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(math.max(30, config.RoleRefreshSeconds or 300))
			for _, player in ipairs(Players:GetPlayers()) do
				task.spawn(Roles.Resolve, player)
			end
		end
	end)
end

return Roles

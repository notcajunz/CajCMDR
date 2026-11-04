--[[
	Rank-aware player selectors.

	"target" / "targets" work like Cmdr's "player" / "players" (me, all, others, random, %Team) but
	automatically leave out players who have an equal or higher role than the person running the command,
	and add an @Role selector:   ;kill @Moderator    ;bring %Red,Bob    ;kick all

	This module runs on both the server and the client (Cmdr replicates it), so it only reads attributes.
]]

const Players = game:GetService("Players")
const HttpService = game:GetService("HttpService")
const ReplicatedStorage = game:GetService("ReplicatedStorage")
const Teams = game:GetService("Teams")

return function(registry: any)
	const Util = registry.Cmdr.Util
	const data = ReplicatedStorage:WaitForChild("CajAdminData")

	const function levelOf(player: Player): number
		return player:GetAttribute("CajLevel") or 0
	end

	const function canTarget(executor: Player, target: Player): boolean
		if executor == target then
			return true
		end

		if data:GetAttribute("Protect") ~= true then
			return true
		end

		const executorLevel = levelOf(executor)
		if executorLevel >= (data:GetAttribute("MaxLevel") or 100) then
			return true
		end

		return executorLevel > levelOf(target)
	end

	const function filterTargets(executor: Player, players: { Player }): { Player }
		const result = {}
		for _, player in ipairs(players) do
			if canTarget(executor, player) then
				table.insert(result, player)
			end
		end

		return result
	end

	const function getRoles(): { { Name: string, Level: number } }
		const raw = data:GetAttribute("Roles")
		if typeof(raw) ~= "string" then
			return {}
		end

		const ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
		return if ok and type(decoded) == "table" then decoded else {}
	end

	const targetType = {
		Transform = function(text: string, executor: Player): { Player }
			const find = Util.MakeFuzzyFinder(Players:GetPlayers())
			return filterTargets(executor, find(text))
		end,

		Validate = function(players: { Player }): (boolean, string?)
			return #players > 0, "No player with that name could be found (or their rank is too high to target)."
		end,

		Autocomplete = function(players: { Player }): { string }
			return Util.GetNames(players)
		end,

		Parse = function(players: { Player }): Player?
			return players[1]
		end,

		Default = function(player: Player): string
			return player.Name
		end,

		ArgumentOperatorAliases = {
			me = ".",
			all = "*",
			others = "**",
			random = "?",
		},
	}

	-- %TeamName
	const teamTargetsType = {
		Listable = true,

		Transform = function(text: string, executor: Player): ({ Team }, Player)
			return Util.MakeFuzzyFinder(Teams:GetTeams())(text), executor
		end,

		Validate = function(teams: { Team }): (boolean, string?)
			return #teams > 0, "No team with that name could be found."
		end,

		Autocomplete = function(teams: { Team }): { string }
			return Util.GetNames(teams)
		end,

		Parse = function(teams: { Team }, executor: Player): { Player }
			return filterTargets(executor, teams[1]:GetPlayers())
		end,
	}

	-- @RoleName
	const roleTargetsType = {
		Listable = true,

		Transform = function(text: string, executor: Player): ({ any }, Player)
			return Util.MakeFuzzyFinder(getRoles())(text), executor
		end,

		Validate = function(roles: { any }): (boolean, string?)
			return #roles > 0, "No role with that name could be found."
		end,

		Autocomplete = function(roles: { any }): { string }
			return Util.GetNames(roles)
		end,

		Parse = function(roles: { any }, executor: Player): { Player }
			const result = {}
			for _, player in ipairs(Players:GetPlayers()) do
				if player:GetAttribute("CajRole") == roles[1].Name and canTarget(executor, player) then
					table.insert(result, player)
				end
			end

			return result
		end,
	}

	registry:RegisterType("target", targetType)
	registry:RegisterType("targets", Util.MakeListableType(targetType, { Prefixes = "% teamTargets @ roleTargets" }))
	registry:RegisterType("teamTargets", teamTargetsType)
	registry:RegisterType("roleTargets", roleTargetsType)
end

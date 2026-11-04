--[[
	Extra argument types used by CajCMDR commands:
		role      - one of the roles from Config.Roles (returns the role name)
		material  - an Enum.Material
		emote     - a built-in R15 emote name
		positiveNumber - a number greater than 0
]]

const HttpService = game:GetService("HttpService")
const ReplicatedStorage = game:GetService("ReplicatedStorage")

const EMOTES = { "wave", "point", "dance", "dance2", "dance3", "laugh", "cheer" }

return function(registry: any)
	const Util = registry.Cmdr.Util
	const data = ReplicatedStorage:WaitForChild("CajAdminData")

	const function getRoles(): { { Name: string, Level: number } }
		const raw = data:GetAttribute("Roles")
		if typeof(raw) ~= "string" then
			return {}
		end

		const ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
		return if ok and type(decoded) == "table" then decoded else {}
	end

	const roleType = {
		Transform = function(text: string): { any }
			return Util.MakeFuzzyFinder(getRoles())(text)
		end,

		Validate = function(roles: { any }): (boolean, string?)
			return #roles > 0, "No role with that name could be found."
		end,

		Autocomplete = function(roles: { any }): { string }
			return Util.GetNames(roles)
		end,

		Parse = function(roles: { any }): string
			return roles[1].Name
		end,
	}

	const positiveNumberType = {
		Transform = function(text: string): number?
			return tonumber(text)
		end,

		Validate = function(value: number?): (boolean, string?)
			return value ~= nil and value > 0, "The number must be greater than 0."
		end,

		Parse = function(value: number): number
			return value
		end,
	}

	registry:RegisterType("role", roleType)
	registry:RegisterType("material", Util.MakeEnumType("Material", Enum.Material))
	registry:RegisterType("emote", Util.MakeEnumType("Emote", EMOTES))
	registry:RegisterType("positiveNumber", positiveNumberType)
end

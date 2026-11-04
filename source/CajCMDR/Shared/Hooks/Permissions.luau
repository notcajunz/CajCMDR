--[[
	Role based permissions for every command.

	Runs on the server (the real enforcement) and on the client (instant feedback + hides commands the
	player cannot use from autocomplete and `help`).  The data it reads is published by the server in
	ReplicatedStorage.CajAdminData and on each Player as the CajLevel / CajRole attributes.
]]

const HttpService = game:GetService("HttpService")
const ReplicatedStorage = game:GetService("ReplicatedStorage")
const RunService = game:GetService("RunService")

const DISABLED = -1

return function(registry: any)
	const data = ReplicatedStorage:WaitForChild("CajAdminData")

	local commandLevels: { [string]: number } = {}
	local groupLevels: { [string]: number } = {}
	local roles: { { Name: string, Level: number } } = {}

	const function decode(attribute: string): any
		const raw = data:GetAttribute(attribute)
		if typeof(raw) ~= "string" then
			return {}
		end

		const ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
		return if ok and type(decoded) == "table" then decoded else {}
	end

	const function refresh()
		commandLevels = decode("CommandLevels")
		groupLevels = decode("GroupLevels")
		roles = decode("Roles")
	end

	refresh()
	data:GetAttributeChangedSignal("CommandLevels"):Connect(function()
		refresh()
		if RunService:IsClient() then
			-- Commands may have been enabled/disabled or re-ranked: re-evaluate what the player can see.
			task.defer(function()
				registry.Cmdr.Dispatcher:RunBeforeCommandRegisterHooks()
			end)
		end
	end)
	data:GetAttributeChangedSignal("Roles"):Connect(refresh)
	data:GetAttributeChangedSignal("GroupLevels"):Connect(refresh)

	const function requiredLevel(context: any): number
		const own = commandLevels[context.Name:lower()]
		if own ~= nil then
			return own
		end

		const group = groupLevels[context.Group or ""]
		if group ~= nil then
			return group
		end

		-- Unknown command from an unknown source: only the highest role may run it.
		return data:GetAttribute("MaxLevel") or 100
	end

	const function roleNameForLevel(level: number): string
		for _, role in ipairs(roles) do
			if role.Level >= level then
				return role.Name
			end
		end

		return "a higher role"
	end

	registry:RegisterHook("BeforeRun", function(context: any): string?
		const needed = requiredLevel(context)
		if needed == DISABLED then
			return `The "{context.Name}" command is disabled.`
		end

		const level = context.Executor:GetAttribute("CajLevel") or 0
		if level < needed then
			return `You need the {roleNameForLevel(needed)} role or higher to use "{context.Name}".`
		end

		return nil
	end, -100)

	if RunService:IsClient() then
		registry:RegisterHook("BeforeCommandRegister", function(context: any): boolean?
			const needed = requiredLevel(context)
			if needed == DISABLED then
				return false
			end

			const level = context.Executor:GetAttribute("CajLevel") or 0
			if level < needed then
				return false
			end

			return nil
		end)
	end
end

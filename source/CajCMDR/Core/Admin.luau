--[[
	Helper API shared by every command module.  Command files receive this table as their only argument:

		return function(Admin)
			return {
				{ Name = "example", Role = "Moderator", Description = "...", Args = { ... }, Run = function(context, ...) end },
			}
		end
]]

const HttpService = game:GetService("HttpService")
const MessagingService = game:GetService("MessagingService")
const Players = game:GetService("Players")
const ServerStorage = game:GetService("ServerStorage")

const GLOBAL_TOPIC = "CajAdminGlobal"

const Admin = {
	Version = "1.0.0",

	Colors = {
		Header = Color3.fromRGB(230, 126, 34),
		Good = Color3.fromRGB(120, 220, 130),
		Warn = Color3.fromRGB(255, 228, 26),
		Bad = Color3.fromRGB(255, 110, 110),
		Dim = Color3.fromRGB(170, 170, 170),
	},

	-- Filled in by Admin.Init
	Cmdr = nil :: any,
	Config = nil :: any,
	Roles = nil :: any,
	Store = nil :: any,
	Log = nil :: any,
	Chat = nil :: any,
	Specs = {} :: { [string]: any }, -- lower-case command name -> { Name, Role, Category, Audit }
	CommandLevels = {} :: { [string]: number }, -- lower-case command name -> level required (-1 = disabled)
	DataFolder = nil :: Folder?, -- ReplicatedStorage.CajAdminData

	-- Server-wide state shared by several commands
	StartTime = os.time(),
	ServerLock = { Level = 0, Reason = "" },
	ServerBans = {} :: { [number]: string }, -- UserId -> reason (this server only)
}

local objectsFolder: Folder? = nil
const states: { [Player]: { [string]: (Player, Model, Humanoid) -> () } } = {}
const globalHandlers: { [string]: (any, string) -> () } = {}
const cooldowns: { [string]: number } = {}
const nameCache: { [number]: string } = {}

function Admin.Init(env: any)
	Admin.Cmdr = env.Cmdr
	Admin.Config = env.Config
	Admin.Roles = env.Roles
	Admin.Store = env.Store
	Admin.Log = env.Log
	Admin.Chat = env.Chat
	Admin.DataFolder = env.DataFolder
end

--[[ Pushes Admin.CommandLevels to the clients and the permission hooks. Call after changing it. ]]
function Admin.PublishCommandLevels()
	if Admin.DataFolder then
		Admin.DataFolder:SetAttribute("CommandLevels", HttpService:JSONEncode(Admin.CommandLevels))
	end
end

----------------------------------------------------------------------------------------------------
-- Messaging the client
----------------------------------------------------------------------------------------------------

--[[ kind: "info" | "success" | "warn" | "error" ]]
function Admin.Notify(player: Player, text: string, kind: string?)
	Admin.Cmdr.Dispatcher:SendEvent(player, "CajNotify", tostring(text), kind or "info")
end

function Admin.NotifyAll(text: string, kind: string?)
	Admin.Cmdr.Dispatcher:BroadcastEvent("CajNotify", tostring(text), kind or "info")
end

function Admin.NotifyStaff(text: string, kind: string?, minLevel: number?)
	for _, player in ipairs(Players:GetPlayers()) do
		if Admin.Roles.GetLevel(player) >= (minLevel or 1) then
			Admin.Notify(player, text, kind)
		end
	end
end

function Admin.Announce(title: string, text: string, duration: number?)
	Admin.Cmdr.Dispatcher:BroadcastEvent("CajAnnounce", title, text, duration or 8)
end

--[[ Runs a client-side effect (fly, noclip, fov, ...) on one player. See CajAdminClient/Effects. ]]
function Admin.Fx(player: Player, effect: string, ...: any)
	Admin.Cmdr.Dispatcher:SendEvent(player, "CajFx", effect, ...)
end

function Admin.FxAll(effect: string, ...: any)
	Admin.Cmdr.Dispatcher:BroadcastEvent("CajFx", effect, ...)
end

function Admin.Reply(context: any, text: string, color: Color3?)
	context:Reply(text, color)
end

--[[ Prints a titled list to the executor's console and returns "" so the command shows no extra line. ]]
function Admin.Output(context: any, title: string, lines: { string }, maxLines: number?): string
	context:Reply(title, Admin.Colors.Header)

	const limit = maxLines or 80
	for index, line in ipairs(lines) do
		if index > limit then
			context:Reply(`... and {#lines - limit} more`, Admin.Colors.Dim)
			break
		end

		context:Reply(line)
	end

	if #lines == 0 then
		context:Reply("(nothing to show)", Admin.Colors.Dim)
	end

	return ""
end

----------------------------------------------------------------------------------------------------
-- Formatting
----------------------------------------------------------------------------------------------------

function Admin.FormatDuration(seconds: number): string
	if seconds == math.huge then
		return "forever"
	end

	seconds = math.floor(seconds)
	if seconds < 1 then
		return "0s"
	end

	const parts = {}
	for _, unit in ipairs({ { "d", 86400 }, { "h", 3600 }, { "m", 60 }, { "s", 1 } }) do
		const count = math.floor(seconds / unit[2])
		if count > 0 then
			table.insert(parts, `{count}{unit[1]}`)
			seconds -= count * unit[2]
		end
	end

	return table.concat(parts, " ")
end

function Admin.Plural(count: number, word: string): string
	return `{count} {word}{if count == 1 then "" else "s"}`
end

function Admin.Result(verb: string, count: number): string
	if count == 0 then
		return "No players were affected."
	end

	return `{verb} {Admin.Plural(count, "player")}.`
end

function Admin.Names(players: { Player }, limit: number?): string
	const names = {}
	const max = limit or 5
	for index, player in ipairs(players) do
		if index > max then
			table.insert(names, `+{#players - max} more`)
			break
		end

		table.insert(names, player.Name)
	end

	return table.concat(names, ", ")
end

function Admin.Timestamp(unixTime: number): string
	return os.date("!%Y-%m-%d %H:%M UTC", unixTime) :: string
end

function Admin.Truncate(text: string, length: number): string
	if #text <= length then
		return text
	end

	return `{text:sub(1, length - 3)}...`
end

--[[ Returns false (and the seconds left) when `key` was used less than `seconds` ago. ]]
function Admin.Cooldown(key: string, seconds: number): (boolean, number)
	const now = os.clock()
	const last = cooldowns[key]
	if last and now - last < seconds then
		return false, seconds - (now - last)
	end

	cooldowns[key] = now
	return true, 0
end

function Admin.NameFromUserId(userId: number): string
	const online = Players:GetPlayerByUserId(userId)
	if online then
		return online.Name
	end

	if nameCache[userId] then
		return nameCache[userId]
	end

	const ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	if ok then
		nameCache[userId] = name
		return name
	end

	return `User{userId}`
end

----------------------------------------------------------------------------------------------------
-- Characters
----------------------------------------------------------------------------------------------------

function Admin.GetHumanoid(player: Player): Humanoid?
	const character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

function Admin.GetRoot(player: Player): BasePart?
	const character = player.Character
	return character and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart) :: BasePart?
end

--[[
	Calls fn(player, character, humanoid, root) for every player that currently has a living-capable character.
	Errors inside fn are caught. Returns how many players were handled (fn can return false to not count one).
]]
function Admin.Each(players: { Player }, fn: (Player, Model, Humanoid, BasePart) -> any?): number
	local count = 0

	for _, player in ipairs(players) do
		const character = player.Character
		const humanoid = character and character:FindFirstChildOfClass("Humanoid")
		const root = character and character:FindFirstChild("HumanoidRootPart")

		if humanoid and root then
			const ok, result = pcall(fn, player, character, humanoid, root)
			if not ok then
				warn(`[CajAdmin] Command error for {player.Name}: {result}`)
			elseif result ~= false then
				count += 1
			end
		end
	end

	return count
end

--[[ Same as Each but for commands that do not need a character. ]]
function Admin.EachPlayer(players: { Player }, fn: (Player) -> any?): number
	local count = 0

	for _, player in ipairs(players) do
		const ok, result = pcall(fn, player)
		if not ok then
			warn(`[CajAdmin] Command error for {player.Name}: {result}`)
		elseif result ~= false then
			count += 1
		end
	end

	return count
end

function Admin.Teleport(character: Model, cframe: CFrame)
	const humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Sit then
		humanoid.Sit = false

		const deadline = os.clock() + 1
		while humanoid.SeatPart and os.clock() < deadline do
			task.wait()
		end
	end

	if character:IsDescendantOf(workspace) then
		character:PivotTo(cframe)
	end
end

--[[ Adds (replacing any old copy) an effect instance named `name` to a body part of the character. ]]
function Admin.AddEffect(character: Model, className: string, name: string, properties: { [string]: any }?, partName: string?): Instance?
	const parent = character:FindFirstChild(partName or "HumanoidRootPart")
	if not parent then
		return nil
	end

	const existing = parent:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end

	const instance = Instance.new(className)
	instance.Name = name
	for key, value in pairs(properties or {}) do
		(instance :: any)[key] = value
	end
	instance.Parent = parent

	return instance
end

--[[ Removes every descendant of the character with this name. Returns how many were removed. ]]
function Admin.RemoveEffect(character: Model, name: string): number
	local count = 0
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant.Name == name then
			descendant:Destroy()
			count += 1
		end
	end

	return count
end

--[[ Sets the transparency of the whole avatar. Pass nil to restore the original look. ]]
function Admin.SetTransparency(character: Model, value: number?)
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant.Name == "HumanoidRootPart" then
			continue
		end

		if descendant:IsA("BasePart") or descendant:IsA("Decal") then
			if value == nil then
				const original = descendant:GetAttribute("CajOrigT")
				if original ~= nil then
					descendant.Transparency = original
					descendant:SetAttribute("CajOrigT", nil)
				end
			else
				if descendant:GetAttribute("CajOrigT") == nil then
					descendant:SetAttribute("CajOrigT", descendant.Transparency)
				end
				descendant.Transparency = value
			end
		end
	end
end

--[[ Resizes an R15 avatar. 1 = normal. Returns false for R6 avatars. ]]
function Admin.SetScale(humanoid: Humanoid, height: number?, width: number?, head: number?): boolean
	const heightValue = humanoid:FindFirstChild("BodyHeightScale")
	if not heightValue then
		return false
	end

	const function set(name: string, value: number?)
		const object = humanoid:FindFirstChild(name)
		if object and value and object:IsA("NumberValue") then
			object.Value = math.clamp(value, 0.1, 12)
		end
	end

	set("BodyHeightScale", height)
	set("BodyWidthScale", width)
	set("BodyDepthScale", width)
	set("HeadScale", head)

	return true
end

----------------------------------------------------------------------------------------------------
-- Effects that should survive respawning (god mode, speed, ...)
----------------------------------------------------------------------------------------------------

function Admin.SetState(player: Player, key: string, apply: (Player, Model, Humanoid) -> ())
	if not states[player] then
		states[player] = {}
	end
	states[player][key] = apply

	const character = player.Character
	const humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if character and humanoid then
		pcall(apply, player, character, humanoid)
	end
end

function Admin.ClearState(player: Player, key: string)
	if states[player] then
		states[player][key] = nil
	end
end

function Admin.ClearStates(player: Player)
	states[player] = nil
end

const function onCharacterAdded(player: Player, character: Model)
	const humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then
		return
	end

	character:WaitForChild("HumanoidRootPart", 10)
	task.wait()

	const applied = states[player]
	if not applied then
		return
	end

	for _, apply in pairs(applied) do
		pcall(apply, player, character, humanoid)
	end
end

----------------------------------------------------------------------------------------------------
-- Tools
----------------------------------------------------------------------------------------------------

function Admin.GetToolsFolder(): Instance?
	return ServerStorage:FindFirstChild(Admin.Config.ToolsFolder or "AdminTools")
end

function Admin.ListTools(): { Tool }
	const folder = Admin.GetToolsFolder()
	const tools = {}
	if folder then
		for _, child in ipairs(folder:GetChildren()) do
			if child:IsA("Tool") then
				table.insert(tools, child)
			end
		end
	end

	return tools
end

function Admin.FindTool(name: string): Tool?
	const lowered = name:lower()
	local partial: Tool? = nil

	for _, tool in ipairs(Admin.ListTools()) do
		if tool.Name:lower() == lowered then
			return tool
		elseif not partial and tool.Name:lower():find(lowered, 1, true) then
			partial = tool
		end
	end

	return partial
end

----------------------------------------------------------------------------------------------------
-- World objects created by commands (cages, clones, ...)
----------------------------------------------------------------------------------------------------

function Admin.GetObjectsFolder(): Folder
	if not objectsFolder or not objectsFolder.Parent then
		const folder = Instance.new("Folder")
		folder.Name = "CajAdminObjects"
		folder.Parent = workspace
		objectsFolder = folder
	end

	return objectsFolder :: Folder
end

----------------------------------------------------------------------------------------------------
-- Running other commands / logging
----------------------------------------------------------------------------------------------------

function Admin.Run(commandText: string, executor: Player): string
	return Admin.Cmdr.Dispatcher:EvaluateAndRun(commandText, executor)
end

--[[ Records a moderation action in the persistent audit log (viewable with `auditlog`). ]]
function Admin.Audit(context: any, details: string)
	Admin.Log.Audit({
		Time = os.time(),
		Executor = context.Executor.Name,
		UserId = context.Executor.UserId,
		Text = context.RawText,
		Response = details,
	})

	Admin.NotifyStaff(`{context.Executor.Name}: {details}`, "info", Admin.Roles.Get("Moderator") and Admin.Roles.Get("Moderator").Level or 1)
end

--[[ True when `executor` is allowed to act on an offline/online user id. Yields. ]]
function Admin.CanAffectUserId(executor: Player, userId: number): boolean
	if executor.UserId == userId then
		return true
	end

	if Admin.Config.ProtectHigherRanks == false then
		return true
	end

	const executorLevel = Admin.Roles.GetLevel(executor)
	if executorLevel >= Admin.Roles.MaxLevel then
		return true
	end

	return executorLevel > Admin.Roles.GetLevelForUserId(userId)
end

----------------------------------------------------------------------------------------------------
-- Cross-server messaging
----------------------------------------------------------------------------------------------------

function Admin.OnGlobal(kind: string, handler: (any, string) -> ())
	globalHandlers[kind] = handler
end

--[[ Returns ok, errorMessage. Handlers also run on the sending server (delivered through MessagingService). ]]
function Admin.PublishGlobal(kind: string, data: any): (boolean, string?)
	const ok, err = pcall(function()
		MessagingService:PublishAsync(GLOBAL_TOPIC, HttpService:JSONEncode({ Kind = kind, Data = data, JobId = game.JobId }))
	end)

	return ok, if ok then nil else tostring(err)
end

--[[ Runs the handler directly on this server (used when MessagingService is unavailable, e.g. in Studio). ]]
function Admin.RunGlobalLocally(kind: string, data: any)
	const handler = globalHandlers[kind]
	if handler then
		handler(data, game.JobId)
	end
end

function Admin.Start()
	const function track(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
	end

	Players.PlayerAdded:Connect(track)
	for _, player in ipairs(Players:GetPlayers()) do
		track(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)

	task.spawn(function()
		pcall(function()
			MessagingService:SubscribeAsync(GLOBAL_TOPIC, function(message)
				const ok, payload = pcall(HttpService.JSONDecode, HttpService, message.Data)
				if not ok or type(payload) ~= "table" then
					return
				end

				const handler = globalHandlers[payload.Kind]
				if handler then
					handler(payload.Data, payload.JobId)
				end
			end)
		end)
	end)
end

return Admin

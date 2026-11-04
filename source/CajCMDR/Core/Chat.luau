--[[
	Chat integration:
	  * runs commands typed in chat (";kill me")
	  * enforces mutes, chat lock and slow mode
	  * keeps the chat log used by the `chatlogs` command

	With TextChatService, TextChannel.ShouldDeliverCallback is called once per recipient, so every decision
	is cached by MessageId and only evaluated for the first recipient.
]]

const Players = game:GetService("Players")
const TextChatService = game:GetService("TextChatService")

const MAX_CACHED_DECISIONS = 400

const Chat = {
	Muted = {} :: { [number]: { Until: number, Reason: string } },
	LockLevel = 0, -- players below this level cannot chat
	SlowSeconds = 0,
}

local env: any = nil
const decisions: { [string]: boolean } = {}
const decisionOrder: { string } = {}
const lastMessageTime: { [number]: number } = {}

----------------------------------------------------------------------------------------------------
-- Mute helpers
----------------------------------------------------------------------------------------------------

function Chat.Mute(userId: number, duration: number?, reason: string?)
	Chat.Muted[userId] = {
		Until = if duration and duration > 0 then os.time() + duration else math.huge,
		Reason = reason or "No reason given",
	}
end

function Chat.Unmute(userId: number): boolean
	const wasMuted = Chat.Muted[userId] ~= nil
	Chat.Muted[userId] = nil
	return wasMuted
end

--[[ Returns isMuted, reason, secondsRemaining (math.huge when permanent). ]]
function Chat.IsMuted(userId: number): (boolean, string?, number)
	const entry = Chat.Muted[userId]
	if not entry then
		return false, nil, 0
	end

	if entry.Until ~= math.huge and os.time() >= entry.Until then
		Chat.Muted[userId] = nil
		return false, nil, 0
	end

	return true, entry.Reason, entry.Until - os.time()
end

----------------------------------------------------------------------------------------------------
-- Chat commands
----------------------------------------------------------------------------------------------------

const function runChatCommand(player: Player, commandLine: string)
	if env.Roles.GetLevel(player) <= 0 then
		return
	end

	for _, part in ipairs(commandLine:split(" && ")) do
		const trimmed = part:match("^%s*(.-)%s*$")
		if trimmed and trimmed ~= "" then
			const response = env.Cmdr.Dispatcher:EvaluateAndRun(trimmed, player)
			if response and response ~= "" and response ~= "Command executed." then
				env.Admin.Notify(player, response, "info")
			end
		end
	end
end

const function tryChatCommand(player: Player, text: string): boolean
	const chatConfig = env.Config.Chat
	if not (chatConfig and chatConfig.Enabled) then
		return false
	end

	const prefix = chatConfig.Prefix or ";"
	if text:sub(1, #prefix) ~= prefix or #text == #prefix then
		return false
	end

	if env.Roles.GetLevel(player) <= 0 then
		return false
	end

	task.spawn(runChatCommand, player, text:sub(#prefix + 1))
	return true
end

----------------------------------------------------------------------------------------------------
-- Delivery callback (TextChatService)
----------------------------------------------------------------------------------------------------

const function evaluate(message: TextChatMessage, source: TextSource): boolean
	const player = Players:GetPlayerByUserId(source.UserId)
	if not player then
		return true
	end

	const level = env.Roles.GetLevel(player)

	env.Log.Chat({ Time = os.time(), Player = player.Name, UserId = player.UserId, Text = message.Text })

	-- Staff commands: run them and keep them out of public chat.
	if tryChatCommand(player, message.Text) then
		return not (env.Config.Chat and env.Config.Chat.HideCommands)
	end

	const muted, reason, remaining = Chat.IsMuted(player.UserId)
	if muted then
		const when = if remaining == math.huge then "permanently" else `for {env.Admin.FormatDuration(remaining)}`
		env.Admin.Notify(player, `You are muted {when}. Reason: {reason}`, "warn")
		return false
	end

	if Chat.LockLevel > 0 and level < Chat.LockLevel then
		env.Admin.Notify(player, "Chat is locked right now.", "warn")
		return false
	end

	if Chat.SlowSeconds > 0 and level <= 0 then
		const now = os.clock()
		const last = lastMessageTime[player.UserId]
		if last and now - last < Chat.SlowSeconds then
			env.Admin.Notify(player, `Slow mode is on. Wait {math.ceil(Chat.SlowSeconds - (now - last))}s.`, "warn")
			return false
		end

		lastMessageTime[player.UserId] = now
	end

	return true
end

const function shouldDeliver(message: TextChatMessage, _recipient: TextSource): boolean
	const source = message.TextSource
	if not source then
		return true
	end

	const id = message.MessageId
	const cached = decisions[id]
	if cached ~= nil then
		return cached
	end

	const ok, result = pcall(evaluate, message, source)
	const decision = if ok then result else true
	if not ok then
		warn(`[CajAdmin] Chat handler error: {result}`)
	end

	decisions[id] = decision
	table.insert(decisionOrder, id)
	if #decisionOrder > MAX_CACHED_DECISIONS then
		decisions[table.remove(decisionOrder, 1) :: string] = nil
	end

	return decision
end

const function hookChannel(channel: Instance)
	if channel:IsA("TextChannel") then
		channel.ShouldDeliverCallback = shouldDeliver
	end
end

----------------------------------------------------------------------------------------------------
-- Legacy chat (Player.Chatted)
----------------------------------------------------------------------------------------------------

const function hookLegacyPlayer(player: Player)
	player.Chatted:Connect(function(text)
		env.Log.Chat({ Time = os.time(), Player = player.Name, UserId = player.UserId, Text = text })
		tryChatCommand(player, text)
	end)
end

function Chat.Start(environment: any)
	env = environment

	if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
		task.spawn(function()
			const channels = TextChatService:WaitForChild("TextChannels", 15)
			if not channels then
				warn("[CajAdmin] TextChatService has no TextChannels; chat commands, mutes and slow mode are disabled.")
				return
			end

			for _, channel in ipairs(channels:GetChildren()) do
				hookChannel(channel)
			end
			channels.ChildAdded:Connect(hookChannel)
		end)
	else
		Players.PlayerAdded:Connect(hookLegacyPlayer)
		for _, player in ipairs(Players:GetPlayers()) do
			hookLegacyPlayer(player)
		end

		warn("[CajAdmin] Legacy chat detected: mutes and slow mode cannot be enforced. Switch the experience to TextChatService.")
	end
end

return Chat

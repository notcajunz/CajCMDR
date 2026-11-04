--[[
	Command log (memory), chat log (memory), audit log (DataStore) and the optional webhook.
]]

const HttpService = game:GetService("HttpService")

const Store = require(script.Parent.Store)

const MAX_COMMANDS = 300
const MAX_CHAT = 200
const MAX_AUDIT = 100
const AUDIT_FLUSH_SECONDS = 30
const WEBHOOK_INTERVAL = 1.2

const Log = {}

local config: any = nil
const commands: { any } = {}
const chat: { any } = {}
const auditQueue: { any } = {}
const webhookQueue: { string } = {}
local webhookRunning = false

const function push(list: { any }, entry: any, max: number)
	table.insert(list, entry)
	if #list > max then
		table.remove(list, 1)
	end
end

function Log.Init(cfg: any)
	config = cfg

	task.spawn(function()
		while true do
			task.wait(AUDIT_FLUSH_SECONDS)
			Log.Flush()
		end
	end)

	game:BindToClose(function()
		Log.Flush()
	end)
end

----------------------------------------------------------------------------------------------------
-- Webhook
----------------------------------------------------------------------------------------------------

const function runWebhookQueue()
	if webhookRunning then
		return
	end

	webhookRunning = true
	task.spawn(function()
		while #webhookQueue > 0 do
			const content = table.remove(webhookQueue, 1) :: string
			const ok, err = pcall(function()
				HttpService:PostAsync(
					config.Webhook.Url,
					HttpService:JSONEncode({ username = "CajCMDR", content = content:sub(1, 1900) }),
					Enum.HttpContentType.ApplicationJson
				)
			end)

			if not ok then
				warn(`[CajAdmin] Webhook failed: {err}`)
			end

			task.wait(WEBHOOK_INTERVAL)
		end

		webhookRunning = false
	end)
end

function Log.Webhook(content: string)
	if not (config.Webhook and config.Webhook.Enabled and config.Webhook.Url ~= "") then
		return
	end

	if #webhookQueue > 50 then
		return
	end

	table.insert(webhookQueue, content)
	runWebhookQueue()
end

----------------------------------------------------------------------------------------------------
-- Commands
----------------------------------------------------------------------------------------------------

function Log.Command(entry: { Time: number, Executor: string, UserId: number, Level: number, Text: string, Response: string?, Command: string })
	push(commands, entry, MAX_COMMANDS)

	if config.Webhook and config.Webhook.Enabled and entry.Level >= (config.Webhook.MinLevel or 0) then
		Log.Webhook(`**{entry.Executor}** ran: {entry.Text}\n{entry.Response or ""}`)
	end
end

function Log.GetCommands(count: number?): { any }
	const result = {}
	const total = #commands
	for index = math.max(1, total - (count or 25) + 1), total do
		table.insert(result, commands[index])
	end

	return result
end

function Log.ClearCommands()
	table.clear(commands)
end

----------------------------------------------------------------------------------------------------
-- Chat
----------------------------------------------------------------------------------------------------

function Log.Chat(entry: { Time: number, Player: string, UserId: number, Text: string })
	push(chat, entry, MAX_CHAT)
end

function Log.GetChat(count: number?): { any }
	const result = {}
	const total = #chat
	for index = math.max(1, total - (count or 25) + 1), total do
		table.insert(result, chat[index])
	end

	return result
end

----------------------------------------------------------------------------------------------------
-- Audit (persistent)
----------------------------------------------------------------------------------------------------

function Log.Audit(entry: { Time: number, Executor: string, UserId: number, Text: string, Response: string? })
	table.insert(auditQueue, entry)
end

function Log.Flush()
	if #auditQueue == 0 then
		return
	end

	const batch = table.clone(auditQueue)
	table.clear(auditQueue)

	Store.Update("Audit", "recent", function(old)
		const list = if type(old) == "table" then old else {}
		for _, entry in ipairs(batch) do
			table.insert(list, entry)
		end

		while #list > MAX_AUDIT do
			table.remove(list, 1)
		end

		return list
	end)
end

function Log.GetAudit(): { any }
	Log.Flush()
	return Store.Get("Audit", "recent", {})
end

return Log

--[[
	CajCMDR client. The server copies this script into every player's PlayerGui, so you never have to place it
	yourself. It starts the Cmdr console, applies your key bindings and shows messages from the server.
]]

const HttpService = game:GetService("HttpService")
const Players = game:GetService("Players")
const ReplicatedStorage = game:GetService("ReplicatedStorage")

const player = Players.LocalPlayer

const data = ReplicatedStorage:WaitForChild("CajAdminData")
const Cmdr = require(ReplicatedStorage:WaitForChild("CmdrClient"))

const Notifications = require(script.Notifications)
const Effects = require(script.Effects)

-- Console look and keys, from the Config on the server.
Cmdr:SetPlaceName(data:GetAttribute("PlaceName") or "CajCMDR")

const keys = {}
const okKeys, keyNames = pcall(HttpService.JSONDecode, HttpService, data:GetAttribute("ConsoleKeys") or "[]")
if okKeys and type(keyNames) == "table" then
	for _, name in ipairs(keyNames) do
		const okCode, code = pcall(function()
			return Enum.KeyCode[name]
		end)
		if okCode and code then
			table.insert(keys, code)
		end
	end
end
Cmdr:SetActivationKeys(if #keys > 0 then keys else { Enum.KeyCode.F2 })

-- Messages and effects sent by the server.
Cmdr:HandleEvent("CajNotify", Notifications.Notify)
Cmdr:HandleEvent("CajAnnounce", Notifications.Announce)
Cmdr:HandleEvent("CajFx", Effects.Run)

-- Command output normally goes to the console. When it is closed (for example after a chat command),
-- show it in a small panel instead so nothing is lost.
Cmdr:HandleEvent("AddLine", function(text: any, options: any)
	const window = Cmdr._interface.Window
	if window:IsVisible() then
		window:AddLine(text, options)
	elseif tostring(text) ~= "" then
		Notifications.Output(tostring(text))
	end
end)

-- Show only the commands this player's role may use, and refresh when the role changes.
const function refreshCommands()
	Cmdr.Dispatcher:RunBeforeCommandRegisterHooks()
end

player:GetAttributeChangedSignal("CajLevel"):Connect(refreshCommands)
task.delay(2, refreshCommands)

if player:GetAttribute("CajRole") and player:GetAttribute("CajRole") ~= "Player" then
	Notifications.Notify(`Welcome, {player:GetAttribute("CajRole")}! Press {(keys[1] or Enum.KeyCode.F2).Name} to open the console.`, "success")
end

player:GetAttributeChangedSignal("CajRole"):Connect(function()
	const role = player:GetAttribute("CajRole")
	if role and role ~= "Player" then
		Notifications.Notify(`You are now {role}. Press {(keys[1] or Enum.KeyCode.F2).Name} to open the console.`, "success")
	end
end)

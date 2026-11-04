--[[
	On-screen messages: toasts, announcement banner, output panel and countdown.
	Everything is built in code so there is nothing to set up in Studio.
]]

const Players = game:GetService("Players")
const TweenService = game:GetService("TweenService")

const COLORS = {
	info = Color3.fromRGB(80, 170, 255),
	success = Color3.fromRGB(110, 220, 140),
	warn = Color3.fromRGB(255, 200, 60),
	error = Color3.fromRGB(255, 100, 100),
}

const BACKGROUND = Color3.fromRGB(24, 26, 32)
const TEXT = Color3.fromRGB(235, 235, 240)
const MAX_TOASTS = 6

const Notifications = {}

local gui: ScreenGui? = nil
local toastHolder: Frame? = nil
local outputPanel: Frame? = nil
local outputScroll: ScrollingFrame? = nil
local outputBuffer: { string } = {}
local outputToken = 0
local countdownToken = 0
local announceBusy = false
const announceQueue: { { string | number } } = {}

const function getGui(): ScreenGui
	if gui and gui.Parent then
		return gui
	end

	const screen = Instance.new("ScreenGui")
	screen.Name = "CajAdminUI"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 100
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	gui = screen
	return screen
end

const function round(parent: Instance, radius: number)
	const corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

const function label(parent: Instance, text: string, size: number, color: Color3, font: Enum.Font?): TextLabel
	const textLabel = Instance.new("TextLabel")
	textLabel.BackgroundTransparency = 1
	textLabel.Text = text
	textLabel.TextSize = size
	textLabel.TextColor3 = color
	textLabel.Font = font or Enum.Font.GothamMedium
	textLabel.TextWrapped = true
	textLabel.TextXAlignment = Enum.TextXAlignment.Left
	textLabel.Parent = parent
	return textLabel
end

----------------------------------------------------------------------------------------------------
-- Toasts
----------------------------------------------------------------------------------------------------

const function getToastHolder(): Frame
	if toastHolder and toastHolder.Parent then
		return toastHolder
	end

	const holder = Instance.new("Frame")
	holder.Name = "Toasts"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(1, 0)
	holder.Position = UDim2.new(1, -16, 0, 56)
	holder.Size = UDim2.fromOffset(340, 400)
	holder.Parent = getGui()

	const layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.Parent = holder

	toastHolder = holder
	return holder
end

function Notifications.Notify(text: string, kind: string?)
	const holder = getToastHolder()

	-- Drop the oldest toast when there are too many.
	const existing = {}
	for _, child in ipairs(holder:GetChildren()) do
		if child:IsA("Frame") then
			table.insert(existing, child)
		end
	end
	if #existing >= MAX_TOASTS then
		existing[1]:Destroy()
	end

	const accent = COLORS[kind or "info"] or COLORS.info

	const toast = Instance.new("Frame")
	toast.BackgroundColor3 = BACKGROUND
	toast.BackgroundTransparency = 0.08
	toast.Size = UDim2.new(1, 0, 0, 0)
	toast.AutomaticSize = Enum.AutomaticSize.Y
	toast.LayoutOrder = math.floor(os.clock() * 1000)
	toast.Parent = holder
	round(toast, 8)

	const bar = Instance.new("Frame")
	bar.BackgroundColor3 = accent
	bar.BorderSizePixel = 0
	bar.Size = UDim2.new(0, 4, 1, 0)
	bar.Parent = toast
	round(bar, 4)

	const padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 16)
	padding.PaddingRight = UDim.new(0, 12)
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.Parent = toast

	const content = label(toast, text, 15, TEXT)
	content.Size = UDim2.new(1, 0, 0, 0)
	content.AutomaticSize = Enum.AutomaticSize.Y

	task.delay(math.clamp(3 + #text / 20, 3, 10), function()
		if toast.Parent then
			TweenService:Create(toast, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
			TweenService:Create(content, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
			TweenService:Create(bar, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
			task.wait(0.35)
			toast:Destroy()
		end
	end)
end

----------------------------------------------------------------------------------------------------
-- Announcement banner
----------------------------------------------------------------------------------------------------

const function showNextAnnouncement()
	if announceBusy then
		return
	end

	const nextItem = table.remove(announceQueue, 1)
	if not nextItem then
		return
	end

	announceBusy = true
	const title, text, duration = nextItem[1] :: string, nextItem[2] :: string, nextItem[3] :: number

	const banner = Instance.new("Frame")
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, -140)
	banner.Size = UDim2.new(0.6, 0, 0, 0)
	banner.AutomaticSize = Enum.AutomaticSize.Y
	banner.BackgroundColor3 = BACKGROUND
	banner.BackgroundTransparency = 0.05
	banner.Parent = getGui()
	round(banner, 12)

	const constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(720, 1000)
	constraint.MinSize = Vector2.new(260, 0)
	constraint.Parent = banner

	const stroke = Instance.new("UIStroke")
	stroke.Color = COLORS.warn
	stroke.Thickness = 2
	stroke.Parent = banner

	const padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 18)
	padding.PaddingRight = UDim.new(0, 18)
	padding.PaddingTop = UDim.new(0, 12)
	padding.PaddingBottom = UDim.new(0, 14)
	padding.Parent = banner

	const layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = banner

	const titleLabel = label(banner, title, 14, COLORS.warn, Enum.Font.GothamBold)
	titleLabel.Size = UDim2.new(1, 0, 0, 18)
	titleLabel.LayoutOrder = 1

	const body = label(banner, text, 22, TEXT, Enum.Font.GothamBold)
	body.Size = UDim2.new(1, 0, 0, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.LayoutOrder = 2

	TweenService:Create(banner, TweenInfo.new(0.4, Enum.EasingStyle.Back), { Position = UDim2.new(0.5, 0, 0, 24) }):Play()

	task.delay(duration, function()
		TweenService:Create(banner, TweenInfo.new(0.35), { Position = UDim2.new(0.5, 0, 0, -160) }):Play()
		task.wait(0.4)
		banner:Destroy()
		announceBusy = false
		showNextAnnouncement()
	end)
end

function Notifications.Announce(title: string, text: string, duration: number?)
	table.insert(announceQueue, { title, text, duration or 8 })
	showNextAnnouncement()
end

----------------------------------------------------------------------------------------------------
-- Output panel (command output when the console is closed, e.g. after a chat command)
----------------------------------------------------------------------------------------------------

const function getOutputPanel(): (Frame, ScrollingFrame)
	if outputPanel and outputPanel.Parent and outputScroll then
		return outputPanel, outputScroll
	end

	const panel = Instance.new("Frame")
	panel.Name = "Output"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(520, 340)
	panel.BackgroundColor3 = BACKGROUND
	panel.BackgroundTransparency = 0.05
	panel.Visible = false
	panel.Parent = getGui()
	round(panel, 10)

	const header = label(panel, "Output", 15, COLORS.warn, Enum.Font.GothamBold)
	header.Position = UDim2.fromOffset(14, 8)
	header.Size = UDim2.new(1, -60, 0, 22)

	const close = Instance.new("TextButton")
	close.Text = "X"
	close.Font = Enum.Font.GothamBold
	close.TextSize = 16
	close.TextColor3 = TEXT
	close.BackgroundColor3 = Color3.fromRGB(60, 62, 72)
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -8, 0, 6)
	close.Size = UDim2.fromOffset(28, 26)
	close.Parent = panel
	round(close, 6)
	close.Activated:Connect(function()
		panel.Visible = false
	end)

	const scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(14, 38)
	scroll.Size = UDim2.new(1, -28, 1, -50)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.ScrollBarThickness = 5
	scroll.Parent = panel

	const layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll

	outputPanel = panel
	outputScroll = scroll
	return panel, scroll
end

--[[ Collects lines for a moment, then shows them together in one panel. ]]
function Notifications.Output(text: string)
	table.insert(outputBuffer, text)
	outputToken += 1
	const token = outputToken

	task.delay(0.25, function()
		if token ~= outputToken then
			return
		end

		const panel, scroll = getOutputPanel()
		scroll:ClearAllChildren()
		const layout = Instance.new("UIListLayout")
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = scroll

		for index, line in ipairs(outputBuffer) do
			const row = label(scroll, line, 14, TEXT, Enum.Font.Code)
			row.Size = UDim2.new(1, -8, 0, 0)
			row.AutomaticSize = Enum.AutomaticSize.Y
			row.LayoutOrder = index
		end

		table.clear(outputBuffer)
		panel.Visible = true

		task.delay(25, function()
			if token == outputToken then
				panel.Visible = false
			end
		end)
	end)
end

----------------------------------------------------------------------------------------------------
-- Countdown
----------------------------------------------------------------------------------------------------

function Notifications.Countdown(seconds: number, caption: string?)
	countdownToken += 1
	const token = countdownToken

	const old = getGui():FindFirstChild("Countdown")
	if old then
		old:Destroy()
	end

	const frame = Instance.new("Frame")
	frame.Name = "Countdown"
	frame.BackgroundTransparency = 1
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0.12, 0)
	frame.Size = UDim2.fromOffset(400, 150)
	frame.Parent = getGui()

	const number = label(frame, tostring(seconds), 96, TEXT, Enum.Font.GothamBlack)
	number.TextXAlignment = Enum.TextXAlignment.Center
	number.Size = UDim2.new(1, 0, 0, 100)
	number.TextStrokeTransparency = 0.4

	const sub = label(frame, caption or "", 24, COLORS.warn, Enum.Font.GothamBold)
	sub.TextXAlignment = Enum.TextXAlignment.Center
	sub.Position = UDim2.fromOffset(0, 100)
	sub.Size = UDim2.new(1, 0, 0, 36)

	task.spawn(function()
		for remaining = seconds, 1, -1 do
			if token ~= countdownToken or not frame.Parent then
				return
			end

			number.Text = tostring(remaining)
			task.wait(1)
		end

		if token == countdownToken and frame.Parent then
			number.Text = "0"
			task.wait(1)
			frame:Destroy()
		end
	end)
end

return Notifications

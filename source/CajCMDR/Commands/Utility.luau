--[[
	Utility: teleporting between servers/places and saved positions.
]]

const TeleportService = game:GetService("TeleportService")

return function(Admin)
	const savedPositions: { [Player]: CFrame } = {}

	game:GetService("Players").PlayerRemoving:Connect(function(player)
		savedPositions[player] = nil
	end)

	const function teleportPlayers(players: { Player }, placeId: number, options: TeleportOptions?): string
		local list = {}
		for _, player in ipairs(players) do
			table.insert(list, player)
		end

		if #list == 0 then
			return "Nobody to teleport."
		end

		const ok, err = pcall(TeleportService.TeleportAsync, TeleportService, placeId, list, options)
		if not ok then
			return `Teleport failed: {err}`
		end

		return `Teleporting {Admin.Plural(#list, "player")}...`
	end

	return {
		{
			Name = "rejoin",
			Role = "Moderator",
			Description = "Sends players back into this same server (fixes stuck characters).",
			Args = { { Type = "players", Name = "players", Description = "The players." } },
			Run = function(_, players: { Player })
				const options = Instance.new("TeleportOptions")
				options.ServerInstanceId = game.JobId
				return teleportPlayers(players, game.PlaceId, options)
			end,
		},
		{
			Name = "serverhop",
			Aliases = { "newserver" },
			Role = "Moderator",
			Description = "Sends players to another server of this place.",
			Args = { { Type = "targets", Name = "players", Description = "The players." } },
			Run = function(_, players: { Player })
				return teleportPlayers(players, game.PlaceId, nil)
			end,
		},
		{
			Name = "place",
			Aliases = { "gotoplace" },
			Role = "Admin",
			Description = "Teleports players to another place of this experience.",
			Args = {
				{ Type = "targets", Name = "players", Description = "The players." },
				{ Type = "positiveInteger", Name = "placeId", Description = "The destination place id." },
			},
			Run = function(context, players: { Player }, placeId: number)
				Admin.Audit(context, `sent {Admin.Names(players)} to place {placeId}`)
				return teleportPlayers(players, placeId, nil)
			end,
		},
		{
			Name = "savepos",
			Aliases = { "setpos" },
			Role = "Helper",
			Description = "Remembers where you are standing.",
			Args = {},
			Run = function(context)
				const root = Admin.GetRoot(context.Executor)
				if not root then
					return "You need a character."
				end

				savedPositions[context.Executor] = root.CFrame
				return "Position saved. Use loadpos to return."
			end,
		},
		{
			Name = "loadpos",
			Aliases = { "backpos" },
			Role = "Helper",
			Description = "Teleports you back to the position saved with savepos.",
			Args = {},
			Run = function(context)
				const spot = savedPositions[context.Executor]
				const character = context.Executor.Character
				if not spot then
					return "You have not saved a position yet."
				end

				if not character then
					return "You need a character."
				end

				Admin.Teleport(character, spot)
				return "Teleported to your saved position."
			end,
		},
	}
end

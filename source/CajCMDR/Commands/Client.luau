--[[
	Client: commands that change what a player's own screen or controls do (fly, noclip, camera, vision tools).
	The server only sends the request; the effects themselves live in the Client > Effects module.
]]

return function(Admin)
	const function targetFx(
		name: string,
		aliases: { string }?,
		role: string,
		description: string,
		extraArgs: { any }?,
		effect: string,
		verb: string,
		protected: boolean
	)
		const args = { { Type = if protected then "targets" else "players", Name = "players", Description = "The players." } }
		for _, argument in ipairs(extraArgs or {}) do
			table.insert(args, argument)
		end

		return {
			Name = name,
			Aliases = aliases,
			Role = role,
			Description = description,
			Args = args,
			Run = function(_, players: { Player }, ...)
				const extra = table.pack(...)
				return Admin.Result(
					verb,
					Admin.EachPlayer(players, function(player)
						Admin.Fx(player, effect, table.unpack(extra, 1, extra.n))
					end)
				)
			end,
		}
	end

	--[[ A command that only affects the person who ran it (vision tools for staff). ]]
	const function selfFx(name: string, aliases: { string }?, role: string, description: string, effect: string, message: string)
		return {
			Name = name,
			Aliases = aliases,
			Role = role,
			Description = description,
			Args = {},
			Run = function(context)
				Admin.Fx(context.Executor, effect)
				return message
			end,
		}
	end

	return {
		targetFx("fly", nil, "Moderator", "Lets players fly (WASD + Space/Shift).", {
			{ Type = "positiveNumber", Name = "speed", Description = "Default 60.", Optional = true },
		}, "fly", "Gave flight to", true),
		targetFx("unfly", nil, "Moderator", "Takes flight away.", nil, "unfly", "Grounded", false),
		targetFx("noclip", nil, "Moderator", "Lets players walk through walls.", nil, "noclip", "Enabled noclip for", true),
		targetFx("clip", { "unnoclip" }, "Moderator", "Turns noclip off.", nil, "clip", "Disabled noclip for", false),
		targetFx("infjump", { "infinitejump" }, "Moderator", "Lets players jump in mid-air forever.", nil, "infjump", "Enabled infinite jump for", true),
		targetFx("uninfjump", { "noinfjump" }, "Moderator", "Turns infinite jump off.", nil, "uninfjump", "Disabled infinite jump for", false),
		targetFx("fov", { "fieldofview" }, "Moderator", "Changes the camera field of view (70 is normal).", {
			{ Type = "number", Name = "degrees", Description = "1 to 120." },
		}, "fov", "Changed the view of", true),
		targetFx("firstperson", { "lockfirst" }, "Moderator", "Forces first-person view.", nil, "firstperson", "Locked first person for", true),
		targetFx("thirdperson", { "unlockfirst" }, "Moderator", "Returns the normal camera.", nil, "thirdperson", "Unlocked the camera of", false),
		targetFx("zoom", { "maxzoom" }, "Moderator", "Sets how far players can zoom out.", {
			{ Type = "positiveNumber", Name = "distance", Description = "Studs (default 128)." },
		}, "zoom", "Changed the zoom of", true),
		targetFx("blind", nil, "Moderator", "Blacks out players' screens.", nil, "blind", "Blinded", true),
		targetFx("unblind", nil, "Moderator", "Restores players' vision.", nil, "unblind", "Restored the vision of", false),
		targetFx("flash", nil, "Moderator", "Flashes players' screens white.", nil, "flash", "Flashed", true),
		targetFx("shake", { "earthquake" }, "Moderator", "Shakes players' cameras.", {
			{ Type = "positiveNumber", Name = "seconds", Description = "Default 3.", Optional = true },
			{ Type = "positiveNumber", Name = "intensity", Description = "Default 1.", Optional = true },
		}, "shake", "Shook the camera of", true),
		targetFx("blur", nil, "Moderator", "Blurs players' screens.", {
			{ Type = "positiveNumber", Name = "size", Description = "1 to 56 (default 20).", Optional = true },
		}, "blur", "Blurred", true),
		targetFx("unblur", nil, "Moderator", "Removes the blur.", nil, "unblur", "Unblurred", false),
		targetFx("hidegui", nil, "Moderator", "Hides players' game interface.", nil, "hidegui", "Hid the interface of", true),
		targetFx("showgui", nil, "Moderator", "Shows players' game interface again.", nil, "showgui", "Showed the interface of", false),
		{
			Name = "view",
			Aliases = { "spectate", "watch" },
			Role = "Helper",
			Description = "Watch the game through another player's camera.",
			Args = { { Type = "player", Name = "player", Description = "The player to watch." } },
			Run = function(context, player: Player)
				Admin.Fx(context.Executor, "view", player.UserId)
				return `Viewing {player.Name}. Use unview to stop.`
			end,
		},
		selfFx("unview", { "unspectate" }, "Helper", "Stops watching another player.", "unview", "Back to your own camera."),
		selfFx("fullbright", { "fb" }, "Helper", "Makes the whole world bright for you only.", "fullbright", "Fullbright on."),
		selfFx("unfullbright", { "unfb" }, "Helper", "Turns fullbright off.", "unfullbright", "Fullbright off."),
		selfFx("xray", nil, "Helper", "See through walls (for you only).", "xray", "X-ray on."),
		selfFx("unxray", nil, "Helper", "Turns x-ray off.", "unxray", "X-ray off."),
		selfFx("esp", { "wallhack" }, "Helper", "Highlights every player through walls (for you only).", "esp", "ESP on."),
		selfFx("unesp", nil, "Helper", "Turns ESP off.", "unesp", "ESP off."),
		targetFx("resetclient", { "resetfx" }, "Moderator", "Turns off every client effect (fly, noclip, blur, ...).", nil, "reset", "Reset the screen of", false),
	}
end

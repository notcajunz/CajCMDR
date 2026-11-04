# CajCMDR

A drop-in admin system for Roblox built on the [Cmdr](https://github.com/evaera/Cmdr) command framework:
**200+ commands**, roles bound to your Roblox **communities (groups)**, chat commands, a console, and nothing to
wire up by hand.

## Install (60 seconds)

1. Open your game in Roblox Studio.
2. Drag **`CajCMDR.rbxmx`** into the Studio window (or right-click **ServerScriptService → Insert from File...**).
3. Make sure the **`CajCMDR`** script sits directly inside **ServerScriptService**.
4. Open **CajCMDR → Config** and put in your community id and rank ids (see below).
5. In **Game Settings → Security** turn on **Allow API Services** (needed for bans and saved data).
6. Play. Press **F2** (or the **`** key) for the console, or type `;cmds` in chat.

That's it: no client script to place, no remotes to create, Cmdr is already bundled inside the package.
While testing in Studio everyone is **Owner** so you can try every command (turn that off with `StudioRole = nil`).

## Binding communities (groups) and ranks to roles

Everything is in the `Config` module:

```lua
Groups = {
	[1234567] = {            -- your community id
		[255] = "Owner",       -- rank id -> role
		[254] = "HeadAdmin",
		[200] = "Admin",
		[150] = "Moderator",
		[100] = "Helper",
	},
},
GroupRankMatching = "AtOrAbove", -- rank 160 counts as Moderator. Use "Exact" to match only the listed ranks.
```

* Community id: `roblox.com/communities/`**`1234567`**`/name`
* Rank id: the 1-255 number next to each role in **Community → Configure → Roles**.
* You can also use the role's exact name instead of its number: `["Head Moderator"] = "Moderator"`.
* Bind as many communities as you like, the highest role a player qualifies for wins.
* Other ways to get a role: `Users` (by UserId), `GamePasses`, and automatically the experience owner (`GameOwnerRole`).
* The roles themselves (names, levels, colors) are the `Roles` table at the top of the Config. Add or rename freely.

## Using it

| How | Example |
| --- | --- |
| Console (F2) | `kick Bob spamming` |
| Chat | `;kick Bob spamming` &nbsp; (several: `;speed me 50 && fly me`) |
| Targets | `me` `all` `others` `random` `Bob,Alice` `%TeamName` `@Moderator` |
| Durations | `30m` `2h` `7d` `1d12h` |

Type `help` for the commands **your role** can use, `help kick` for details, `perms kick` to see which role a command
needs. Players with an equal or higher role than you are automatically left out of harmful commands.

## What's inside

| Category | Examples |
| --- | --- |
| **Moderation** | kick, ban, tempban, unban, baninfo, serverban, warn, warnings, mute, lockchat, slowmode, jail, punish, slock, shutdown, gkick, report, notes |
| **Character** | kill, heal, god, ff, speed, jumppower, freeze, ragdoll, size, char, color, material, invisible, hat, give, team, bring, goto, tp, swap |
| **Fun** | fire, smoke, sparkles, trail, explode, nuke, lightning, meteor, fireworks, fling, rocket, spin, rainbow, neon, gold, ice, giant, dance, clone |
| **World** | announce, gannounce (all servers), hint, countdown, settime, day, night, timelapse, fog, gravity, music, volume, loopkill, loop, delay, roll |
| **Client** | fly, noclip, infjump, fov, view (spectate), blind, shake, blur, fullbright, xray, esp, hidegui |
| **Info** | whoami, roles, admins, whois, serverinfo, ping, position, logs, chatlogs, auditlog, userid, perms |
| **Staff** | setrole, saverole, removerole, refreshroles, staffchat, setcmdrole, disablecmd, setprefix |
| **Utility** | rejoin, serverhop, place, savepos, loadpos |

Cmdr's own utility commands (`help`, `alias`, `bind`, `run`, `var`, ...) are included too.

### Handy config options

* `CommandRoles = { kick = "Helper" }` change who may use a command.
* `DisabledCommands` / `DisabledCategories` remove commands entirely (`insert` is disabled by default).
* `Chat = { Prefix = ";" }` change or disable chat commands.
* `Bans`, `Warnings.AutoKickAt`, `ToolsFolder`, `Webhook` (logging to Discord via a relay URL).
* Tools for `give`: put Tool objects in **ServerStorage → AdminTools**.

## Adding your own commands

Open any file in **CajCMDR → Commands** (or add a new ModuleScript there). Each file returns a list of commands:

```lua
return function(Admin)
	return {
		{
			Name = "hello",
			Role = "Helper",                      -- minimum role
			Description = "Greets a player.",
			Args = {
				{ Type = "players", Name = "players", Description = "Who to greet." },
			},
			Run = function(context, players)
				for _, player in ipairs(players) do
					Admin.Notify(player, "Hello from " .. context.Executor.Name)
				end
				return "Greeted " .. #players .. " players."
			end,
		},
	}
end
```

Use the `targets` argument type for anything harmful (it respects role protection) and `players` for harmless things.
`Admin` offers helpers such as `Admin.Each`, `Admin.Notify`, `Admin.Announce`, `Admin.Fx` and `Admin.Audit`.

## Notes

* Bans use Roblox's `Players:BanAsync`, so they cover every server and alt accounts. In Studio they fall back to a
  server-only ban, because BanAsync is unavailable there.
* Chat commands, mutes and slow mode need the default `TextChatService` chat.
* The console and Cmdr itself need a Studio version that supports the newest Luau syntax (Cmdr 1.13+ uses `const`).

## Rebuilding the package (developers only)

`CajCMDR.rbxmx` is generated from `source/CajCMDR` plus the `Cmdr/Cmdr` library:

```bash
python build.py
```

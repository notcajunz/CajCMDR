--[[
	Template cloned once per command. The loader stores the command's public definition (name, description,
	arguments, ...) as JSON in the "Def" attribute, Cmdr replicates the clone to every client, and this tiny
	script turns it back into the definition table Cmdr expects.  The server-side Run function never leaves
	the server.
]]

return game:GetService("HttpService"):JSONDecode(script:GetAttribute("Def"))

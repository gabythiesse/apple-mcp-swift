-- Sonde 09 : réponse + transfert enregistrés en brouillon (avec fenêtre, seule variante qui ne bloque pas), puis fermeture ; jamais envoyés
tell application "Mail"
	set out to "outgoing ouverts avant: " & (count of outgoing messages) & linefeed
	set m to first message of mailbox "MCP-TEST-$2/[mcp-test] sous" whose id is $1
	set r to reply m with opening window
	set content of r to "Réponse de test mcp." & linefeed & linefeed & (content of r)
	save r
	set fw to forward m with opening window
	tell fw to make new to recipient at end of to recipients with properties {address:"fwd-test@example.com"}
	save fw
	delay 2
	set out to out & "outgoing ouverts: " & (count of outgoing messages) & linefeed
	close r saving yes
	close fw saving yes
	delay 1
	set out to out & "outgoing après close: " & (count of outgoing messages) & linefeed
	repeat with x in (messages of drafts mailbox whose subject contains "[mcp-test]")
		set out to out & "brouillon id " & (id of x) & " | " & (subject of x) & " | to " & (address of to recipients of x as text) & linefeed
	end repeat
	return out
end tell

-- Sonde 08 : réponse isolée ($3 = with/without opening window), enregistrée en brouillon, jamais envoyée
tell application "Mail"
	set m to first message of mailbox "MCP-TEST-$2/[mcp-test] sous" whose id is $1
	set r to reply m $3 opening window
	set out to "réponse: " & (subject of r) & " | to " & (address of to recipients of r as text) & " | visible " & (visible of r) & linefeed
	return out
end tell

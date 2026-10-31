-- Sonde 13 : recherche dans le corps par AppleScript, limitée à la boîte de test
tell application "Mail"
	set r to (messages of mailbox "MCP-TEST-$1/[mcp-test] renommée" whose content contains "zéphyr")
	return "trouvés: " & (count of r)
end tell

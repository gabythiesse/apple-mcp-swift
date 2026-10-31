-- Sonde 15 : l'UUID des URL de l'index correspond-il à l'id des comptes AppleScript ? (booléens seulement)
tell application "Mail"
	set ids to id of every account
	return "imap B438… est un compte: " & (ids contains "B438865A-FB87-4B00-A0FD-D4429B6DA08A") & " | INBOX existe: " & (exists mailbox "INBOX" of (first account whose id is "B438865A-FB87-4B00-A0FD-D4429B6DA08A")) & " | local 3BDA… est un compte: " & (ids contains "3BDAAC82-EE87-420C-96CB-D6536528629E") & " | Drafts du compte: " & (exists mailbox "Drafts" of (first account whose id is "B438865A-FB87-4B00-A0FD-D4429B6DA08A"))
end tell

-- Sonde 06 : message de test dans la boîte locale — états (lu, drapeau, couleur de drapeau, fond, indésirable) et lecture complète
on essai(lbl, f)
	return lbl & ": " & f & linefeed
end essai
tell application "Mail"
	set mb to mailbox "MCP-TEST-$2/[mcp-test] sous"
	set m to first message of mb whose id is $1
	set read status of m to false
	set flagged status of m to true
	set flag index of m to 4
	set background color of m to green
	set out to "lu " & (read status of m) & " | drapeau " & (flagged status of m) & " idx " & (flag index of m) & " | fond " & (background color of m) & " | indésirable " & (junk mail status of m) & linefeed
	try
		set out to out & "contenu: " & (content of m) & linefeed
	on error e
		set out to out & "contenu ERR " & e & linefeed
	end try
	try
		set out to out & "taille " & (message size of m) & " | message id " & (message id of m) & linefeed
	on error e
		set out to out & "méta ERR " & e & linefeed
	end try
	try
		set out to out & "en-têtes: " & (count of headers of m) & " | to " & (address of to recipients of m as text) & " | cc " & (address of cc recipients of m as text) & linefeed
	on error e
		set out to out & "destinataires ERR " & e & linefeed
	end try
	try
		set s to source of m
		set out to out & "source: " & (length of s) & " car." & linefeed
	on error e
		set out to out & "source ERR " & e & linefeed
	end try
	set out to out & "pj: " & (count of mail attachments of m) & linefeed
	set out to out & "boîte: " & (name of mailbox of m) & " < " & (name of container of mailbox of m)
	return out
end tell

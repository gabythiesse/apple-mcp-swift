-- Sonde 07 : pièce jointe dans un brouillon (variante alias + délai), réponse et transfert enregistrés en brouillon (jamais envoyés)
tell application "Mail"
	set out to ""
	set om to make new outgoing message with properties {subject:"[mcp-test] pj $2", content:"Corps de test pj." & linefeed & linefeed, visible:false}
	tell om to make new to recipient at end of to recipients with properties {address:"dest-test@example.com"}
	set f to (POSIX file "$3") as alias
	tell content of om to make new attachment with properties {file name:f} at after last paragraph
	delay 1
	set out to out & "pj dans outgoing: " & (count of attachments of content of om) & linefeed
	save om
	-- réponse et transfert d'un message de test
	set m to first message of mailbox "MCP-TEST-$2/[mcp-test] sous" whose id is $1
	set r to reply m opening window no reply to all yes
	set out to out & "réponse: sujet " & (subject of r) & " | to " & (address of to recipients of r as text) & " | cc " & (address of cc recipients of r as text) & linefeed
	set content of r to "Réponse de test." & linefeed & (content of r)
	save r
	set fw to forward m opening window no
	tell fw to make new to recipient at end of to recipients with properties {address:"fwd-test@example.com"}
	set out to out & "transfert: sujet " & (subject of fw) & linefeed
	save fw
	delay 3
	repeat with x in (messages of drafts mailbox whose subject contains "[mcp-test]")
		set out to out & "brouillon id " & (id of x) & " | " & (subject of x) & " | pj " & (count of mail attachments of x) & linefeed
	end repeat
	close om saving no
	close r saving no
	close fw saving no
	return out
end tell

-- Sonde 05 : brouillon complet (destinataires to/cc/bcc, pièce jointe, invisible) enregistré sans envoi, relu dans Brouillons
tell application "Mail"
	set om to make new outgoing message with properties {subject:"[mcp-test] brouillon $1", content:"Corps de test du brouillon, mot-clé zéphyr." & linefeed, visible:false}
	tell om
		make new to recipient at end of to recipients with properties {name:"Dest Test", address:"dest-test@example.com"}
		make new cc recipient at end of cc recipients with properties {address:"copie-test@example.com"}
		make new bcc recipient at end of bcc recipients with properties {address:"cache-test@example.com"}
		tell content to make new attachment with properties {file name:(POSIX file "$2")} at after last paragraph
	end tell
	set omid to id of om
	save om
	delay 2
	set out to "outgoing id: " & omid & " | expéditeur: " & ((sender of om) is not "") & linefeed
	set found to (messages of drafts mailbox whose subject is "[mcp-test] brouillon $1")
	set out to out & "trouvés dans Brouillons: " & (count of found) & linefeed
	repeat with m in found
		set out to out & "id " & (id of m) & " | boîte " & (name of mailbox of m) & " | compte " & ((account of mailbox of m) is not missing value) & " | to " & (address of to recipients of m as text) & " | pj " & (count of mail attachments of m) & linefeed
	end repeat
	close om saving no
	return out
end tell

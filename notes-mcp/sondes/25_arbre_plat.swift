// Sonde 25 : arbre des dossiers en lot (id, nom, conteneur) ; la corbeille y figure-t-elle ? comptage en lot ?
// Rien n'est affiché des dossiers de l’utilisateur : seulement des comptes et des booléens.
show("arbre plat", runAS("""
tell application "Notes"
  set ac to default account
  set i to id of folders of ac
  set n to name of folders of ac
  set p to id of container of folders of ac
  set corb to ("Recently Deleted" is in n) or ("Supprimées récemment" is in n)
  set racine to 0
  repeat with x in p
    if (contents of x) contains "/ICAccount/" then set racine to racine + 1
  end repeat
  return ((count of i) as string) & " dossiers, " & racine & " à la racine, corbeille listée=" & corb
end tell
"""))
show("comptage en lot", runAS("tell application \"Notes\" to return (count of (count of notes of folders of default account)) as string"))
show("comptage en lot (every)", runAS("tell application \"Notes\"\nset c to {}\nrepeat with fo in (folders of default account)\nset end of c to count of notes of fo\nend repeat\nreturn (count of c) as string\nend tell"))
show("notes de la corbeille par folder id", runAS("tell application \"Notes\" to return (count of notes of folder id \"x-coredata://776CB633-AE08-4EDE-8F4F-3AF34F655A7F/ICFolder/p3\") as string"))

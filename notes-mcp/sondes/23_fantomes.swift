// Sonde 23 : dossiers de test supprimés mais encore listés par « folders of account » : comment les reconnaître ?
let st = "x-coredata://776CB633-AE08-4EDE-8F4F-3AF34F655A7F/ICFolder/p"
for pk in [1592, 1623, 1624] {
  show("d\(pk)", runAS("""
  tell application "Notes"
    set r to ""
    try
      set f to folder id "\(st)\(pk)"
      set r to "app: nom=" & name of f
      set c to container of f
      set r to r & " conteneur=" & (class of c as string)
    on error e
      set r to "app: KO " & e
    end try
    set r to r & " | app folders whose id: " & (count of (folders whose id is "\(st)\(pk)"))
    set r to r & " | compte: " & (count of (folders of default account whose id is "\(st)\(pk)"))
    return r
  end tell
  """))
}
show("racine app vs compte", runAS("tell application \"Notes\" to return ((count of folders) as string) & \" / \" & (count of folders of default account)"))

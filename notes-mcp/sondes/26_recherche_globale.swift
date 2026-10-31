// Sonde 26 : recherche globale en un « whose » au niveau de l'app, conteneurs en lot (n'affiche que des comptes)
show("whose global + conteneurs", runAS("""
tell application "Notes"
  set L to (notes whose name contains "[mcp-test]" or plaintext contains "[mcp-test]")
  set {i, n, m} to {id, name, modification date} of (notes whose name contains "[mcp-test]" or plaintext contains "[mcp-test]")
  set c to id of container of (notes whose name contains "[mcp-test]" or plaintext contains "[mcp-test]")
  return ((count of i) as string) & " / " & (count of c) & " : " & (item 1 of c)
end tell
"""))
show("toutes les notes : id/nom/modif/conteneur", runAS("""
tell application "Notes"
  set {i, n, m} to {id, name, modification date} of notes
  set c to id of container of notes
  return ((count of i) as string) & " / " & (count of c)
end tell
"""))

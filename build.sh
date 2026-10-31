#!/bin/zsh
# Build release d'un serveur, installation au chemin stable bin/<Binaire>, signature avec l'identité fixe « Apple MCP ».
# macOS lie les autorisations à « identifiant + certificat » : elles survivent aux recompilations.
# (Une signature ad hoc lie l'autorisation au contenu exact du binaire : chaque build la faisait redemander.)
# L'identité vit dans le trousseau dédié ~/Library/Keychains/apple-mcp.keychain-db (voir .signature/), que codesign
# peut utiliser sans aucune invite. Le certificat doit être marqué « de confiance » une fois (.signature/confiance.command).
# Usage : ./build.sh safari-mcp   |   ./build.sh --signer <binaire> [identifiant]   |   ./build.sh --tout
set -e
RACINE=${0:a:h}
IDENTITE=$(<"$RACINE/.signature/identite.sha1")
TROUSSEAU="$HOME/Library/Keychains/apple-mcp.keychain-db"

signer() {
  security unlock-keychain -p "$(<"$RACINE/.signature/trousseau.motdepasse")" "$TROUSSEAU" 2>/dev/null || true
  if [[ -n $2 ]]; then codesign --force --timestamp=none -s "$IDENTITE" -i "$2" "$1"
  else codesign --force --timestamp=none -s "$IDENTITE" "$1"; fi
}

if [[ $1 == --signer ]]; then signer "$2" "$3"; exit; fi
if [[ $1 == --tout ]]; then for d in "$RACINE"/*-mcp "$RACINE"/launcher; do "$0" "${d:t}"; done; exit; fi

dossier="$RACINE/${1:?usage : build.sh <dossier>-mcp}"
cd "$dossier"
[[ -x build.sh ]] && exec ./build.sh   # Contacts : lanceur + bibliothèque, script propre
binaire=$(ls bin | grep -v '^\.' | grep -v '\.' | head -1)
out=$(swift build -c release 2>&1) || { echo "$out" | grep -E "error:"; echo "build en échec"; exit 1 }
install -m 755 .build/release/$binaire bin/$binaire
signer bin/$binaire dev.applemcp.${1}
rm -f bin/*.cstemp(N)
echo "installé et signé : $PWD/bin/$binaire"

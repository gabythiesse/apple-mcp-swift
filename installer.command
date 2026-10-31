#!/bin/zsh
# Installation complète, en une fois, des serveurs MCP Apple (Rappels, Calendrier, Mail, Notes, Contacts, Safari).
# Double-clic ou : ./installer.command
#
# Ce que ça fait, et pourquoi une seule fois :
#  1. Crée une identité de signature locale « Apple MCP » dans un trousseau dédié (aucune fenêtre à chaque build).
#  2. Compile les six serveurs et le lanceur unique AppleMCP, tous signés avec cette identité.
#  3. Déclare le certificat de confiance (macOS demande le mot de passe de session : UNE fois).
#     macOS lie alors chaque autorisation à « identifiant + certificat » : les recompilations ne redemandent plus rien.
#  4. Déclare les six serveurs dans Claude (app) et Codex (ChatGPT) s'ils sont installés, via le lanceur AppleMCP,
#     qui est le seul nom que macOS affiche (un interrupteur, pas six).
#  5. Fait un premier appel à chaque serveur : clique « Autoriser » à chaque fenêtre « AppleMCP ».
#  6. Ouvre « Accès complet au disque » : active l'interrupteur AppleMCP (Mail lit l'index local de Mail).
#  7. Ouvre « Accessibilité » : active l'interrupteur AppleMCP (fenêtres privées et suppressions dans Safari).
set -e
RACINE=${0:a:h}
cd "$RACINE"
SIG="$RACINE/.signature"
KC="$HOME/Library/Keychains/apple-mcp.keychain-db"
mkdir -p "$SIG" bin && chmod 700 "$SIG"
umask 077

echo "1/7 — identité de signature"
if [[ ! -s $SIG/identite.sha1 ]] || ! security find-identity -p codesigning "$KC" 2>/dev/null | grep -q "$(<"$SIG/identite.sha1")"; then
  PW=$(openssl rand -hex 24); printf '%s' "$PW" > "$SIG/trousseau.motdepasse"
  cat > "$SIG/openssl.cnf" <<'CNF'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = Apple MCP
[ext]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
CNF
  openssl req -x509 -newkey rsa:2048 -sha256 -days 7300 -nodes -keyout "$SIG/AppleMCP.key" -out "$SIG/AppleMCP.pem" -config "$SIG/openssl.cnf" 2>/dev/null
  openssl x509 -in "$SIG/AppleMCP.pem" -outform DER -out "$SIG/AppleMCP.cer"
  openssl pkcs12 -export -inkey "$SIG/AppleMCP.key" -in "$SIG/AppleMCP.pem" -out "$SIG/AppleMCP.p12" -passout pass:mcp -legacy 2>/dev/null \
    || openssl pkcs12 -export -inkey "$SIG/AppleMCP.key" -in "$SIG/AppleMCP.pem" -out "$SIG/AppleMCP.p12" -passout pass:mcp
  [[ -f $KC ]] && security delete-keychain "$KC"
  security create-keychain -p "$PW" "$KC"
  security set-keychain-settings "$KC"
  security unlock-keychain -p "$PW" "$KC"
  security import "$SIG/AppleMCP.p12" -k "$KC" -P mcp -T /usr/bin/codesign -T /usr/bin/security -f pkcs12 >/dev/null
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PW" "$KC" >/dev/null
  existants=$(security list-keychains -d user | tr -d '" ')
  echo "$existants" | grep -q "apple-mcp.keychain-db" || security list-keychains -d user -s ${=existants} "$KC"
  security find-identity -p codesigning "$KC" | grep "Apple MCP" | head -1 | awk '{print $2}' | tr -d '\n' > "$SIG/identite.sha1"
  rm -f "$SIG/AppleMCP.key" "$SIG/AppleMCP.p12"
  echo "   ✓ identité créée"
else
  echo "   ✓ identité déjà en place"
fi

echo "2/7 — compilation et signature (quelques minutes la première fois)"
./build.sh --tout

echo "3/7 — confiance du certificat"
if security verify-cert -c "$SIG/AppleMCP.pem" -p codeSign >/dev/null 2>&1; then
  echo "   ✓ déjà approuvé"
else
  echo "   → macOS demande ton mot de passe de session (une seule fois) : saisis-le, puis « Mettre à jour les réglages »."
  security add-trusted-cert -r trustRoot -k "$HOME/Library/Keychains/login.keychain-db" "$SIG/AppleMCP.cer"
  security verify-cert -c "$SIG/AppleMCP.pem" -p codeSign >/dev/null 2>&1 && echo "   ✓ certificat approuvé" || { echo "   ✗ non approuvé : relance l'installeur"; exit 1 }
fi

echo "4/7 — déclaration dans les clients"
/usr/bin/python3 -I - "$RACINE/bin/AppleMCP" <<'PY'
import json, os, re, shutil, sys, time
lanceur = sys.argv[1]
noms = ["reminders", "mail", "calendar", "safari", "notes", "contacts"]
p = os.path.expanduser("~/Library/Application Support/Claude/claude_desktop_config.json")
if os.path.isdir(os.path.dirname(p)):
    d = json.load(open(p)) if os.path.exists(p) else {}
    if os.path.exists(p): shutil.copy(p, p + f".bak-{int(time.time())}")
    s = d.setdefault("mcpServers", {})
    for k in noms:
        if k in s and "/mcp/" not in s[k].get("command", "") and s[k].get("command") != lanceur:
            print(f"   ! Claude : l'entrée « {k} » pointe ailleurs, non modifiée"); continue
        s[k] = {"command": lanceur, "args": [k]}
    json.dump(d, open(p, "w"), indent=2, ensure_ascii=False)
    print("   ✓ app Claude : six serveurs déclarés (quitte et relance Claude pour les activer)")
c = os.path.expanduser("~/.codex/config.toml")
if os.path.exists(c):
    t = open(c).read(); shutil.copy(c, c + f".bak-{int(time.time())}")
    for k in noms:
        bloc = f'[mcp_servers.{k}]\ncommand = "{lanceur}"\nargs = ["{k}"]\n'
        t, n = re.subn(rf'\[mcp_servers\.{k}\]\ncommand = "[^"]+"\n(args = \[[^\]]*\]\n)?', bloc, t)
        if n == 0: t = t.rstrip("\n") + "\n\n" + bloc
    open(c, "w").write(t)
    print("   ✓ Codex : six serveurs déclarés (relance l'app ChatGPT pour les activer)")
PY

echo "5/7 — premier appel : clique « Autoriser » à chaque fenêtre « AppleMCP »"
/usr/bin/python3 -I "$SIG/premier-appel.py" || true

echo "6/7 — Accès complet au disque (pour Mail) : active l'interrupteur « AppleMCP » dans la fenêtre qui s'ouvre, puis relance l'installeur si Mail était bloqué"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
echo "7/7 — Accessibilité (pour Safari : fenêtres privées, suppressions) : active l'interrupteur « AppleMCP » dans la fenêtre Réglages Système, confirme avec Touch ID"
"$RACINE/bin/AppleMCP" safari --accessibilite >/dev/null 2>&1 || true
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
echo
echo "Terminé. Exemple à dire à Claude : « Montre-moi mes rappels du jour »."

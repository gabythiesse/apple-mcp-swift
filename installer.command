#!/bin/zsh
# One-shot install of the Apple MCP servers (Reminders, Calendar, Mail, Notes, Contacts, Safari).
# Double-click, or: ./installer.command          (check only, changes nothing: ./installer.command --check)
#
# Every macOS permission is given here, once, while you are at the Mac. After that, no window ever again:
# not on the first use of a tool, not after a rebuild, not after a restart (the servers are often used remotely).
#  1. Reuses the local "Apple MCP" code-signing identity, or creates it the first time (dedicated keychain).
#     macOS ties every permission to "identifier + certificate": a new certificate means every permission is asked again,
#     so it is never replaced without asking you.
#  2. Builds the six servers and the single AppleMCP launcher, all signed with that identity.
#  3. Trusts the certificate (macOS asks for your login password once).
#  4. Registers the six servers in Claude (desktop app) and Codex (ChatGPT) if installed, through the AppleMCP launcher.
#  5. Asks for every permission listed in docs/permissions.md, under the "AppleMCP" name only, then checks them all.
#     "Done" only when every line is ✓. Run it again to redo only what is missing.
set -e
ROOT=${0:a:h}
cd "$ROOT"
SIG="$ROOT/.signature"
KC="$HOME/Library/Keychains/apple-mcp.keychain-db"

# Signing state, without changing anything. Prints one line, returns 0 when all is in place.
signature_state() {
  local id=$(security find-identity -p codesigning "$KC" 2>/dev/null | awk '/"Apple MCP"/{print $2; exit}')
  [[ -n $id ]] || { echo "  ✗ signing identity \"Apple MCP\" not found in $KC"; return 1 }
  [[ -s $SIG/AppleMCP.pem ]] && security verify-cert -c "$SIG/AppleMCP.pem" -p codeSign >/dev/null 2>&1 \
    || { echo "  ✗ certificate \"Apple MCP\" not trusted"; return 1 }
  local tmp=$(mktemp -d)
  (cd "$tmp" && codesign -d --extract-certificates "$ROOT/bin/AppleMCP" 2>/dev/null)
  local signed=$(openssl x509 -inform DER -in "$tmp/codesign0" -noout -fingerprint -sha1 2>/dev/null | cut -d= -f2 | tr -d :)
  rm -rf "$tmp"
  [[ $signed == $id ]] || { echo "  ✗ bin/AppleMCP is not signed with the \"Apple MCP\" identity ($id)"; return 1 }
  echo "  ✓ bin/AppleMCP signed with \"Apple MCP\" (${id[1,8]}…), certificate trusted"
}

if [[ $1 == --check ]]; then
  [[ -x bin/AppleMCP ]] || { echo "✗ bin/AppleMCP missing: run ./installer.command"; exit 1 }
  ok=0
  signature_state || ok=1
  bin/AppleMCP permissions || ok=1
  exit $ok
fi

mkdir -p "$SIG" bin && chmod 700 "$SIG"
umask 077

echo "1/5 — signing identity"
id=$(security find-identity -p codesigning "$KC" 2>/dev/null | awk '/"Apple MCP"/{print $2; exit}')
if [[ -n $id ]] && security unlock-keychain -p "$(cat "$SIG/trousseau.motdepasse" 2>/dev/null)" "$KC" 2>/dev/null; then
  [[ $(cat "$SIG/identite.sha1" 2>/dev/null) == $id ]] || printf '%s' "$id" > "$SIG/identite.sha1"
  [[ -s $SIG/AppleMCP.pem ]] || security find-certificate -c "Apple MCP" -p "$KC" > "$SIG/AppleMCP.pem"
  [[ -s $SIG/AppleMCP.cer ]] || openssl x509 -in "$SIG/AppleMCP.pem" -outform DER -out "$SIG/AppleMCP.cer"
  echo "   ✓ identity reused (${id[1,8]}…): permissions already given stay valid"
else
  if [[ -n $id || -f $KC || -s $SIG/identite.sha1 || -x bin/AppleMCP ]]; then
    echo "   ! The existing \"Apple MCP\" signing identity cannot be used (missing, or its keychain password is lost)."
    echo "     A NEW identity means macOS sees a different app: EVERY permission will be asked again."
    read -r "answer?     Type yes to create a new identity, anything else to stop: "
    [[ $answer == yes ]] || { echo "   stopped, nothing changed"; exit 1 }
  fi
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
  existing=$(security list-keychains -d user | tr -d '" ')
  echo "$existing" | grep -q "apple-mcp.keychain-db" || security list-keychains -d user -s ${=existing} "$KC"
  security find-identity -p codesigning "$KC" | grep "Apple MCP" | head -1 | awk '{print $2}' | tr -d '\n' > "$SIG/identite.sha1"
  rm -f "$SIG/AppleMCP.key" "$SIG/AppleMCP.p12"
  echo "   ✓ identity created"
fi

echo "2/5 — build and sign (a few minutes the first time)"
./build.sh --all

echo "3/5 — trust the certificate"
if security verify-cert -c "$SIG/AppleMCP.pem" -p codeSign >/dev/null 2>&1; then
  echo "   ✓ already trusted"
else
  echo "   → macOS asks for your login password (only once): enter it, then click \"Update Settings\"."
  security add-trusted-cert -r trustRoot -k "$HOME/Library/Keychains/login.keychain-db" "$SIG/AppleMCP.cer"
  security verify-cert -c "$SIG/AppleMCP.pem" -p codeSign >/dev/null 2>&1 && echo "   ✓ certificate trusted" || { echo "   ✗ not trusted: run the installer again"; exit 1 }
fi

echo "4/5 — register in clients"
/usr/bin/python3 -I - "$ROOT/bin/AppleMCP" <<'PY'
import json, os, re, shutil, sys, time
launcher = sys.argv[1]
names = ["reminders", "mail", "calendar", "safari", "notes", "contacts"]
p = os.path.expanduser("~/Library/Application Support/Claude/claude_desktop_config.json")
if os.path.isdir(os.path.dirname(p)):
    d = json.load(open(p)) if os.path.exists(p) else {}
    if os.path.exists(p): shutil.copy(p, p + f".bak-{int(time.time())}")
    s = d.setdefault("mcpServers", {})
    for k in names:
        if k in s and s[k].get("command") != launcher:
            print(f"   ! Claude: entry \"{k}\" points elsewhere, left unchanged"); continue
        s[k] = {"command": launcher, "args": [k]}
    json.dump(d, open(p, "w"), indent=2, ensure_ascii=False)
    print("   ✓ Claude app: six servers registered (quit and reopen Claude to enable them)")
c = os.path.expanduser("~/.codex/config.toml")
if os.path.exists(c):
    t = open(c).read(); shutil.copy(c, c + f".bak-{int(time.time())}")
    for k in names:
        # an existing [mcp_servers.<k>] table, whatever its key order: never overwritten, never duplicated (invalid TOML)
        m = re.search(rf'^\[mcp_servers\.{re.escape(k)}\]\n((?:(?!\[).*\n?)*)', t, re.M)
        if m:
            if f'command = "{launcher}"' not in m.group(1):
                print(f"   ! Codex: entry \"{k}\" points elsewhere, left unchanged")
            continue
        t = t.rstrip("\n") + f'\n\n[mcp_servers.{k}]\ncommand = "{launcher}"\nargs = ["{k}"]\n'
    open(c, "w").write(t)
    print("   ✓ Codex: servers registered (restart the ChatGPT app to enable them)")
PY

echo "5/5 — permissions: click \"Allow\"/\"OK\" on every \"AppleMCP\" prompt, turn on the switches System Settings shows"
bin/AppleMCP permissions --request && ok=0 || ok=1
echo
if (( ok == 0 )); then
  echo "Done. Every permission is given: no macOS window will interrupt the tools, even remotely."
  echo "Quit and reopen Claude, then try: \"Show me today's reminders\". To check again later: ./installer.command --check"
else
  echo "Not done: turn on the switches marked ✗ above, then run ./installer.command again (it only redoes what is missing)."
  exit 1
fi

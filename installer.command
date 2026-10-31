#!/bin/zsh
# One-shot install of the Apple MCP servers (Reminders, Calendar, Mail, Notes, Contacts, Safari).
# Double-click, or: ./installer.command
#
# What it does, and why only once:
#  1. Creates a local "Apple MCP" code-signing identity in a dedicated keychain (no prompt on every build).
#  2. Builds the six servers and the single AppleMCP launcher, all signed with that identity.
#  3. Trusts the certificate (macOS asks for your login password ONCE).
#     macOS then ties every permission to "identifier + certificate": rebuilds never ask again.
#  4. Registers the six servers in Claude (desktop app) and Codex (ChatGPT) if installed, through the AppleMCP launcher,
#     which is the only name macOS shows (one switch, not six).
#  5. Calls each server once: click "Allow" on every "AppleMCP" prompt.
#  6. Opens "Full Disk Access": turn on the AppleMCP switch (Mail reads Mail's local index).
#  7. Opens "Accessibility": turn on the AppleMCP switch (private windows and deletions in Safari).
set -e
ROOT=${0:a:h}
cd "$ROOT"
SIG="$ROOT/.signature"
KC="$HOME/Library/Keychains/apple-mcp.keychain-db"
mkdir -p "$SIG" bin && chmod 700 "$SIG"
umask 077

echo "1/7 — signing identity"
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
  existing=$(security list-keychains -d user | tr -d '" ')
  echo "$existing" | grep -q "apple-mcp.keychain-db" || security list-keychains -d user -s ${=existing} "$KC"
  security find-identity -p codesigning "$KC" | grep "Apple MCP" | head -1 | awk '{print $2}' | tr -d '\n' > "$SIG/identite.sha1"
  rm -f "$SIG/AppleMCP.key" "$SIG/AppleMCP.p12"
  echo "   ✓ identity created"
else
  echo "   ✓ identity already in place"
fi

echo "2/7 — build and sign (a few minutes the first time)"
./build.sh --all

echo "3/7 — trust the certificate"
if security verify-cert -c "$SIG/AppleMCP.pem" -p codeSign >/dev/null 2>&1; then
  echo "   ✓ already trusted"
else
  echo "   → macOS asks for your login password (only once): enter it, then click \"Update Settings\"."
  security add-trusted-cert -r trustRoot -k "$HOME/Library/Keychains/login.keychain-db" "$SIG/AppleMCP.cer"
  security verify-cert -c "$SIG/AppleMCP.pem" -p codeSign >/dev/null 2>&1 && echo "   ✓ certificate trusted" || { echo "   ✗ not trusted: run the installer again"; exit 1 }
fi

echo "4/7 — register in clients"
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
        block = f'[mcp_servers.{k}]\ncommand = "{launcher}"\nargs = ["{k}"]\n'
        t, n = re.subn(rf'\[mcp_servers\.{k}\]\ncommand = "[^"]+"\n(args = \[[^\]]*\]\n)?', block, t)
        if n == 0: t = t.rstrip("\n") + "\n\n" + block
    open(c, "w").write(t)
    print("   ✓ Codex: six servers registered (restart the ChatGPT app to enable them)")
PY

echo "5/7 — first call: click \"Allow\" on every \"AppleMCP\" prompt"
/usr/bin/python3 -I "$ROOT/scripts/first-call.py" || true

echo "6/7 — Full Disk Access (for Mail): turn on the \"AppleMCP\" switch in the window that opens, then run the installer again if Mail was blocked"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
echo "7/7 — Accessibility (for Safari: private windows, deletions): turn on the \"AppleMCP\" switch in System Settings, confirm with Touch ID"
"$ROOT/bin/AppleMCP" safari --accessibility >/dev/null 2>&1 || true
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
echo
echo "Done. Try asking Claude: \"Show me today's reminders\"."

#!/bin/zsh
# Runs the smoke tests of the servers that read local databases (Notes, Mail, Safari), or the ones given as arguments.
# They create MCP-TEST-<timestamp> items in the real apps and remove them; they never send email or invitations.
# Needs Full Disk Access for the app running this script (Terminal): Mail's index, Notes' and Safari's databases.
# Usage: scripts/smoke-all.sh [reminders calendar contacts notes mail safari]
ROOT=${0:a:h:h}
cd "$ROOT"
typeset -A BIN=(reminders RemindersMCP calendar CalendarMCP contacts ContactsMCP notes NotesMCP mail MailMCP safari SafariMCP)
servers=("$@")
(( ${#servers} )) || servers=(notes mail safari)

if ! ls "$HOME/Library/Mail" >/dev/null 2>&1; then
  echo "✗ No Full Disk Access for this terminal."
  echo "  System Settings > Privacy & Security > Full Disk Access > turn on your terminal app, quit it (Cmd+Q), reopen, run again."
  exit 1
fi

for s in $servers; do
  b="$ROOT/$s-mcp/.build/release/${BIN[$s]}"
  [[ -x $b ]] || (cd "$s-mcp" && swift build -c release >/dev/null 2>&1)
done

# Without the AppleMCP launcher, each server would disclaim responsibility and become its own (unsigned, unauthorized)
# process for macOS. These markers make it inherit the terminal's permissions instead, Full Disk Access included.
export RAPPELS_MCP_RESPONSABLE=1 CALENDRIER_MCP_RESPONSABLE=1 CONTACTS_MCP_RESPONSABLE=1
export NOTES_MCP_RESPONSABLE=1 MAIL_MCP_RESPONSABLE=1 SAFARI_MCP_RESPONSABLE=1

failed=()
for s in $servers; do
  echo "===== $s"
  /usr/bin/python3 -I "$s-mcp/tests/smoke.py" "$ROOT/$s-mcp/.build/release/${BIN[$s]}" > "/tmp/smoke-$s.log" 2>&1 || failed+=$s
  grep -E "✗|Error|Traceback" "/tmp/smoke-$s.log" | head -10
  tail -2 "/tmp/smoke-$s.log"
done

if (( ${servers[(Ie)mail]} )); then
  echo "===== mail cleanup"
  /usr/bin/python3 -I mail-mcp/tests/smoke.py "$ROOT/mail-mcp/.build/release/MailMCP" --nettoyage 2>&1 | tail -2
fi

echo
(( ${#failed} )) && echo "✗ FAILED: $failed (full logs: /tmp/smoke-<server>.log)" || echo "✓ ALL SMOKE TESTS PASS: $servers"

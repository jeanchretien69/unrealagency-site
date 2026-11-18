#!/bin/bash
# Unreal Agency — ActivityWatch sync for Mac.
# Install: curl -fsSL https://unrealagency.ai/tools/aw-mac.sh | bash -s YOUR_TOKEN
# Update (keeps your token): curl -fsSL https://unrealagency.ai/tools/aw-mac.sh | bash
set -e
TOKEN="$1"
DIR="$HOME/.unreal"; mkdir -p "$DIR"
if [ -z "$TOKEN" ] && [ -f "$DIR/aw-sync.sh" ]; then TOKEN="$(sed -n 's/^TOKEN="\(.*\)"$/\1/p' "$DIR/aw-sync.sh" | head -1)"; fi
if [ -z "$TOKEN" ]; then echo "Missing token"; exit 1; fi
cat > "$DIR/aw-sync.sh" <<SYNC
#!/bin/bash
TOKEN="$TOKEN"
URL="https://ljhpdqttcxwgufcejfor.supabase.co/rest/v1/rpc/aw_ingest"
KEY="sb_publishable_Nu7S4SnvuTFRg1ODn4VVrA_hCH5X1wY"
AW="http://localhost:5600/api/0"
DEV="\$(scutil --get ComputerName 2>/dev/null | tr -cd '[:alnum:] _-' | cut -c1-40)"
STAMP="$DIR/last-sync"
if [ -f "\$STAMP" ]; then START="\$(date -u -v-10M +%Y-%m-%dT%H:%M:%SZ)"; else START="\$(date -u -v-24H +%Y-%m-%dT%H:%M:%SZ)"; fi
BUCKETS="\$(curl -s --max-time 10 "\$AW/buckets/" | grep -oE '"aw-watcher-(window|afk|web)[^"]*"' | tr -d '"' | sort -u)"
[ -z "\$BUCKETS" ] && exit 0
OK=1
for B in \$BUCKETS; do
  EV="\$(curl -s --max-time 20 "\$AW/buckets/\$B/events?start=\$START&limit=5000")"
  [ -z "\$EV" ] && continue
  BODY="{\"p_token\":\"\$TOKEN\",\"p_device\":\"\$DEV\",\"p_bucket\":\"\$B\",\"p_events\":\$EV}"
  CODE="\$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 -X POST "\$URL" -H "apikey: \$KEY" -H "Authorization: Bearer \$KEY" -H 'Content-Type: application/json' --data-binary "\$BODY")"
  [ "\$CODE" = "200" ] || OK=0
done
[ "\$OK" = "1" ] && date -u +%s > "\$STAMP"
SYNC
chmod +x "$DIR/aw-sync.sh"
PL="$HOME/Library/LaunchAgents/ai.unrealagency.awsync.plist"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PL" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>ai.unrealagency.awsync</string>
<key>ProgramArguments</key><array><string>/bin/bash</string><string>$DIR/aw-sync.sh</string></array>
<key>StartInterval</key><integer>60</integer>
<key>RunAtLoad</key><true/>
</dict></plist>
PLIST
launchctl unload "$PL" 2>/dev/null || true
launchctl load "$PL"
/bin/bash "$DIR/aw-sync.sh" || true
echo "Unreal tracking installed. It syncs every minute while ActivityWatch is running."

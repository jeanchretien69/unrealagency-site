#!/bin/bash
# Unreal Agency phone reader: Mac installer. Double-click it (or run it in Terminal). No admin rights needed.
# Installs everything into ~/UnrealPhone, then keeps it running by itself (starts at login, restarts if it stops).
set -u
cd "$(dirname "$0")" || exit 1
SRC="$(pwd)"
HOME_DIR="$HOME/UnrealPhone"
TOOLS="$HOME_DIR/tools"
LA="$HOME/Library/LaunchAgents"
UID_N="$(id -u)"
SUPABASE_GATE="https://ljhpdqttcxwgufcejfor.supabase.co/functions/v1/phone-gate"
PHONE_HOST="phone.unrealagency.ai"
SCRCPY_VERSION="5.0.1"
CLOUDFLARED_VERSION="2026.10.4"
NODE_LINE="latest-v22.x"

say()  { printf "\n\033[1;35m▸ %s\033[0m\n" "$*"; }
ok()   { printf "  \033[32m✓\033[0m %s\n" "$*"; }
die()  { printf "\n\033[1;31m✗ %s\033[0m\n\n" "$*"; read -r -p "Press Enter to close" _; exit 1; }
dl()   { # dl URL FILE
  curl -fL --retry 3 --connect-timeout 20 -o "$2" "$1" || die "Download failed: $1"
  [ -s "$2" ] || die "Downloaded file is empty: $2"
}

case "$(uname -m)" in
  arm64) ARCH=arm64; NODE_ARCH=arm64 ;;
  x86_64) ARCH=amd64; NODE_ARCH=x64 ;;
  *) die "Unknown Mac type: $(uname -m)" ;;
esac

if [ "${1:-}" = "status" ]; then
  curl -s http://127.0.0.1:8100/health; echo
  launchctl list | grep -i unrealphone
  exit 0
fi

say "1/6  Folders"
mkdir -p "$TOOLS" "$HOME_DIR/public" "$HOME_DIR/logs" "$LA"
cp "$SRC/server.mjs" "$HOME_DIR/server.mjs" || die "server.mjs is missing next to this installer"
cp -R "$SRC/public/." "$HOME_DIR/public/" || die "public folder is missing next to this installer"
ok "Reader files copied to $HOME_DIR"

say "2/6  Node (portable, nothing is installed on your Mac)"
if [ ! -x "$TOOLS/node/bin/node" ]; then
  NODE_FILE="$(curl -fsSL "https://nodejs.org/dist/$NODE_LINE/SHASUMS256.txt" | awk '{print $2}' | grep "darwin-$NODE_ARCH.tar.gz$" | head -1)"
  [ -n "$NODE_FILE" ] || die "Could not find the Node download"
  dl "https://nodejs.org/dist/$NODE_LINE/$NODE_FILE" "$TOOLS/node.tgz"
  mkdir -p "$TOOLS/node" && tar -xzf "$TOOLS/node.tgz" -C "$TOOLS/node" --strip-components=1 && rm -f "$TOOLS/node.tgz"
fi
"$TOOLS/node/bin/node" -v >/dev/null 2>&1 || die "Node did not install"
ok "Node $("$TOOLS/node/bin/node" -v)"

say "3/6  adb (Google's official Android tool)"
if [ ! -x "$TOOLS/platform-tools/adb" ]; then
  dl "https://dl.google.com/android/repository/platform-tools-latest-darwin.zip" "$TOOLS/pt.zip"
  unzip -oq "$TOOLS/pt.zip" -d "$TOOLS" && rm -f "$TOOLS/pt.zip"
fi
[ -x "$TOOLS/platform-tools/adb" ] || die "adb did not install"
ok "adb ready"

say "4/6  Screen-sharing app for the phone (scrcpy $SCRCPY_VERSION) and Cloudflare tunnel tool"
[ -s "$TOOLS/scrcpy-server" ] || dl "https://github.com/Genymobile/scrcpy/releases/download/v$SCRCPY_VERSION/scrcpy-server-v$SCRCPY_VERSION" "$TOOLS/scrcpy-server"
if [ ! -x "$TOOLS/cloudflared" ]; then
  dl "https://github.com/cloudflare/cloudflared/releases/download/$CLOUDFLARED_VERSION/cloudflared-darwin-$ARCH.tgz" "$TOOLS/cf.tgz"
  tar -xzf "$TOOLS/cf.tgz" -C "$TOOLS" && rm -f "$TOOLS/cf.tgz"
fi
[ -x "$TOOLS/cloudflared" ] || die "cloudflared did not install"
ok "scrcpy-server and cloudflared ready"

say "5/6  Phone on USB"
"$TOOLS/platform-tools/adb" start-server >/dev/null 2>&1
echo "  On the phone: Settings > About phone > Software information > tap 'Build number' 7 times."
echo "  Then Settings > Developer options > turn on 'USB debugging' and 'Stay awake'."
echo "  Plug the phone into this Mac (USB mode: File transfer), and tap 'Always allow this computer' > Allow."
for i in $(seq 1 60); do
  S="$("$TOOLS/platform-tools/adb" devices | awk 'NR>1 && $2=="device"{print $1}' | head -1)"
  [ -n "$S" ] && break
  UN="$("$TOOLS/platform-tools/adb" devices | awk 'NR>1 && $2=="unauthorized"{print $1}' | head -1)"
  [ -n "$UN" ] && printf "\r  Phone found but not allowed yet: look at its screen and tap Allow…      "
  sleep 2
done
[ -n "${S:-}" ] || die "No phone found. Check the cable (a data cable, not charge-only), USB debugging, then run this again."
ok "Phone connected: $S"

say "6/6  Cloudflare tunnel"
if [ ! -s "$HOME_DIR/tunnel.token" ]; then
  echo "  In Cloudflare: Networking > Tunnels > Create a tunnel > choose macOS > copy the command shown."
  echo "  Add a route: subdomain 'phone', domain unrealagency.ai, service http://localhost:8100"
  echo "  Then paste the whole command here (it stays hidden) and press Enter:"
  read -r -s -p "  > " CMD; echo
  TOKEN="$(printf "%s" "$CMD" | grep -oE 'eyJ[A-Za-z0-9=_-]{40,}' | head -1)"
  [ -n "$TOKEN" ] || die "I could not find the tunnel token in what you pasted. Copy the full command from Cloudflare."
  umask 077; printf "%s" "$TOKEN" > "$HOME_DIR/tunnel.token"; chmod 600 "$HOME_DIR/tunnel.token"
fi
ok "Tunnel token saved on this Mac only"

# ---- keep it running by itself (launchd) ----
cat > "$LA/ai.unrealagency.phone-reader.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>ai.unrealagency.phone-reader</string>
  <key>ProgramArguments</key><array>
    <string>/usr/bin/caffeinate</string><string>-i</string>
    <string>$TOOLS/node/bin/node</string><string>$HOME_DIR/server.mjs</string>
  </array>
  <key>WorkingDirectory</key><string>$HOME_DIR</string>
  <key>EnvironmentVariables</key><dict>
    <key>HOST</key><string>127.0.0.1</string>
    <key>PORT</key><string>8100</string>
    <key>ADB</key><string>$TOOLS/platform-tools/adb</string>
    <key>SCRCPY_SERVER</key><string>$TOOLS/scrcpy-server</string>
    <key>SCRCPY_VERSION</key><string>$SCRCPY_VERSION</string>
    <key>PHONE_SERIAL</key><string>usb</string>
    <key>GATE_URL</key><string>$SUPABASE_GATE</string>
    <key>PHONE_HOST</key><string>$PHONE_HOST</string>
    <key>FRAME_ANCESTORS</key><string>https://unrealagency.ai https://www.unrealagency.ai</string>
  </dict>
  <key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$HOME_DIR/logs/reader.log</string>
  <key>StandardErrorPath</key><string>$HOME_DIR/logs/reader.log</string>
</dict></plist>
PLIST
cat > "$LA/ai.unrealagency.phone-tunnel.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>ai.unrealagency.phone-tunnel</string>
  <key>ProgramArguments</key><array>
    <string>/bin/bash</string><string>-c</string>
    <string>exec "$TOOLS/cloudflared" tunnel --no-autoupdate run --token "\$(cat "$HOME_DIR/tunnel.token")"</string>
  </array>
  <key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$HOME_DIR/logs/tunnel.log</string>
  <key>StandardErrorPath</key><string>$HOME_DIR/logs/tunnel.log</string>
</dict></plist>
PLIST
for L in ai.unrealagency.phone-reader ai.unrealagency.phone-tunnel; do
  launchctl bootout "gui/$UID_N/$L" >/dev/null 2>&1
  launchctl bootstrap "gui/$UID_N" "$LA/$L.plist" || die "Could not start $L"
done
sleep 3
H="$(curl -s --max-time 5 http://127.0.0.1:8100/health)"
[ -n "$H" ] && ok "Reader running: $H" || die "Reader did not start. See $HOME_DIR/logs/reader.log"
ok "Tunnel started (log: $HOME_DIR/logs/tunnel.log)"

printf "\n\033[1;32mDone.\033[0m Open unrealagency.ai/members > Phone control.\n"
printf "It starts by itself when this Mac starts. Keep the Mac plugged in and the phone on USB.\n"
printf "Check anytime:  bash \"%s/install.command\" status\n\n" "$SRC"
read -r -p "Press Enter to close" _

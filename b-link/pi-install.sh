#!/bin/bash
# B.Link for Raspberry Pi (64-bit Raspberry Pi OS). Installs, updates and launches B.Link.
#   bash pi-install.sh            install or update, then open it
#   ~/.local/bin/b-link           the launcher: checks for an update, then opens B.Link
# Everything comes from the public GitHub folder and is SHA-256 checked. No sudo needed.
set -u
BASE="${BLINK_BASE:-https://raw.githubusercontent.com/MissSpock-OddFM/public/main/b-link}"
DIR="${BLINK_DIR:-$HOME/.local/share/B.Link}"
DATA="${BLINK_DATA:-$HOME/.config/B.Link}"
BIN="${BLINK_BIN:-$HOME/.local/bin}"
ARCH="${BLINK_ARCH:-linux-arm64}"
say() { echo "[B.Link] $*"; }
die() { say "ERROR: $*"; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "$1 is missing. Run: sudo apt install -y $2"; }
need curl curl; need unzip unzip; need python3 python3; need tar tar
if [ -z "${BLINK_ARCH:-}" ] && [ "$(uname -m)" != "aarch64" ]; then
  die "This needs 64-bit Raspberry Pi OS (aarch64). This system reports $(uname -m)."
fi
WORK="$DIR/.work"; mkdir -p "$WORK" "$BIN" "$DATA"
sha() { sha256sum "$1" | cut -d' ' -f1; }
getf() { # url sha256 dest : download with resume, verify, reuse if already good
  local url="$1" want="$2" dst="$3"
  if [ -f "$dst" ] && [ "$(sha "$dst")" = "$want" ]; then return 0; fi
  say "Downloading $(basename "$dst")..."
  curl -fL --progress-bar --retry 3 --retry-delay 2 -C - -o "$dst" "$url" || { rm -f "$dst"; return 1; }
  [ "$(sha "$dst")" = "$want" ] || { rm -f "$dst"; say "Checksum did not match for $(basename "$dst")"; return 1; }
}
M="$WORK/latest.json"
if ! curl -fsSL --max-time 15 "$BASE/latest.json?t=$(date +%s)" -o "$M.tmp"; then
  rm -f "$M.tmp"
  [ -x "$DIR/electron/electron" ] && { say "Offline: opening the installed B.Link."; exec "$DIR/electron/electron" --no-sandbox "$DIR/electron/resources/app"; }
  die "Cannot reach GitHub and B.Link is not installed yet."
fi
mv "$M.tmp" "$M"
j() { python3 -c "import json,sys;d=json.load(open('$M'));print(eval(sys.argv[1]))" "$1"; }
VER=$(j "d['version']"); APPURL=$(j "d['app']['url']"); APPSHA=$(j "d['app']['sha256']")
EURL=$(j "d['electron_$ARCH'.replace('-','_')]['url']") || die "This release has no Raspberry Pi build yet."
ESHA=$(j "d['electron_$ARCH'.replace('-','_')]['sha256']")
SURL=$(j "d['sherpa_$ARCH'.replace('-','_')]['url']"); SSHA=$(j "d['sherpa_$ARCH'.replace('-','_')]['sha256']")
case "$APPURL" in http*) ;; *) APPURL="$BASE/$APPURL";; esac
REC="$DIR/install.json"
HAVE=""; [ -f "$REC" ] && HAVE=$(python3 -c "import json;d=json.load(open('$REC'));print(d.get('app','')+'|'+d.get('electron',''))" 2>/dev/null)
if [ "$HAVE" = "$APPSHA|$ESHA" ] && [ -x "$DIR/electron/electron" ]; then
  say "B.Link $VER is up to date."
else
  say "Installing B.Link $VER..."
  getf "$EURL" "$ESHA" "$WORK/electron-$ESHA.zip" || die "Electron download failed."
  getf "$APPURL" "$APPSHA" "$WORK/app-$APPSHA.zip" || die "B.Link download failed."
  getf "$SURL" "$SSHA" "$WORK/sherpa-$SSHA.tgz" || die "Speech engine download failed."
  NEW="$DIR/electron.new"; rm -rf "$NEW"; mkdir -p "$NEW"
  unzip -q "$WORK/electron-$ESHA.zip" -d "$NEW" || die "Could not unpack Electron."
  chmod +x "$NEW/electron"
  rm -f "$NEW/resources/default_app.asar"; mkdir -p "$NEW/resources/app"
  unzip -q "$WORK/app-$APPSHA.zip" -d "$NEW/resources/app" || die "Could not unpack B.Link."
  # the app zip carries the Windows speech engine; swap in the Raspberry Pi one
  rm -rf "$NEW/resources/app/node_modules/sherpa-onnx-win-x64" "$NEW/resources/app/node_modules/sherpa-onnx-win-ia32"
  S="$NEW/resources/app/node_modules/sherpa-onnx-linux-arm64"; [ "$ARCH" = "linux-x64" ] && S="$NEW/resources/app/node_modules/sherpa-onnx-linux-x64"
  mkdir -p "$S"; tar -xzf "$WORK/sherpa-$SSHA.tgz" -C "$S" --strip-components=1 || die "Could not unpack the speech engine."
  rm -rf "$DIR/electron.old"; [ -d "$DIR/electron" ] && mv "$DIR/electron" "$DIR/electron.old"
  mv "$NEW" "$DIR/electron" || { [ -d "$DIR/electron.old" ] && mv "$DIR/electron.old" "$DIR/electron"; die "Could not switch to the new version."; }
  rm -rf "$DIR/electron.old"
  printf '{"version":"%s","app":"%s","electron":"%s"}\n' "$VER" "$APPSHA" "$ESHA" > "$REC"
  say "B.Link $VER installed."
fi
# voice pack: Betty speaking and F9 dictation (downloaded once)
VP="$DIR/electron/resources/app/voicepack.json"
if [ -f "$VP" ]; then
  python3 - "$VP" "$DATA/speech" "$WORK" <<'PY' || say "The voice did not finish installing. B.Link works without it; run this again to retry."
import json, os, sys, subprocess, hashlib, shutil, tarfile
vp, root, work = sys.argv[1:4]
for a in json.load(open(vp))["assets"]:
    dest = os.path.join(root, *a["dest"].replace("\\", "/").split("/"))
    if os.path.isdir(dest) and os.listdir(dest): continue
    f = os.path.join(work, a["id"] + ".tar.bz2")
    if not (os.path.exists(f) and hashlib.sha256(open(f, "rb").read()).hexdigest() == a["sha256"]):
        print("[B.Link] Downloading voice:", a["id"], "(%d MB)" % (a["bytes"] // 1048576), flush=True)
        subprocess.run(["curl", "-fL", "--progress-bar", "--retry", "3", "-C", "-", "-o", f, a["url"]], check=True)
        if hashlib.sha256(open(f, "rb").read()).hexdigest() != a["sha256"]:
            os.remove(f); sys.exit("checksum mismatch for " + a["id"])
    tmp = os.path.join(work, "x-" + a["id"]); shutil.rmtree(tmp, ignore_errors=True)
    with tarfile.open(f) as t:
        t.extractall(tmp, filter="data") if hasattr(tarfile, "data_filter") else t.extractall(tmp)
    os.makedirs(dest, exist_ok=True)
    for name in a["copy"]:
        s = os.path.join(tmp, a["folder"], name); d = os.path.join(dest, name)
        shutil.copytree(s, d, dirs_exist_ok=True) if os.path.isdir(s) else shutil.copy2(s, d)
    shutil.rmtree(tmp, ignore_errors=True)
PY
fi
# launcher + menu entry + desktop icon
cat > "$BIN/b-link" <<LAUNCH
#!/bin/bash
# Opens B.Link, updating it first if GitHub has a newer version.
if [ -f "$DIR/pi-install.sh" ]; then bash "$DIR/pi-install.sh" --run-quiet >/dev/null 2>&1; fi
exec "$DIR/electron/electron" --no-sandbox --ozone-platform-hint=auto "$DIR/electron/resources/app" "\$@"
LAUNCH
chmod +x "$BIN/b-link"
if [ -f "$0" ] && [ "$(readlink -f "$0")" != "$(readlink -f "$DIR/pi-install.sh")" ]; then cp "$0" "$DIR/pi-install.sh"; elif [ ! -f "$0" ]; then curl -fsSL "$BASE/pi-install.sh" -o "$DIR/pi-install.sh.tmp" && mv "$DIR/pi-install.sh.tmp" "$DIR/pi-install.sh"; fi
mkdir -p "$HOME/.local/share/applications"
ICON="$DIR/electron/resources/app/renderer/icon.png"
cat > "$HOME/.local/share/applications/b-link.desktop" <<DESK
[Desktop Entry]
Type=Application
Name=B.Link
Comment=B.Link terminal
Exec=$BIN/b-link
Icon=$( [ -f "$ICON" ] && echo "$ICON" || echo utilities-terminal )
Terminal=false
Categories=Utility;
DESK
D="$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")"
[ -d "$D" ] && { cp "$HOME/.local/share/applications/b-link.desktop" "$D/B.Link.desktop"; chmod +x "$D/B.Link.desktop"; }
say "Done. Open B.Link from the desktop icon, the menu (Accessories), or by typing: b-link"
[ "${1:-}" = "--no-launch" ] || [ "${1:-}" = "--run-quiet" ] || { [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && { say "Opening B.Link..."; nohup "$BIN/b-link" >/dev/null 2>&1 & } ; }
exit 0

#!/bin/bash
# B.Link OS system update 1: B.Link settings helper (clock, Bluetooth), Bluetooth audio, default time zone.
# Run as root at boot by blink-sysupdate.sh after its sha256 was checked against the signed-off manifest.
export DEBIAN_FRONTEND=noninteractive
apt-get -o DPkg::Lock::Timeout=300 install -y --no-install-recommends sudo bluez libspa-0.2-bluetooth pulseaudio-utils rfkill || { apt-get update && apt-get install -y --no-install-recommends sudo bluez libspa-0.2-bluetooth pulseaudio-utils rfkill; } || exit 1
cat > /usr/local/sbin/blink-sys <<'BLINKSYS'
#!/bin/bash
# B.Link OS settings helper. Runs as root through sudo from B.Link (user "blink"). Only the commands below exist;
# every argument is checked before use. BLINK_SYS_DRY=1 prints what would run (used by the tests).
set -u
DRY="${BLINK_SYS_DRY:-}"
run() { if [ -n "$DRY" ]; then echo "RUN $*"; else "$@"; fi; }
cmd="${1:-}"; arg="${2:-}"
mac_ok() { [[ "$1" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; }
case "$cmd" in
  time-status)
    timedatectl show -p Timezone -p NTP -p NTPSynchronized 2>&1
    date '+LOCAL=%Y-%m-%d %H:%M:%S %Z' ;;
  tz-set)
    [[ "$arg" =~ ^[A-Za-z0-9_+/-]{1,40}$ ]] && [[ "$arg" != *..* ]] && { [ -n "$DRY" ] || [ -f "/usr/share/zoneinfo/$arg" ]; } || { echo BAD_ZONE; exit 2; }
    run timedatectl set-timezone "$arg" ;;
  ntp-sync)
    run timedatectl set-ntp true; run systemctl restart systemd-timesyncd ;;
  time-set)
    [[ "$arg" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}(:[0-9]{2})?$ ]] || { echo BAD_TIME; exit 2; }
    run timedatectl set-ntp false; run timedatectl set-time "$arg" ;;
  bt-scan)
    run rfkill unblock bluetooth; run systemctl start bluetooth; sleep 1
    run bluetoothctl power on
    if [ -n "$DRY" ]; then echo "RUN bluetoothctl --timeout 10 scan on"; else bluetoothctl --timeout 10 scan on >/dev/null 2>&1; fi ;&
  bt-list)
    [ -n "$DRY" ] && { echo "RUN bluetoothctl devices"; exit 0; }
    bluetoothctl devices 2>/dev/null | while read -r _ mac name; do
      info=$(bluetoothctl info "$mac" 2>/dev/null)
      p=no; c=no; echo "$info" | grep -q 'Paired: yes' && p=yes; echo "$info" | grep -q 'Connected: yes' && c=yes
      echo "DEV|$mac|$name|$p|$c"
    done ;;
  bt-pair)
    mac_ok "$arg" || { echo BAD_MAC; exit 2; }
    [ -n "$DRY" ] && { echo "RUN pair $arg"; exit 0; }
    ( echo 'agent NoInputNoOutput'; echo 'default-agent'; echo "pair $arg"; sleep 9; echo "trust $arg"; echo "connect $arg"; sleep 7; echo quit ) | bluetoothctl >/dev/null 2>&1
    bluetoothctl info "$arg" | grep -E 'Paired|Connected' ;;
  bt-connect)
    mac_ok "$arg" || { echo BAD_MAC; exit 2; }
    [ -n "$DRY" ] && { echo "RUN connect $arg"; exit 0; }
    bluetoothctl --timeout 15 connect "$arg" 2>&1 | tail -3 ;;
  bt-disconnect)
    mac_ok "$arg" || { echo BAD_MAC; exit 2; }
    run bluetoothctl disconnect "$arg" ;;
  bt-remove)
    mac_ok "$arg" || { echo BAD_MAC; exit 2; }
    run bluetoothctl remove "$arg" ;;
  *) echo "UNKNOWN_COMMAND"; exit 2 ;;
esac
BLINKSYS
chmod 755 /usr/local/sbin/blink-sys
echo 'blink ALL=(root) NOPASSWD: /usr/local/sbin/blink-sys *' > /etc/sudoers.d/blink-sys.tmp
chmod 440 /etc/sudoers.d/blink-sys.tmp
visudo -cf /etc/sudoers.d/blink-sys.tmp >/dev/null && mv /etc/sudoers.d/blink-sys.tmp /etc/sudoers.d/blink-sys || { rm -f /etc/sudoers.d/blink-sys.tmp; exit 1; }
usermod -aG bluetooth blink 2>/dev/null
systemctl enable --now bluetooth 2>/dev/null; rfkill unblock bluetooth 2>/dev/null
# the clock: keep it synced, and move it off UTC to Eastern unless someone already chose another zone
timedatectl set-ntp true 2>/dev/null
[ "$(timedatectl show -p Timezone --value 2>/dev/null)" = "Etc/UTC" -o "$(timedatectl show -p Timezone --value 2>/dev/null)" = "UTC" ] && timedatectl set-timezone America/New_York 2>/dev/null
systemctl restart systemd-timesyncd 2>/dev/null
exit 0

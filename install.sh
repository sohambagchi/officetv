#!/usr/bin/env bash
# Recreate the officetv setup: Waydroid + Android TV (LineageOS, GAPPS) images,
# a kiosk-style TV config for always-on Spotify, and the `officetv` CLI.
#
# Run as your normal user (not root); it calls sudo where needed. Safe to rerun,
# and it should be rerun after upgrading the waydroid package.
#
#   ./install.sh [--autostart] [--fresh]
#   curl -fsSL <raw url of this file> | bash -s -- [--autostart]
#
# --fresh wipes Android (apps, sign-ins, images) and reinstalls the waydroid
# package first, i.e. behaves as on a new machine.
set -euo pipefail

REPO_URL="${OFFICETV_REPO:-https://github.com/sohambagchi/officetv.git}"
OTA="${OFFICETV_OTA:-https://waydroid-atv.github.io/ota/a16-tv}"
SYSTEM_TYPE="${OFFICETV_SYSTEM_TYPE:-GAPPS}" # Play Store is needed for Spotify
NET_SCRIPT=/usr/lib/waydroid/data/scripts/waydroid-net.sh
AUTOSTART=0
FRESH=0
for arg in "$@"; do
  case $arg in
    --autostart) AUTOSTART=1 ;;
    --fresh) FRESH=1 ;;
    *) echo "usage: install.sh [--autostart] [--fresh]" >&2; exit 1 ;;
  esac
done

say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
die() { printf 'install.sh: %s\n' "$*" >&2; exit 1; }

# When piped from curl there is no checkout next to us: clone and re-exec.
SRC="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
if [[ ! -f $SRC/officetv || ! -f $SRC/flake.nix ]]; then
  SRC="${XDG_DATA_HOME:-$HOME/.local/share}/officetv"
  command -v git >/dev/null || die "git is required"
  if [[ -d $SRC/.git ]]; then git -C "$SRC" pull --ff-only; else git clone "$REPO_URL" "$SRC"; fi
  exec bash "$SRC/install.sh" "$@"
fi

[[ $EUID -ne 0 ]] || die "run as your normal user, not root"
[[ $(uname -m) == x86_64 ]] || die "only x86_64 TV images are published"

say "Checking kernel support"
if ! grep -qw binder /proc/filesystems; then
  sudo modprobe binder_linux 2>/dev/null || true
  grep -qw binder /proc/filesystems ||
    die "kernel has no binder support (CONFIG_ANDROID_BINDERFS); install a kernel with it, e.g. linux-zen or xanmod"
fi
[[ -n ${WAYLAND_DISPLAY:-} || -S /run/user/$(id -u)/wayland-0 ]] ||
  echo "warning: no Wayland session found; Waydroid needs one (GNOME/KDE/sway) to show the TV"

if [[ $FRESH == 1 ]] && command -v waydroid >/dev/null; then
  say "Wiping the existing Waydroid install (--fresh)"
  waydroid session stop >/dev/null 2>&1 || true
  sudo systemctl stop waydroid-container || true
  sudo rm -rf /var/lib/waydroid "$HOME/.local/share/waydroid"
  rm -f "$HOME"/.local/share/applications/waydroid.*.desktop
  # Restores the stock waydroid-net.sh, so the networking check below is exercised.
  if command -v apt-get >/dev/null; then sudo apt-get install -y --reinstall waydroid; fi
fi

say "Installing Waydroid"
if ! command -v waydroid >/dev/null; then
  command -v apt-get >/dev/null ||
    die "install waydroid with your distro's package manager (https://docs.waydro.id), then rerun"
  sudo apt-get install -y curl ca-certificates
  curl -fsSL https://repo.waydro.id | sudo bash
  sudo apt-get install -y waydroid
fi
waydroid --version

say "Checking container networking"
# Kernels without CONFIG_NETFILTER_XTABLES_LEGACY can't run iptables-legacy, which
# waydroid-net.sh prefers whenever it is installed. Switch the script to nftables.
if command -v iptables-legacy >/dev/null && ! sudo iptables-legacy -w -L -n >/dev/null 2>&1; then
  command -v nft >/dev/null || sudo apt-get install -y nftables
  sudo sed -i 's/^LXC_USE_NFT="false"/LXC_USE_NFT="true"/' "$NET_SCRIPT"
  echo "legacy iptables unavailable: waydroid-net.sh switched to nftables"
else
  echo "ok"
fi

say "Installing Android TV images ($SYSTEM_TYPE)"
cfg=/var/lib/waydroid/waydroid.cfg
want="$OTA/system/lineage/waydroid_x86_64/$SYSTEM_TYPE.json"
if [[ -f $cfg ]] && grep -q "^system_ota = $want$" "$cfg" && [[ -f /var/lib/waydroid/images/system.img ]]; then
  echo "already initialised"
else
  waydroid session stop >/dev/null 2>&1 || true
  sudo waydroid init -f -s "$SYSTEM_TYPE" -c "$OTA/system" -v "$OTA/vendor"
fi
sudo systemctl enable --now waydroid-container

say "Installing the officetv command"
if command -v nix >/dev/null; then
  # Profile entries are named after the checkout directory; replace to pick up changes.
  nix --extra-experimental-features 'nix-command flakes' profile remove "$(basename "$SRC")" >/dev/null 2>&1 || true
  nix --extra-experimental-features 'nix-command flakes' profile add "path:$SRC"
  OFFICETV="$HOME/.nix-profile/bin/officetv"
else
  command -v adb >/dev/null || { command -v apt-get >/dev/null && sudo apt-get install -y adb; } ||
    die "install adb (android-tools), then rerun"
  install -Dm755 "$SRC/officetv" "$HOME/.local/bin/officetv"
  OFFICETV="$HOME/.local/bin/officetv"
fi
echo "$OFFICETV"

say "Starting the TV"
"$OFFICETV" start
"$OFFICETV" adb start-server >/dev/null 2>&1 || true # creates ~/.android/adbkey

say "Configuring Android TV"
# Trust this user's adb key, skip the remote-pairing setup wizard, never sleep.
sudo waydroid shell -- sh -c "
mkdir -p /data/misc/adb
grep -qF '$(cat "$HOME/.android/adbkey.pub")' /data/misc/adb/adb_keys 2>/dev/null ||
  echo '$(cat "$HOME/.android/adbkey.pub")' >> /data/misc/adb/adb_keys
chmod 640 /data/misc/adb/adb_keys; chown system:shell /data/misc/adb/adb_keys

settings put global device_provisioned 1
settings put secure user_setup_complete 1
settings put secure tv_user_setup_complete 1
for p in \$(pm list packages | sed 's/package://' | grep -iE 'setupwraith|tvsetup|setupwizard'); do
  pm disable-user --user 0 \$p >/dev/null || true
done

settings put global stay_on_while_plugged_in 7
settings put system screen_off_timeout 2147483647
settings put secure sleep_timeout -1
settings put secure attentive_timeout -1
settings put secure screensaver_enabled 0
settings put secure screensaver_activate_on_sleep 0

am start -a android.intent.action.MAIN -c android.intent.category.HOME >/dev/null 2>&1
"
# Don't freeze Android when the window loses focus (must run as the session user).
waydroid prop set persist.waydroid.suspend false

if [[ $AUTOSTART == 1 ]]; then
  say "Enabling autostart at login"
  mkdir -p "$HOME/.config/systemd/user"
  cat > "$HOME/.config/systemd/user/officetv.service" <<EOF
[Unit]
Description=officetv: Waydroid Android TV session
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$OFFICETV start
ExecStop=$OFFICETV stop
TimeoutStartSec=180

[Install]
WantedBy=graphical-session.target
EOF
  systemctl --user daemon-reload
  systemctl --user enable officetv.service
fi

say "Remaining manual steps"
gsf=$(sudo waydroid shell -- sh -c \
  "sqlite3 /data/data/com.google.android.gsf/databases/gservices.db \"select value from main where name = 'android_id';\"" 2>/dev/null || true)
pm=$("$OFFICETV" adb shell pm list packages com.spotify.tv.android 2>/dev/null || true)
if [[ -n $pm ]]; then
  echo "Spotify is installed. Pick this TV from Spotify Connect on your phone."
else
  cat <<EOF
1. Register this device with Google so Play Store sign-in works:
     https://www.google.com/android/uncertified  ->  ${gsf:-<run this script again once the TV has booted>}
   (approval can take up to an hour)
2. In the TV window: sign in to Play Store with the keyboard, install Spotify, sign in.
3. On your phone, pick the TV in Spotify Connect.
EOF
  "$OFFICETV" adb shell am start -a android.intent.action.VIEW \
    -d market://details?id=com.spotify.tv.android >/dev/null 2>&1 || true
fi
echo
echo "Done. Try: officetv status"

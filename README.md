# officetv

An always-on Android TV for Spotify, running in [Waydroid](https://waydro.id) on a Linux desktop,
plus a small `officetv` CLI to control it from any shell (including over SSH).

Uses the LineageOS Android TV images from [waydroid-atv](https://waydroid-atv.github.io)
(Android 16, GAPPS build so the Play Store and Spotify work).

## Install

```sh
git clone https://github.com/sohambagchi/officetv.git && cd officetv
./install.sh --autostart      # --autostart: start the TV at graphical login
```

or in one line:

```sh
curl -fsSL https://raw.githubusercontent.com/sohambagchi/officetv/main/install.sh | bash -s -- --autostart
```

Run it as your normal user; it asks for sudo. It is idempotent, so rerun it after upgrading the
`waydroid` package (the upgrade reverts the networking fix below). It:

1. checks the kernel has binder support and installs Waydroid (Debian/Ubuntu via repo.waydro.id;
   elsewhere install Waydroid yourself first);
2. switches Waydroid's container networking to nftables if `iptables-legacy` can't run
   (kernels without `CONFIG_NETFILTER_XTABLES_LEGACY`);
3. initialises the Android TV images;
4. installs `officetv` (into your Nix profile if Nix is available, otherwise `~/.local/bin` with
   the system `adb`);
5. boots the TV, trusts your adb key, skips the remote-pairing setup wizard, and disables sleep,
   the screensaver and Waydroid's freeze-on-unfocus.

Then, once per machine: register the printed device ID at
<https://www.google.com/android/uncertified>, sign in to the Play Store in the TV window with the
keyboard, install Spotify, and pick the TV from Spotify Connect on your phone.

Requirements: x86_64, a Wayland desktop session (GNOME, KDE, sway, ...), a kernel with binder.

Environment overrides: `OFFICETV_OTA` (image channel), `OFFICETV_SYSTEM_TYPE` (`GAPPS`, `VANILLA`,
`FOSS`), `OFFICETV_REPO` (clone URL for the curl install).

## Usage

```
officetv start | stop | restart       restart also recovers a dead container
officetv restart spotify
officetv play | pause | next | prev
officetv mute | unmute
officetv volume [0-100]               set or show Android media volume
officetv status
officetv adb <args>                   adb against the TV, e.g. officetv adb shell
```

Without installing: `nix run github:sohambagchi/officetv -- status`.

## Notes

- Don't restart Android from its own settings: that stops the container and Waydroid doesn't
  bring it back. Use `officetv restart`.
- `officetv volume` steps with volume keys because `media_session volume --set` writes the
  headphone profile, not the active output.
- Audio goes to the host's default PipeWire/PulseAudio sink.

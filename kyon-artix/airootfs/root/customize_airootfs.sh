#!/usr/bin/env bash
set -e -u

# Runs at build time inside the airootfs chroot, AFTER packages are installed.
# This version is adapted for Artix Linux with dinit init system.

pacman-key --init
pacman-key --populate archlinux artix

# ── Enable dinit services for the live ISO ────────────────────────────────
# The -dinit packages (bluez-dinit, cups-dinit, etc.) install their service
# files directly to /etc/dinit.d/ — they are already enabled.
# Only services that ship in /usr/lib/dinit.d/ need manual symlinking.
# sshd is created manually in /etc/dinit.d/sshd via the airootfs overlay.

enable_dinit() {
    local svc="$1"
    local src="/usr/lib/dinit.d/$svc"
    local dst="/etc/dinit.d/$svc"
    if [ -f "$src" ] && [ ! -e "$dst" ]; then
        ln -sf "$src" "$dst"
        echo "enabled dinit service: $svc"
    fi
}

# Core live-ISO services
# networkmanager-dinit, sddm-dinit, bluez-dinit, cups-dinit, avahi-dinit
# install directly to /etc/dinit.d/ — already enabled.
# sshd is in /etc/dinit.d/sshd (from our airootfs overlay) — already enabled.
# Verify they're all present:
for svc in networkmanager sddm bluetoothd cupsd avahi-daemon sshd; do
    if [ ! -e "/etc/dinit.d/$svc" ]; then
        echo "WARNING: dinit service '$svc' not found in /etc/dinit.d/" >&2
    fi
done

# ── Calamares modules ────────────────────────────────────────────────────
# Artix's stock calamares build already ships the modules this settings.conf
# needs (shellprocess, partition, unpackfs, users, umount, packages, welcome,
# summary, initcpiocfg, localecfg). No EndeavourOS full-module overlay is
# used here, unlike the systemd build.

# Artix's stock calamares build ships these modules. Unlike the EndeavourOS
# build, it does NOT ship services-systemd (we use shellprocess@dinit instead),
# so it is intentionally not part of this list.
for m in shellprocess partition unpackfs users umount packages welcome summary initcpiocfg localecfg; do
  [ -d "/usr/lib/calamares/modules/$m" ] || {
    echo "FATAL: calamares module '$m' missing after full-module install" >&2
    exit 1
  }
done

# Replace the stock /etc/calamares configs with the Kyon ones.
rm -rf /etc/calamares
cp -a /root/kyon-calamares-configs /etc/calamares
rm -rf /root/kyon-calamares-configs

# ── Skel / dotfiles ───────────────────────────────────────────────────────
install -Dm644 /root/dotfiles/.zshrc /etc/skel/.zshrc
rm -rf /root/dotfiles

# Give the live root session the same dotfiles as /etc/skel.
cp -a /etc/skel/. /root/

# Oh My Zsh setup for the live session (non-fatal if offline).
if [ -x /bin/zsh ] && command -v curl >/dev/null 2>&1 && command -v git >/dev/null 2>&1; then
    CHSH=no RUNZSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" || true
    if [ -d /root/.oh-my-zsh ]; then
        omz_plugins="/root/.oh-my-zsh/custom/plugins"
        mkdir -p "$omz_plugins"
        for p in zsh-autosuggestions zsh-syntax-highlighting; do
            [ -d "/usr/share/zsh/plugins/$p" ] && ln -sfn "/usr/share/zsh/plugins/$p" "$omz_plugins/$p"
        done
        if [ ! -e "$omz_plugins/fast-syntax-highlighting" ]; then
            git clone --depth 1 https://github.com/zdharma-continuum/fast-syntax-highlighting \
                "$omz_plugins/fast-syntax-highlighting" &>/dev/null || true
        fi
    fi
fi

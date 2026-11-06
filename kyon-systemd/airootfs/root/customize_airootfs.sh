#!/usr/bin/env bash
set -e -u

# Runs at build time inside the airootfs chroot, AFTER the `calamares` package
# has been installed (it comes from the [endeavouros] repo; the kyonrepo
# does not carry calamares).
#
# WHY this extra step exists:
#   The EndeavourOS *release* calamares package (26.03.2.3) is built with only
#   a subset of the fork's modules. It ships 32 modules and is MISSING
#   shellprocess, partition, unpackfs, users, umount, packages, welcome,
#   summary and services-systemd - i.e. almost everything Kyon's
#   /etc/calamares/settings.conf uses (including the shellprocess job that
#   installs the bootloader). With the release package alone, Calamares fails
#   at startup with "Module X not found in module search paths" (the
#   "bootloader" step included), so the installer errors out constantly.
#
#   EndeavourOS's own ISO never uses the release package on its own: it
#   overlays a full-module build (their "calamares-git" devel package, built
#   from the same fork with all modules enabled) over it. We do the same here:
#   download that full build and install it over the release package BEFORE
#   copying the Kyon configs below.
#
# NOTE on ordering: the devel package also installs its own /etc/calamares
# files (EOS settings_*.conf, module configs and scripts). The Kyon configs
# must therefore be copied LAST, which the block at the bottom does.
pacman-key --init
pacman-key --populate archlinux endeavouros cachyos chaotic 2>/dev/null || true

# Prefer the EOS full-module Calamares build when its package is still cached
# locally. The release/nyarch installs do not provide the packagechooser or
# netinstall modules, which would leave the installer without desktop
# selection, package choice and bootloader selection pages.
if [ -f /var/cache/pacman/pkg/calamares-26.03.2.3-1-any.pkg.tar.zst ]; then
    echo "Found cached EOS calamares; upgrading installer over nyarch package"
    # Use -U with --overwrite to force the full-module build over the release package
    if pacman -U --overwrite '*' --noconfirm /var/cache/pacman/pkg/calamares-26.03.2.3-1-any.pkg.tar.zst; then
        echo "Successfully upgraded calamares to full-module version"
    else
        echo "WARNING: pacman -U failed to upgrade calamares. Installer may be broken." >&2
    fi
else
    echo "ERROR: /var/cache/pacman/pkg/calamares-26.03.2.3-1-any.pkg.tar.zst is missing" >&2
    echo "       interactive packagechooser desktop/bootloader/package selection cannot be provided" >&2
    echo "       Restore the cached EOS calamares package before building." >&2
    exit 1
fi

# Sanity check: every module settings.conf relies on must now exist. Fail the
# build loudly instead of silently producing an ISO whose installer cannot run.
for m in shellprocess packagechooser netinstall partition unpackfs users umount packages welcome summary services-systemd initcpiocfg localecfg; do
  [ -d "/usr/lib/calamares/modules/$m" ] || {
    echo "FATAL: calamares module '$m' missing after full-module install - the installer would be broken" >&2
    exit 1
  }
done

# Replace the stock /etc/calamares configs (from the calamares package) with
# the Kyon Linux ones. This must run AFTER the full-module install so the
# Kyon configs win over the package's own /etc/calamares files.
rm -rf /etc/calamares
cp -a /root/kyon-calamares-configs /etc/calamares

# If the cached EOS full-module installer is available, activate the
# interactive settings (packagechooser + netinstall + bootloader pages).
if [ -f /var/cache/pacman/pkg/calamares-26.03.2.3-1-any.pkg.tar.zst ]; then
    echo "Found cached EOS calamares; enabling interactive installer settings"
    cp -f /root/kyon-calamares-configs/settings-full.conf /etc/calamares/settings.conf 2>/dev/null || true
fi

# Keep a copy/symlink in /root as well for compatibility with setups that look there
rm -rf /root/kyon-calamares-configs
cp -a /etc/calamares /root/kyon-calamares-configs 2>/dev/null || ln -sf /etc/calamares /root/kyon-calamares-configs 2>/dev/null || true

# Install Kyon's custom /etc/skel/.zshrc AFTER packages are installed. It must
# not be present during the package install step: grml-zsh-config ships the
# same path, and pacman's file-conflict check aborts the transaction instead
# of consulting NoExtract. Ship the custom file in the airootfs under
# /root/dotfiles and install it here once that collision window is over.
if [ -f /root/dotfiles/.zshrc ]; then
    install -Dm644 /root/dotfiles/.zshrc /etc/skel/.zshrc
    rm -rf /root/dotfiles
else
    echo 'WARNING: /root/dotfiles/.zshrc missing; keeping whatever is already in /etc/skel/.zshrc' >&2
fi

# Give the live root session (SDDM autologin -> Plasma) the same zsh config as
# /etc/skel. The live ISO is the first place the user sees the setup, and
# without this /root would keep the package's .zshrc instead of Kyon's custom
# one. Other /etc/skel contents are copied separately below.
install -Dm644 /etc/skel/.zshrc /root/.zshrc

# Mirror the rest of /etc/skel into /root so the live root session gets the
# same dotfiles as new users created during install (kitty, zsh, ...).
cp -a /etc/skel/. /root/

# The live root session also needs the Oh My Zsh + plugin setup that
# shell-setup applies to new users during install (the .zshrc sources
# ~/.oh-my-zsh and starship/fastfetch binaries). Mirror it here so the live
# ISO's zsh prompt works, not just the installed system. Non-fatal: a build
# without network must not fail because of this.
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

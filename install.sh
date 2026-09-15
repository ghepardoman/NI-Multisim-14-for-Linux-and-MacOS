#!/bin/bash
# Automated Multisim 14.3 installer (Wine)
# Authors: Giovanni De Rosa, Lorenzo Pappalardo
# Description: Downloads NI's official online installer for Multisim 14.3
#              (Educational or Professional) and sets it up under Wine.
#
# NOTE ON THIS VERSION:
#   - No patched installer folder needed anymore - this pulls the real
#     installer straight from NI's servers.
#   - The actual install steps are still a single unified method with no
#     distro branching. The only distro-aware logic is (a) checking that
#     required tools/packages are present and (b) checking whether Wine
#     itself is recent enough, since old distro-packaged Wine builds
#     (e.g. Ubuntu/Mint's apt package) are known to crash on this installer.
#   - Wine, winetricks, cabextract, wget and git must already be installed.

set -e # Exit on errors
exec </dev/tty

echo "============================================================================================"
echo "   'NI Multisim 14.3 for Linux'  Copyright (C)  2026  Giovanni De Rosa, Lorenzo Pappalardo"
echo "   This program comes with ABSOLUTELY NO WARRANTY; for details type 'show w'."
echo "   This is free software, and you are welcome to redistribute it"
echo "   under certain conditions; type 'show c' for details."
echo "============================================================================================"
echo

while true; do
  read -p "Do you wish to see the warranty or the license details [w/c; press Enter to skip]: " GPL_choice

  if [[ -z "$GPL_choice" ]]; then
    break

  elif [[ "$GPL_choice" =~ ^[Ww]$ ]]; then
    echo "THERE IS NO WARRANTY FOR THE PROGRAM, TO THE EXTENT PERMITTED BY"
    echo "APPLICABLE LAW.  EXCEPT WHEN OTHERWISE STATED IN WRITING THE COPYRIGHT"
    echo "HOLDERS AND/OR OTHER PARTIES PROVIDE THE PROGRAM 'AS IS' WITHOUT WARRANTY"
    echo "OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO,"
    echo "THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR"
    echo "PURPOSE.  THE ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE PROGRAM"
    echo "IS WITH YOU.  SHOULD THE PROGRAM PROVE DEFECTIVE, YOU ASSUME THE COST OF"
    echo "ALL NECESSARY SERVICING, REPAIR OR CORRECTION."
    echo
    echo

  elif [[ "$GPL_choice" =~ ^[Cc]$ ]]; then
    echo "This program is free software: you can redistribute it and/or modify"
    echo "it under the terms of the GNU General Public License as published by"
    echo "the Free Software Foundation, either version 3 of the License, or"
    echo "(at your option) any later version."
    echo
    echo
    echo "You must provide source code and preserve this license when conveying"
    echo "modified or unmodified versions."
    echo
    echo

  else
    echo "Invalid input. Press Enter with no input to skip."
    echo
    echo
  fi
done

echo "=============================="
echo "  Multisim 14.3 Installer"
echo "=============================="
echo

# ──────────────────────────────────────────────
# CONFIG
# ──────────────────────────────────────────────
export WINEPREFIX="${WINEPREFIX:-$HOME/.multisim143}"
# No WINEARCH override: standard 64-bit prefix with WoW64 support.
# Dedicated prefix (not the default ~/.wine) so this never touches/depends
# on other Wine apps, and every run starts from known state.

MIN_RECOMMENDED_WINE_VERSION="11.0"

# All the noisy/verbose command output goes here instead of the terminal,
# unless the user opts into verbose mode below.
LOGFILE="/tmp/multisim143-install-full.log"
: >"$LOGFILE"
VERBOSE=false

step() {
  echo "==> $*"
}

# Runs a command, sending its output either to the terminal (verbose mode)
# or to $LOGFILE (default). Use this for anything noisy.
run() {
  if $VERBOSE; then
    "$@"
  else
    "$@" >>"$LOGFILE" 2>&1
  fi
}

# True if this is a Debian/Ubuntu-family distro (Ubuntu, Mint, Pop!_OS,
# elementary, etc.) - checked via both ID and ID_LIKE since derivatives
# like Linux Mint report ID=linuxmint, not ID=ubuntu.
is_debian_based() {
  [ -f /etc/os-release ] || return 1
  local id id_like
  id="$(. /etc/os-release && echo "$ID")"
  id_like="$(. /etc/os-release && echo "${ID_LIKE:-}")"
  echo "$id $id_like" | grep -qiE 'ubuntu|debian'
}

# ──────────────────────────────────────────────
# PREREQUISITES
# (installing these is out of scope for this script)
# ──────────────────────────────────────────────
check_prerequisites() {
  # On Debian/Ubuntu-family distros, Wine can come from two different
  # sources: the distro's own "wine"/"wine32"/"wine64" packages, or the
  # WineHQ repo's "winehq-stable"/"-devel"/"-staging" meta-packages (which
  # install to /opt/wine-*/bin, not /usr/bin - so plain 'wine' won't resolve
  # unless that directory is on $PATH). Do this detection FIRST, before
  # checking for the "wine" command, otherwise a WineHQ-only install looks
  # like "wine is missing" just because $PATH hasn't been fixed up yet.
  if is_debian_based; then
    local distro_wine_installed=false winehq_installed=false winehq_dir="" pkg
    for pkg in wine wine32 wine64; do
      dpkg -s "$pkg" &>/dev/null && distro_wine_installed=true
    done
    for pkg in stable devel staging; do
      if dpkg -s "winehq-$pkg" &>/dev/null; then
        winehq_installed=true
        winehq_dir="/opt/wine-$pkg/bin"
      fi
    done

    if $winehq_installed && $distro_wine_installed; then
      echo "❌ Both a WineHQ package (winehq-stable/devel/staging) and the distro's own"
      echo "   wine/wine32/wine64 packages are installed at the same time. Whichever one"
      echo "   ends up first on \$PATH is the one that actually runs - silently - which"
      echo "   makes this script's behavior unpredictable."
      echo "   Remove the distro packages and keep the WineHQ build:"
      echo "     sudo apt remove --purge wine wine32 wine64"
      echo "   Then re-run this script."
      exit 1
    fi

    if $winehq_installed && [ -d "$winehq_dir" ]; then
      case ":$PATH:" in
      *":$winehq_dir:"*) ;; # already on PATH
      *) export PATH="$winehq_dir:$PATH" ;;
      esac
    fi
  fi

  local missing=()
  for cmd in wget git wine winetricks cabextract curl unzip; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
  done

  if [ ${#missing[@]} -gt 0 ]; then
    echo "❌ Missing required tools: ${missing[*]}"
    echo "   Install them with your distro's package manager, then re-run this script."
    exit 1
  fi

  if is_debian_based && ! $winehq_installed && ! $distro_wine_installed; then
    echo "⚠️  Debian/Ubuntu-family distro detected, but Wine doesn't appear to come from"
    echo "   either the distro's wine/wine32/wine64 packages or a WineHQ package - if"
    echo "   something goes wrong, that's worth double-checking."
    echo
  fi

  echo "✅ wget, git, wine, winetricks, cabextract, curl and unzip are all available."
  echo
}

check_prerequisites

# ──────────────────────────────────────────────
# WINE VERSION CHECK
# ──────────────────────────────────────────────
# Old distro-packaged Wine builds (e.g. Ubuntu/Mint's apt "wine" package,
# which lags well behind WineHQ's own releases) are known to crash on this
# installer with unhandled exceptions coming from a Wine/vkd3d shader
# compiler bug in the WPF rendering path. If we detect an old version:
#   - On Debian/Ubuntu-family distros, offer to switch to the official
#     WineHQ repo and install winehq-stable instead.
#   - On everything else, just warn and point the user at winehq.org.
check_wine_version() {
  local raw major_minor smallest already_on_winehq=false

  raw="$(wine --version 2>/dev/null || true)"
  major_minor="$(echo "$raw" | grep -oE '[0-9]+\.[0-9]+' | head -n1)"

  if is_debian_based && dpkg -s winehq-stable &>/dev/null; then
    already_on_winehq=true
  fi

  if [ -z "$major_minor" ]; then
    echo "⚠️  Could not determine your Wine version (got: '$raw'). Skipping the version check."
    echo
    return
  fi

  smallest="$(printf '%s\n%s\n' "$MIN_RECOMMENDED_WINE_VERSION" "$major_minor" | sort -V | head -n1)"

  if [ "$smallest" = "$major_minor" ] && [ "$major_minor" != "$MIN_RECOMMENDED_WINE_VERSION" ]; then
    echo "⚠️  Your Wine version ($raw) looks old (older than $MIN_RECOMMENDED_WINE_VERSION)."
    echo "   Old Wine builds - especially the ones shipped in distro apt repos - are known to"
    echo "   crash partway through this installer due to a Wine shader-compiler bug."
    echo

    if is_debian_based && ! $already_on_winehq; then
      read -rp "   Switch to the official WineHQ repository and install winehq-stable now? [y/N]: " wine_upgrade_choice
      if [[ "$wine_upgrade_choice" =~ ^[Yy]$ ]]; then
        install_winehq_stable
      else
        echo "   Skipping. You can do this later yourself - see https://www.winehq.org/download"
        echo
      fi
    else
      echo "   Recommended: update Wine using your distro's package manager, or install the"
      echo "   latest build from https://www.winehq.org/download"
      echo
    fi
  fi
}

install_winehq_stable() {
  local id ubuntu_codename version_codename base_distro codename

  id="$(. /etc/os-release && echo "$ID")"
  ubuntu_codename="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-}")"
  version_codename="$(. /etc/os-release && echo "${VERSION_CODENAME:-}")"

  # Ubuntu derivatives (Mint, Pop!_OS, etc.) expose UBUNTU_CODENAME for the
  # underlying Ubuntu base - that's what WineHQ's repo needs, not the
  # derivative's own codename.
  if [ -n "$ubuntu_codename" ]; then
    base_distro="ubuntu"
    codename="$ubuntu_codename"
  elif [ "$id" = "debian" ]; then
    base_distro="debian"
    codename="$version_codename"
  else
    base_distro="ubuntu"
    codename="$version_codename"
  fi

  if [ -z "$codename" ]; then
    echo "   ❌ Could not determine your distro's codename - please install winehq-stable"
    echo "      manually following https://wiki.winehq.org/Download"
    return
  fi

  step "Adding the WineHQ apt repository ($base_distro/$codename)"
  sudo mkdir -pm755 /etc/apt/keyrings
  sudo wget -O /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key
  sudo wget -NP /etc/apt/sources.list.d/ \
    "https://dl.winehq.org/wine-builds/${base_distro}/dists/${codename}/winehq-${codename}.sources"

  step "Installing winehq-stable"
  sudo dpkg --add-architecture i386
  sudo apt update
  sudo apt install --install-recommends -y winehq-stable

  if dpkg -s wine &>/dev/null || dpkg -s wine32 &>/dev/null || dpkg -s wine64 &>/dev/null; then
    step "Removing the distro's own wine/wine32/wine64 (avoids a PATH conflict with winehq-stable)"
    sudo apt remove --purge -y wine wine32 wine64 2>/dev/null || true
  fi

  echo "✅ winehq-stable installed."
  echo "   Add this to your shell (and re-run the script) so the right 'wine' is used:"
  echo "     export PATH=\"/opt/wine-stable/bin:\$PATH\""
  echo
  export PATH="/opt/wine-stable/bin:$PATH"
}

check_wine_version

# ──────────────────────────────────────────────
# VERBOSITY / DURATION NOTICE
# ──────────────────────────────────────────────
echo "ℹ️  Heads up: the full install (Wine setup, .NET, the NI installer itself, and the"
echo "   database engine components) can take quite a while depending on your connection"
echo "   and machine - please be patient."
echo
read -rp "Show the full Wine/winetricks output as it runs, instead of hiding it? [y/N]: " verbose_choice
if [[ "$verbose_choice" =~ ^[Yy]$ ]]; then
  VERBOSE=true
  echo "   Verbose mode on - you'll see raw Wine/winetricks output below."
else
  echo "   Output will be kept quiet; full logs are saved to $LOGFILE if you need them."
fi
echo

# ──────────────────────────────────────────────
# CREATE THE DEDICATED PREFIX
# ──────────────────────────────────────────────
step "Creating Wine prefix for Multisim at $WINEPREFIX"
run wineboot
echo

# ──────────────────────────────────────────────
# WORKING DIRECTORY
# ──────────────────────────────────────────────
WORKDIR="$(mktemp -d /tmp/multisim143_install.XXXXXX)"
cd "$WORKDIR" || exit 1
echo "Working directory: $WORKDIR"
echo

# ──────────────────────────────────────────────
# CHOOSE EDITION & DOWNLOAD THE OFFICIAL ONLINE INSTALLER
# ──────────────────────────────────────────────
choose_edition() {
  echo "Which Multisim 14.3 edition would you like to install?"
  echo "  1) Educational"
  echo "  2) Professional"
  read -rp "Enter choice [1/2]: " edition_choice

  case "$edition_choice" in
  1)
    INSTALLER_URL="https://download.ni.com/support/nipkg/products/ni-c/ni-cds-educational/14.3/online/ni-cds-educational_14.3_online.exe"
    INSTALLER_FILE="ni-cds-educational_14.3_online.exe"
    ;;
  2)
    INSTALLER_URL="https://download.ni.com/support/nipkg/products/ni-c/ni-cds-professional/14.3/online/ni-cds-professional_14.3_online.exe"
    INSTALLER_FILE="ni-cds-professional_14.3_online.exe"
    ;;
  *)
    echo "❌ Invalid choice."
    exit 1
    ;;
  esac

  step "Downloading $INSTALLER_FILE from NI"
  local wget_args=(-O "$INSTALLER_FILE" "$INSTALLER_URL")
  $VERBOSE || wget_args=(-q "${wget_args[@]}")
  run wget "${wget_args[@]}"
  echo
}

choose_edition

# ──────────────────────────────────────────────
# WINE PREFIX SETUP
# ──────────────────────────────────────────────
step "Running winetricks (corefonts, dotnet48)"
winetricks_args=(corefonts dotnet48)
$VERBOSE || winetricks_args=(-q "${winetricks_args[@]}")
run winetricks "${winetricks_args[@]}"
echo

set_winver_win10() {
  step "Setting Wine Windows version to 10"
  run wine winecfg -v win10
  echo
}

set_winver_win10

# ──────────────────────────────────────────────
# RUN THE NI ONLINE INSTALLER
# ──────────────────────────────────────────────
# Run through cmd's "start /wait" rather than invoking the exe directly:
# the installer's own "please reboot" prompt at the end otherwise leaves a
# Wine process sitting around forever and the script never gets control back.
step "Running the Multisim 14.3 online installer"
if $VERBOSE; then
  wine cmd /c "start /wait \"\" $INSTALLER_FILE" || true
else
  WINEDEBUG=-all wine cmd /c "start /wait \"\" $INSTALLER_FILE" >>"$LOGFILE" 2>&1 || true
fi

echo "Installer finished."
sleep 5

step "Stopping Wine"
wineserver -k || true
echo "Multisim installation stage complete."
echo

# ──────────────────────────────────────────────
# DATABASE ENGINE: MDAC 2.7 + JET 4.0
# (archived copies - Microsoft's original download links are dead)
# ──────────────────────────────────────────────
install_database_engine() {
  step "Downloading MDAC 2.7 and Jet 4.0 redistributables"
  local mdac_args=(-O MDAC_TYP.EXE "https://web.archive.org/web/20060718123742/http://ftp.gunadarma.ac.id/pub/driver/itegno/USB%20Software/MDAC/MDAC_TYP.EXE")
  local jet_args=(-O Jet40SP8_9xNT.exe "https://web.archive.org/web/20210225171713/http://download.microsoft.com/download/4/3/9/4393c9ac-e69e-458d-9f6d-2fe191c51469/Jet40SP8_9xNT.exe")
  $VERBOSE || mdac_args=(-q "${mdac_args[@]}")
  $VERBOSE || jet_args=(-q "${jet_args[@]}")
  run wget "${mdac_args[@]}"
  run wget "${jet_args[@]}"

  step "Installing MDAC 2.7"
  run wine MDAC_TYP.EXE

  step "Installing Jet 4.0"
  run wine Jet40SP8_9xNT.exe
  echo

  step "Extracting Jet 4.0 DLLs"
  mkdir -p /tmp/jet40
  pushd /tmp/jet40 >/dev/null

  run cabextract "$WORKDIR/Jet40SP8_9xNT.exe"
  run cabextract jetsetup.exe
  run cabextract jetsetup.cab

  mkdir -p "$WINEPREFIX/drive_c/windows/syswow64"
  mkdir -p "$WINEPREFIX/drive_c/Program Files/Common Files/Microsoft Shared/DAO"

  cp dao360.dll "$WINEPREFIX/drive_c/windows/syswow64/"
  cp msjet40.dll "$WINEPREFIX/drive_c/windows/syswow64/"
  cp msrd3x40.dll "$WINEPREFIX/drive_c/windows/syswow64/"

  step "Registering DLLs"
  run wine regsvr32 'C:\windows\syswow64\dao360.dll'
  run wine regsvr32 'C:\windows\syswow64\msjet40.dll'

  popd >/dev/null
  rm -rf /tmp/jet40
  echo "✅ Database engine setup complete."
  echo
}

install_database_engine

# ──────────────────────────────────────────────
# CLEANUP
# ──────────────────────────────────────────────
step "Cleaning up downloaded installer files"
cd "$HOME" || exit 1
rm -rf "$WORKDIR"

# ──────────────────────────────────────────────
# macOS: INSTALL THE MULTISIM.APP SHORTCUT
# ──────────────────────────────────────────────
# TODO: confirm/replace this with the actual raw download URL for
# multisim.app.zip from the repo's assets/multisim14-3/macOS folder.
MACOS_APP_ZIP_URL="https://github.com/ghepardoman/NI-Multisim-14-for-Linux-and-MacOS/raw/refs/heads/main/assets/macOS/multisim.app.zip"

install_macos_app() {
  step "Installing Multisim.app into /Applications"

  local tmpzip
  tmpzip="$(mktemp /tmp/multisim_app.XXXXXX.zip)"

  local curl_args=(-fL -o "$tmpzip" "$MACOS_APP_ZIP_URL")
  $VERBOSE || curl_args=(-s "${curl_args[@]}")
  if ! run curl "${curl_args[@]}"; then
    echo "⚠️  Could not download multisim.app.zip - skipping shortcut install."
    echo "    You can manually unzip it into /Applications/ later."
    rm -f "$tmpzip"
    return
  fi

  local tmpdir
  tmpdir="$(mktemp -d /tmp/multisim_app_extract.XXXXXX)"
  local unzip_args=(-o "$tmpzip" -d "$tmpdir")
  $VERBOSE || unzip_args=(-q "${unzip_args[@]}")
  run unzip "${unzip_args[@]}"

  local app_path
  app_path="$(find "$tmpdir" -maxdepth 2 -name '*.app' -print -quit)"

  if [ -z "$app_path" ]; then
    echo "⚠️  Could not find a .app bundle inside multisim.app.zip - skipping."
  else
    rm -rf "/Applications/$(basename "$app_path")"
    cp -R "$app_path" /Applications/
    echo "✅ Multisim shortcut installed to /Applications/$(basename "$app_path")."
  fi

  rm -f "$tmpzip"
  rm -rf "$tmpdir"
  echo
}

if [[ "$(uname -s)" == "Darwin" ]]; then
  install_macos_app
fi

echo
echo "======================================="
echo "✅ Multisim 14.3 installation complete!"
echo "   WINEPREFIX: $WINEPREFIX"
echo "A reboot of your machine is recommended"
echo "======================================="

read -rp "Do you want to restart the machine now? [y/N]: " answer

case "$answer" in
[Yy] | [Yy][Ee][Ss])
  echo "Restarting system..."
  sudo reboot
  ;;
*)
  echo "Restart skipped. You can reboot later manually."
  ;;
esac

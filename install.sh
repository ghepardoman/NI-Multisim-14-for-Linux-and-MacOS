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

[[ "$(uname -s)" == "Darwin" ]] && [[ "$(uname -m)" == arm64* || "$(sysctl -in hw.optional.arm64 2>/dev/null)" == "1" ]] && IS_MACOS_ARM64=true || IS_MACOS_ARM64=false
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
  if $IS_MACOS_ARM64; then
    local wine_bin wine_file_info
    wine_bin="$(command -v wine)"
    wine_file_info="$(file -b "$wine_bin" 2>/dev/null || true)"
    if [[ "$wine_file_info" != *arm64* ]]; then
      echo "❌ Apple Silicon (macOS arm64) detected, but Wine ($wine_bin) is not a native arm64 binary."
      echo "   Detected binary type: ${wine_file_info:-unknown}"
      echo "   A native arm64 Wine build with FEX-Emu and 4K page size support (e.g. MetalSharp-Wine) is required."
      exit 1
    fi
  fi

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
WINEDLLOVERRIDES=mscoree=d run wineboot
echo

# ──────────────────────────────────────────────
# WORKING DIRECTORY
# ──────────────────────────────────────────────
WORKDIR="$(mktemp -d /tmp/multisim143_install.XXXXXX)"
cd "$WORKDIR" || exit 1
echo "Working directory: $WORKDIR"
echo

# ──────────────────────────────────────────────
# CHOOSE EDITION & DOWNLOAD THE OFFICIAL INSTALLER
# ──────────────────────────────────────────────
download_online_installer() {
  case "$edition_choice" in
  1)
    INSTALLER_URL="https://download.ni.com/support/nipkg/products/ni-c/ni-cds-educational/14.3/online/ni-cds-educational_14.3_online.exe"
    INSTALLER_FILE="ni-cds-educational_14.3_online.exe"
    ;;
  2)
    INSTALLER_URL="https://download.ni.com/support/nipkg/products/ni-c/ni-cds-professional/14.3/online/ni-cds-professional_14.3_online.exe"
    INSTALLER_FILE="ni-cds-professional_14.3_online.exe"
    ;;
  esac

  step "Downloading $INSTALLER_FILE from NI"
  local wget_args=(-O "$INSTALLER_FILE" "$INSTALLER_URL")
  $VERBOSE || wget_args=(-q "${wget_args[@]}")
  run wget "${wget_args[@]}"
  echo
}

download_offline_installer() {
  case "$edition_choice" in
  1)
    INSTALLER_URL="https://download.ni.com/support/nipkg/products/ni-c/ni-cds-educational/14.3/offline/ni-cds-educational_14.3.0_offline.iso"
    INSTALLER_FILE="$HOME/ni-cds-educational_14.3.0_offline.iso"
    ;;
  2)
    INSTALLER_URL="https://download.ni.com/support/nipkg/products/ni-c/ni-cds-professional/14.3/offline/ni-cds-professional_14.3.0_offline.iso"
    INSTALLER_FILE="$HOME/ni-cds-professional_14.3.0_offline.iso"
    ;;
  esac

  if [ -f "$INSTALLER_FILE" ]; then
    step "Found existing ISO at $INSTALLER_FILE - skipping download"
    echo
    return
  fi

  step "Downloading $(basename "$INSTALLER_FILE") to $HOME from NI"
  local wget_args=(-O "$INSTALLER_FILE" "$INSTALLER_URL")
  $VERBOSE || wget_args=(-q "${wget_args[@]}")
  run wget "${wget_args[@]}"
  echo
}

choose_edition() {
  echo "Which Multisim 14.3 edition would you like to install?"
  echo "  1) Educational"
  echo "  2) Professional"
  read -rp "Enter choice [1/2]: " edition_choice

  case "$edition_choice" in
  1 | 2) ;;
  *)
    echo "❌ Invalid choice."
    exit 1
    ;;
  esac

  if $IS_MACOS_ARM64; then
    download_offline_installer
  else
    download_online_installer
  fi
}

choose_edition
# ──────────────────────────────────────────────
# ──────────────────────────────────────────────
# WINE PREFIX SETUP
# ──────────────────────────────────────────────
run_winetricks() {
  local args=("$@")
  $VERBOSE || args=(-q "${args[@]}")
  run winetricks "${args[@]}"
}

wine_prefix_setup() {
  step "Running winetricks (corefonts, dotnet48)"
  run_winetricks corefonts dotnet48
  echo
}

# Office PIA: extract only the seven legacy assemblies directly into the GAC
# without installing the MSI or running managed helper programs.
pia_metadata() {
  local name="$1" filename="$2" version="$3" token="$4" signature="$5" mvid="$6"
  printf '%s\r\n' \
    '[AssemblyInfo]' \
    "Signature=$signature" \
    "MVID=$mvid" \
    "URL=file:///C:/windows/assembly/GAC/$name/${version}__${token}/$filename" \
    "DisplayName=$name, Version=$version, Culture=neutral, PublicKeyToken=$token" ''
}

install_office_pia() {
  local dir="$WORKDIR/office-pia"
  local url='https://download.microsoft.com/download/C/1/D/C1D6DBBB-700D-4669-98CF-820AC3AE8E55/PIARedist.exe'
  local msi_win
  mkdir -p "$dir"
  step "Downloading Office 2010 Primary Interop Assemblies"
  run curl -fL --retry 3 -o "$dir/PIARedist.exe" "$url"
  run cabextract -d "$dir" "$dir/PIARedist.exe"
  msi_win=$(wine winepath -w "$dir/o2010pia.msi")

  step "Extracting embedded PIA cabinet (no MSI installation)"
  (cd "$dir" && WINEDEBUG=-all run wine msidb.exe -d "$msi_win" -x PIAREDIST.CAB)
  step "Extracting and installing Office PIA assemblies into GAC"
  install_pia_assembly "$dir" \
    "ADODB" "adodb.dll" "FL_adodb_dll_____X86.3643236F_FC70_11D3_A536_0090278A1BB8" \
    "7.0.3300.0" "b03f5f7f11d50a3a" \
    "e2bceb4817b7301863f7b2bc6f88d3668bcc942f" "25aad7bf29a3084a9a0ecbcc74338efe"
  install_pia_assembly "$dir" \
    "MSDATASRC" "msdatasrc.dll" "FL_msdatasrc_dll_____X86.3643236F_FC70_11D3_A536_0090278A1BB8" \
    "7.0.3300.0" "b03f5f7f11d50a3a" \
    "95cc2f0a0474c30729367a2bb77c3df98f4df945" "d8efdf9edbb0e04aa81029fe4ab3888d"
  install_pia_assembly "$dir" \
    "stdole" "stdole.dll" "stdole_dll_4_____X86.3643236F_FC70_11D3_A536_0090278A1BB8" \
    "7.0.3300.0" "b03f5f7f11d50a3a" \
    "d149e67e8b05b32835fea81b94ec3b9c7202ab8d" "8151f01db1e8e5419e16182d6b591d92"

  install_pia_assembly "$dir" \
    "Microsoft.StdFormat" "Microsoft.stdformat.dll" "FL_Microsoft_stdformat_dll_____X86.3643236F_FC70_11D3_A536_0090278A1BB8" \
    "7.0.3300.0" "b03f5f7f11d50a3a" \
    "508f28dd10e9ceaeead832451b771eaa01a11fc7" "8e52eb1fc766e24d9a8d26e37a63720e"

  install_pia_assembly "$dir" \
    "Extensibility" "extensibility.dll" "FL_extensibility_dll_____X86.3643236F_FC70_11D3_A536_0090278A1BB8" \
    "7.0.3300.0" "b03f5f7f11d50a3a" \
    "1fa9f788ec95fd8289a27ce679cc27bd1229113c" "e074f5a6d750b647ac049250c35aac75"

  install_pia_assembly "$dir" \
    "Microsoft.mshtml" "Microsoft.mshtml.dll" "FL_Microsoft_mshtml_dll_____X86.3643236F_FC70_11D3_A536_0090278A1BB8" \
    "7.0.3300.0" "b03f5f7f11d50a3a" \
    "558f255b2490c3bffc4c7c363eb09ee951516fec" "3c45a4ac22776244af35d1385b23eb22"

  install_pia_assembly "$dir" \
    "mscomctl" "mscomctl.dll" "mscomctl.dll.D0DF3458_A845_11D3_8D0A_0050046416B9" \
    "10.0.4504.0" "31bf3856ad364e35" \
    "80135593cc73a56bf43f02998db4feaee9eef251" "75d44e7ae8a0ef40bf4540ddbb718f15"
}
install_pia_assembly() {
  local dir="$1" name="$2" filename="$3" entry="$4" version="$5" token="$6" signature="$7" mvid="$8"
  local target="$WINEPREFIX/drive_c/windows/assembly/GAC/$name/${version}__${token}"

  mkdir -p "$target"
  run cabextract -d "$target" -F "$entry" "$dir/PIAREDIST.CAB"
  mv "$target/$entry" "$target/$filename"
  pia_metadata "$name" "$filename" "$version" "$token" "$signature" "$mvid" > "$target/__AssemblyInfo__.ini"
  $VERBOSE && echo "Installed: $target/$filename"
}
optimize_clr_stage() {
  local clr="$1" framework ngen_bin
  for framework in Framework64 Framework; do
    ngen_bin="$WINEPREFIX/drive_c/windows/Microsoft.NET/$framework/$clr/ngen.exe"
    if [[ -f "$ngen_bin" ]]; then
      step "Running NGen for $framework/$clr"
      run wine "$ngen_bin" executeQueuedItems || echo "Warning: NGen failed for $framework/$clr; continuing."
    else
      echo "Warning: NGen unavailable for $framework/$clr; skipping."
    fi
  done
}

install_netfx35() {
  step "Running winetricks (dotnet35sp1)"
  run_winetricks dotnet35sp1
  optimize_clr_stage "v2.0.50727"
  step "Stopping Wine"
  run wineserver -k || true
  run wineserver -w
}

wine_prefix_setup_fex() {
  step "Running winetricks (corefonts, vcrun2005, vcrun2008, vcrun2010, msxml6, gdiplus, wsh57)"
  run_winetricks corefonts vcrun2005 vcrun2008 vcrun2010 msxml6 gdiplus wsh57

  mkdir -p "$WINEPREFIX"
  grep -qxF "ucrtbase2019" "$WINEPREFIX/winetricks.log" 2>/dev/null || echo "ucrtbase2019" >> "$WINEPREFIX/winetricks.log"
  
  run wineserver -k || true
  run wineserver -w

  step "Running winetricks (vcrun2019)"
  run_winetricks vcrun2019

  install_office_pia
  install_netfx35

  step "Running winetricks (dotnet48)"
  run_winetricks dotnet48

  read -rp "Optimize .NET Framework 4.8 assemblies now (NGen)? [y/N]: " ngen_choice
  if [[ "$ngen_choice" =~ ^[Yy]$ ]]; then
    optimize_clr_stage "v4.0.30319"
  else
    step "Skipping NGen optimization for .NET Framework 4.8"
  fi

  step "Running winetricks (webview2)"
  run_winetricks webview2
  echo
}

if $IS_MACOS_ARM64; then
  wine_prefix_setup_fex
else
  wine_prefix_setup
fi
set_winver_win10() {
  step "Setting Wine Windows version to 10"
  run wine winecfg -v win10
  echo
}

set_winver_win10

# ──────────────────────────────────────────────
# RUN THE NI INSTALLER
# ──────────────────────────────────────────────
install_online() {
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
}

detect_disk_image_backend() {
  local version major
  version=$(sw_vers -productVersion) || return 1
  major=${version%%.*}
  if [[ ! "$major" =~ ^[0-9]+$ ]]; then
    echo "Invalid macOS version: $version" >&2
    return 1
  fi
  if (( major >= 27 )); then
    DISK_IMAGE_BACKEND=diskutil
  else
    DISK_IMAGE_BACKEND=hdiutil
  fi
  step "macOS $version: disk image backend $DISK_IMAGE_BACKEND"
}

# Detach only the mount point obtained from our image attachment.
detach_offline_iso() {
  if [[ -z "${ISO_MOUNT:-}" ]]; then
    return 0
  fi
  step "Unmounting ISO from $ISO_MOUNT"
  if [[ "$DISK_IMAGE_BACKEND" == diskutil ]]; then
    run diskutil eject "$ISO_MOUNT" || true
  else
    run hdiutil detach "$ISO_MOUNT" || true
  fi
  ISO_MOUNT=""
}

# diskutil attach returns a structured list of attached entities. It may
# report an existing mount rather than the requested mount point.
attach_diskutil_iso() {
  local target="$1" plist="$WORKDIR/attach.plist" i=0 mount
  if ! diskutil image attach --plist --readOnly --mountOptions nobrowse \
      --mountPoint "$target" "$ISO_PATH" >"$plist" 2>>"$LOGFILE"; then
    cat "$plist" >>"$LOGFILE"
    echo "diskutil could not attach the ISO; inspect $LOGFILE." >&2
    return 1
  fi
  cat "$plist" >>"$LOGFILE"
  while /usr/libexec/PlistBuddy -c "Print :system-entities:$i" "$plist" >/dev/null 2>&1; do
    mount=$(/usr/libexec/PlistBuddy -c "Print :system-entities:$i:mount-point" "$plist" 2>/dev/null) || mount=""
    if [[ -n "$mount" && -d "$mount" ]]; then
      ISO_MOUNT="$mount"
      step "Mounted ISO: $ISO_MOUNT"
      return 0
    fi
    i=$((i+1))
  done
  echo "diskutil returned no mounted entity; inspect $plist." >&2
  return 1
}

# Read hdiutil's structured output, matching the actual image path rather
# than guessing a volume name. PlistBuddy is shipped with macOS.
find_iso_mount() {
  local plist="$WORKDIR/images.plist" i=0 j image_path mount
  hdiutil info -plist > "$plist" || return 2
  while image_path=$(/usr/libexec/PlistBuddy -c "Print :images:$i:image-path" "$plist" 2>/dev/null); do
    if [[ "$image_path" == "$ISO_PATH" || "$image_path" -ef "$ISO_PATH" ]]; then
      j=0
      while /usr/libexec/PlistBuddy -c "Print :images:$i:system-entities:$j" "$plist" >/dev/null 2>&1; do
        mount=$(/usr/libexec/PlistBuddy -c "Print :images:$i:system-entities:$j:mount-point" "$plist" 2>/dev/null) || mount=""
        if [[ -n "$mount" && -d "$mount" ]]; then
          printf '%s\n' "$mount"
          return 0
        fi
        j=$((j+1))
      done
    fi
    i=$((i+1))
  done
  return 1
}

install_nipkg_vc2015() {
  local nipkg_src="$ISO_MOUNT/pool/ni-msvcrt-2015_14.1.5.49152-0+f0_windows_all.nipkg"
  local stage="$WORKDIR/ni-msvcrt-2015"
  local msi msi_path msi_win

  if [[ ! -f "$nipkg_src" ]]; then
    echo "❌ Could not find $nipkg_src inside mounted ISO." >&2
    return 1
  fi

  mkdir -p "$stage"
  step "Extracting NI VC2015 runtime package (.nipkg)"
  (cd "$stage" && run ar -x "$nipkg_src")
  run tar -xzf "$stage/data.tar.gz" -C "$stage"

  for msi in VC2015-32Wrapper.msi VC2015-64Wrapper.msi VC2015Core.msi; do
    msi_path="$(find "$stage" -name "$msi" -print -quit)"
    if [[ -z "$msi_path" ]]; then
      echo "❌ Missing $msi inside extracted data.tar.gz." >&2
      return 1
    fi
    msi_win="$(wine winepath -w "$msi_path")"
    step "Installing $msi"
    run wine msiexec /i "$msi_win" LicenseAccepted=1 /qf /norestart
  done
}

start_ni_offline_monitor() {
  local vbs_file="$WORKDIR/ni_monitor.vbs"
  MONITOR_FLAG="$WORKDIR/ni_monitor.flag"
  MONITOR_READY="${MONITOR_FLAG}.ready"
  local result_file="$WORKDIR/ni_monitor.result"
  local vbs_win flag_win result_win waited=0
  cat <<'VBS' > "$vbs_file"
Option Explicit

Dim wmi, fso, flag, result, started, idleSince
Dim seen, count, previous, proc, elapsed, lastBeat, out
Dim niSeen, name, idle, niName, processes, queryError
Dim previousNi, managerActive

Set wmi = GetObject("winmgmts:\\.\root\cimv2")
Set fso = CreateObject("Scripting.FileSystemObject")

flag = WScript.Arguments(0)
result = WScript.Arguments(1)

started = Now
idleSince = Empty
seen = False
niSeen = False
previous = -1
previousNi = False
lastBeat = Now

Set out = fso.CreateTextFile(flag & ".ready", True)
out.Close

WScript.Echo Now & " [NI] Waiting for NIPackageManager.exe"

Do While fso.FileExists(flag)

    count = 0
    niName = ""
    idle = 0

    On Error Resume Next
    Err.Clear

    Set processes = wmi.ExecQuery("SELECT Name FROM Win32_Process")

    If Err.Number = 0 Then
        For Each proc In processes
            name = ""

            If Not IsNull(proc.Name) Then name = LCase(proc.Name)

            If name = "nipackagemanager.exe" Then niName = name
            If name = "msiexec.exe" Then count = count + 1
        Next
    End If

    queryError = Err.Number
    On Error GoTo 0

    elapsed = DateDiff("s", started, Now)

    If queryError <> 0 Then

        idleSince = Empty
        WScript.Echo Now & " [NI] WMI error=" & queryError & "; idle reset"

    Else

        managerActive = (niName <> "")

        If Not niSeen And managerActive Then
            niSeen = True
            WScript.Echo Now & " [NI] NI Package Manager detected: " & niName
        End If

        If niSeen And count > 0 Then seen = True

        ' Track MSI inactivity in both scenarios.
        If niSeen And count = 0 And (seen Or managerActive) Then
            If IsEmpty(idleSince) Then idleSince = Now
            idle = DateDiff("s", idleSince, Now)
        Else
            idleSince = Empty
        End If

        If count <> previous Or managerActive <> previousNi Or Not IsEmpty(idleSince) Or DateDiff("s", lastBeat, Now) >= 30 Then
            WScript.Echo Now & " [NI] elapsed=" & elapsed & _
                " NI=" & niSeen & _
                " NIPMActive=" & managerActive & _
                " MSISeen=" & seen & _
                " MSI=" & count & _
                " idle=" & idle & "/50"

            previous = count
            previousNi = managerActive
            lastBeat = Now
        End If

        If niSeen And idle >= 50 Then

            If seen Then

                ' Normal installation scenario.
                If managerActive Then
                    WScript.Echo Now & " [NI] MSI idle threshold reached; NI Package Manager still active, waiting"
                Else
                    Set out = fso.CreateTextFile(result, True)
                    out.WriteLine "idle"
                    out.Close

                    WScript.Echo Now & " [NI] MSI idle threshold reached"
                    WScript.Quit 0
                End If

            ElseIf managerActive Then

                ' No MSI processes were started.
                Set out = fso.CreateTextFile(result, True)
                out.WriteLine "idle"
                out.Close

                WScript.Echo Now & " [NI] NI Package Manager idle without MSI activity"
                WScript.Quit 0

            End If

        End If

    End If

    If elapsed >= 10800 Then
        WScript.Echo Now & " [NI] timeout"
        WScript.Quit 6
    End If

    WScript.Sleep 10000

Loop

WScript.Echo Now & " [NI] cancelled by host"
WScript.Quit 7
VBS

  : > "$MONITOR_FLAG"
  rm -f "$MONITOR_READY" "$result_file"

  vbs_win="$(wine winepath -w "$vbs_file")"
  flag_win="$(wine winepath -w "$MONITOR_FLAG")"
  result_win="$(wine winepath -w "$result_file")"

  step "Starting NI Package Manager WMI monitor"
  if $VERBOSE; then
    wine cscript.exe //Nologo "$vbs_win" "$flag_win" "$result_win" &
  else
    WINEDEBUG=-all wine cscript.exe //Nologo "$vbs_win" "$flag_win" "$result_win" >>"$LOGFILE" 2>&1 &
  fi
  MONITOR_PID=$!

  while [[ ! -f "$MONITOR_READY" ]]; do
    if ! kill -0 "$MONITOR_PID" 2>/dev/null; then
      echo "❌ WMI monitor exited unexpectedly before signaling ready." >&2
      return 1
    fi
    if (( waited >= 60 )); then
      rm -f "$MONITOR_FLAG"
      echo "❌ Timed out waiting for WMI monitor readiness." >&2
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done
}
install_offline() {
  ISO_PATH="$INSTALLER_FILE"
  ISO_MOUNT=""
  MONITOR_PID=""
  MONITOR_FLAG=""
  MONITOR_READY=""
  local mounted_by_script=false

  detect_disk_image_backend

  if [[ "$DISK_IMAGE_BACKEND" == hdiutil ]]; then
    if ISO_MOUNT="$(find_iso_mount)"; then
      step "Found existing ISO mount at $ISO_MOUNT"
    else
      ISO_MOUNT="$WORKDIR/iso-mount"
      mkdir -p "$ISO_MOUNT"
      step "Mounting ISO with hdiutil at $ISO_MOUNT"
      run hdiutil attach -readonly -nobrowse -mountpoint "$ISO_MOUNT" "$ISO_PATH"
      mounted_by_script=true
    fi
  else
    local target_mount="$WORKDIR/iso-mount"
    mkdir -p "$target_mount"
    attach_diskutil_iso "$target_mount"
    mounted_by_script=true
  fi

  local rc=0
  (
    set -e
    install_nipkg_vc2015
    start_ni_offline_monitor

    local installer_exe="$ISO_MOUNT/install.exe"
    if [[ ! -f "$installer_exe" ]]; then
      installer_exe="$(find "$ISO_MOUNT" -maxdepth 1 -iname 'install.exe' -print -quit)"
    fi
    if [[ -z "$installer_exe" || ! -f "$installer_exe" ]]; then
      echo "❌ Could not find install.exe at the root of $ISO_MOUNT." >&2
      exit 1
    fi

    step "Running the Multisim 14.3 offline installer (--quiet --accept-eulas --prevent-reboot)"
    if $VERBOSE; then
      wine "$installer_exe" --quiet --accept-eulas --prevent-reboot &
    else
      WINEDEBUG=-all wine "$installer_exe" --quiet --accept-eulas --prevent-reboot >>"$LOGFILE" 2>&1 &
    fi

    wait "$MONITOR_PID"
    rm -f "$MONITOR_FLAG" "$MONITOR_READY"

    step "Stopping Wine"
    run wineserver -k || true
    run wineserver -w
    echo "Multisim offline installation stage complete."
    echo
  ) || rc=$?

  rm -f "${MONITOR_FLAG:-}" "${MONITOR_READY:-}"
  if $mounted_by_script; then
    detach_offline_iso
  fi

  return "$rc"
}

if $IS_MACOS_ARM64; then
  install_offline
else
  install_online
fi
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

  cp dao360.dll msjet40.dll msrd3x40.dll "$WINEPREFIX/drive_c/windows/syswow64/"

  step "Registering DLLs"
  run wine regsvr32 'C:\windows\syswow64\dao360.dll' 'C:\windows\syswow64\msjet40.dll'

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
	find "$app_path" -type f -name "run.sh" -exec chmod +x {} \;
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

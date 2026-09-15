<img src="assets/images/banner.png" alt="MULTISIM" />

![Supported OS: Linux](https://img.shields.io/badge/Supported_OS-Linux%20and%20MacOS-orange.svg)
![Bash](https://img.shields.io/badge/Language-Bash-blue.svg)
> Automated installer for **NI Multisim 14.3** on Linux and MacOS via [Wine](https://www.winehq.org/).

Built for the redpilled breed of engineers and students who rely on [NI Multisim](https://www.ni.com/en/support/downloads/software-products/download.multisim.html) every day but run Linux/MacOS as their primary OS. This repository provides the tools, tweaks, and compatibility setup needed to make Multisim usable on a daily-driver environment without the usual headaches.

**Authors:** [Giovanni De Rosa](https://github.com/ghepardoman), [Lorenzo Pappalardo](https://github.com/Lobbo4), [Andrea Lestingi](https://github.com/AndreaLestingi)

> ⚠️ Beware of unofficial copies of this project.
---

## 📋 Table of Contents

- [Overview](#overview)
- [Linux Support](#-linux-support)
- [MacOS Support](#-macos-support)
- [Usage](#-install)
- [How it works](#%EF%B8%8F-how-it-works)
- [Notes & Known Issues](#%EF%B8%8F-notes--known-issues)

---

## Overview

This bash script automates the full process of installing **NI Circuit Design Suite 14.3 (Multisim)** on Linux or MacOS. It handles Wine installation, a dedicated Wine prefix, dependency setup, and the Multisim installer execution — all in a single run across all supported distros.



### Prerequisites
 `wget`, `git`, `wine` or `winehq-stable`, `winetricks`, `cabextract`, `curl` and `unzip` available on your system

---

## 🐧 Linux Support

### Supported Distributions

| Distribution Family | Tested Distros |
|---|---|
| 🔵 Arch | [Arch Linux](https://archlinux.org/) |
| 🟠 Debian / Ubuntu | [Ubuntu](https://ubuntu.com/) |
| 🔴 Fedora / RHEL | [Fedora](https://fedoraproject.org/) |
| 🟢 openSUSE | [openSUSE](https://www.opensuse.org/) Tumbleweed |


## 🍎 MacOS Support 

### Requirements
- macOS 10.14 (Mojave) or later *(the script has been tested on macOS 26)*
- Intel or Apple Silicon

Many of the required dependencies are already on the system.
If `git` is not already present in your system, type it in your terminal: it will yield an error but you will then be prompted to install the XCode Command Line Tools and the issue will be fixed.

Wine should be installed with Homebrew: `brew install --cask wine-stable winetricks`.
If Wine *suddenly disappears*, `brew remove` it and install it again.

---

## 💻 Install

```bash
curl -fsSL https://raw.githubusercontent.com/ghepardoman/NI-Multisim-14-for-Linux-and-MacOS/main/install.sh -o install.sh && bash install.sh
```

Or,

```bash
# 1. Download the script
curl -fsSL https://raw.githubusercontent.com/ghepardoman/NI-Multisim-14-for-Linux-and-MacOS/main/install.sh -o install.sh

# 2. Make it executable (optional but good practice)
chmod +x install.sh

# 3. Run it normally
./install.sh
```

> ⚠️ **Do not run as root.** The script uses `sudo` internally where needed.

## 🧹 Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/ghepardoman/NI-Multisim-14-for-Linux-and-MacOS/main/uninstall.sh -o uninstall.sh && bash uninstall.sh
```

Or more explicitly,

```bash
# 1. Download the script
curl -fsSL https://raw.githubusercontent.com/ghepardoman/NI-Multisim-14-for-Linux-and-MacOS/main/uninstall.sh -o uninstall.sh

# 2. Make it executable (optional)
chmod +x uninstall.sh

# 3. Run it
./uninstall.sh
```

---

## ⚙️ How it works

### Distro/OS Detection
The script is "universal" in the sense that it has cross-compatibility between Linux distros/macOS without the use of unique functions, albeit the script occasionally uses `/etc/os-release` or `uname -s` if a distro-specific or macOS-specific step/fix is required.



### Checking for Prerequisites
Automatically checks for required packages and prints out the missing ones, if any.



### Wine Prefix Setup
Creates a **dedicated Wine prefix** at `~/.multisim143`, isolated from your default Wine environment, configured with Windows 10 compatibility mode.
Because it is just a regular 64-bit prefix there's no need to mess with wine versions.



### Choosing Multisim Edition
Allows you to choose whether to install Multisim Educational or Professional.
Script-wise this only affects which installer gets downloaded with `wget`.
Both the installers are the "online" version, making their filesize much lighter.



### Installing Multisim
The script will run Multisim's installer; here you're required to follow the setup steps manually.
**We highly suggest you say "no" when prompted for automatic updates at the very end of the installation.**



### Getting the Jet Database to work
**MDAC 2.7** and **Jet 4.0**'s installation will be handled by the script:
both of their redistributables are pulled with `wget` from the Web Archive (the same location where `winetricks` installs them from).

**MDAC 2.7** is installed by simply running what the downloaded with Wine, `MDAC_TYP.exe`.

**Jet 4.0**'s installation requires a few extra steps:
- First the script runs through Wine the redistributable that has just been downloaded (`Jet40SP8_9xNT.exe`);
- Then it is required to extract the DLL files by running cabextract a few times *(view `install.sh` for specific steps)`;
- The three required DLLs are then copied inside `~/.multisim143/drive_c/windows/syswow64/`;
- Two of the DLLs have to be registered using `wine regsvr32`.

#### Why not just use Winetricks?
Because we'd just end up having architecture-wise compatibility issues.



### Cleanup
Removes whichever temporary folders were created for installed files/extraction operations.



### Adding Multisim to Applications __(macOS only)__
Because it is not handled by macOS, unlike how it happens on Linux distros, the script downloads the `.app` package that we created from this repository (assets/macOS/multisim.app.zip); it is then unzipped and placed inside `/Applications/` allowing Multisim to be launched easily.



### Reboot
Asks for system reboot; not required but fixes any issue with running Multisim most times.

---

## 🗒️ Notes & Known Issues

### Linux-Specific
- The Wine prefix is stored at `~/.multisim143` and is completely separate from any existing Wine setup you may have.
- A **system reboot** is recommended after installation.
- If Multisim does not appear in your application launcher after install, try running:
  ```bash
  update-desktop-database ~/.local/share/applications
  ```
- Only the subsequent distros were tested: Arch Linux, Ubuntu, Fedora, openSUSE Tumbleweed.

### MacOS-Specific
- The `.app` bundle needed to be created manually.

---

## ⚠️ Disclaimer

> **This project is provided "as is", without warranty of any kind, express or implied.**
>
> The authors are **not responsible** for:
> - Any damage to your system resulting from the use of this script
> - Compatibility issues with specific hardware, software, or OS versions
> - Changes to third-party services (NI download servers, Wine, Homebrew, package repositories) that may break the installer
> - Any legal issues arising from the installation or use of NI Multisim 14.3
>
> **NI Multisim is proprietary software owned by National Instruments (NI) / Emerson.**
> This script only automates the download of the official installer from NI's own servers and does not redistribute any proprietary software.
>
>
>
> You are solely responsible for ensuring you have a valid license to use NI Multisim 14.3.

---

## 📄 License

This script is released under the **GNU General Public License v3.0**.  
You are free to use, modify, and redistribute it, provided you include the original copyright notice and this license.

<h1 align="center">
  <img loading="lazy" src="readme-res/banner.png"/>
</h1>
<p align="center">
  <a href="https://github.com/bbeguinstl/HubbleROM/blob/seventeen/LICENSE"><img loading="lazy" src="https://img.shields.io/github/license/bbeguinstl/HubbleROM?style=for-the-badge&logo=github"/></a>
  <a href="https://github.com/bbeguinstl/HubbleROM/commits/seventeen"><img loading="lazy" src="https://img.shields.io/github/last-commit/bbeguinstl/HubbleROM/seventeen?style=for-the-badge"/></a>
  <a href="https://github.com/bbeguinstl/HubbleROM/stargazers"><img loading="lazy" src="https://img.shields.io/github/stars/bbeguinstl/HubbleROM?style=for-the-badge"/></a>
  <a href="https://github.com/bbeguinstl/HubbleROM/actions/workflows/ci.yml"><img loading="lazy" alt="CI" src="https://img.shields.io/github/actions/workflow/status/bbeguinstl/HubbleROM/ci.yml?branch=seventeen&amp;label=CI&amp;style=for-the-badge"/></a>
  <a href="https://github.com/bbeguinstl/HubbleROM/releases"><img loading="lazy" alt="Latest ROM release" src="https://img.shields.io/github/v/release/bbeguinstl/HubbleROM?include_prereleases&amp;label=ROM%20release&amp;style=for-the-badge"/></a>
</p>
<p align="center">HubbleROM is a custom One UI 9.5 Beta 1 port for the Samsung Galaxy S20+ LTE (y2slte).</p>

> **Boot notice:** HubbleROM v1.0.0 bootloops on y2s. Use v1.0.1 instead; it includes the netd startup fix.

> **Project base:** HubbleROM continues [ShitStockMod](https://github.com/At30c/ShitStockModOrSomething)’s Galaxy S26+ One UI 9 port for y2slte, updated here to the Galaxy S26+ One UI 9.5 Beta 1 firmware. It retains the [UN1CA](https://github.com/salvogiangri/UN1CA) build system and compatible modules.

<p align="center">
  <a href="https://github.com/bbeguinstl/HubbleROM">📦 Source</a>
  •
  <a href="https://github.com/bbeguinstl/HubbleROM/releases">⬇️ Releases</a>
</p>

# What is HubbleROM?
HubbleROM ports the Galaxy S26+ 5G One UI 9.5 Beta 1 firmware (`S947BXXS6BZK1`) to the Galaxy S20+ LTE (`y2slte`, Exynos 990), with device-specific kernel and compatibility changes.

The project builds the required tools, extracts firmware components, applies the y2slte patches and creates a flashable zip.

The goal is to bring the current One UI experience to y2slte while keeping its hardware and device support usable.

Contributions, suggestions, bug reports and feature requests are welcome.

# Device support

| Device | Codename | Status |
| --- | --- | --- |
| Galaxy S20+ LTE (Exynos) | `y2slte` | Current beta target |
| Galaxy S20 Ultra (Exynos) | `z3s` | Planned; not supported yet |
| Galaxy S20 (Exynos) | `x1s` | Planned; not supported yet |

## Adding a device port

Device support is specific to its firmware, partition layout and hardware. To propose a new S20-series target:

1. Add its target configuration and exact stock firmware source/target versions under `target/<codename>/`.
2. Add and review device-specific kernel, boot/DTBO, partition, fstab, SELinux, vendor and compatibility changes; do not assume y2slte patches apply to another model.
3. Add the device to the build workflow target matrix and any installer or OTA assertions that need to recognize it.
4. Build and verify installation, boot, radio, camera, audio, biometrics and OTA behavior on that model; record known limitations.
5. Update this device table and the release notes only after the target has been built and verified.

`z3s` and `x1s` are planned contributions. They must remain marked as planned until their code and device testing are merged.

# Features
### Core features:
- Updated from the ShitStockMod Galaxy S26+ One UI 9 base to Galaxy S26+ One UI 9.5 Beta 1 (`S947BXXS6BZK1`)
- Ported for Samsung Galaxy S20+ LTE (`y2slte`, Exynos 990)
- EROFS powered
- Galaxy S26+ wallpapers and sounds included
- Galaxy AI support
  - Audio eraser
  - Browsing assist
  - Call assist
  - Drawing assist
  - Interpreter
  - Note assist
  - Now brief
  - Photo assist
  - Semantic search
  - Transcript assist
  - Writing assist
- High end animations
- Native/live blur support
- AOD clock transition support
- Adaptive color tone support
- Adaptive refresh rate support
- Extra brightness support
- Picture remaster support
- Object, shadow and reflection eraser support
- Image clipper support
- Multi user support
- Samsung DeX support*
- Camera privacy toggle support
- Debloated from useless system services/additional apps
- Dual Messenger available for all apps
- Custom FlipFont fonts support
- Outdoor mode support
- Auto PIN confirm with 4 digits
- [BluetoothLibraryPatcher](https://github.com/3arthur6/BluetoothLibraryPatcher) integrated
- [KnoxPatch](https://github.com/salvogiangri/KnoxPatch) integrated
- Extra CSC features enabled (Call recording, Hiya, Network speed in status bar, AltZLife)

\* DeX via HDMI not available for devices without USB-C DP support

### HubbleROM tools and additions:
- Hubble Settings panel with HubbleROM branding in About device
- Integrated OTA updates app
- Native/live blur toggle
- One UI Home animations option
- Vulkan renderer toggle
- Key attestation spoof ([TrickyStore](https://github.com/5ec1cff/TrickyStore)) options*
- Play Integrity Fix integrated
- Ability to hide installed apps ([Hide My Applist](https://github.com/Dr-TSNG/Hide-My-Applist))
- Ability to hide developer options
- Allow app downgrade toggle
- Allow secure screenshot toggle
- Screenshot/screen recording detection toggle
- Unlimited backup storage on Google Photos
- Games FPS unlock toggle

\* Requires a valid keybox

# Licensing
This project is licensed under the terms of the [GNU General Public License v3.0](LICENSE). External dependencies might be distributed under a different license, such as:
- [android-tools](https://github.com/nmeum/android-tools), licensed under the [Apache License 2.0](https://github.com/nmeum/android-tools/blob/master/LICENSE)
- [apktool](https://github.com/iBotPeaches/Apktool), licensed under the [Apache License 2.0](https://github.com/iBotPeaches/Apktool/blob/master/LICENSE.md)
- [erofs-utils](https://github.com/sekaiacg/erofs-utils/), dual license ([GPL-2.0](https://github.com/sekaiacg/erofs-utils/blob/dev/LICENSES/GPL-2.0), [Apache-2.0](https://github.com/sekaiacg/erofs-utils/blob/dev/LICENSES/Apache-2.0))
- [img2sdat](https://github.com/xpirt/img2sdat), licensed under the [MIT License](https://github.com/xpirt/img2sdat/blob/master/LICENSE)
- [platform_build](https://android.googlesource.com/platform/build/) (ext4_utils, f2fs_utils, signapk), licensed under the [Apache License 2.0](https://source.android.com/docs/setup/about/licenses)

# Contributors
<p align="center">
  <a href="https://github.com/At30c" title="At30c"><img loading="lazy" src="https://github.com/At30c.png?size=112" alt="At30c" width="88" height="88" style="border-radius:50%"/></a>
  <a href="https://github.com/bbeguinstl" title="bbeguinstl"><img loading="lazy" src="https://github.com/bbeguinstl.png?size=112" alt="bbeguinstl" width="88" height="88" style="border-radius:50%"/></a>
  <a href="https://github.com/miguelbarretoo" title="miguelbarretoo"><img loading="lazy" src="https://github.com/miguelbarretoo.png?size=112" alt="miguelbarretoo" width="88" height="88" style="border-radius:50%"/></a>
</p>

See [CONTRIBUTORS.md](CONTRIBUTORS.md) for the same linked profile images.

# Credits
A special thanks goes to the following for their invaluable contributions in no particular order:
- **[ShitStockMod](https://github.com/At30c/ShitStockModOrSomething)** for the S26+ One UI 9 y2slte port that HubbleROM continues.
- **[UN1CA](https://github.com/salvogiangri/UN1CA)** and **[salvogiangri](https://github.com/salvogiangri)** for the build system, reusable modules and the ROM foundations used by this port.
- **Samsung** for the Galaxy S26+ One UI 9.5 Beta firmware and the Galaxy S20+ device software.
- **[ShaDisNX255](https://github.com/ShaDisNX255)** for his help, time and for his [NcX ROM](https://github.com/ShaDisNX255/NcX_Stock) which inspired this project
- **[DavidArsene](https://github.com/DavidArsene)** for his help and time
- **[paulowesll](https://github.com/paulowesll)** for his help and support
- **[Simon1511](https://github.com/Simon1511)** for his support and some of the device-specific patches
- **[ananjaser1211](https://github.com/ananjaser1211)** for troubleshooting and his time
- **[Fede2782](https://github.com/Fede2782)** for his contributions and help with Exynos/MTK support
- **[iDrinkCoffee](https://github.com/iDrinkCoffee-TG)** and **[RisenID](https://github.com/RisenID)** for their support
- **[LineageOS Team](https://www.lineageos.org/)** for their original [OTA updater implementation](https://github.com/LineageOS/android_packages_apps_Updater)
- *All the ShitStockMod and UN1CA contributors, testers and users whose work made this port possible ❤️*

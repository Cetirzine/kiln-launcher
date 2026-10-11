<img src="assets/logo.svg" width="128" alt="Kiln Launcher">

# Kiln Launcher

<p align="center">
  <img src="https://img.shields.io/badge/Swift-5.9+-F05138?logo=swift&logoColor=white" alt="Swift">
  <img src="https://img.shields.io/badge/macOS-14.0+-0A7AFF?logo=apple&logoColor=white" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Apple_Silicon-native-34C759?logo=apple&logoColor=white" alt="Apple Silicon">
  <a href="https://github.com/Cetirzine/kiln-launcher/releases/latest"><img src="https://img.shields.io/github/v/release/Cetirzine/kiln-launcher?logo=github&label=release" alt="Release"></a>
  <a href="https://github.com/Cetirzine/kiln-launcher/releases"><img src="https://img.shields.io/github/downloads/Cetirzine/kiln-launcher/total?logo=github&label=downloads" alt="Downloads"></a>
  <a href="https://github.com/Cetirzine/kiln-launcher/stargazers"><img src="https://img.shields.io/github/stars/Cetirzine/kiln-launcher?logo=github" alt="Stars"></a>
  <a href="LICENSE.md"><img src="https://img.shields.io/badge/license-PolyForm_Strict_1.0.0-blue" alt="License"></a>
</p>

A native macOS launcher for Minecraft: Java Edition, built with SwiftUI and tuned for Apple silicon.

[中文说明](README.md)

## What it does

- Installs and launches vanilla, Fabric, Quilt, Forge and NeoForge versions; OptiFine and LiteLoader can be added alongside Forge where available
- Finds, selects or downloads the right Java runtime (Mojang runtimes, Azul Zulu for arm64 Java 8)
- Signs in with a Microsoft account (OAuth 2.0 device code flow), an authlib-injector skin site such as LittleSkin (passwords are never stored), or an offline profile; switch accounts with ⌃⌘1–9 and pin an account to an instance
- Skins: local or same-name player skins for offline accounts; upload skins and switch capes for Microsoft accounts
- Searches and downloads mods, resource packs and shaders from Modrinth and CurseForge (via the MCIM mirror, or with your own API key), installing required dependencies automatically
- Identifies installed mods and updates them one by one or all at once
- Installs Modrinth (.mrpack) and CurseForge modpacks and exports instances as .mrpack
- Renames and duplicates instances; imports and exports worlds; manages resource packs, shaders and screenshots
- Chinese mod names, with search by Chinese, pinyin or pinyin initials; the name table lives in `assets/mod-names-zh.json` and accepts pull requests
- Shows game logs and explains common crash causes
- Checks for new versions and, once you confirm, downloads, verifies and replaces itself

## Apple silicon

| Game version | How it runs |
| --- | --- |
| 1.19 and newer | Native arm64 (natives ship with the game) |
| 1.13 – 1.18 | Native: LWJGL is swapped for 3.3.1 with arm64 natives |
| 1.12.2 and older | Native: arm64 LWJGL 2 build plus arm64 Java 8 |

Rosetta 2 is only used as a fallback.

Performance work includes tuned G1 settings, the Java 25 AOT cache (Java 19–24: dynamic CDS), compact object headers on Java 24+, skipping SHA-1 checks for unchanged files, and running the game at a high QoS so it is scheduled on performance cores. On supported versions, the experimental [MetalUniversal](https://github.com/EternityQwQ/MetalUniversal) renderer can be enabled with one switch.

Downloads use the official servers by default with the BMCLAPI mirror as a fallback (configurable); failed files are retried with lower concurrency, which helps behind proxies.

## Microsoft sign-in and privacy

- Public client, device code flow against the `consumers` endpoint, scopes `XboxLive.signin offline_access`
- Tokens are exchanged only with Microsoft, Xbox Live and Minecraft services, to obtain the Minecraft access token and profile needed to launch the game
- The refresh token is stored locally in the macOS Keychain
- The launcher has no backend server and collects no user data

## Building

Only the Xcode Command Line Tools are required.

```bash
./scripts/build-app.sh
```

This produces `build/Kiln.app` (arm64, release build).

## License

Kiln is available under the [PolyForm Strict License 1.0.0](LICENSE.md): noncommercial use only; no distribution (including redistributing the app or its source) and no changes or derivative works.

## Credits

- LTCat (龙腾猫跃) and [Plain Craft Launcher 2](https://github.com/Meloong-Git/PCL)
- [HMCL](https://github.com/HMCL-dev/HMCL), [MetalUniversal](https://github.com/EternityQwQ/MetalUniversal), [MinecraftMachina/lwjgl](https://github.com/MinecraftMachina/lwjgl), [BMCLAPI](https://bmclapi.bangbang93.com), [Modrinth](https://modrinth.com), [Azul Zulu](https://www.azul.com/downloads/), [authlib-injector](https://github.com/yushijinhun/authlib-injector) (downloaded at runtime for third-party login and offline skins)

## Star History

<a href="https://star-history.com/#Cetirzine/kiln-launcher&Date">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=Cetirzine/kiln-launcher&type=Date&theme=dark">
    <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=Cetirzine/kiln-launcher&type=Date">
  </picture>
</a>

Minecraft is a trademark of Mojang Studios. This project is not an official Minecraft product and is not approved by or associated with Mojang or Microsoft.

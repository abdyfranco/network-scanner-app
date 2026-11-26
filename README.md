<p align="center">
  <img src="Resources/AppIcon.png" width="128" height="128" alt="Network Scanner app icon">
</p>

<h1 align="center">Network Scanner</h1>

<p align="center">A native network scanner for macOS that finds every device on your network and identifies it, with a Liquid Glass design.</p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/screenshot-dark.png">
    <img src="docs/screenshot-light.png" width="760" alt="Network Scanner with a home network's devices in the sidebar and a Mac mini's overview on the right">
  </picture>
</p>

## Features

- **Scans a subnet or IP range** over IPv4 and IPv6, combining ping, TCP probes, the ARP and neighbor caches, Bonjour, NetBIOS and UniFi discovery
- **Identifies each device** by name, vendor, MAC, type and model, with macOS's own picture of each Apple product and matching icons for UniFi gear and everything else
- **Port scan** for any device: common ports, 1–1024, 1–10000, all 65,535 or your own list, with links to open web, SSH, SMB and screen sharing
- **Wi-Fi scan** with the Mac's own Wi-Fi card: nearby networks with their signal, channel, band, width, security and Wi-Fi generation, a channel chart, and details of the current connection
- **Wake-on-LAN** for Macs, PCs, servers and network storage, showing when each one answers
- **Open in UniFi Network**, which takes a UniFi gateway, switch or access point straight to its panel on your console
- **Offline vendor lookup** from the IEEE registry, updatable from Settings
- **Automatic updates** from this repository's releases, with the choice to install, wait or skip each version
- In English, Spanish (Spain and Latin America), French, German, Italian, Portuguese (Brazil), Japanese and Chinese (Simplified), following your Mac's language

## Install

Download the latest `Network-Scanner-x.y.z.dmg` from [Releases](https://github.com/advandz/network-scanner-app/releases), open it and drag **Network Scanner** to **Applications**.

Requires macOS 26 or later; the app runs natively on Apple silicon and Intel. It isn't notarized, so if macOS can't verify it, choose **Open Anyway** in **System Settings → Privacy & Security**.

Network Scanner checks this repository's tags once a day, when it starts: the first launch each day checks, later ones that day don't. It also checks whenever you choose **Network Scanner → Check for Updates…**. When there's a newer version it shows the release notes and offers **Install Update**, **Later** or **Skip This Version**. Installing downloads the release's DMG and installs it only if its signature matches the release key built into the app. It then checks the app inside (bundle ID, version and code signature), swaps it in place and restarts. Automatic checks can be turned off in **Settings → Updates**.

## macOS Gatekeeper

Network Scanner isn't notarized by Apple, so macOS Gatekeeper may stop it the first time you open it. You may see a message such as:

- “Network Scanner” is damaged and can't be opened. You should move it to the Trash.
- “Network Scanner” can't be opened because Apple cannot check it for malicious software.
- “Network Scanner” is not safe to open.

The download isn't corrupt. macOS marks every app downloaded from the internet as quarantined, and Gatekeeper blocks quarantined apps that aren't notarized.

**To open it**

1. Drag **Network Scanner** to **Applications**, then open it. When macOS blocks it, click **Done** (not **Move to Trash**).
2. Open **System Settings → Privacy & Security** and scroll down to **Security**.
3. Next to the message about Network Scanner, click **Open Anyway**, then confirm with your password or Touch ID.

**If it says the app is damaged**

That message has no **Open Anyway** button. Remove the quarantine flag in Terminal, then open the app normally:

```bash
xattr -dr com.apple.quarantine "/Applications/Network Scanner.app"
```

If the app isn't in **Applications**, use its actual path. Only do this for a copy you downloaded from this repository's [Releases](https://github.com/advandz/network-scanner-app/releases) page.

## Build from source

You need Xcode 26, which compiles the Liquid Glass icon and the translations. Select it once:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcodebuild -runFirstLaunch
```

Then build:

| Command | What it does |
|:--|:--|
| `./build-app.sh` | Builds the universal, ad-hoc signed app (with the hardened runtime) into `build/Network Scanner.app`, and `build/Network-Scanner-<version>.dmg` |
| `./build-app.sh --open` | Also opens it |
| `Scripts/update-strings.sh` | Adds new UI text from the code to `Resources/Localizable.xcstrings` |
| `Scripts/check-strings.py` | Checks that every string is translated in every language |
| `Scripts/make-icon.sh` | Re-renders the icon files from `Resources/AppIcon.icon` |

For development, `swift run` also works, in English and without the app icon.

The first scan asks for **Local Network** access; allow it, or scans find nothing. Rebuilt ad-hoc signed apps can lose that permission, so if scans come back empty, allow Network Scanner again in **System Settings → Privacy & Security → Local Network**.

The Wi-Fi tab asks for **Location** access, because macOS shows network addresses (BSSIDs) and the name of the connected network only to apps that have it. Without it, the tab still lists nearby networks with their channel, signal and security. The app never reads your actual location.

Translations live in `Resources/Localizable.xcstrings`, and the permission prompts' text in `Resources/InfoPlist.xcstrings`. To add a language, translate every key into it; `check-strings.py` lists any that are missing.

## Release

The updater picks the highest version among the repository's tags, such as `v1.0.1` or `1.0.1`; pre-release tags like `v1.1.0-beta` are ignored. It installs the `.dmg` attached to that tag's GitHub release, and only when the release also has the DMG's signature, `<dmg>.sig`, made with the release key.

The release key is an Ed25519 key pair. Its public half is compiled into the app (`Updater.signingKey` in `Sources/NetScanner/App/Updater.swift`). The private half is a key file outside this repository, `~/.network-scanner-signing/update-signing.key` on the Mac that publishes releases (or the path in `NETWORK_SCANNER_SIGNING_KEY`). Back the file up, for example in a password manager, and never commit it: without it, installed copies refuse every future update. To publish from another Mac, copy the file to the same place there, readable only by you (`chmod 600`). `swift Scripts/update-key.swift keygen` creates a key if there's none yet; put the public key it prints into `Updater.signingKey`.

To publish a version:

1. Set `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`.
2. Run `./build-app.sh`, which also writes `build/Network-Scanner-<version>.dmg` and, when the key file is there, its signature `build/Network-Scanner-<version>.dmg.sig`.
3. Commit, then tag and publish the release with both files attached. Its notes appear in the update prompt.

   ```bash
   git tag v1.0.1 && git push origin v1.0.1
   gh release create v1.0.1 build/Network-Scanner-1.0.1.dmg build/Network-Scanner-1.0.1.dmg.sig --title "Network Scanner 1.0.1" --notes "What changed"
   ```

If the newest tag has no release, no DMG or no signature, the prompt offers **View Release** instead. Installing in place needs the app in a folder it can write to, such as `/Applications` for an administrator, or `~/Applications`.

To try the updater without publishing anything, point it at a local copy of the API with the hidden `UpdateFeedURL` setting, for example `open "build/Network Scanner.app" --args -UpdateFeedURL http://127.0.0.1:8765`. It expects `tags` and `releases/tags/<tag>` in GitHub's format there. The setting is ignored unless the feed is on this Mac, and downloads then have to come from this Mac too. Sign the test DMG with `swift Scripts/update-key.swift sign <file.dmg>` and serve the `.sig` beside it.

## Command line

The app binary can also scan from a terminal and print a table:

```bash
"build/Network Scanner.app/Contents/MacOS/NetScanner" --scan 192.168.1.0/24 --verbose
```

A port scan takes `common`, `wellKnown`, `extended`, `all` or a list such as `"22,80,8000-8100"`:

```bash
"build/Network Scanner.app/Contents/MacOS/NetScanner" --ports 192.168.1.1 all
```

`--wifi` lists the Wi-Fi networks around you. From a terminal, BSSIDs show only if the terminal app has Location access:

```bash
"build/Network Scanner.app/Contents/MacOS/NetScanner" --wifi
```

`--demo` opens the window on a made-up network and made-up Wi-Fi networks instead of scanning, as in the screenshot above. Add `--light` or `--dark` to pick the appearance:

```bash
open "build/Network Scanner.app" --args --demo --dark
```

## Good to know

- macOS keeps ARP entries for up to about 20 minutes, so a device that just left the network can still show once.
- On other subnets, devices are found by ping and TCP and named through DNS. Their MAC addresses aren't visible across a router.
- Only scan networks you own or are allowed to test.

## License

Copyright © 2026 Advandz Technologies, LLC. Released under the [MIT License](LICENSE.md).

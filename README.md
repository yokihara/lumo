# Lumo

> External display brightness, input, and darkroom — from a single menu bar icon. No settings window, no daemon, under 1 MB.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Platform: macOS arm64](https://img.shields.io/badge/platform-macOS%2013%2B%20·%20arm64-blue.svg)
[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-support-yellow?logo=buymeacoffee&logoColor=black)](https://www.buymeacoffee.com/yokihara93q)

Lumo is a tiny, free, open-source menu bar app for controlling **external monitor brightness on Apple Silicon Macs** (M1, M2, M3, M4) over DDC/CI. Think of it as a lightweight **alternative to MonitorControl, Lunar, and BetterDisplay** — it adds **input-source switching** and a **per-display night / darkroom dimmer**, all in a sub-1 MB app with no settings window.

Common use cases: adjusting a second monitor's brightness from the keyboard's reach, dimming a USB-C or HDMI display below its hardware minimum at night, and switching a shared monitor's input like a software KVM.

- **Brightness** (DDC/CI): control the hardware backlight of external monitors
- **Input source switching** (DDC/CI): change a monitor's input from the menu bar, like a KVM
- **Darkroom** (gamma): dim and warm any screen for a "night mode" — works on every screen including the built-in display, even monitors without DDC support

No preferences window, no background daemon — a single menu bar icon is all there is. DMG under 1 MB.

## Screenshot

<!-- TODO: drop a screenshot or gif of the menu bar dropdown here, e.g. docs/demo.gif -->
_Coming soon — the menu bar dropdown with brightness, input source, and darkroom sliders._

## Why Lumo?

MonitorControl is excellent and free, and Lumo uses the same underlying technique for brightness. Lumo's focus is deliberately narrow: stay tiny and do the few things many multi-monitor setups actually reach for.

| | Lumo | MonitorControl | Lunar / BetterDisplay |
|---|---|---|---|
| Price | Free (MIT) | Free (OSS) | Freemium / paid |
| Footprint | < 1 MB, no daemon | ~25 MB | 30 MB+ |
| Brightness (DDC) | ✓ | ✓ | ✓ |
| Input source switching | ✓ | ✗ | Pro |
| Per-display darkroom (dim + warmth) | ✓ | ✗ | ✓ (among many features) |
| Settings window | none | yes | extensive |

Sizes are approximate. If you want a deep, highly configurable tool, use Lunar or BetterDisplay. If you want brightness + input switching + a per-display night dimmer in a sub-1 MB menu bar app with zero configuration, that's Lumo.

## Two control layers

| Layer | Mechanism | Targets | Notes |
|---|---|---|---|
| Brightness · Input | DDC/CI over I2C (`IOAVService`) | External monitors | Hardware backlight / input |
| Darkroom | Gamma table (`CGSetDisplayTransferByFormula`) | All screens | GPU output transform, per-screen |

Darkroom gamma persists **only while the setting process is alive** (macOS restores it when the process exits).
That's why darkroom lives in the always-running menu bar app, and the CLI only exposes `gamma reset` (a panic restore).
Display sleep or a resolution change wipes the gamma table, so the app watches for screen-configuration changes and re-applies automatically.

## Install

Requirements: Apple Silicon Mac, macOS 13 (Ventura) or later.

**① Download the DMG from GitHub Releases (recommended)**

Grab the latest `Lumo-<version>.dmg` from [Releases](https://github.com/yokihara/lumo/releases), open it,
and drag `Lumo.app` into `Applications`. (Notarized builds open without a Gatekeeper warning.)

**② Homebrew Cask**

```sh
brew install --cask yokihara/tap/lumo
```

> `yokihara/tap` is a placeholder for the actual tap path; it changes once the tap repository is published.
> The cask definition draft lives in [`Casks/lumo.rb`](Casks/lumo.rb).

To build it yourself, see the [Build](#build) section below.

## Build

```sh
./make-app.sh        # produces dist/Lumo.app
open dist/Lumo.app   # a ☀️ icon appears in the menu bar
```

Launch at login: System Settings → General → Login Items → add `dist/Lumo.app`.

## CLI mode

Running the built binary with arguments makes it behave as a CLI.

```sh
.build/release/Lumo list           # list external displays
.build/release/Lumo get 1          # read brightness of display 1
.build/release/Lumo set 1 70       # set display 1 brightness to 70
.build/release/Lumo input 1        # show the current input source
.build/release/Lumo input 1 hdmi1  # switch input (dp1 dp2 hdmi1 hdmi2 usbc, or a hex code)
.build/release/Lumo debug 1        # dump the raw DDC reply (for troubleshooting)
```

Note: switching the input to another device's port will make this Mac see the monitor as disconnected — that's expected.
You can switch back from the monitor's OSD or from the other device.

## Distribution (DMG)

```sh
./release.sh                   # produces dist/Lumo-<version>.dmg (ad-hoc signed)
```

For a proper signature + notarization after joining the Apple Developer Program:

```sh
# one time: store notarization credentials (create an app password at appleid.apple.com)
xcrun notarytool store-credentials lumo-notary \
  --apple-id <apple-id> --team-id <team-id> --password <app-password>

# each release
DEV_ID_APP="Developer ID Application: NAME (TEAMID)" ./release.sh
```

A notarized DMG installs anywhere without a Gatekeeper warning. An ad-hoc DMG requires
the recipient to right-click → Open on first launch.

## How it works

- It sends what the monitor's OSD menu does over the DDC/CI protocol (I2C).
- On Apple Silicon it finds the IORegistry `DCPAVServiceProxy` (Location=External) node and talks to it
  through the private `IOAVServiceWriteI2C` / `IOAVServiceReadI2C` APIs (the same approach as MonitorControl).
- Brightness is VCP code `0x10`. Contrast (0x12), volume (0x62), and input source (0x60) are extensible the same way.

## Limitations

- Apple Silicon only (Intel Macs need a different I2C path).
- The monitor must support DDC/CI (toggleable in most external monitors' OSD settings).
- Uses private APIs, so it can't ship on the App Store — for personal / direct distribution.

## Contributing

Bug reports, feature ideas, and PRs are all welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for build steps and the PR workflow.

## Support

If Lumo is useful to you, you can buy me a coffee ☕

[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-support-yellow?logo=buymeacoffee&logoColor=black)](https://www.buymeacoffee.com/yokihara93q)

## License

[MIT](LICENSE) © 2026 brpark

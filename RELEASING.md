# Release checklist

Lumo uses private APIs (IOAVService) and can't ship on the Mac App Store, so it's distributed
as a **Developer ID-signed + notarized DMG** directly via GitHub Releases.

## 0. One-time setup

A proper signature/notarization requires an Apple Developer Program membership.

```sh
# store notarization credentials as a keychain profile (create an app password at appleid.apple.com)
xcrun notarytool store-credentials lumo-notary \
  --apple-id <apple-id-email> \
  --team-id <team-id> \
  --password <app-password>
```

- `release.sh` references the profile name `lumo-notary` directly.
- The signing ID for `DEV_ID_APP` looks like: `Developer ID Application: NAME (TEAMID)`
  (find it with `security find-identity -v -p codesigning`).

## 1. Bump the version

Update the two values in `Info.plist`.

- `CFBundleShortVersionString` — the user-facing version (e.g. `1.3` → `1.4`)
- `CFBundleVersion` — the build number, monotonically increasing per release (e.g. `4` → `5`)

`release.sh` reads `CFBundleShortVersionString` to name the DMG (`dist/Lumo-<version>.dmg`).

## 2. Build a signed + notarized DMG

```sh
DEV_ID_APP="Developer ID Application: NAME (TEAMID)" ./release.sh
```

- `release.sh` runs `make-app.sh` (build + sign the app) → create DMG → sign → submit for notarization (`--wait`) → staple.
- Notarization takes a few minutes.
- Result: `dist/Lumo-<version>.dmg` (installs anywhere without a Gatekeeper warning).
- Without `DEV_ID_APP` it produces an ad-hoc signed DMG that requires right-click → Open on first launch. (Don't use it for real releases.)

## 3. Compute the sha256

For the Homebrew cask and integrity checks.

```sh
shasum -a 256 dist/Lumo-<version>.dmg
```

## 4. Create a GitHub Release and attach the DMG

Tagging with the `v<version>` convention is recommended (e.g. `v1.4`).

```sh
gh release create v<version> dist/Lumo-<version>.dmg \
  --title "Lumo <version>" \
  --notes "summary of changes"
```

(You can also create the Release in the web UI and drag-attach the DMG.)

## 5. Update the Homebrew cask sha256

Fill in the placeholders in `Casks/lumo.rb` with real values.

- `version` — this release's version (e.g. `1.4`)
- `sha256` — the DMG sha256 from step 3
- `url` — the download URL of the DMG attached to the Release
  (`https://github.com/yokihara/lumo/releases/download/v<version>/Lumo-<version>.dmg`)

Test the install:

```sh
brew install --cask ./Casks/lumo.rb   # verify against the local file
```

If you distribute via a separate tap repository (e.g. `yokihara/homebrew-tap`), update that
repository's `Casks/lumo.rb` with the same values and commit/push.

## 6. Final checks

- [ ] Open the notarized DMG on another Mac (or a fresh user) and confirm it installs without a Gatekeeper warning
- [ ] Confirm the menu bar icon appears and brightness / input / darkroom work (smoke test)
- [ ] Record notable changes/caveats in the Release notes
- [ ] (If using a tap) verify `brew install --cask yokihara/tap/lumo` installs for real

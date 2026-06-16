# Homebrew Cask draft (Lumo)
#
# Fill in these placeholders for a real release:
#   - VERSION_PLACEHOLDER : the release version (e.g. 1.3). The Info.plist CFBundleShortVersionString value.
#   - SHA256_PLACEHOLDER  : the DMG sha256. Compute with `shasum -a 256 dist/Lumo-<version>.dmg`.
#
# `url` points at the DMG attached to the GitHub Release.
# See "5. Update the Homebrew cask sha256" in RELEASING.md for the full procedure.

cask "lumo" do
  version "VERSION_PLACEHOLDER"
  sha256 "SHA256_PLACEHOLDER"

  url "https://github.com/yokihara/lumo/releases/download/v#{version}/Lumo-#{version}.dmg"
  name "Lumo"
  desc "Ultra-light display control menu bar app for Apple Silicon Macs"
  homepage "https://github.com/yokihara/lumo"

  depends_on arch: :arm64
  depends_on macos: ">= :ventura"

  app "Lumo.app"
  # The app writes no preference file (state is in-memory only), so there is nothing to zap.
end

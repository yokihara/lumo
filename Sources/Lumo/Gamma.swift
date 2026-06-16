import AppKit
import CoreGraphics

/// Software dimming + warmth via per-display gamma tables. This is the layer that
/// makes "darkroom mode" work per monitor — CGSetDisplayTransferByFormula is keyed
/// by CGDirectDisplayID, so each screen (including the built-in) is independent and
/// it works even on displays without DDC support.
///
/// Note: gamma is a separate identifier space from DDC's IOAVService. A Screen here
/// is addressed by CGDirectDisplayID; the DDC ExternalDisplay is addressed by EDID.
struct Screen {
    let id: CGDirectDisplayID
    let name: String
    let isBuiltin: Bool

    static func all() -> [Screen] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            let id = CGDirectDisplayID(number.uint32Value)
            return Screen(id: id, name: screen.localizedName, isBuiltin: CGDisplayIsBuiltin(id) != 0)
        }
    }

    /// brightness/warmth are 0...1. Neutral = brightness 1, warmth 0.
    /// Dimming scales every channel's ceiling; warmth pulls the blue (and a little
    /// green) ceiling down so whites shift amber, mimicking a night/darkroom look.
    @discardableResult
    func applyDarkroom(brightness: Float, warmth: Float) -> Bool {
        let b = max(0, min(1, brightness))
        let w = max(0, min(1, warmth))
        let redMax: CGGammaValue = b
        let greenMax: CGGammaValue = b * (1 - 0.15 * w)
        let blueMax: CGGammaValue = b * (1 - 0.40 * w)
        let result = CGSetDisplayTransferByFormula(
            id,
            0, redMax, 1.0,
            0, greenMax, 1.0,
            0, blueMax, 1.0
        )
        return result == .success
    }

    /// Restore this one display to a neutral (identity) transfer table.
    @discardableResult
    func resetGamma() -> Bool {
        applyDarkroom(brightness: 1, warmth: 0)
    }
}

/// Restore every display to its ColorSync profile (undoes all gamma tweaks).
func resetAllGamma() {
    CGDisplayRestoreColorSyncSettings()
}

/// Holds each screen's darkroom level. Because gamma tables are bound to this
/// (long-running) process, applying once keeps them in effect — but the system
/// wipes them on any display reconfiguration, so reapplyAll() must run whenever
/// the screen layout changes.
final class GammaManager {
    static let shared = GammaManager()

    /// brightness 1.0 + warmth 0.0 = neutral (no darkroom).
    struct Setting {
        var brightness: Float
        var warmth: Float
        var isNeutral: Bool { brightness >= 1.0 && warmth <= 0.0 }
    }

    private var settings: [CGDirectDisplayID: Setting] = [:]

    func setting(for id: CGDirectDisplayID) -> Setting {
        settings[id] ?? Setting(brightness: 1, warmth: 0)
    }

    func apply(_ setting: Setting, to id: CGDirectDisplayID) {
        let screen = Screen.all().first { $0.id == id }
        if setting.isNeutral {
            settings[id] = nil
            screen?.resetGamma()
        } else {
            settings[id] = setting
            screen?.applyDarkroom(brightness: setting.brightness, warmth: setting.warmth)
        }
    }

    /// Re-assert darkroom on every still-present screen (call after a display
    /// reconfiguration, which resets all gamma tables to neutral).
    func reapplyAll() {
        let present = Screen.all()
        settings = settings.filter { id, _ in present.contains { $0.id == id } }
        for screen in present {
            if let setting = settings[screen.id] {
                screen.applyDarkroom(brightness: setting.brightness, warmth: setting.warmth)
            }
        }
    }
}

import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())

func usage() -> Never {
    print("""
    usage:
      lumo               run as menu bar app
      lumo list          list external displays
      lumo get <n>       read brightness of display n (1-based)
      lumo set <n> <v>   set brightness of display n to v (0-100)
      lumo input <n>     read current input source of display n
      lumo input <n> <s> switch input: dp1 dp2 hdmi1 hdmi2 usbc, or a hex code
      lumo screens       list all screens (incl built-in)
      lumo gamma reset   panic-restore all screens to neutral (darkroom lives in the app)
      lumo debug <n>     dump raw DDC reply for display n
    """)
    exit(1)
}

if arguments.isEmpty {
    MenuBarApp.run()
} else {
    let displays = ExternalDisplay.enumerate()

    switch arguments[0] {
    case "list":
        if displays.isEmpty {
            print("no external displays with DDC support found")
            exit(2)
        }
        for (index, display) in displays.enumerated() {
            print("\(index + 1): \(display.name) (serial \(display.serial))")
        }

    case "get":
        guard arguments.count == 2, let n = Int(arguments[1]), displays.indices.contains(n - 1) else { usage() }
        guard let result = displays[n - 1].read(vcp: VCP.brightness) else {
            print("DDC read failed")
            exit(2)
        }
        print("brightness: \(result.current)/\(result.max)")

    case "set":
        guard arguments.count == 3, let n = Int(arguments[1]), let value = UInt16(arguments[2]),
              displays.indices.contains(n - 1) else { usage() }
        guard displays[n - 1].write(vcp: VCP.brightness, value: value) else {
            print("DDC write failed")
            exit(2)
        }
        print("ok")

    case "input":
        guard arguments.count >= 2, let n = Int(arguments[1]), displays.indices.contains(n - 1) else { usage() }
        let display = displays[n - 1]
        if arguments.count == 2 {
            guard let result = display.read(vcp: VCP.inputSource) else {
                print("DDC read failed")
                exit(2)
            }
            let code = UInt8(result.current & 0xFF)
            print("input: \(InputSource.label(for: code)) [0x\(String(format: "%02X", code))]")
        } else {
            let raw = arguments[2].lowercased()
            let code: UInt16?
            switch raw {
            case "dp", "dp1", "displayport": code = 0x0F
            case "dp2": code = 0x10
            case "hdmi", "hdmi1": code = 0x11
            case "hdmi2": code = 0x12
            case "usbc", "usb-c", "typec": code = 0x19
            default: code = UInt16(raw.replacingOccurrences(of: "0x", with: ""), radix: 16)
            }
            guard let value = code else { usage() }
            guard display.write(vcp: VCP.inputSource, value: value) else {
                print("DDC write failed")
                exit(2)
            }
            print("ok")
        }

    case "screens":
        let screens = Screen.all()
        for (index, screen) in screens.enumerated() {
            let tag = screen.isBuiltin ? " [built-in]" : ""
            print("\(index + 1): \(screen.name)\(tag)")
        }

    case "gamma":
        // Gamma persists only while the setting process is alive (the system restores it on exit).
        // So darkroom only makes sense in the always-running menu bar app; the CLI offers panic-restore only.
        guard arguments.count == 2, arguments[1] == "reset" else { usage() }
        resetAllGamma()
        print("ok (all screens restored)")

    case "debug":
        guard arguments.count >= 2, let n = Int(arguments[1]), displays.indices.contains(n - 1) else { usage() }
        let vcp = arguments.count >= 3 ? (UInt8(arguments[2].replacingOccurrences(of: "0x", with: ""), radix: 16) ?? VCP.brightness) : VCP.brightness
        if let reply = displays[n - 1].readRaw(vcp: vcp) {
            print("raw reply:", reply.map { String(format: "%02X", $0) }.joined(separator: " "))
        } else {
            print("I2C transaction failed")
            exit(2)
        }

    default:
        usage()
    }
}

import Foundation
import IOKit

// Private IOAVService APIs (exported by IOKit on Apple Silicon).
// These are the only way to reach external displays' DDC/CI bus on M-series Macs,
// where the old IOFramebuffer I2C path no longer exists.
@_silgen_name("IOAVServiceCreateWithService")
private func IOAVServiceCreateWithService(_ allocator: CFAllocator?, _ service: io_service_t) -> Unmanaged<AnyObject>?

@_silgen_name("IOAVServiceCopyEDID")
private func IOAVServiceCopyEDID(_ service: AnyObject, _ data: UnsafeMutablePointer<Unmanaged<CFData>?>) -> IOReturn

@_silgen_name("IOAVServiceWriteI2C")
private func IOAVServiceWriteI2C(_ service: AnyObject, _ chipAddress: UInt32, _ dataAddress: UInt32, _ inputBuffer: UnsafeRawPointer, _ inputBufferSize: UInt32) -> IOReturn

@_silgen_name("IOAVServiceReadI2C")
private func IOAVServiceReadI2C(_ service: AnyObject, _ chipAddress: UInt32, _ offset: UInt32, _ outputBuffer: UnsafeMutableRawPointer, _ outputBufferSize: UInt32) -> IOReturn

enum VCP {
    static let brightness: UInt8 = 0x10
    static let inputSource: UInt8 = 0x60
}

enum InputSource {
    // Only the MCCS standard codes that actually exist on modern monitors. USB-C (0x19)
    // isn't in the standard but is the de facto value most vendors (LG etc.) use.
    static let known: [(code: UInt8, label: String)] = [
        (0x0F, "DisplayPort 1"),
        (0x10, "DisplayPort 2"),
        (0x11, "HDMI 1"),
        (0x12, "HDMI 2"),
        (0x19, "USB-C"),
    ]

    static func label(for code: UInt8) -> String {
        known.first { $0.code == code }?.label ?? String(format: "Unknown (0x%02X)", code)
    }
}

final class ExternalDisplay {
    let service: AnyObject
    let name: String
    let serial: String

    // All DDC traffic must be serialized per display; concurrent I2C
    // transactions on the same bus corrupt each other.
    private let queue = DispatchQueue(label: "lumo.ddc")

    init(service: AnyObject, name: String, serial: String) {
        self.service = service
        self.name = name
        self.serial = serial
    }

    /// DDC/CI "Set VCP Feature": host (0x51) -> display (0x6E), payload [opcode 0x03, vcp, hi, lo].
    /// Checksum is XOR of destination address, source address and every payload byte.
    func write(vcp: UInt8, value: UInt16) -> Bool {
        var packet: [UInt8] = [0x84, 0x03, vcp, UInt8(value >> 8), UInt8(value & 0xFF), 0]
        packet[5] = packet[0..<5].reduce(0x6E ^ 0x51) { $0 ^ $1 }
        return queue.sync {
            for attempt in 0..<3 {
                usleep(attempt == 0 ? 10_000 : 40_000)
                if IOAVServiceWriteI2C(service, 0x37, 0x51, packet, UInt32(packet.count)) == KERN_SUCCESS {
                    return true
                }
            }
            return false
        }
    }

    /// DDC/CI "Get VCP Feature": request [opcode 0x01, vcp], reply carries max at bytes 6-7
    /// and current value at bytes 8-9.
    func read(vcp: UInt8) -> (current: UInt16, max: UInt16)? {
        var request: [UInt8] = [0x82, 0x01, vcp, 0]
        request[3] = request[0..<3].reduce(0x6E ^ 0x51) { $0 ^ $1 }
        return queue.sync {
            for attempt in 0..<4 {
                usleep(attempt == 0 ? 10_000 : 40_000)
                guard IOAVServiceWriteI2C(service, 0x37, 0x51, request, UInt32(request.count)) == KERN_SUCCESS else { continue }
                usleep(50_000)
                var reply = [UInt8](repeating: 0, count: 11)
                guard IOAVServiceReadI2C(service, 0x37, 0x51, &reply, UInt32(reply.count)) == KERN_SUCCESS else { continue }
                guard reply[2] == 0x02, reply[3] == 0x00, reply[4] == vcp else { continue }
                let checksum = reply[0..<10].reduce(0x50 as UInt8) { $0 ^ $1 }
                guard checksum == reply[10] else { continue }
                let max = UInt16(reply[6]) << 8 | UInt16(reply[7])
                let current = UInt16(reply[8]) << 8 | UInt16(reply[9])
                return (current, max)
            }
            return nil
        }
    }

    func readRaw(vcp: UInt8) -> [UInt8]? {
        var request: [UInt8] = [0x82, 0x01, vcp, 0]
        request[3] = request[0..<3].reduce(0x6E ^ 0x51) { $0 ^ $1 }
        return queue.sync {
            usleep(10_000)
            guard IOAVServiceWriteI2C(service, 0x37, 0x51, request, UInt32(request.count)) == KERN_SUCCESS else { return nil }
            usleep(50_000)
            var reply = [UInt8](repeating: 0, count: 11)
            guard IOAVServiceReadI2C(service, 0x37, 0x51, &reply, UInt32(reply.count)) == KERN_SUCCESS else { return nil }
            return reply
        }
    }

    static func enumerate() -> [ExternalDisplay] {
        var displays: [ExternalDisplay] = []
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            defer {
                IOObjectRelease(entry)
                entry = IOIteratorNext(iterator)
            }
            guard let location = IORegistryEntryCreateCFProperty(entry, "Location" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String,
                  location == "External",
                  let service = IOAVServiceCreateWithService(kCFAllocatorDefault, entry)?.takeRetainedValue()
            else { continue }

            var name = "External Display"
            var serial = ""
            var edidRef: Unmanaged<CFData>?
            if IOAVServiceCopyEDID(service, &edidRef) == KERN_SUCCESS, let edid = edidRef?.takeRetainedValue() as Data? {
                let parsed = parseEDID(edid)
                if let n = parsed.name { name = n }
                serial = parsed.serial
            }
            displays.append(ExternalDisplay(service: service, name: name, serial: serial))
        }
        return displays.sorted { $0.serial < $1.serial }
    }

    /// EDID block 0: serial number lives at bytes 12-15; the monitor name is in an
    /// 18-byte descriptor (tag 0xFC) somewhere in bytes 54-125.
    private static func parseEDID(_ edid: Data) -> (name: String?, serial: String) {
        guard edid.count >= 128 else { return (nil, "") }
        let serialValue = UInt32(edid[12]) | UInt32(edid[13]) << 8 | UInt32(edid[14]) << 16 | UInt32(edid[15]) << 24
        var name: String?
        for offset in stride(from: 54, to: 126, by: 18) {
            guard edid[offset] == 0, edid[offset + 1] == 0, edid[offset + 3] == 0xFC else { continue }
            let raw = edid[(offset + 5)..<(offset + 18)]
            name = String(bytes: raw, encoding: .ascii)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }
        return (name, String(serialValue))
    }
}

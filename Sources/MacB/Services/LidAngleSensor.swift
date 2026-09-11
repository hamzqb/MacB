import Foundation
import IOKit.hid

/// Reads how far the lid is open, in degrees.
///
/// Apple silicon MacBooks carry a hinge angle sensor on the HID bus. It is not
/// documented, so this only ever reads: the device is opened without seizing it,
/// a feature report is fetched, and anything outside nought to a hundred and
/// eighty is discarded rather than trusted. Machines without the sensor simply
/// report nothing and everything built on it stays switched off.
///
/// The matching criteria and the report layout come from Jhey Tompkins' Lid
/// Plane (MIT), recorded in THIRD_PARTY_NOTICES.md.
final class LidAngleSensor {
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
    private var device: IOHIDDevice?

    /// Why there is no reading, in words, for the settings page to show.
    private(set) var diagnostic = "Bu Mac'te menteşe açısı sensörü bulunamadı."

    var isAvailable: Bool { device != nil }

    init() {
        IOHIDManagerSetDeviceMatching(manager, [
            "VendorID": 0x05ac, "ProductID": 0x8104,
            "PrimaryUsagePage": 0x20, "PrimaryUsage": 0x8a
        ] as CFDictionary)
        guard IOHIDManagerOpen(manager, 0) == kIOReturnSuccess else {
            diagnostic = "HID erişimi açılamadı."
            return
        }
        let candidates = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
        for candidate in candidates {
            guard IOHIDDeviceOpen(candidate, 0) == kIOReturnSuccess else { continue }
            device = candidate
            if read() != nil {
                // Deliberately no angle here: this string is built once, and a
                // number from the moment the app launched would sit in the
                // settings window disagreeing with the live reading beside it.
                diagnostic = "Menteşe sensörü bağlı."
                return
            }
            IOHIDDeviceClose(candidate, 0)
            device = nil
        }
        if !candidates.isEmpty {
            diagnostic = "Sensör bulundu ama açı okunamadı."
        }
    }

    func read() -> Double? {
        guard let device else { return nil }
        var report = [UInt8](repeating: 0, count: 8)
        var length = report.count
        guard IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &report, &length) == kIOReturnSuccess,
              length >= 3 else { return nil }
        let angle = Double(UInt16(report[1]) | UInt16(report[2]) << 8)
        return (0...180).contains(angle) ? angle : nil
    }

    deinit {
        if let device { IOHIDDeviceClose(device, 0) }
        IOHIDManagerClose(manager, 0)
    }
}

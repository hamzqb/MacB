import Foundation

/// A page of System Settings MacB can open.
///
/// macOS does not let an application change most of these from the outside, and
/// the ones it does let through need an administrator or a private interface.
/// So MacB does the honest half: it opens the right page, and the person makes
/// the change. That is faster than describing where the setting lives, and it
/// never pretends to a power it does not have.
///
/// The list is closed, and each entry maps to an address written here. A pane
/// name the model invents opens nothing.
public enum SettingsPane: String, CaseIterable, Sendable {
    case sound, display, network, wifi, bluetooth, notifications, focus
    case keyboard, trackpad, mouse, battery, privacy, accessibility
    case appearance, general, storage, softwareUpdate = "software_update"
    case users, wallpaper, screenTime = "screen_time", printers, sharing
    case timeMachine = "time_machine", dateAndTime = "date_and_time"
    case siri, vpn, extensions

    /// The Turkish name of the page, for what MacB says afterwards.
    public var title: String {
        switch self {
        case .sound: return "Ses"
        case .display: return "Ekranlar"
        case .network: return "Ağ"
        case .wifi: return "Wi-Fi"
        case .bluetooth: return "Bluetooth"
        case .notifications: return "Bildirimler"
        case .focus: return "Odak"
        case .keyboard: return "Klavye"
        case .trackpad: return "İzleme Dörtgeni"
        case .mouse: return "Fare"
        case .battery: return "Pil"
        case .privacy: return "Gizlilik ve Güvenlik"
        case .accessibility: return "Erişilebilirlik"
        case .appearance: return "Görünüm"
        case .general: return "Genel"
        case .storage: return "Depolama"
        case .softwareUpdate: return "Yazılım Güncelleme"
        case .users: return "Kullanıcılar ve Gruplar"
        case .wallpaper: return "Masaüstü Arka Planı"
        case .screenTime: return "Ekran Süresi"
        case .printers: return "Yazıcılar ve Tarayıcılar"
        case .sharing: return "Paylaşım"
        case .timeMachine: return "Time Machine"
        case .dateAndTime: return "Tarih ve Saat"
        case .siri: return "Siri"
        case .vpn: return "VPN"
        case .extensions: return "Genişletmeler"
        }
    }

    /// The address that opens the page. `x-apple.systempreferences:` is the
    /// scheme macOS itself uses for this.
    public var address: String {
        let base = "x-apple.systempreferences:com.apple."
        switch self {
        case .sound: return base + "preference.sound"
        case .display: return base + "Displays-Settings.extension"
        case .network: return base + "Network-Settings.extension"
        case .wifi: return base + "wifi-settings-extension"
        case .bluetooth: return base + "BluetoothSettings"
        case .notifications: return base + "preference.notifications"
        case .focus: return base + "Focus-Settings.extension"
        case .keyboard: return base + "Keyboard-Settings.extension"
        case .trackpad: return base + "Trackpad-Settings.extension"
        case .mouse: return base + "Mouse-Settings.extension"
        case .battery: return base + "preference.battery"
        case .privacy: return base + "settings.PrivacySecurity.extension"
        case .accessibility: return base + "preference.universalaccess"
        case .appearance: return base + "Appearance-Settings.extension"
        case .general: return base + "systempreferences.GeneralSettings"
        case .storage: return base + "settings.Storage"
        case .softwareUpdate: return base + "Software-Update-Settings.extension"
        case .users: return base + "Users-Groups-Settings.extension"
        case .wallpaper: return base + "Wallpaper-Settings.extension"
        case .screenTime: return base + "Screen-Time-Settings.extension"
        case .printers: return base + "Print-Scan-Settings.extension"
        case .sharing: return base + "Sharing-Settings.extension"
        case .timeMachine: return base + "settings.TimeMachine"
        case .dateAndTime: return base + "Date-Time-Settings.extension"
        case .siri: return base + "Siri-Settings.extension"
        case .vpn: return base + "NetworkExtensionSettingsUI.NESettingsUIExtension"
        case .extensions: return base + "ExtensionsPreferences"
        }
    }
}

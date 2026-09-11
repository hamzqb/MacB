import AppKit
import Darwin
import Foundation

/// Stops macOS from drawing its own volume panel while MacB draws one.
///
/// macOS renders that panel from a helper process that launchd starts on demand
/// and lets exit again. Pausing that process stops the panel without modifying,
/// replacing or patching anything: the process is owned by the same user, the
/// signal is the ordinary one a shell sends with Ctrl-Z, and resuming it puts
/// everything back.
///
/// The cost is stated plainly in settings, because it is not only the volume
/// panel: brightness, caps lock and the AirPods banner come from the same
/// helper, and MacB replaces only the volume one.
@MainActor final class SystemHUDSuppressor {
    private static let helperPath = "/System/Library/CoreServices/OSDUIHelper.app"
    private static let processName = "OSDUIHelper"

    private(set) var isSuppressing = false

    /// Resumes the helper if a previous run left it paused.
    ///
    /// A crash cannot run cleanup code, so the repair happens on the way in
    /// rather than only on the way out.
    func repairAfterCrash() {
        guard let pid = Self.helperProcessID() else { return }
        kill(pid, SIGCONT)
    }

    func setSuppressing(_ suppressing: Bool) {
        guard suppressing != isSuppressing else {
            // Re-apply anyway: the helper may have been restarted since.
            if suppressing { applyStop() }
            return
        }
        isSuppressing = suppressing
        if suppressing { applyStop() } else { resume() }
    }

    func resume() {
        isSuppressing = false
        guard let pid = Self.helperProcessID() else { return }
        kill(pid, SIGCONT)
    }

    private func applyStop() {
        if let pid = Self.helperProcessID() {
            kill(pid, SIGSTOP)
            return
        }
        // Not running yet. Start it once so the first key press has nothing left
        // to draw, rather than flashing the system panel one last time.
        let url = URL(fileURLWithPath: Self.helperPath)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] _, _ in
            Task { @MainActor in
                guard let self, self.isSuppressing else { return }
                // Give launchd a moment to publish the process before signalling.
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard self.isSuppressing, let pid = Self.helperProcessID() else { return }
                kill(pid, SIGSTOP)
            }
        }
    }

    /// Finds the helper without shelling out, by walking the kernel process list.
    private static func helperProcessID() -> pid_t? {
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var length = 0
        guard sysctl(&name, UInt32(name.count - 1), nil, &length, nil, 0) == 0, length > 0 else { return nil }
        let count = length / MemoryLayout<kinfo_proc>.stride
        var processes = [kinfo_proc](repeating: kinfo_proc(), count: count)
        guard sysctl(&name, UInt32(name.count - 1), &processes, &length, nil, 0) == 0 else { return nil }
        let found = length / MemoryLayout<kinfo_proc>.stride
        let uid = getuid()
        for index in 0..<min(found, processes.count) {
            var process = processes[index]
            guard process.kp_eproc.e_ucred.cr_uid == uid else { continue }
            let comm = withUnsafeBytes(of: &process.kp_proc.p_comm) { raw -> String in
                let bytes = raw.bindMemory(to: CChar.self)
                return String(cString: Array(bytes) + [0])
            }
            // p_comm is truncated to 16 characters, so match the prefix.
            if processName.hasPrefix(comm) || comm.hasPrefix(String(processName.prefix(15))) {
                return process.kp_proc.p_pid
            }
        }
        return nil
    }
}

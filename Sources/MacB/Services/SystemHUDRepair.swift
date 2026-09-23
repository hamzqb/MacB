import Darwin
import Foundation

/// Hands the volume and brightness indicator over to MacB, and hands it back.
///
/// macOS draws its own volume, brightness and Caps Lock panels from
/// `OSDUIHelper`, a small process of the user's own. There is no supported way
/// to ask it to stay quiet, so MacB pauses it (SIGSTOP) while its own island
/// indicator is doing the job, and resumes it (SIGCONT) the moment the setting
/// is turned off, the app quits, or the app is killed and started again.
///
/// Nothing is installed, nothing is deleted and no permission is needed: the
/// helper belongs to the same user. A paused process keeps its place; it draws
/// nothing while it is paused and picks up normally afterwards. macOS restarts
/// the helper with a new process id from time to time, so a paused state has to
/// be reapplied rather than set once.
enum SystemHUDRepair {
    private static let processName = "OSDUIHelper"

    /// Resumes the helper. Sending SIGCONT to a process that is already
    /// running does nothing, which is what makes this safe to call at every
    /// launch — including after a crash that left it paused.
    static func resumeIndicatorHelper() {
        guard let pid = helperProcessID() else { return }
        kill(pid, SIGCONT)
    }

    /// Pauses the helper if it is running and not already paused.
    ///
    /// Returns true when the helper is paused afterwards. A helper that is not
    /// running yet is not an error: macOS starts it at the first key press,
    /// and the next call catches it.
    @discardableResult
    static func pauseIndicatorHelper() -> Bool {
        guard let process = helperProcess() else { return false }
        if process.isStopped { return true }
        return kill(process.pid, SIGSTOP) == 0
    }

    static var isIndicatorHelperPaused: Bool { helperProcess()?.isStopped ?? false }

    static var isIndicatorHelperRunning: Bool { helperProcess() != nil }

    private struct Helper {
        var pid: pid_t
        var isStopped: Bool
    }

    private static func helperProcessID() -> pid_t? { helperProcess()?.pid }

    /// Only this user's own copy of the helper, found by name.
    private static func helperProcess() -> Helper? {
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
            guard processName.hasPrefix(comm) || comm.hasPrefix(String(processName.prefix(15))) else { continue }
            return Helper(pid: process.kp_proc.p_pid, isStopped: process.kp_proc.p_stat == SSTOP)
        }
        return nil
    }
}

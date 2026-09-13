import Darwin
import Foundation

/// Undoes the pause an older MacB used to put on the macOS indicator helper.
///
/// Until this version MacB could take over the volume panel by stopping
/// `OSDUIHelper`, the process macOS draws volume, brightness and Caps Lock
/// from. That feature is gone, but a Mac that was running the old build when it
/// quit unexpectedly still has the helper stopped, and nothing else would ever
/// start it again: the user would simply have no indicators, with no way to
/// guess why.
///
/// So MacB resumes it once at launch and never touches it otherwise. Sending
/// SIGCONT to a process that is already running does nothing at all, which is
/// what makes this safe to run every time rather than tracking whether it is
/// needed.
enum SystemHUDRepair {
    private static let processName = "OSDUIHelper"

    static func resumeIndicatorHelper() {
        guard let pid = helperProcessID() else { return }
        kill(pid, SIGCONT)
    }

    /// Only this user's own copy of the helper, found by name.
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

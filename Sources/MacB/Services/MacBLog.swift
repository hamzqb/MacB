import Foundation

/// A line of explanation, for when MacB is being run from a terminal to find
/// out why something took so long.
///
/// Off unless `MACB_VERBOSE` is set, so a normal run says nothing. Nothing
/// here ever carries what the user asked, what was answered, or any key:
/// which provider, which model, how long.
@MainActor enum MacBLog {
    static var isVerbose = ProcessInfo.processInfo.environment["MACB_VERBOSE"] != nil
        || CommandLine.arguments.contains("--verbose")

    static func note(_ message: @autoclosure () -> String) {
        guard isVerbose else { return }
        print("· " + message())
    }
}

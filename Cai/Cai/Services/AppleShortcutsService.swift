import AppKit
import Foundation

/// Reads the user's Apple Shortcuts.app library via the `/usr/bin/shortcuts`
/// CLI, and exposes the Shortcuts.app icon for chip rendering.
///
/// **Why an actor:** the underlying `Process` invocation is I/O-bound; we
/// don't want to spawn `shortcuts list` from the main thread (would beachball
/// on machines with 100+ shortcuts). All public methods are async.
///
/// **Why no caching:** we deliberately re-fetch on every dropdown open. The
/// CLI is fast (~50-200ms cold). Caching would create a stale-data window
/// when the user creates a new shortcut in Shortcuts.app and immediately
/// returns to Cai expecting it to appear. Re-fetch on demand is the simpler
/// + correct trade-off until performance complaints surface.
///
/// **Per-shortcut icons** are not exposed by the CLI as of macOS 14
/// (`shortcuts list --output-format json` doesn't exist; the plain
/// `shortcuts list` returns names only). We use the Shortcuts.app
/// application icon for all entries — visually distinct, recognizable
/// (rainbow gradient), and zero risk vs. reading private sidecar files.
/// Per-shortcut icons could be added in a future release via
/// `~/Library/Shortcuts/...` sidecar parsing if user demand justifies the
/// fragility.
actor AppleShortcutsService {

    static let shared = AppleShortcutsService()

    /// Lists the user's Apple Shortcuts by name, sorted alphabetically.
    /// Empty array if the user has no shortcuts (or `shortcuts list` fails —
    /// we swallow errors here because a missing/empty shortcuts library is
    /// not actionable for the user, and the chain editor just shows an
    /// empty section in that case).
    func list() async -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["list"]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()  // discard stderr noise

        do {
            try process.run()
        } catch {
            // /usr/bin/shortcuts not installed (impossible on macOS 14+ but
            // defensive) — return empty rather than crashing the editor.
            return []
        }

        // 5s timeout — shortcuts list should complete in <1s on any
        // realistic library. If it hangs we'd rather bail than block the
        // dropdown indefinitely.
        let exitTask = Task.detached { process.waitUntilExit() }
        let timeoutTask = Task.detached {
            try await Task.sleep(nanoseconds: 5 * 1_000_000_000)
            process.terminate()
        }
        await exitTask.value
        timeoutTask.cancel()

        guard process.terminationStatus == 0 else { return [] }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .sorted()
    }

    // MARK: - Icon

    /// Shortcuts.app application icon (rainbow gradient). Used as the chip
    /// glyph for every Apple Shortcut entry in the chain editor. Cached on
    /// first access; the icon doesn't change between launches.
    @MainActor
    static let appIcon: NSImage = {
        let path = "/System/Applications/Shortcuts.app"
        if FileManager.default.fileExists(atPath: path) {
            return NSWorkspace.shared.icon(forFile: path)
        }
        // Fallback to the generic application icon if Shortcuts.app isn't
        // at the expected path (shouldn't happen on macOS 14+ but defensive).
        return NSWorkspace.shared.icon(for: .application)
    }()
}

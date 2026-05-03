import Foundation

// MARK: - Background Task Tracker

/// Tracks the count of in-flight background tasks so the UI can surface a
/// "Cai is working…" indicator (menu bar icon pulse + tooltip).
///
/// Used today by background shell-shortcut execution (the `runInBackground`
/// path triggered when a `.shell` shortcut has `runInBackground == true` or
/// its template contains `|llm`). Could be extended to other long-running
/// async work in the future (e.g. extension catalog refresh).
///
/// **Lifecycle:** callers wrap their async work in `tracking { ... }` or call
/// `start()`/`end()` manually as a matched pair. The tracker increments the
/// counter on start and decrements on end; observers see `isBusy == true`
/// whenever the counter is positive.
///
/// **Threading:** `@MainActor`-isolated because it drives UI updates via
/// `@Published`. Callers from background contexts hop to the main actor
/// briefly to mutate state — the mutation itself is trivial; the actual work
/// runs off-main inside the wrapped block.
@MainActor
final class BackgroundTaskTracker: ObservableObject {

    static let shared = BackgroundTaskTracker()

    private init() {}

    /// Number of background tasks currently in flight. `@Published` so SwiftUI
    /// views and AppKit observers (e.g. AppDelegate's status-item animator)
    /// can react to changes.
    @Published private(set) var activeTaskCount: Int = 0

    /// Convenience: true while any background task is running.
    var isBusy: Bool { activeTaskCount > 0 }

    // MARK: - Manual start/end

    /// Increment the active-task counter. Must be paired with `end()`.
    /// Prefer `tracking(_:)` when possible — it can't accidentally leak the
    /// counter on early return / throw paths.
    func start() {
        activeTaskCount += 1
    }

    /// Decrement the active-task counter. Clamped at zero so a stray extra
    /// `end()` call can't drop the counter into negative territory.
    func end() {
        activeTaskCount = max(0, activeTaskCount - 1)
    }

    // MARK: - Tracked block

    /// Runs `block` inside a tracked window — increments the counter before,
    /// decrements after (even on throw), and returns the block's result.
    /// Use this when your block is `async throws` and you don't want to
    /// hand-balance `start()`/`end()` across the throw path.
    func tracking<T>(_ block: () async throws -> T) async rethrows -> T {
        start()
        do {
            let result = try await block()
            end()
            return result
        } catch {
            end()
            throw error
        }
    }
}

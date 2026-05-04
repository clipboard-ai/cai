import AppKit
import Foundation

// MARK: - Chain Executor

/// Runs a sequential chain of Cai actions (`Shortcut.next` / `OutputDestination.next`).
///
/// **Design (locked 2026-05-04):**
/// - Sequential pipe: A → B → C, where each step's output becomes the next
///   step's `{{result}}`.
/// - **NOT routed through the system clipboard.** The chain holds an
///   in-memory pipe value so the user can copy other text mid-chain without
///   breaking the flow. Live clipboard is read once at chain start (the
///   initial pipe value) and never touched again unless an action explicitly
///   writes to it via `pbcopy` etc.
/// - Cycle detection: tracks visited slugs; throws if a cycle is detected.
/// - Max depth: hard cap of 10 steps; throws if exceeded. Catches runaway
///   loops the cycle check might miss (e.g., 50 distinct slugs in a line).
/// - Lookup is by `name`, preferring shortcuts over destinations on collision.
/// - Per-step output convention:
///     - shortcut `.shell`     → stdout (trimmed)
///     - shortcut `.prompt`    → LLM response (trimmed)
///     - shortcut `.url`       → "" (URL was opened; nothing to propagate)
///     - destination of any kind → "" (side-effect actions; chain output ends)
///   Empty pipe values flow through cleanly; the next step gets "".
/// - MCP form actions are not chainable in v1 (multi-field inputs don't fit
///   the single-pipe model). They can be `next:` *targets* in v2 if demand
///   surfaces, but not v1 sources.
///
/// **Threading:** `@MainActor`-isolated for safe access to `CaiSettings.shared`
/// and notification posting. Long-running work (LLM, shell) hops to background
/// queues internally. Reuses `BackgroundTaskTracker` so the menu bar icon
/// pulses for the duration of the chain (free UX from step 7).
///
/// **Toast UX:** on success, posts `caiShowToast` with the final action's
/// name. On failure, posts a toast naming the failing step + reason. The
/// chain aborts at the first failure; no partial-success retries.
@MainActor
final class ChainExecutor {

    static let shared = ChainExecutor()

    /// Resolves an action name to either a `CaiShortcut` or `OutputDestination`.
    /// The production resolver reads from `CaiSettings.shared`; tests inject a
    /// closure that returns from a known fixture map so they don't depend on
    /// the global singleton's state.
    typealias Resolver = @MainActor (String) -> ResolvedAction?

    private let injectedResolver: Resolver?

    /// Default init wires the production singleton-backed resolver. Tests use
    /// `init(resolver:)` to supply a fixture-backed closure.
    init(resolver: Resolver? = nil) {
        self.injectedResolver = resolver
    }

    /// Hard cap on chain depth. Catches pathological non-cyclic chains
    /// (50+ distinct slugs in a line) and provides belt-and-suspenders
    /// safety against any cycle the visited-set check might miss. Realistic
    /// chains are 2-4 steps; 10 is generous headroom.
    static let maxDepth = 10

    // MARK: - Errors

    enum ChainError: Error, LocalizedError {
        case unknownAction(String)
        case cycle(detected: String, path: [String])
        case tooDeep(maxDepth: Int)
        case stepFailed(action: String, underlying: Error)
        case unsupportedActionType(String)

        var errorDescription: String? {
            switch self {
            case .unknownAction(let name):
                return "Chain step not found: '\(name)'. Check the action name."
            case .cycle(let slug, let path):
                let pathStr = (path + [slug]).joined(separator: " → ")
                return "Chain cycle detected: \(pathStr)"
            case .tooDeep(let max):
                return "Chain exceeded \(max) steps. Possible runaway."
            case .stepFailed(let action, let underlying):
                return "Step '\(action)' failed: \(underlying.localizedDescription)"
            case .unsupportedActionType(let type):
                return "Action type '\(type)' can't be used in a chain (v1)."
            }
        }
    }

    // MARK: - Resolved action wrapper
    //
    // Lookup happens by `name`. Shortcuts win on collision with destinations,
    // mirroring the action-list dispatch order.
    //
    // Internal (not private) so tests can construct fixtures via `Resolver`.

    enum ResolvedAction {
        case shortcut(CaiShortcut)
        case destination(OutputDestination)

        var name: String {
            switch self {
            case .shortcut(let s): return s.name
            case .destination(let d): return d.name
            }
        }

        var next: [String] {
            switch self {
            case .shortcut(let s): return s.next
            case .destination(let d): return d.next
            }
        }
    }

    // MARK: - Public entry

    /// Runs a chain. Use this when an action that's been triggered has a
    /// non-empty `next:` list.
    ///
    /// Pulses the menu bar icon for the chain duration (via
    /// `BackgroundTaskTracker.shared`). Surfaces a toast on completion.
    ///
    /// - Parameters:
    ///   - slugs: ordered list of action names to run.
    ///   - initialInput: the starting pipe value (typically the user's
    ///     clipboard at chain start).
    ///   - sourceBundleId: bundle ID of the app the user copied from; forwarded
    ///     to `|llm` filters and Context Snippet lookups.
    func runChain(
        _ slugs: [String],
        initialInput: String,
        sourceBundleId: String?
    ) async {
        BackgroundTaskTracker.shared.start()
        defer { BackgroundTaskTracker.shared.end() }

        do {
            let finalOutput = try await execute(
                slugs: slugs,
                pipe: initialInput,
                sourceBundleId: sourceBundleId,
                visited: [],
                depth: 0
            )
            // Toast with last step's name + brief output snippet (trimmed,
            // first 80 chars) so the user knows the chain completed.
            let snippet = String(finalOutput.prefix(80))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let lastStepName = slugs.last ?? "chain"
            let message = snippet.isEmpty
                ? "Done — \(lastStepName)"
                : snippet
            NotificationCenter.default.post(
                name: .caiShowToast,
                object: nil,
                userInfo: ["message": message]
            )
        } catch {
            NotificationCenter.default.post(
                name: .caiShowToast,
                object: nil,
                userInfo: ["message": "Chain failed: \(error.localizedDescription)"]
            )
        }
    }

    // MARK: - Recursive executor

    /// Executes the slugs sequentially. Returns the final pipe value.
    /// Each step also runs ITS OWN `next:` chain before returning, so a chain
    /// of [A→B] where A also has `next: [Z]` produces A → Z → B (depth-first).
    private func execute(
        slugs: [String],
        pipe: String,
        sourceBundleId: String?,
        visited: Set<String>,
        depth: Int
    ) async throws -> String {
        var currentPipe = pipe
        var currentVisited = visited

        for slug in slugs {
            if depth >= Self.maxDepth {
                throw ChainError.tooDeep(maxDepth: Self.maxDepth)
            }
            if currentVisited.contains(slug) {
                throw ChainError.cycle(detected: slug, path: Array(currentVisited))
            }
            guard let resolved = resolve(slug) else {
                throw ChainError.unknownAction(slug)
            }
            currentVisited.insert(slug)

            // Run the step.
            let stepOutput: String
            do {
                stepOutput = try await runOne(
                    resolved,
                    input: currentPipe,
                    sourceBundleId: sourceBundleId
                )
            } catch {
                throw ChainError.stepFailed(action: resolved.name, underlying: error)
            }

            currentPipe = stepOutput

            // Recurse into this action's own `next:` before moving on to the
            // next sibling slug. Depth-first preserves the natural reading of
            // "A says: after me, run X. Then come back and run B."
            if !resolved.next.isEmpty {
                currentPipe = try await execute(
                    slugs: resolved.next,
                    pipe: currentPipe,
                    sourceBundleId: sourceBundleId,
                    visited: currentVisited,
                    depth: depth + 1
                )
            }
        }

        return currentPipe
    }

    // MARK: - Lookup

    private func resolve(_ name: String) -> ResolvedAction? {
        if let injected = injectedResolver {
            return injected(name)
        }
        if let shortcut = CaiSettings.shared.shortcuts.first(where: { $0.name == name }) {
            return .shortcut(shortcut)
        }
        if let dest = CaiSettings.shared.outputDestinations.first(where: { $0.name == name }) {
            return .destination(dest)
        }
        return nil
    }

    // MARK: - Test entry
    //
    // Exposes the throwing recursive executor so tests can assert directly on
    // outputs and `ChainError` cases. The public `runChain(...)` wraps this
    // with toast + tracker plumbing, both of which are tedious to test.

    #if DEBUG
    func executeForTesting(
        slugs: [String],
        initialInput: String,
        sourceBundleId: String? = nil
    ) async throws -> String {
        try await execute(
            slugs: slugs,
            pipe: initialInput,
            sourceBundleId: sourceBundleId,
            visited: [],
            depth: 0
        )
    }
    #endif

    // MARK: - Single-step dispatch

    private func runOne(
        _ action: ResolvedAction,
        input: String,
        sourceBundleId: String?
    ) async throws -> String {
        switch action {
        case .shortcut(let s):
            switch s.type {
            case .shell:
                return try await runShell(template: s.value, input: input, sourceBundleId: sourceBundleId)
            case .prompt:
                return try await runPrompt(prompt: s.value, input: input, sourceBundleId: sourceBundleId)
            case .url:
                let resolved = try await TemplateEngine.render(
                    s.value.replacingOccurrences(of: "%s", with: "{{result|url_encode|raw}}"),
                    vars: ["result": input],
                    context: .raw,
                    sourceBundleId: sourceBundleId
                )
                if let url = URL(string: resolved) {
                    NSWorkspace.shared.open(url)
                }
                return ""  // URL actions don't propagate output
            }
        case .destination(let d):
            // OutputDestinationService is an actor; it handles its own threading.
            try await OutputDestinationService.shared.execute(d, with: input, sourceBundleId: sourceBundleId)
            return ""  // destinations don't propagate output for v1
        }
    }

    // MARK: - Shell shortcut runner
    //
    // Mirrors `ActionListWindow.runShellCommand`. TODO: extract to a shared
    // ShellRunner helper in v1.7 polish — right now there are two copies.

    private func runShell(template: String, input: String, sourceBundleId: String?) async throws -> String {
        let resolved = try await TemplateEngine.render(
            template,
            vars: ["result": input],
            context: .shell,
            sourceBundleId: sourceBundleId
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", resolved]

        // Stdin = pipe value (so users can `cat`-style consume it in their command)
        let inputPipe = Pipe()
        let inputData = input.data(using: .utf8) ?? Data()
        inputPipe.fileHandleForWriting.write(inputData)
        inputPipe.fileHandleForWriting.closeFile()
        process.standardInput = inputPipe

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()

        // 60s timeout — same as runShellCommand. Generous buffer for |llm
        // cold start + the actual command (e.g., `say` reading a sentence).
        let exitTask = Task.detached { process.waitUntilExit() }
        let timeoutTask = Task.detached {
            try await Task.sleep(nanoseconds: 60 * 1_000_000_000)
            process.terminate()
        }
        await exitTask.value
        timeoutTask.cancel()

        if process.terminationReason == .uncaughtSignal {
            throw NSError(domain: "Cai", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Shell command exceeded 60s and was stopped"
            ])
        }

        let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            let message = stderr.isEmpty
                ? "Command failed with exit code \(process.terminationStatus)"
                : stderr
            throw NSError(domain: "Cai", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: message
            ])
        }

        return stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Prompt shortcut runner
    //
    // Builds messages via `LLMService.buildMessages` (which handles "About You"
    // and Context Snippet injection) and dispatches via `generateWithMessages`.

    private func runPrompt(prompt: String, input: String, sourceBundleId: String?) async throws -> String {
        // Substitute {{result}} in the prompt with the pipe value, plus any
        // standard variables the engine knows about. Context.raw means no
        // automatic escaping — the prompt is sent verbatim to the LLM.
        let userPrompt = try await TemplateEngine.render(
            prompt,
            vars: ["result": input],
            context: .raw,
            sourceBundleId: sourceBundleId
        )

        let aboutYou = CaiSettings.shared.aboutYou
        let snippet = ContextSnippetsManager.shared.snippet(forBundleId: sourceBundleId)

        // System prompt frames the LLM for "output the result, no preamble"
        // so chain steps can compose cleanly. User-defined prompts sometimes
        // bury the actual ask in conversational context; this keeps output tight.
        let systemPrompt = """
            Output ONLY the result. No preamble, no explanations, no quotes around \
            the output. Plain text, no markdown.
            """

        let messages = LLMService.buildMessages(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            aboutYou: aboutYou,
            snippet: snippet
        )

        let response = try await LLMService.shared.generateWithMessages(messages)
        return response.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

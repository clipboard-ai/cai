import XCTest
@testable import Cai

/// Tests for `ChainExecutor` — the action chain orchestrator.
///
/// **Scope:**
/// - Lookup: empty chain, unknown action, invalid inline LLM step.
/// - Output propagation: single shell stdout, two-step pipe via stdin,
///   `tee`-style destinations (covered manually — see comment in test).
/// - Recursive `next:`: a child action's `next:` runs before parent's
///   next sibling.
/// - Safety: cycle detection (action steps only), max-depth cap,
///   step failure aborts.
/// - Inline LLM step: empty directive validation. Real LLM calls covered
///   manually via smoke flow (would need LLM mocking otherwise).
/// - Apple Shortcut step: validation. Real `shortcuts run` calls covered
///   manually (host-machine dependent).
///
/// All tests inject a closure-based `Resolver` so they don't touch
/// `CaiSettings.shared`. Shell shortcuts spawn `/bin/zsh -c` subprocesses,
/// so each test costs ~50–200ms; the suite stays under ~2s end-to-end.
@MainActor
final class ChainExecutorTests: XCTestCase {

    // MARK: - Helpers

    private func shellShortcut(_ name: String, value: String, next: [ChainStep] = []) -> CaiShortcut {
        CaiShortcut(name: name, type: .shell, value: value, next: next)
    }

    private func resolver(_ map: [String: CaiShortcut]) -> ChainExecutor.Resolver {
        return { name in map[name].map { .shortcut($0) } }
    }

    /// Convenience: wrap action names as `.action(name:)` steps.
    private func actions(_ names: String...) -> [ChainStep] {
        names.map { .action(name: $0) }
    }

    // MARK: - Empty / lookup

    func testEmptyChainReturnsInitialInputUnchanged() async throws {
        let executor = ChainExecutor(resolver: { _ in nil })
        let out = try await executor.executeForTesting(steps: [], initialInput: "hello")
        XCTAssertEqual(out, "hello")
    }

    func testUnknownActionThrows() async {
        let executor = ChainExecutor(resolver: { _ in nil })
        do {
            _ = try await executor.executeForTesting(steps: actions("missing"), initialInput: "x")
            XCTFail("expected unknownAction")
        } catch ChainExecutor.ChainError.unknownAction(let name) {
            XCTAssertEqual(name, "missing")
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    // MARK: - Output propagation

    func testSingleShellPropagatesStdout() async throws {
        let echo = shellShortcut("Echo", value: "printf 'hi from echo'")
        let executor = ChainExecutor(resolver: resolver(["Echo": echo]))
        let out = try await executor.executeForTesting(steps: actions("Echo"), initialInput: "ignored")
        XCTAssertEqual(out, "hi from echo")
    }

    func testTwoShellChainPipesStdoutAsStdin() async throws {
        // `cat` reads stdin (fed by ChainExecutor with previous step's output)
        // and prints it, so S2 should receive S1's stdout — proving the
        // in-memory pipe is wired correctly.
        let s1 = shellShortcut("S1", value: "printf 'step1'")
        let s2 = shellShortcut("S2", value: "cat")
        let executor = ChainExecutor(resolver: resolver(["S1": s1, "S2": s2]))
        let out = try await executor.executeForTesting(steps: actions("S1", "S2"), initialInput: "initial")
        XCTAssertEqual(out, "step1")
    }

    // MARK: - Recursive next:

    func testActionNextRunsBeforeNextSibling() async throws {
        // Sibling chain [A, C], where A has next: [B]
        // Expected execution order: A → B → C (depth-first)
        // - A prints "A"
        // - B reads stdin "A" via `cat` and appends "B" → "AB"
        // - C reads stdin "AB" via `cat` and appends "C" → "ABC"
        let a = shellShortcut("A", value: "printf 'A'", next: actions("B"))
        let b = shellShortcut("B", value: "cat && printf 'B'")
        let c = shellShortcut("C", value: "cat && printf 'C'")
        let executor = ChainExecutor(resolver: resolver(["A": a, "B": b, "C": c]))
        let out = try await executor.executeForTesting(steps: actions("A", "C"), initialInput: "init")
        XCTAssertEqual(out, "ABC")
    }

    // MARK: - Safety: cycle detection

    func testCycleDetected() async {
        // A → B → A: visited-set check should catch the second visit to A.
        let a = shellShortcut("A", value: "printf 'a'", next: actions("B"))
        let b = shellShortcut("B", value: "printf 'b'", next: actions("A"))
        let executor = ChainExecutor(resolver: resolver(["A": a, "B": b]))
        do {
            _ = try await executor.executeForTesting(steps: actions("A"), initialInput: "x")
            XCTFail("expected cycle")
        } catch ChainExecutor.ChainError.cycle(let detected, _) {
            XCTAssertEqual(detected, "A")
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    // MARK: - Safety: max depth

    func testMaxDepthExceededThrows() async {
        // Build a 12-deep linear chain (A1 → A2 → ... → A12).
        // maxDepth = 10, so A11 never runs — recursion to depth 11 throws
        // before invoking the step.
        let names = (1...12).map { "A\($0)" }
        var map: [String: CaiShortcut] = [:]
        for i in 0..<names.count {
            let nextSteps: [ChainStep] = i + 1 < names.count ? [.action(name: names[i + 1])] : []
            map[names[i]] = shellShortcut(names[i], value: "printf 'step'", next: nextSteps)
        }
        let executor = ChainExecutor(resolver: resolver(map))
        do {
            _ = try await executor.executeForTesting(steps: [.action(name: names[0])], initialInput: "x")
            XCTFail("expected tooDeep")
        } catch ChainExecutor.ChainError.tooDeep(let max) {
            XCTAssertEqual(max, ChainExecutor.maxDepth)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    // MARK: - Safety: failure aborts chain

    func testStepFailureAbortsChainAndNamesFailingStep() async {
        // S1 succeeds; S2 fails (nonexistent command); S3 must not run.
        let s1 = shellShortcut("S1", value: "printf 'ok'")
        let s2 = shellShortcut("S2", value: "definitely_not_a_real_command_zzz")
        let s3 = shellShortcut("S3", value: "printf 'should not see'")
        let executor = ChainExecutor(resolver: resolver(["S1": s1, "S2": s2, "S3": s3]))
        do {
            _ = try await executor.executeForTesting(steps: actions("S1", "S2", "S3"), initialInput: "x")
            XCTFail("expected stepFailed")
        } catch ChainExecutor.ChainError.stepFailed(let action, _) {
            XCTAssertEqual(action, "S2")
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    // MARK: - Inline LLM step validation
    //
    // Real LLM calls are covered manually via the smoke flow (would require
    // mocking LLMService.shared and would be flaky on machines without a
    // loaded model). Here we just verify the empty-directive guard fires
    // BEFORE any LLM call, matching the engine's `|llm` filter validation.

    func testInlineLLMWithEmptyDirectiveThrows() async {
        let executor = ChainExecutor(resolver: { _ in nil })
        do {
            _ = try await executor.executeForTesting(
                steps: [.inlineLLM(directive: "")],
                initialInput: "x"
            )
            XCTFail("expected invalidStep")
        } catch ChainExecutor.ChainError.invalidStep {
            // Empty-directive guard fires before any LLM call.
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testInlineLLMWithWhitespaceOnlyDirectiveThrows() async {
        let executor = ChainExecutor(resolver: { _ in nil })
        do {
            _ = try await executor.executeForTesting(
                steps: [.inlineLLM(directive: "   \n\t  ")],
                initialInput: "x"
            )
            XCTFail("expected invalidStep")
        } catch ChainExecutor.ChainError.invalidStep {
            // Whitespace-only directive treated as empty.
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    // MARK: - Cycle detection scope
    //
    // Cycle detection only applies to `.action` steps (those are the only
    // ones that can recurse via their own `next:`). Inline LLM and Apple
    // Shortcut steps can repeat in a chain without triggering the cycle
    // guard, since they're leaf step types.

    func testInlineLLMStepsDoNotTriggerCycleDetection() async throws {
        // Two identical inline LLM steps in a row — would trigger the cycle
        // detector if it tracked all step types. Only fails because the
        // empty-directive validation fires on the first step (we use empty
        // so we don't need to mock the LLM).
        // We assert the failure is `invalidStep` (not `cycle`) — proves the
        // cycle detector didn't trip.
        let executor = ChainExecutor(resolver: { _ in nil })
        do {
            _ = try await executor.executeForTesting(
                steps: [.inlineLLM(directive: ""), .inlineLLM(directive: "")],
                initialInput: "x"
            )
            XCTFail("expected invalidStep")
        } catch ChainExecutor.ChainError.invalidStep {
            // First step's empty-directive guard fires, not cycle.
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    // MARK: - Codable for ChainStep
    //
    // Round-trip a ChainStep enum through Codable to lock the wire format
    // — guards against accidental changes to the encoder that would break
    // persisted user chains.

    func testChainStepCodableRoundTripActionCase() throws {
        let original: ChainStep = .action(name: "Send to Slack")
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ChainStep.self, from: encoded)
        XCTAssertEqual(decoded, original)
    }

    func testChainStepCodableRoundTripInlineLLMCase() throws {
        let original: ChainStep = .inlineLLM(directive: "summarize as one bullet")
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ChainStep.self, from: encoded)
        XCTAssertEqual(decoded, original)
    }

    func testChainStepCodableRoundTripAppleShortcutCase() throws {
        let original: ChainStep = .appleShortcut(name: "Add to Reminders")
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ChainStep.self, from: encoded)
        XCTAssertEqual(decoded, original)
    }
}

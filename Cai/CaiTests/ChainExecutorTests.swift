import XCTest
@testable import Cai

/// Tests for `ChainExecutor` — the v1.6 action chain orchestrator.
///
/// **Scope (locked 2026-05-04):**
/// - Lookup: empty chain, unknown slug.
/// - Output propagation: single shell stdout, two-step pipe via stdin.
/// - Recursive `next:`: a child's `next:` runs before the parent's next sibling.
/// - Safety: cycle detection, max-depth cap, step failure aborts.
///
/// **Out of scope (deferred):**
/// - `.prompt` shortcuts (would require LLM mocking; covered manually via the
///   smoke flow).
/// - Destinations (would require `OutputDestinationService` mocking; v1.7).
///
/// All tests inject a closure-based `Resolver` so they don't touch
/// `CaiSettings.shared`. Shell shortcuts spawn `/bin/zsh -c` subprocesses, so
/// each test costs ~50–200ms; the suite stays under ~2s end-to-end.
@MainActor
final class ChainExecutorTests: XCTestCase {

    // MARK: - Helpers

    private func shellShortcut(_ name: String, value: String, next: [String] = []) -> CaiShortcut {
        CaiShortcut(name: name, type: .shell, value: value, next: next)
    }

    private func resolver(_ map: [String: CaiShortcut]) -> ChainExecutor.Resolver {
        return { name in map[name].map { .shortcut($0) } }
    }

    // MARK: - Empty / lookup

    func testEmptyChainReturnsInitialInputUnchanged() async throws {
        let executor = ChainExecutor(resolver: { _ in nil })
        let out = try await executor.executeForTesting(slugs: [], initialInput: "hello")
        XCTAssertEqual(out, "hello")
    }

    func testUnknownSlugThrows() async {
        let executor = ChainExecutor(resolver: { _ in nil })
        do {
            _ = try await executor.executeForTesting(slugs: ["missing"], initialInput: "x")
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
        let out = try await executor.executeForTesting(slugs: ["Echo"], initialInput: "ignored")
        XCTAssertEqual(out, "hi from echo")
    }

    func testTwoShellChainPipesStdoutAsStdin() async throws {
        // `cat` reads stdin (fed by ChainExecutor with previous step's output)
        // and prints it, so S2 should receive S1's stdout — proving the
        // in-memory pipe is wired correctly.
        let s1 = shellShortcut("S1", value: "printf 'step1'")
        let s2 = shellShortcut("S2", value: "cat")
        let executor = ChainExecutor(resolver: resolver(["S1": s1, "S2": s2]))
        let out = try await executor.executeForTesting(slugs: ["S1", "S2"], initialInput: "initial")
        XCTAssertEqual(out, "step1")
    }

    // MARK: - Recursive next:

    func testActionNextRunsBeforeNextSibling() async throws {
        // Sibling chain [A, C], where A has next: [B]
        // Expected execution order: A → B → C (depth-first)
        // - A prints "A"
        // - B reads stdin "A" via `cat` and appends "B" → "AB"
        // - C reads stdin "AB" via `cat` and appends "C" → "ABC"
        let a = shellShortcut("A", value: "printf 'A'", next: ["B"])
        let b = shellShortcut("B", value: "cat && printf 'B'")
        let c = shellShortcut("C", value: "cat && printf 'C'")
        let executor = ChainExecutor(resolver: resolver(["A": a, "B": b, "C": c]))
        let out = try await executor.executeForTesting(slugs: ["A", "C"], initialInput: "init")
        XCTAssertEqual(out, "ABC")
    }

    // MARK: - Safety: cycle detection

    func testCycleDetected() async {
        // A → B → A: visited-set check should catch the second visit to A.
        let a = shellShortcut("A", value: "printf 'a'", next: ["B"])
        let b = shellShortcut("B", value: "printf 'b'", next: ["A"])
        let executor = ChainExecutor(resolver: resolver(["A": a, "B": b]))
        do {
            _ = try await executor.executeForTesting(slugs: ["A"], initialInput: "x")
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
            map[names[i]] = shellShortcut(
                names[i],
                value: "printf 'step'",
                next: i + 1 < names.count ? [names[i + 1]] : []
            )
        }
        let executor = ChainExecutor(resolver: resolver(map))
        do {
            _ = try await executor.executeForTesting(slugs: [names[0]], initialInput: "x")
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
            _ = try await executor.executeForTesting(slugs: ["S1", "S2", "S3"], initialInput: "x")
            XCTFail("expected stepFailed")
        } catch ChainExecutor.ChainError.stepFailed(let action, _) {
            XCTAssertEqual(action, "S2")
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }
}

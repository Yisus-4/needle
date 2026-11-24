import Foundation

struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String = "Assertion failed", file: String = #fileID, line: Int = #line) throws {
    if !condition() {
        throw TestFailure(description: "\(file):\(line): \(message)")
    }
}

func expectEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String = "", file: String = #fileID, line: Int = #line) throws {
    if lhs != rhs {
        let extra = message.isEmpty ? "" : " (\(message))"
        throw TestFailure(description: "\(file):\(line): expected \(rhs), got \(lhs)\(extra)")
    }
}

func expectClose(_ lhs: Double, _ rhs: Double, accuracy: Double = 0.01, _ message: String = "", file: String = #fileID, line: Int = #line) throws {
    if abs(lhs - rhs) > accuracy {
        let extra = message.isEmpty ? "" : " (\(message))"
        throw TestFailure(description: "\(file):\(line): expected \(rhs) ± \(accuracy), got \(lhs)\(extra)")
    }
}

struct TestCase {
    let suite: String
    let name: String
    let run: @Sendable () async throws -> Void
}

final class TestRunner {
    private var cases: [TestCase] = []

    func add(_ suite: String, _ name: String, _ body: @escaping @Sendable () async throws -> Void) {
        cases.append(TestCase(suite: suite, name: name, run: body))
    }

    func execute(filter: String?) async -> Int32 {
        let selected = cases.filter { tc in
            guard let filter, !filter.isEmpty else { return true }
            return tc.suite.localizedCaseInsensitiveContains(filter) || tc.name.localizedCaseInsensitiveContains(filter)
        }
        var passed = 0
        var failed = 0

        for tc in selected {
            do {
                try await tc.run()
                print("PASS \(tc.suite).\(tc.name)")
                passed += 1
            } catch {
                fputs("FAIL \(tc.suite).\(tc.name): \(error)\n", stderr)
                failed += 1
            }
        }

        print("Summary: \(passed)/\(selected.count) passed, \(failed) failed")
        return failed == 0 && !selected.isEmpty ? 0 : 1
    }
}

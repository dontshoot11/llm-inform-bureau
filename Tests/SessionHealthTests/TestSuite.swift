import Foundation

/// A test run: named cases, recorded failures, a summary and an exit code.
///
/// Deliberately tiny. Both Swift test frameworks (XCTest and swift-testing) ship inside
/// Xcode, and this package is built and tested with the Command Line Tools alone, so
/// `swift test` cannot run here. See SessionHealthTests.md.
final class TestSuite {
    private var currentFailures: [String] = []
    private var testCount = 0
    private var failedTests: [String] = []

    func test(_ name: String, _ body: () -> Void) {
        testCount += 1
        currentFailures = []
        body()
        if currentFailures.isEmpty {
            print("  ok   \(name)")
        } else {
            print("  FAIL \(name)")
            for failure in currentFailures {
                print("         \(failure)")
            }
            failedTests.append(name)
        }
    }

    func expect(_ condition: Bool, _ message: @autoclosure () -> String, line: UInt = #line) {
        if !condition {
            currentFailures.append("\(message()) — line \(line)")
        }
    }

    func expectEqual<T: Equatable>(
        _ actual: T,
        _ expected: T,
        _ label: String,
        line: UInt = #line
    ) {
        if actual != expected {
            currentFailures.append("\(label): expected \(expected), got \(actual) — line \(line)")
        }
    }

    func expectClose(
        _ actual: Double?,
        _ expected: Double,
        _ label: String,
        tolerance: Double = 0.001,
        line: UInt = #line
    ) {
        guard let actual else {
            currentFailures.append("\(label): expected \(expected), got nil — line \(line)")
            return
        }
        if abs(actual - expected) > tolerance {
            currentFailures.append("\(label): expected \(expected), got \(actual) — line \(line)")
        }
    }

    /// Prints the summary and exits: zero when everything passed, one otherwise.
    func finish(section: String) -> Never {
        print("")
        if failedTests.isEmpty {
            print("\(section): \(testCount) tests, all passed")
            exit(0)
        }
        print("\(section): \(testCount) tests, \(failedTests.count) failed")
        for name in failedTests {
            print("  - \(name)")
        }
        exit(1)
    }
}

/// Runs `body` against a directory that exists only for the duration of the call.
func withTemporaryDirectory(_ suite: TestSuite, named name: String, _ body: (URL) -> Void) {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
    do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    } catch {
        suite.test("temporary directory for \(name)") {
            suite.expect(false, "could not create \(directory.path): \(error)")
        }
        return
    }
    defer { try? FileManager.default.removeItem(at: directory) }
    body(directory)
}

/// Creates a subdirectory of a temporary directory, so each case gets its own fixtures.
func makeDirectory(_ root: URL, _ name: String, _ suite: TestSuite) -> URL {
    let directory = root.appendingPathComponent(name, isDirectory: true)
    do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    } catch {
        suite.expect(false, "could not create \(directory.path): \(error)")
    }
    return directory
}

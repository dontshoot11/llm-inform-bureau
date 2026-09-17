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

/// Runs `body` with these files unopenable, and hands their permissions back afterwards.
///
/// How "the reader did not open it" is checked rather than assumed. Changing the mode touches
/// neither the size, the modification date nor the identifier of a file — the three things
/// `FileMemory` is keyed by — so a reader that remembers the file cannot tell the difference,
/// and one that opens it comes back empty-handed. Every such case is followed by the same
/// files read through a reader with no memory, so that a run where the permissions did not
/// bite — as root, say — fails instead of passing for the wrong reason.
func withoutPermissions(_ urls: [URL], _ suite: TestSuite, _ body: () -> Void) {
    let manager = FileManager.default
    var restore: [URL: NSNumber] = [:]
    for url in urls {
        restore[url] = (try? manager.attributesOfItem(atPath: url.path)[.posixPermissions]) as? NSNumber
        do {
            try manager.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        } catch {
            suite.expect(false, "could not take the permissions off \(url.lastPathComponent): \(error)")
        }
    }
    defer {
        for url in urls {
            try? manager.setAttributes(
                [.posixPermissions: restore[url] ?? 0o644], ofItemAtPath: url.path
            )
        }
    }
    body()
}

func withoutPermissions(_ url: URL, _ suite: TestSuite, _ body: () -> Void) {
    withoutPermissions([url], suite, body)
}

/// Every regular file under a directory, however deeply nested. What a pass is allowed to open.
func everyFile(under directory: URL) -> [URL] {
    guard let walker = FileManager.default.enumerator(
        at: directory,
        includingPropertiesForKeys: [.isRegularFileKey]
    ) else { return [] }
    return walker.compactMap { $0 as? URL }.filter {
        (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
    }
}

/// What the reader's memory is keyed by, as a test can see it: how big a file is, when it was
/// last written, and the volume's own identifier for it.
///
/// Read through a `URL` made on the spot every time. A `URL` caches the resource values it is
/// asked for, so one kept from before answers with what the file looked like then — the same
/// trap the reader itself has to stay out of.
struct FileFacts: Equatable {
    let size: Int?
    let modified: Date?
    let identity: Data?
}

func facts(of url: URL) -> FileFacts {
    let values = try? URL(fileURLWithPath: url.path).resourceValues(
        forKeys: [.fileSizeKey, .contentModificationDateKey, .fileResourceIdentifierKey]
    )
    return FileFacts(
        size: values?.fileSize,
        modified: values?.contentModificationDate,
        identity: values?.fileResourceIdentifier as? Data
    )
}

/// Removes a file, so that what is written under its name next is a *different* file with an
/// identifier of its own — a directory tidied and written again, a transcript restored from
/// elsewhere. Writing over a file in place keeps its identifier and is a different case.
func removeFile(_ url: URL, _ suite: TestSuite) {
    do {
        try FileManager.default.removeItem(at: url)
    } catch {
        suite.expect(false, "could not remove \(url.lastPathComponent): \(error)")
    }
}

/// Moves a file, which leaves its size, its date and its identifier exactly as they were.
/// What changes is only whether a walk of the tree still finds it.
func moveFile(_ url: URL, to destination: URL, _ suite: TestSuite) {
    do {
        try FileManager.default.moveItem(at: url, to: destination)
    } catch {
        suite.expect(false, "could not move \(url.lastPathComponent): \(error)")
    }
}

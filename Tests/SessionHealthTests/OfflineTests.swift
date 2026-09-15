import Foundation

/// That the app cannot go to the network.
///
/// "It works with the network off" is not a behaviour that can be exercised from a test —
/// there is no request to fail. What can be checked is the only reason it holds: nothing under
/// `Sources` reaches for a network API at all. The rule is `AGENTS.md`'s, the temptation is
/// real (a threshold has a published source and fetching it would be one line), and this is
/// what would notice the line being added.
func runOfflineTests(_ suite: TestSuite) {
    /// Every way this app would plausibly acquire one. Names rather than imports: `Foundation`
    /// is imported everywhere and carries `URLSession` with it.
    let networkAPIs = [
        "URLSession", "URLRequest", "URLConnection", "URLDownload",
        "NWConnection", "NWBrowser", "NWListener", "NWPathMonitor",
        "CFSocket", "CFStream", "CFHTTP", "getaddrinfo", "socket(",
        "import Network", "import FoundationNetworking"
    ]

    let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // Tests/SessionHealthTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // the package root
        .appendingPathComponent("Sources", isDirectory: true)

    let files = (FileManager.default.enumerator(atPath: sources.path)?
        .compactMap { $0 as? String }
        .filter { $0.hasSuffix(".swift") } ?? [])
        .sorted()

    suite.test("the sources are where this test thinks they are") {
        suite.expect(files.count > 10, "found \(files.count) Swift files under \(sources.path)")
    }

    suite.test("no source file reaches for the network") {
        for file in files {
            let path = sources.appendingPathComponent(file)
            guard let text = try? String(contentsOf: path, encoding: .utf8) else {
                suite.expect(false, "could not read \(file)")
                continue
            }
            for api in networkAPIs where text.contains(api) {
                suite.expect(false, "\(file) uses \(api) — this app reads local files and nothing else")
            }
        }
    }
}

import Foundation
import Handout

// Renders the description to a PDF. Run by Scripts/build-handout.sh, which is where the
// version and the path come from — this side takes them as they are given and reports what it
// wrote, so that the script above it can hand the path on.
//
// Both arguments are required rather than defaulted: a default version would be a second place
// the number could come from, and a default path would write into whatever directory it was
// called from.
let arguments = CommandLine.arguments.dropFirst()
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: BuildHandout <version> <output.pdf>\n".utf8))
    exit(2)
}

let version = arguments.first!
let output = URL(fileURLWithPath: Array(arguments)[1])

do {
    try Handout.write(version: version, to: output)
    print(output.path)
} catch {
    FileHandle.standardError.write(Data("could not build the description: \(error)\n".utf8))
    exit(1)
}

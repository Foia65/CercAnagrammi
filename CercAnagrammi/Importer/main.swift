import Foundation

guard let parsed = parseArgs(CommandLine.arguments) else {
    usage()
    exit(1)
}

Task { @MainActor in
    await runImport(parsed)
    exit(0)
}

dispatchMain()

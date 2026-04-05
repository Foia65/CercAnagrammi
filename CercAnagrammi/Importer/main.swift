import Foundation

guard let parsed = parseArgs(CommandLine.arguments) else {
    usage()
    exit(1)
}

runImport(parsed)

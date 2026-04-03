// WordImporter.swift
// CLI tool to populate a SwiftData store from a newline-delimited .txt file.
// Only uppercase A-Z strings are accepted. SHA-256 hash is computed and stored.
//
// Usage:
//   WordImporter <input-file> --output <output-db-path> [--batch-size N] [--dry-run]
//
// Add this file + Word.swift to the Populate CLI target only.

import Foundation
import CryptoKit
import SwiftData
import Dispatch


// ─────────────────────────────────────────────
// MARK: - Argument parsing
// ─────────────────────────────────────────────

/// Parsed command line arguments
struct ParsedArgs {
    var inputPath:  String    // Path to input .txt file
    var outputPath: String    // Path to output SwiftData store
    var batchSize:  Int       // Number of words to batch before saving
    var dryRun:     Bool      // Whether to validate only without saving
}

/// Parses command line arguments into a ParsedArgs struct.
/// Returns nil if required arguments are missing or unknown arguments are found.
func parseArgs(_ args: [String]) -> ParsedArgs? {
    var inputPath:  String? = nil
    var outputPath: String? = nil
    var batchSize             = 5000   // Default batch size
    var dryRun                = false  // Default: perform import

    var i = 1
    while i < args.count {
        switch args[i] {
        case "--output":
            i += 1
            if i < args.count { outputPath = args[i] }
        case "--batch-size":
            i += 1
            if i < args.count, let v = Int(args[i]) { batchSize = v }
        case "--dry-run":
            dryRun = true
        default:
            // The first non-flag argument is assumed to be the input path
            if inputPath == nil && !args[i].hasPrefix("--") {
                inputPath = args[i]
            } else {
                print("Unknown argument: \(args[i])")
                return nil
            }
        }
        i += 1
    }

    // Ensure mandatory input and output paths are provided
    guard let inp = inputPath, let out = outputPath else { return nil }
    return ParsedArgs(inputPath: inp, outputPath: out, batchSize: batchSize, dryRun: dryRun)
}

/// Prints usage instructions to the console.
func usage() {
    let exe = CommandLine.arguments.first ?? "WordImporter"
    print("""
    Usage: \(exe) <input-file> --output <output-db-path> [--batch-size N] [--dry-run]

      <input-file>      Path to the .txt file (one word per line)
      --output          Path where the SwiftData .store file will be written
      --batch-size N    Save to disk every N valid words (default: 5000)
      --dry-run         Validate and count without writing anything to disk
    """)
}


// ─────────────────────────────────────────────
// MARK: - Helpers
// ─────────────────────────────────────────────

/// Removes all accents/diacritics (Unicode combining marks) from a string.
/// This normalization step ensures that words differing only by accents
/// are treated identically (important for hash calculations and matching).
func removeAccents(_ s: String) -> String {
    s.applyingTransform(.stripDiacritics, reverse: false) ?? s
}

/// Returns a string with all its letters sorted alphabetically.
/// Sorting letters normalizes anagrams to the same representation.
/// This allows generating an anagram-insensitive hash.
func sortedString(_ s: String) -> String {
    String(s.sorted())
}

/// Checks if a word is valid: non-empty and composed only of uppercase letters.
/// This ensures data cleanliness by excluding any invalid characters or empty lines.
func isValidWord(_ s: String) -> Bool {
    guard !s.isEmpty else { return false }
    // Only allow words made up entirely of uppercase Unicode letters (A-Z)
    let allowedSet = CharacterSet.uppercaseLetters
    return s.unicodeScalars.allSatisfy { allowedSet.contains($0) }
}

/// Computes the SHA-256 hash of a string and returns its hex representation.
/// Hashes are used to uniquely identify anagram groups after normalization.
func sha256Hex(of s: String) -> String {
    let digest = SHA256.hash(data: Data(s.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
}


// ─────────────────────────────────────────────
// MARK: - Importer
// ─────────────────────────────────────────────

/// Main import routine, runs asynchronously on the main actor.
///
/// Reads the input file, validates and processes words, and inserts them into a SwiftData store.
/// Supports a dry run mode to validate without writing.
///
/// - Parameter parsed: Parsed command line arguments with input/output paths and options.
@MainActor
func runImport(_ parsed: ParsedArgs) async {

    // Expand tilde paths for input and output files
    let inputURL  = URL(fileURLWithPath: (parsed.inputPath  as NSString).expandingTildeInPath)
    let targetURL = URL(fileURLWithPath: (parsed.outputPath as NSString).expandingTildeInPath)

    // ── Validate input file ──────────────────────────────────────────────────

    // Ensure the input file is readable before proceeding
    guard FileManager.default.isReadableFile(atPath: inputURL.path) else {
        print("Cannot read input file: \(inputURL.path)")
        exit(1)
    }

    // ── Dry run: validate only, no disk writes ───────────────────────────────

    if parsed.dryRun {
        print("DRY RUN — no files will be written.\n")
        let content: String
        do {
            // Read entire file contents as a string
            content = try String(contentsOf: inputURL, encoding: .utf8)
        }
        catch {
            print("Failed to read file: \(error)")
            exit(1)
        }

        var valid = 0, skipped = 0, invalid = 0

        // Process each line, validating uppercase words only
        for raw in content.components(separatedBy: .newlines) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            // Normalize to uppercase using current locale
            let word = trimmed.uppercased(with: Locale.current)
            if word.isEmpty {
                skipped += 1
                continue
            }
            if isValidWord(word) {
                valid += 1
            } else {
                invalid += 1
                print("  ✖ Invalid: \(word)")
            }
        }

        // Summary report for dry-run mode
        print("\nDry run complete. Valid: \(valid), Invalid: \(invalid), Blank/skipped: \(skipped)")
        exit(0)
    }

    // ── Ensure output directory exists ───────────────────────────────────────

    let targetDir = targetURL.deletingLastPathComponent()
    do {
        // Create output directory if missing (including intermediate directories)
        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
    } catch {
        print("Cannot create output directory \(targetDir.path): \(error)")
        exit(1)
    }

    // ── Remove any pre-existing store files at the target path ───────────────
    // This prevents schema conflicts from leftover files in SwiftData stores

    let baseName = targetURL.deletingPathExtension().lastPathComponent
    if let items = try? FileManager.default.contentsOfDirectory(at: targetDir, includingPropertiesForKeys: nil) {
        for item in items where item.lastPathComponent.hasPrefix(baseName) {
            try? FileManager.default.removeItem(at: item)
        }
    }

    // ── Build SwiftData container at the target path ─────────────────────────

    let schema = Schema([Word.self])
    let config = ModelConfiguration(
        "WordsStore",
        schema: schema,
        url: targetURL,
        allowsSave: true
    )

    let container: ModelContainer
    do {
        // Create the ModelContainer (SwiftData database) with given config
        container = try ModelContainer(for: schema, configurations: config)
    } catch {
        print("Failed to create ModelContainer: \(error)")
        exit(1)
    }

    // Create a ModelContext to batch insert Word objects
    let context = ModelContext(container)

    // ── Read source file ─────────────────────────────────────────────────────

    let content: String
    do {
        // Read entire input file as a single string
        content = try String(contentsOf: inputURL, encoding: .utf8)
    }
    catch {
        print("Failed to read input file: \(error)")
        exit(1)
    }

    // Split input into lines for processing
    let lines = content.components(separatedBy: .newlines)

    // ── Validate, hash, insert ───────────────────────────────────────────────

    var seenInRun = Set<String>()  // Track duplicates within this run
    var batchCount = 0             // Count of words inserted since last save
    var valid = 0                  // Valid words inserted
    var skipped = 0                // Blank or duplicate lines skipped
    var invalid = 0                // Invalid lines skipped

    for (lineNumber, rawWord) in lines.enumerated() {
        // Trim whitespace/newlines
        let trimmed = rawWord.trimmingCharacters(in: .whitespacesAndNewlines)
        // Normalize to uppercase with locale
        let word = trimmed.uppercased(with: Locale.current)
        if word.isEmpty {
            skipped += 1
            continue
        }

        // Validate word characters (only uppercase letters)
        guard isValidWord(word) else {
            invalid += 1
            print("  ⚠︎  Line \(lineNumber + 1) invalid, skipped: \"\(word)\"")
            continue
        }

        // Skip duplicates already inserted in this run
        if seenInRun.contains(word) {
            skipped += 1
            continue
        }
        seenInRun.insert(word)

        // Insert Word object with:
        // - original word
        // - hash computed from sorted, accent-free letters (anagram-insensitive)
        // - length of the word
        context.insert(Word(
            original:  word,
            // Remove accents and sort letters so anagrams yield the same hash
            hash:      sha256Hex(of: sortedString(removeAccents(word))),
            length:    word.count
        ))

        valid      += 1
        batchCount += 1

        // Save batch if batchSize is reached to improve performance and avoid large memory use
        if batchCount >= parsed.batchSize {
            do {
                try context.save()
            } catch {
                print("Warning: batch save failed at line \(lineNumber + 1): \(error)")
            }
            batchCount = 0
        }
    }

    // Final save to persist any remaining inserts
    if batchCount > 0 {
        do {
            try context.save()
        } catch {
            print("Warning: final save failed: \(error)")
        }
    }

    // ── Report ───────────────────────────────────────────────────────────────

    // Summary output after import finishes
    print("""

    ────────────────────────────────────────────
    Import complete.
      Valid inserted : \(valid)
      Invalid lines  : \(invalid)
      Blank/duplicate: \(skipped)

    Store written to:
      \(targetURL.path)

    Next step: drag this file into Xcode →
    app target → Copy Bundle Resources.
    ────────────────────────────────────────────
    """)
}


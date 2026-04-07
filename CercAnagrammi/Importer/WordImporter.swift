// WordImporter.swift
// CLI tool to populate a lean SQLite database from a newline-delimited .txt file.
// Only uppercase A-Z strings are accepted.
// Produces a single-table DB: words(word, sorted)
//
// Usage:
//   WordImporter <input-file> --output <output-db-path> [--batch-size N] [--dry-run]

import Foundation
import SQLite3

// ─────────────────────────────────────────────
// MARK: - Argument parsing
// ─────────────────────────────────────────────

struct ParsedArgs {
    var inputPath: String
    var outputPath: String
    var batchSize: Int
    var dryRun: Bool
}

func parseArgs(_ args: [String]) -> ParsedArgs? {
    var inputPath: String? = nil
    var outputPath: String? = nil
    var batchSize = 5000
    var dryRun = false

    var i = 1
    while i < args.count {
        switch args[i] {
        case "--output":
            i += 1
            if i < args.count { outputPath = args[i] }
        case "--batch-size":
            i += 1
            if i < args.count, let batchSizeValue = Int(args[i]) { batchSize = batchSizeValue }
        case "--dry-run":
            dryRun = true
        default:
            if inputPath == nil && !args[i].hasPrefix("--") {
                inputPath = args[i]
            } else {
                print("Unknown argument: \(args[i])")
                return nil
            }
        }
        i += 1
    }

    guard let inp = inputPath, let out = outputPath else { return nil }
    return ParsedArgs(inputPath: inp, outputPath: out, batchSize: batchSize, dryRun: dryRun)
}

func usage() {
    let exe = CommandLine.arguments.first ?? "WordImporter"
    print("""
    Usage: \(exe) <input-file> --output <output-db-path> [--batch-size N] [--dry-run]

      <input-file>      Path to the .txt file (one word per line)
      --output          Path where the SQLite .db file will be written
      --batch-size N    Commit every N valid words (default: 5000)
      --dry-run         Validate and count without writing anything to disk
    """)
}

// ─────────────────────────────────────────────
// MARK: - Helpers
// ─────────────────────────────────────────────

func removeAccents(_ str: String) -> String {
    str.applyingTransform(.stripDiacritics, reverse: false) ?? str
}

/// Anagram key: strip accents, sort letters.
/// e.g. "CARET" → "ACERT", same as "TRACE" → "ACERT"
func sortedLetters(_ str: String) -> String {
    String(str.sorted())
}

func isValidWord(_ str: String) -> Bool {
    guard !str.isEmpty else { return false }
    return str.unicodeScalars.allSatisfy { CharacterSet.uppercaseLetters.contains($0) }
}

func sqliteError(_ dBas: OpaquePointer?) -> String {
    dBas.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
}

// ─────────────────────────────────────────────
// MARK: - SQLite bootstrap
// ─────────────────────────────────────────────

func openDatabase(at path: String) -> OpaquePointer {
    var dBase: OpaquePointer?
    guard sqlite3_open_v2(path, &dBase,
                          SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK,
          let dBase else {
        print("❌ Cannot open/create DB at \(path)")
        exit(1)
    }

    let pragmas = """
        PRAGMA journal_mode = WAL;
        PRAGMA synchronous  = NORMAL;
        PRAGMA temp_store   = MEMORY;
        PRAGMA cache_size   = -64000;
    """
    sqlite3_exec(dBase, pragmas, nil, nil, nil)

    let ddl = """
        CREATE TABLE IF NOT EXISTS words (
            word   TEXT PRIMARY KEY,
            sorted TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_sorted ON words(sorted);
    """
    guard sqlite3_exec(dBase, ddl, nil, nil, nil) == SQLITE_OK else {
        print("❌ Schema creation failed: \(sqliteError(dBase))")
        exit(1)
    }

    return dBase
}

// ─────────────────────────────────────────────
// MARK: - Importer
// ─────────────────────────────────────────────

func runImport(_ parsed: ParsedArgs) {
    let inputURL  = URL(fileURLWithPath: (parsed.inputPath  as NSString).expandingTildeInPath)
    let targetURL = URL(fileURLWithPath: (parsed.outputPath as NSString).expandingTildeInPath)

    guard FileManager.default.isReadableFile(atPath: inputURL.path) else {
        print("❌ Cannot read input file: \(inputURL.path)")
        exit(1)
    }

    let content: String
    do {
        content = try String(contentsOf: inputURL, encoding: .utf8)
    } catch {
        print("❌ Failed to read file: \(error)")
        exit(1)
    }

    let lines = content.components(separatedBy: .newlines)

    // ── Dry run ──────────────────────────────────────────────────────────────

    if parsed.dryRun {
        print("DRY RUN — no files will be written.\n")
        var valid = 0, skipped = 0, invalid = 0
        for raw in lines {
            let word = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                         .uppercased(with: Locale.current)
            if word.isEmpty { skipped += 1; continue }
            if isValidWord(word) { valid += 1 } else {
                invalid += 1
                print("  ✖ Invalid: \(word)")
            }
        }
        print("\nDry run complete. Valid: \(valid), Invalid: \(invalid), Blank/skipped: \(skipped)")
        return
    }

    // ── Prepare output directory ─────────────────────────────────────────────

    let targetDir = targetURL.deletingLastPathComponent()
    do {
        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
    } catch {
        print("❌ Cannot create output directory: \(error)")
        exit(1)
    }

    try? FileManager.default.removeItem(at: targetURL)

    // ── Open DB & prepare statement ──────────────────────────────────────────

    let dBase = openDatabase(at: targetURL.path)
    defer { sqlite3_close(dBase) }

    var stmt: OpaquePointer?
    let insertSQL = "INSERT OR IGNORE INTO words(word, sorted) VALUES(?, ?)"
    guard sqlite3_prepare_v2(dBase, insertSQL, -1, &stmt, nil) == SQLITE_OK else {
        print("❌ Failed to prepare insert statement: \(sqliteError(dBase))")
        exit(1)
    }
    defer { sqlite3_finalize(stmt) }

    // ── Import loop ──────────────────────────────────────────────────────────

    var seenInRun  = Set<String>()
    var batchCount = 0
    var valid = 0, skipped = 0, invalid = 0

    sqlite3_exec(dBase, "BEGIN TRANSACTION", nil, nil, nil)

    for (lineNumber, rawWord) in lines.enumerated() {
        let word = rawWord
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased(with: Locale.current)

        if word.isEmpty { skipped += 1; continue }

        guard isValidWord(word) else {
            invalid += 1
            print("  ⚠︎  Line \(lineNumber + 1) invalid, skipped: \"\(word)\"")
            continue
        }

        guard !seenInRun.contains(word) else { skipped += 1; continue }
        seenInRun.insert(word)

        let sorted = sortedLetters(removeAccents(word))

        sqlite3_bind_text(stmt, 1, (word   as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (sorted as NSString).utf8String, -1, nil)

        if sqlite3_step(stmt) != SQLITE_DONE {
            print("  ⚠︎  Insert failed at line \(lineNumber + 1): \(sqliteError(dBase))")
        }
        sqlite3_reset(stmt)

        valid      += 1
        batchCount += 1

        if batchCount >= parsed.batchSize {
            sqlite3_exec(dBase, "COMMIT", nil, nil, nil)
            sqlite3_exec(dBase, "BEGIN TRANSACTION", nil, nil, nil)
            batchCount = 0
            print("  … \(valid) words imported")
        }
    }

    sqlite3_exec(dBase, "COMMIT", nil, nil, nil)
    
    // ── Finalize: collapse WAL and switch to DELETE journal mode ─────────────
    sqlite3_exec(dBase, "PRAGMA wal_checkpoint(TRUNCATE);", nil, nil, nil)
    sqlite3_exec(dBase, "PRAGMA journal_mode=DELETE;", nil, nil, nil)
    sqlite3_exec(dBase, "VACUUM;", nil, nil, nil)
    
    // ── Report ───────────────────────────────────────────────────────────────

    print("""

    ────────────────────────────────────────────
    Import complete.
      Valid inserted : \(valid)
      Invalid lines  : \(invalid)
      Blank/duplicate: \(skipped)

    DB written to:
      \(targetURL.path)

    Schema:
      words(word   TEXT PRIMARY KEY,
            sorted TEXT NOT NULL)
      INDEX idx_sorted ON words(sorted)

    Journal mode set to DELETE (no -wal/-shm sidecars).
    DB is self-contained and ready to bundle.

    Next step: drag Words.db into Xcode →
    app target → Copy Bundle Resources.
    ────────────────────────────────────────────
    """)
    
}

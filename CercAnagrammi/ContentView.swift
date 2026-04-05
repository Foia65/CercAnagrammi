import SwiftUI
import SQLite3

// ─────────────────────────────────────────────
// MARK: - Database
// ─────────────────────────────────────────────

final class WordDatabase {
    static let shared = WordDatabase()

    private var db: OpaquePointer?

    private init() {
        // Use the real Mac home, not the simulator sandbox
        let realHome = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] ?? NSHomeDirectory()
        let path = URL(fileURLWithPath: realHome)
            .appendingPathComponent("Desktop/CercAnagrammi/CercAnagrammi/Resources/Words.db")
            .path

        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            print("❌ Could not open DB at \(path)")
            return
        }
        print("✅ SQLite DB opened at \(path)")
    }

    /// Returns words whose `word` column contains the search term (case-insensitive).
    /// Returns the first 200 matches, sorted alphabetically.
    /// If term is empty, returns the first 100 words.
    func search(_ term: String) -> [String] {
        guard let db else { return [] }

        let sql: String
        let args: [String]

        if term.isEmpty {
            sql  = "SELECT word FROM words ORDER BY word LIMIT 100"
            args = []
        } else {
            sql  = "SELECT word FROM words WHERE word LIKE ? ORDER BY word LIMIT 200"
            args = ["%\(term.uppercased())%"]
        }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        for (i, arg) in args.enumerated() {
            sqlite3_bind_text(stmt, Int32(i + 1), (arg as NSString).utf8String, -1, nil)
        }

        var results: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let cStr = sqlite3_column_text(stmt, 0) {
                results.append(String(cString: cStr))
            }
        }
        return results
    }

    /// Returns all anagrams of the given word using the pre-computed `sorted` key.
    /// This is an indexed exact match — effectively instant on 735k rows.
    func anagrams(of word: String) -> [String] {
        guard let db else { return [] }

        let key = String(word.uppercased().sorted())
        let sql = "SELECT word FROM words WHERE sorted = ? ORDER BY word"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, nil)

        var results: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let cStr = sqlite3_column_text(stmt, 0) {
                results.append(String(cString: cStr))
            }
        }
        return results
    }

    /// Returns all words from the database (be cautious: for large DBs, this may be slow)
    func allWords() -> [String] {
        guard let db else { return [] }
        let sql = "SELECT word FROM words"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var results: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let cStr = sqlite3_column_text(stmt, 0) {
                results.append(String(cString: cStr))
            }
        }
        return results
    }
}

// ─────────────────────────────────────────────
// MARK: - MatchResult
// ─────────────────────────────────────────────

struct MatchResult: Identifiable {
    let id = UUID()
    let word: String
    let isFullMatch: Bool
    let leftover: String
    let usedLetterCount: Int
}

// ─────────────────────────────────────────────
// MARK: - View
// ─────────────────────────────────────────────

struct ContentView: View {
    @State private var searchText = ""
    @State private var results: [MatchResult] = []

    private func performSearch() {
        let input = searchText
        guard !input.isEmpty else {
            results = []
            return
        }
        // Get all possible candidates (restricting to words containing first letter for speed if you like)
        let candidates = WordDatabase.shared.allWords()
        // For demo, use all candidates; for large DB, would need to scan all words efficiently
        var output: [MatchResult] = []
        let inputLetters = Array(input)
        let inputLetterCounts = inputLetters.reduce(into: [:]) { $0[$1, default: 0] += 1 }

        for word in candidates {
            if word == input { continue }
            let wordLetters = Array(word)
            var tempCounts = inputLetterCounts
            var canMake = true
            for c in wordLetters {
                if let count = tempCounts[c], count > 0 {
                    tempCounts[c]! -= 1
                } else {
                    canMake = false
                    break
                }
            }
            if canMake {
                let leftover = tempCounts.flatMap { Array(repeating: $0.key, count: $0.value) }.map(String.init).joined()
                let isFull = leftover.isEmpty && wordLetters.count == inputLetters.count
                output.append(MatchResult(word: word, isFullMatch: isFull, leftover: leftover, usedLetterCount: wordLetters.count))
            }
        }
        // Sort: full matches at top, then by usedLetterCount descending, then word
        results = output.sorted {
            if $0.isFullMatch != $1.isFullMatch {
                return $0.isFullMatch
            }
            if $0.usedLetterCount != $1.usedLetterCount {
                return $0.usedLetterCount > $1.usedLetterCount
            }
            return $0.word < $1.word
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Cerca una parola...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding()
                .autocorrectionDisabled(true)
                .autocapitalization(.allCharacters)
                .onChange(of: searchText) { _, newValue in
                        searchText = newValue.uppercased()
                    }

            Divider()

            if results.isEmpty {
                Spacer()
                Text(searchText.isEmpty ? "Scrivi per cercare..." : "Nessun risultato trovato.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(results) { result in
                    HStack {
                        Text(result.word)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(result.isFullMatch ? .bold : .regular)
                            .foregroundStyle(result.isFullMatch ? .blue : .primary)
                        if !result.isFullMatch && !result.leftover.isEmpty {
                            Spacer()
                            Text("+ " + result.leftover)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .onAppear { performSearch() }
        .onChange(of: searchText) { _ in performSearch() }
    }
}

// ─────────────────────────────────────────────
// MARK: - Preview
// ─────────────────────────────────────────────

#Preview {
    ContentView()
}

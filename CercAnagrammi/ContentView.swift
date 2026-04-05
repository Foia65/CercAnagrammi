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
}

// ─────────────────────────────────────────────
// MARK: - View
// ─────────────────────────────────────────────

struct ContentView: View {
    @State private var searchText = ""
    @State private var results:   [String] = []

    private func performSearch() {
        // Always search by the sorted string, using the anagrams(of:) function
        results = WordDatabase.shared.anagrams(of: searchText)
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Cerca una parola...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding()

            Divider()

            if results.isEmpty {
                Spacer()
                Text(searchText.isEmpty ? "Scrivi per cercare..." : "Nessun risultato trovato.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(results, id: \.self) { word in
                    Text(word)
                        .font(.system(.body, design: .monospaced))
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

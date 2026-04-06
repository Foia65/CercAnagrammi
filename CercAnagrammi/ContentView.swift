import SwiftUI
import SQLite3

// ─────────────────────────────────────────────
// MARK: - Database
// ─────────────────────────────────────────────


final class WordDatabase {
    static let shared = WordDatabase()

    private var db: OpaquePointer?

    private init() {
        guard let bundlePath = Bundle.main.path(forResource: "Words", ofType: "db") else {
            print("❌ Words.db not found in app bundle")
            return
        }

        guard sqlite3_open_v2(bundlePath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            print("❌ Could not open DB at \(bundlePath)")
            return
        }
        print("✅ SQLite DB opened from bundle at \(bundlePath)")
    }
    
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


struct ContentView: View {
    @State private var searchText = ""
    @State private var results: [MatchResult] = []
    
    // Filtri
    @State private var searchAsYouType = false
    @State private var fullMatchesOnly = true
    @State private var minLength: Int = 4
    
    private struct StatCell: View {
        let value: String
        let label: String
        var color: Color = .primary

        var body: some View {
            VStack(spacing: 2) {
                Text(value)
                    .font(.system(size: 17, weight: .medium, design: .monospaced))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .frame(minWidth: 72)
            .padding(.vertical, 8)
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(Color(.separator))
                    .frame(width: 0.5)
            }
        }
    }
    
    // Cache locale per le parole
    @State private var allWordsCache: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            // --- HEADER: Ricerca e Controlli ---
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    
                    TextField("Lettere da anagrammare...", text: $searchText)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled(true)
                        .disableAutocorrection(true)  // Alternate/older API
                        .keyboardType(.alphabet)     // Alphabet keyboard (no numbers row)

                        .onSubmit {
                            if !searchAsYouType { performSearch() }
                        }
                    
                    if !searchText.isEmpty {
                        if !searchAsYouType {
                            Button {
                                performSearch()
                            } label: {
                                Image(systemName: "arrow.right.circle.fill")
                                    .foregroundStyle(.orange)
                            }
                        } else {
                            Button {
                                searchText = ""
                                results = []
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(10)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
                
                // Barra dei filtri orizzontale
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        Toggle(isOn: $searchAsYouType) {
                            Label("Live", systemImage: "bolt.fill")
                        }
                        .toggleStyle(.button)
                        .tint(.orange)
                        .controlSize(.small)

                        Toggle(isOn: $fullMatchesOnly) {
                            Label("Solo 100%", systemImage: "target")
                        }
                        .toggleStyle(.button)
                        .tint(.blue)
                        .controlSize(.small)
                        
                        // Stepper compatto per la lunghezza
                        HStack(spacing: 4) {
                            Image(systemName: "textformat.size")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Min: \(minLength)")
                                .font(.footnote.bold())
                            Stepper("", value: $minLength, in: 3...15)
                                .labelsHidden()
                                .scaleEffect(0.8)
                        }
                        .padding(.leading, 8)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(8)
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            
            Divider()

            // --- AREA RISULTATI ---
            if results.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: searchText.isEmpty ? "text.magnifyingglass" : "questionmark.circle")
                        .font(.system(size: 60))
                        .foregroundStyle(.quaternary)
                    Text(searchText.isEmpty ? "Inserisci delle lettere" : "Nessun risultato")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                List(results) { result in
                    HStack(alignment: .center, spacing: 8) {
                        // 1. La parola trovata
                        Text("\(result.word) ")
                        Text("(\(result.word.count))")
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                                                
                        Spacer()
                        
                        // 2. Separatore (opzionale, solo se ci sono avanzi)
                        if !result.isFullMatch && !result.leftover.isEmpty {
                                Text("+")
                                    .foregroundStyle(.quaternary)
                                
                                // 3. Lettere avanzate sulla stessa linea
                                Text(result.leftover)
                                    .font(.system(.subheadline, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color(.secondarySystemBackground))
                                    .cornerRadius(4)
                        }
                                                
                        // 4. Badge Anagramma Puro
                        if result.isFullMatch {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
                .listStyle(.plain)
            }
            
            // --- STATISTICS BAR ---
            if !results.isEmpty {
                Divider()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        StatCell(value: "\(stats.total)", label: "trovate")
                        StatCell(value: "\(stats.fullMatches)", label: "100% match", color: .blue)
                        StatCell(value: "\(stats.longest)", label: "più lunga", color: .orange)
                        StatCell(value: String(format: "%.1f", stats.avgLength), label: "lung. media")
                      }
                    .frame(maxWidth: .infinity)
                }
                .background(Color(.secondarySystemBackground))
            }
            
        }
        .onAppear {
            DispatchQueue.global(qos: .userInitiated).async {
                let words = WordDatabase.shared.allWords()
                DispatchQueue.main.async {
                    self.allWordsCache = words
                }
            }
        }
        .onChange(of: searchText) { if searchAsYouType { performSearch() } }
        .onChange(of: fullMatchesOnly) { performSearch() }
        .onChange(of: minLength) { performSearch() }
    }

    private func performSearch() {
        let input = searchText.uppercased().replacingOccurrences(of: " ", with: "")
        guard input.count >= 2 else {
            results = []
            return
        }

        let inputLetterCounts = Array(input).reduce(into: [:]) { $0[$1, default: 0] += 1 }
        var output: [MatchResult] = []

        for word in allWordsCache {
            if word == input || word.count < minLength { continue }
            
            let wordLetters = Array(word)
            var tempCounts = inputLetterCounts
            var canMake = true
            
            for char in wordLetters {
                if let count = tempCounts[char], count > 0 {
                    tempCounts[char]! -= 1
                } else {
                    canMake = false
                    break
                }
            }
            
            if canMake {
                let leftover = tempCounts.flatMap { Array(repeating: $0.key, count: $0.value) }
                    .sorted().map(String.init).joined()
                
                let isFull = leftover.isEmpty && word.count == input.count
                if fullMatchesOnly && !isFull { continue }
                
                output.append(MatchResult(word: word, isFullMatch: isFull, leftover: leftover, usedLetterCount: word.count))
            }
        }

        results = output.sorted {
            if $0.isFullMatch != $1.isFullMatch { return $0.isFullMatch }
            if $0.usedLetterCount != $1.usedLetterCount { return $0.usedLetterCount > $1.usedLetterCount }
            return $0.word < $1.word
        }
    }
    
    // Computed stats from results
    private var stats: (total: Int, fullMatches: Int, longest: String, avgLength: Double, ) {
        let total = results.count
        let fullMatches = results.filter { $0.isFullMatch }.count
        let longest = results.max(by: { $0.word.count < $1.word.count })?.word ?? "-"
        let avgLength = total > 0
            ? Double(results.map { $0.word.count }.reduce(0, +)) / Double(total)
            : 0
        return (total, fullMatches, longest, avgLength)
    }
    
}





// ─────────────────────────────────────────────
// MARK: - Preview
// ─────────────────────────────────────────────

#Preview {
    ContentView()
}

import SwiftUI
import SQLite3

// ─────────────────────────────────────────────
// MARK: - Database
// ─────────────────────────────────────────────

final class WordDatabase {
    static let shared = WordDatabase()

    private var database: OpaquePointer?

    private init() {
        guard let bundlePath = Bundle.main.path(forResource: "Words", ofType: "db") else {
            print("❌ Words.db not found in app bundle")
            return
        }

        // Apriamo il DB in sola lettura: il file è nel bundle e non va modificato a runtime.
        guard sqlite3_open_v2(bundlePath, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            print("❌ Could not open DB at \(bundlePath)")
            return
        }
        print("✅ SQLite DB opened from bundle at \(bundlePath)")
    }
    
    func search(_ term: String) -> [String] {
        guard let database else { return [] }

        let sql: String
        let args: [String]

        if term.isEmpty {
            sql  = "SELECT word FROM words ORDER BY word LIMIT 100"
            args = []
        } else {
            sql  = "SELECT word FROM words WHERE word LIKE ? ORDER BY word LIMIT 200"
            args = ["%\(term.uppercased())%"]
        }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        for (index, arg) in args.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), (arg as NSString).utf8String, -1, nil)
        }

        var results: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let cString = sqlite3_column_text(statement, 0) {
                results.append(String(cString: cString))
            }
        }
        return results
    }

    func anagrams(of word: String) -> [String] {
        guard let database else { return [] }

        let key = String(word.uppercased().sorted())
        let sql = "SELECT word FROM words WHERE sorted = ? ORDER BY word"

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, (key as NSString).utf8String, -1, nil)

        var results: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let cString = sqlite3_column_text(statement, 0) {
                results.append(String(cString: cString))
            }
        }
        return results
    }

    // Returns all words from the database
    func allWords() -> [String] {
        guard let database else { return [] }
        let sql = "SELECT word FROM words"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        var results: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let cString = sqlite3_column_text(statement, 0) {
                results.append(String(cString: cString))
            }
        }
        return results
    }
}

// ─────────────────────────────────────────────
// MARK: - MatchResult
// ─────────────────────────────────────────────

// Modello per un risultato di match/anagramma; contiene metadati utili alla UI (match pieno, lettere usate, avanzi).
struct MatchResult: Identifiable {
    let id = UUID()
    let word: String
    let isFullMatch: Bool
    let leftover: String
    let usedLetterCount: Int
}

struct ContentView: View {
    // Vista principale dell'app:
    // - Gestisce l'input dell'utente (solo lettere e spazi, uppercase)
    // - Esegue la ricerca in memoria (cache delle parole) con debounce per la modalità Live
    // - Raggruppa i risultati per numero di lettere utilizzate e mostra sezioni con percentuale
    // - Presenta una barra statistiche riassuntiva
    
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    @State private var searchText = "" // testo inserito dall'utente
    @State private var results: [MatchResult] = [] // risultati correnti della ricerca
    
    // Filtri e parametri di ricerca
    @State private var searchAsYouType = false // se attivo, ricerca live durante la digitazione
    @State private var fullMatchesOnly = true // mostra solo anagrammi 100% (nessun avanzo)
    @State private var minLength: Int = 4 // lunghezza minima delle parole trovate

    // ───────── Debounce per la ricerca Live ─────────
    // Debounce work item for live search
    @State private var liveSearchWorkItem: DispatchWorkItem?

    private func debounceLiveSearch(delay: TimeInterval = 0.12) { // ritarda l'esecuzione per coalescere input ravvicinati
        liveSearchWorkItem?.cancel()
        let work = DispatchWorkItem { performSearch() }
        liveSearchWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
    
    // Cella compatta per mostrare piccole statistiche nella barra inferiore
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
    
    // Cache locale di tutte le parole (caricate una volta all'avvio) per ricerche rapide in memoria
    @State private var allWordsCache: [String] = []
    
    // Raggruppa i risultati per numero di lettere utilizzate (usedLetterCount)
    // - Ordina le sezioni in modo decrescente (più lettere trovate in alto)
    // - Ordina le parole alfabeticamente dentro ogni sezione
    private var groupedResults: [(count: Int, items: [MatchResult])] {
        let groups = Dictionary(grouping: results) { $0.usedLetterCount }
        // Sort sections descending by matched letters; items alphabetically
        return groups
            .map { (key: $0.key, value: $0.value.sorted { $0.word < $1.word }) }
            .sorted { $0.key > $1.key }
            .map { (count: $0.key, items: $0.value) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // --- HEADER: Ricerca e Controlli ---
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    
                    TextField("Scrivi qui...", text: $searchText)
                        // Preferenze tastiera: solo lettere maiuscole, niente correzione, layout alfabetico
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled(true)
                        .disableAutocorrection(true)  // Alternate/older API
                        .keyboardType(.alphabet)     // Alphabet keyboard (no numbers row)

                        // Esegue la ricerca solo su invio quando la modalità Live è disattivata
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
                
                // Controlli disposti su due righe per migliore scopribilità (senza ScrollView orizzontale)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        // Pulsante "Ricerca Live" (stato evidenziato quando attivo)
                        Button(action: { searchAsYouType.toggle() }) {
                            HStack(spacing: 6) {
                                Image(systemName: "bolt.fill")
                                Text("Ricerca Live")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(searchAsYouType ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground))
                            .foregroundStyle(searchAsYouType ? Color.accentColor : Color.primary)
                            .overlay(
                                Capsule()
                                    .stroke(searchAsYouType ? Color.accentColor : Color(.separator), lineWidth: 1)
                            )
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        // Pulsante filtro "Solo 100%" (mostra solo match completi)
                        Button(action: { fullMatchesOnly.toggle() }) {
                            HStack(spacing: 6) {
                                Image(systemName: "target")
                                Text("Solo 100%")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(fullMatchesOnly ? Color.blue.opacity(0.15) : Color(.secondarySystemBackground))
                            .foregroundStyle(fullMatchesOnly ? Color.blue : Color.primary)
                            .overlay(
                                Capsule()
                                    .stroke(fullMatchesOnly ? Color.blue : Color(.separator), lineWidth: 1)
                            )
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)

                    }

                    HStack(spacing: 12) {
                        HStack(spacing: 10) {
                            Label("Lunghezza minima", systemImage: "textformat.size")
                                .labelStyle(.titleAndIcon)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)

                            Spacer(minLength: 8)

                            // Stepper compatto con bottoni -/+ e valore monospaziato (limiti 3...15)
                            HStack(spacing: 6) {
                                Button(action: {
                                    if minLength > 3 { minLength -= 1 }
                                }) {
                                    Image(systemName: "minus")
                                        .font(.footnote.weight(.semibold))
                                        .frame(width: 24, height: 24)
                                        .background(Color(.secondarySystemBackground))
                                        .foregroundStyle(minLength > 3 ? Color.primary : Color.secondary)
                                        .clipShape(Circle())
                                        .overlay(Circle().stroke(Color(.separator), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                                .disabled(minLength <= 3)

                                Text("\(minLength)")
                                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                    .frame(minWidth: 28)

                                Button(action: {
                                    if minLength < 15 { minLength += 1 }
                                }) {
                                    Image(systemName: "plus")
                                        .font(.footnote.weight(.semibold))
                                        .frame(width: 24, height: 24)
                                        .background(Color(.secondarySystemBackground))
                                        .foregroundStyle(minLength < 15 ? Color.primary : Color.secondary)
                                        .clipShape(Circle())
                                        .overlay(Circle().stroke(Color(.separator), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                                .disabled(minLength >= 15)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                        // Spazio per futuri controlli (es. Picker di ordinamento)
                        Spacer()
                    }
                }
                .padding(.vertical, 2)
            }
            .padding()
            .background(.ultraThinMaterial)
            
            Divider()

            // Lista dei risultati: sezioni per numero di lettere trovate; header mostra conteggio e percentuale rispetto all'input
            if results.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: searchText.isEmpty ? "text.magnifyingglass" : "questionmark.circle")
                        .font(.system(size: 60))
                        .foregroundStyle(.quaternary)
                    Text(searchText.isEmpty ? "Inserisci le lettere da anagrammare (minimo \(minLength))" : "Nessun risultato")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                // Lista dei risultati: sezioni per numero di lettere trovate; header mostra conteggio e percentuale rispetto all'input
                List {
                    ForEach(groupedResults, id: \ .count) { section in
                        let pct = searchText.isEmpty ? 0 : Int(round((Double(section.count) / Double(searchText.replacingOccurrences(of: " ", with: "").count)) * 100)) // percentuale di lettere usate / lunghezza input
                        Section(header: HStack {
                            Text("\(section.count) lettere trovate")
                            Text("(\(pct)%)")
                                .foregroundStyle(.secondary)
                        }) {
                            ForEach(section.items) { result in
                                HStack(alignment: .center, spacing: 8) {
                                    // 1. La parola trovata
                                    Text(result.word)
                                        .font(.system(.subheadline, design: .monospaced))
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
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .padding(.bottom, 20) // spazio extra sopra la barra statistiche per respiro visivo
            }
            // Barra statistiche riassuntiva (conteggio, match 100%, parola più lunga, media lunghezze)
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
                let words = WordDatabase.shared.allWords() // carica tutte le parole in background
                DispatchQueue.main.async {
                    self.allWordsCache = words
                }
            }
        }
        // Reazioni ai cambi di filtro e input
        .onChange(of: fullMatchesOnly) { performSearch() }
        .onChange(of: minLength) { performSearch() }
        // Sanitizza l'input (solo lettere e spazi, uppercase) e avvia la ricerca live con debounce
        .onChange(of: searchText) { newValue in
            // Allow only letters and spaces; keep uppercase for consistency.
            let cleaned = newValue
                .uppercased()
                .filter { $0.isLetter || $0 == " " }

            if cleaned != newValue {
                // Update on next runloop to avoid fighting the keyboard's composition state.
                DispatchQueue.main.async {
                    if searchText != cleaned { // guard again in case user typed more
                        searchText = cleaned
                    }
                }
                return
            }

            // Debounce live search slightly to reduce keyboard churn
            if searchAsYouType {
                debounceLiveSearch()
            }
        }
    }

    // Esegue la ricerca sugli anagrammi:
    // 1) Normalizza l'input (uppercase, rimuove spazi) e conta le lettere
    // 2) Per ogni parola in cache verifica se può essere costruita con le lettere disponibili
    // 3) Calcola le lettere avanzate (leftover) e se il match è completo (100%)
    // 4) Applica i filtri (fullMatchesOnly, minLength) e produce MatchResult
    // 5) Ordina i risultati: prima match completi, poi per lunghezza decrescente, poi alfabetico
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
    
    // Statistiche derivate dai risultati correnti (per la barra inferiore)
    private struct Stats {
        let total: Int
        let fullMatches: Int
        let longest: String
        let avgLength: Double
    }

    private var stats: Stats {
        let total = results.count
        let fullMatches = results.filter { $0.isFullMatch }.count
        let longest = results.max(by: { $0.word.count < $1.word.count })?.word ?? "-"
        let avgLength = total > 0
            ? Double(results.map { $0.word.count }.reduce(0, +)) / Double(total)
            : 0

        return Stats(
            total: total,
            fullMatches: fullMatches,
            longest: longest,
            avgLength: avgLength
        )
    }
    
}

// ─────────────────────────────────────────────
// MARK: - Preview
// ─────────────────────────────────────────────

#Preview {
    ContentView()
}

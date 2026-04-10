import SwiftUI
import SQLite3
import UIKit

// ─────────────────────────────────────────────
// MARK: - Database
// ─────────────────────────────────────────────

final class WordDatabase {
    static let shared = WordDatabase()
    private var database: OpaquePointer?
    private let dbQueue = DispatchQueue(label: "WordDatabase.SerialQueue")

    private init() {
        guard let bundlePath = Bundle.main.path(forResource: "Words", ofType: "db") else { return }
        sqlite3_open_v2(bundlePath, &database, SQLITE_OPEN_READONLY, nil)
    }

    func exactMatches(using letters: String) -> [String] {
        return dbQueue.sync {
            guard let database else { return [] }
            let key = String(letters.uppercased().sorted())
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
    }

    func allWords() -> [String] {
        return dbQueue.sync {
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
}

struct MatchResult: Identifiable {
    let id = UUID()
    let word: String
    let isFullMatch: Bool
    let leftover: String
    let usedLetterCount: Int
}

// ─────────────────────────────────────────────
// MARK: - App Bar
// ─────────────────────────────────────────────

/// La barra superiore scura con titolo, sottotitolo contestuale e azioni.
struct AppBar: View {
    
    let resultCount: Int?          // nil = nessuna ricerca ancora
    let showScrollTop: Bool
    let onScrollTop: () -> Void
    let onHelp: () -> Void
    
    let maxLengthText: String?
    let averageText: String?

    // Sottotitolo: feedback contestuale o etichetta fissa
    private var subtitle: String {
        // Base: feedback sul numero di risultati, oppure etichetta fissa quando non si è ancora cercato
        let base: String = {
            guard let count = resultCount else { return "" } // qui ci può stare un sottotitolo in attesa dei risultati
            switch count {
            case 0: return "Nessuna parola trovata"
            case 1: return "1 parola trovata"
            default: return "\(count) parole trovate"
            }
        }()
        // Aggiungi statistiche se presenti
        if let maxLengthText, let averageText, resultCount != nil, resultCount! > 0 {
            return "\(base) • Lun. Max: \(maxLengthText) • Media: \(averageText)"
        } else {
            return base
        }
    }

    private var subtitleColor: Color {
        guard let count = resultCount else { return Color(hex: "#378ADD") }
        return count == 0 ? Color(hex: "#F09595") : Color(hex: "#5DCAA5")
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("CercAnagramma")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Color(hex: "#E6F1FB"))

                Text(subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(subtitleColor)
                    .animation(.easeInOut(duration: 0.2), value: subtitle)
            }

            Spacer()

            HStack(spacing: 12) {
                if showScrollTop {
                    AppBarButton(icon: "arrow.up.to.line", action: onScrollTop)
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                }
                AppBarButton(icon: "questionmark", action: onHelp)
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showScrollTop)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Color(hex: "#0C1B2E"))
    }
}

struct AppBarButton: View {
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                )
                .foregroundStyle(Color.white.opacity(0.55))
        }
        .buttonStyle(.plain)
    }
}

// ─────────────────────────────────────────────
// MARK: - Search Row
// ─────────────────────────────────────────────

/// Barra di ricerca con campo, contatore lettere, ✕ interno e bottone azione.
struct SearchRow: View {
    @Binding var searchText: String
    let hasResults: Bool
    let hasSearched: Bool
    let searchAsYouType: Bool
    let onSearch: () -> Void
    let onReset: () -> Void

    // Opzione 3: bottone FA SOLO RICERCA, sempre
    private var isSearchDisabled: Bool {
        searchText.isEmpty
    }

    var body: some View {
        HStack(spacing: 8) {
            // Campo
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                TextField("Scrivi qui…", text: $searchText)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled(true)
                    .submitLabel(.search)
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                    .onSubmit {
                        if !searchText.isEmpty {
                            onSearch()
                        }
                    }

                if !searchText.isEmpty {
                    // Contatore lettere (solo caratteri non-spazio)
                    let letterCount = searchText.filter { $0.isLetter }.count
                    Text("\(letterCount)")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    // ✕ dentro il campo: reset COMPLETO (testo + risultati)
                    Button {
                        searchText = ""
                        onReset()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color(.systemGray3))
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5)
            )
            .animation(.easeInOut(duration: 0.15), value: searchText.isEmpty)

            // Bottone azione: SOLO RICERCA (sempre icona lente)
            Button {
                onSearch()
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 40, height: 40)
                    .background(isSearchDisabled ? Color(.systemGray4) : Color(hex: "#185FA5"))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(isSearchDisabled)
            .sensoryFeedback(.impact(weight: .medium), trigger: hasSearched)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
    }
}

// ─────────────────────────────────────────────
// MARK: - Controls Row
// ─────────────────────────────────────────────

struct ControlsRow: View {
    @Binding var fullMatchesOnly: Bool
    @Binding var searchAsYouType: Bool
    @Binding var deepSearchEnabled: Bool
    @Binding var minLength: Int

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ControlChip(
                    title: "Solo 100%",
                    isActive: fullMatchesOnly,
                    activeColor: .green
                ) { fullMatchesOnly.toggle() }

                ControlChip(
                    title: "Live",
                    isActive: searchAsYouType,
                    activeColor: .blue
                ) { searchAsYouType.toggle() }

                ControlChip(
                    title: "Avanzata",
                    isActive: deepSearchEnabled,
                    activeColor: .purple
                ) { deepSearchEnabled.toggle() }

                Divider()
                    .frame(height: 18)
                    .padding(.horizontal, 2)

                // Controllo lunghezza minima
                HStack(spacing: 5) {
                    Button { if minLength > 3 { minLength -= 1 } } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 20, height: 20)
                            .background(Color(.systemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(minLength <= 3)

                    Text("Min \(minLength)")
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)

                    Button { if minLength < 15 { minLength += 1 } } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 20, height: 20)
                            .background(Color(.systemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(minLength >= 15)
                }
                .sensoryFeedback(.selection, trigger: minLength)
            }
            .padding(.horizontal, 14)
        }
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(.separator).opacity(0.4))
                .frame(height: 0.5)
        }
    }
}

struct ControlChip: View {
    let title: String
    let isActive: Bool
    let activeColor: Color
    let action: () -> Void

    private var bgColor: Color {
        isActive ? activeColor.opacity(0.12) : Color(.systemBackground)
    }
    private var fgColor: Color {
        isActive ? activeColor : Color.secondary
    }
    private var borderColor: Color {
        isActive ? activeColor.opacity(0.4) : Color(.separator).opacity(0.5)
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(fgColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(bgColor)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(borderColor, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: isActive)
        .animation(.easeInOut(duration: 0.15), value: isActive)
    }
}

// ─────────────────────────────────────────────
// MARK: - Main View
// ─────────────────────────────────────────────

struct ContentView: View {
    @State private var searchText = ""
    @State private var results: [MatchResult] = []
    @State private var searchAsYouType = false
    @State private var fullMatchesOnly = true
    @State private var minLength: Int = 4
    @State private var deepSearchEnabled = false
    @State private var hasSearched = false

    @State private var loadingLeftovers: Set<String> = []
    @State private var leftoverCache: [String: [String]] = [:]
    @State private var allWordsCache: [String] = []
    @State private var liveSearchWorkItem: DispatchWorkItem?

    @State private var showingHelp = false
    @State private var definitionTerm: String?
    @State private var scrollToTopTrigger = false

    private struct LeftoverPresentation: Identifiable {
        let id = UUID()
        let title: String
        let words: [String]
    }
    @State private var leftoverSheetItem: LeftoverPresentation?

    private var groupedResults: [(count: Int, items: [MatchResult])] {
        let groups = Dictionary(grouping: results) { $0.usedLetterCount }
        return groups
            .map { (key: $0.key, value: $0.value.sorted { $0.word < $1.word }) }
            .sorted { $0.key > $1.key }
            .map { (count: $0.key, items: $0.value) }
    }

    var body: some View {
        VStack(spacing: 0) {

            // ── App Bar ──────────────────────────────
            AppBar(
                resultCount: hasSearched ? results.count : nil,
                showScrollTop: !results.isEmpty,
                onScrollTop: { scrollToTopTrigger.toggle() },
                onHelp: { showingHelp = true },
                maxLengthText: (results.isEmpty ? nil : String(results.max(by: { $0.word.count < $1.word.count })?.word.count ?? 0)),
                averageText: (results.isEmpty ? nil : String(format: "%.1f", (Double(results.reduce(0) { $0 + $1.word.count }) / Double(results.count))))
            )

            // ── Search Row ───────────────────────────
            SearchRow(
                searchText: $searchText,
                hasResults: !results.isEmpty,
                hasSearched: hasSearched,
                searchAsYouType: searchAsYouType,
                onSearch: performSearch,
                onReset: {
                    results = []
                    hasSearched = false
                }
            )

            // ── Controls Row ─────────────────────────
            ControlsRow(
                fullMatchesOnly: $fullMatchesOnly,
                searchAsYouType: $searchAsYouType,
                deepSearchEnabled: $deepSearchEnabled,
                minLength: $minLength
            )

            // ── Results / Empty state ─────────────────
            if results.isEmpty {
                EmptyStateView(searchText: searchText, minLength: minLength)
            } else {
                ScrollViewReader { proxy in
                    List {
                        ForEach(groupedResults, id: \.count) { section in
                            Section(header: Text("\(section.count) lettere")) {
                                ForEach(section.items) { result in
                                    ResultRow(
                                        result: result,
                                        deepSearchEnabled: deepSearchEnabled,
                                        leftoverCache: leftoverCache,
                                        loadingLeftovers: loadingLeftovers,
                                        onLoadLeftover: loadLeftover,
                                        onShowSheet: { title, matches in
                                            leftoverSheetItem = LeftoverPresentation(title: title, words: matches)
                                        },
                                        onWordTapped: { word in definitionTerm = word }
                                    )
                                    .id(result.id)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .onChange(of: scrollToTopTrigger) { _, _ in
                        if let firstItem = groupedResults.first?.items.first {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo(firstItem.id, anchor: .top)
                            }
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .top) {
            // Add a spacer matching the app bar background so content starts below the status bar
            Color(hex: "#0C1B2E").frame(height: 0)
                .background(Color(hex: "#0C1B2E").ignoresSafeArea(edges: .top))
        }
        .sheet(item: $leftoverSheetItem) { item in
            LeftoverSheet(title: item.title, words: item.words)
        }
        .fullScreenCover(isPresented: $showingHelp) {
            HelpView()
        }
        .fullScreenCover(isPresented: Binding<Bool>(
            get: { definitionTerm != nil },
            set: { if !$0 { definitionTerm = nil } }
        )) {
            if let term = definitionTerm {
                DictionaryDefinitionView(term: term)
            }
        }
        .onAppear { loadInitialData() }
        .onChange(of: fullMatchesOnly)    { _, _ in performSearch() }
        .onChange(of: minLength)          { _, _ in performSearch() }
        .onChange(of: deepSearchEnabled)  { _, newValue in if newValue { triggerDeepSearch() } }
        .onChange(of: searchText)         { _, newValue in handleSearchTextChange(newValue) }
    }

    // ─── Logic ───────────────────────────────────

    private func performSearch() {
        let input = searchText.uppercased().replacingOccurrences(of: " ", with: "")
        guard input.count >= 2 else {
            results = []
            hasSearched = false
            return
        }

        let inputCounts = Array(input).reduce(into: [:]) { $0[$1, default: 0] += 1 }
        var output: [MatchResult] = []

        for word in allWordsCache {
            if word == input || word.count < minLength { continue }
            var tempCounts = inputCounts
            var canMake = true
            for char in Array(word) {
                if let count = tempCounts[char], count > 0 { tempCounts[char]! -= 1 }
                else { canMake = false; break }
            }
            guard canMake else { continue }

            let leftover = tempCounts
                .flatMap { Array(repeating: $0.key, count: $0.value) }
                .sorted().map(String.init).joined()
            let isFull = leftover.isEmpty && word.count == input.count
            if fullMatchesOnly && !isFull { continue }

            output.append(MatchResult(word: word, isFullMatch: isFull, leftover: leftover, usedLetterCount: word.count))
        }

        results = output.sorted {
            if $0.isFullMatch != $1.isFullMatch { return $0.isFullMatch }
            return $0.usedLetterCount > $1.usedLetterCount
        }
        hasSearched = true
        if deepSearchEnabled { triggerDeepSearch() }
    }

    private func triggerDeepSearch() {
        for result in results where result.leftover.count >= 2 {
            loadLeftover(result.leftover)
        }
    }

    private func loadLeftover(_ leftover: String) {
        guard leftover.count >= 2,
              leftoverCache[leftover] == nil,
              !loadingLeftovers.contains(leftover) else { return }
        loadingLeftovers.insert(leftover)
        DispatchQueue.global(qos: .userInitiated).async {
            let matches = WordDatabase.shared.exactMatches(using: leftover)
            DispatchQueue.main.async {
                loadingLeftovers.remove(leftover)
                leftoverCache[leftover] = matches
            }
        }
    }

    private func loadInitialData() {
        DispatchQueue.global(qos: .userInitiated).async {
            let words = WordDatabase.shared.allWords()
            DispatchQueue.main.async { self.allWordsCache = words }
        }
    }

    private func handleSearchTextChange(_ newValue: String) {
        let cleaned = newValue.uppercased().filter { $0.isLetter || $0 == " " }
        if cleaned != newValue { searchText = cleaned }
        if searchAsYouType {
            liveSearchWorkItem?.cancel()
            let work = DispatchWorkItem { performSearch() }
            liveSearchWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
        } else {
            // In modalità non-Live, quando l'utente modifica il testo, resetta i risultati
            // così il bottone "Cerca" è necessario per vedere nuovi risultati
            if hasSearched {
                results = []
                hasSearched = false
            }
        }
    }
}

// ─────────────────────────────────────────────
// MARK: - Hex Color helper
// ─────────────────────────────────────────────

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let red = Double((int >> 16) & 0xFF) / 255
        let green = Double((int >> 8)  & 0xFF) / 255
        let blue = Double(int         & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}

// ─────────────────────────────────────────────
// MARK: - Subviews (invariati)
// ─────────────────────────────────────────────

struct ResultRow: View {
    let result: MatchResult
    let deepSearchEnabled: Bool
    let leftoverCache: [String: [String]]
    let loadingLeftovers: Set<String>
    let onLoadLeftover: (String) -> Void
    let onShowSheet: (String, [String]) -> Void
    let onWordTapped: (String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button { onWordTapped(result.word) } label: {
                Text(result.word)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)

            Spacer()

            if !result.isFullMatch && !result.leftover.isEmpty {
                let matches = leftoverCache[result.leftover]
                let hasMatches = !(matches?.isEmpty ?? true)
                let isPurple = deepSearchEnabled && hasMatches

                Text("+").font(.system(.caption2, design: .monospaced))

                Button {
                    guard isPurple, let matches, !matches.isEmpty else { return }
                    onShowSheet(result.leftover, matches)
                } label: {
                    HStack(spacing: 4) {
                        Text(result.leftover).font(.system(.caption, design: .monospaced))
                        if deepSearchEnabled && loadingLeftovers.contains(result.leftover) {
                            ProgressView().scaleEffect(0.6)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(isPurple ? Color.purple.opacity(0.15) : Color(.secondarySystemBackground))
                    .foregroundStyle(isPurple ? Color.purple : Color.secondary)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .onAppear { if deepSearchEnabled { onLoadLeftover(result.leftover) } }
            }

            if result.isFullMatch {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }
        }
    }
}

struct LeftoverSheet: View {
    let title: String
    let words: [String]
    @State private var selectedTerm: String?

    var body: some View {
        NavigationStack {
            List(words, id: \.self) { word in
                Button {
                    selectedTerm = word
                } label: {
                    Text(word)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Risultati per: \(title)")
            .navigationBarTitleDisplayMode(.inline)
        }
        .fullScreenCover(isPresented: Binding<Bool>(
            get: { selectedTerm != nil },
            set: { if !$0 { selectedTerm = nil } }
        )) {
            if let term = selectedTerm { DictionaryDefinitionView(term: term) }
        }
    }
}

struct EmptyStateView: View {
    let searchText: String
    let minLength: Int

    var body: some View {
        VStack {
            Spacer()
            Image(systemName: searchText.isEmpty ? "text.magnifyingglass" : "questionmark.circle")
                .font(.system(size: 50))
                .foregroundStyle(.quaternary)
                .padding(.bottom, 8)
            Text(searchText.isEmpty
                 ? "Inserisci le lettere da anagrammare\n(minimo \(minLength))"
                 : "Nessun risultato")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
    }
}

#Preview {
    ContentView()
}

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

    // accetta minLength e lo applica nella query SQL
    func exactMatches(using letters: String, minLength: Int = 4) -> [String] {
        return dbQueue.sync {
            guard let database else { return [] }
            let key = String(letters.uppercased().sorted())
            let sql = "SELECT word FROM words WHERE sorted = ? AND LENGTH(word) >= ? ORDER BY word"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_text(statement, 1, (key as NSString).utf8String, -1, nil)
            sqlite3_bind_int(statement, 2, Int32(minLength))
            var results: [String] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                if let cString = sqlite3_column_text(statement, 0) {
                    results.append(String(cString: cString))
                }
            }
            return results
        }
    }

    // pre-filtra a >= 4 hardcoded (minLength assoluto)
    func allWords(minLength: Int = 4) -> [String] {
        return dbQueue.sync {
            guard let database else { return [] }
            let sql = "SELECT word FROM words WHERE LENGTH(word) >= ?"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int(statement, 1, Int32(minLength))
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
    let id: String // per evitare l'overheade delle allocazioni UID
    let word: String
    let isFullMatch: Bool
    let leftover: String
    let usedLetterCount: Int
}

// ─────────────────────────────────────────────
// MARK: - App Bar
// ─────────────────────────────────────────────
struct AppBar: View {
    
    let resultCount: Int?
    let showScrollTop: Bool
    let onScrollTop: () -> Void
    let onHelp: () -> Void
    
    let maxLengthText: String?
    let averageText: String?
    let isCapped: Bool

    private var subtitle: String {
        let base: String = {
            guard let count = resultCount else { return "" }
            switch count {
            case 0: return "Nessuna parola trovata"
            case 1: return isCapped ? "Prima parola (risultati troncati)" : "1 parola trovata"
            default: return isCapped ? "Prime \(count) parole" : "\(count) parole trovate"
            }
        }()
        if let maxLengthText, let averageText, resultCount != nil, resultCount! > 0 {
            return "\(base) • Lun. Max: \(maxLengthText) • Media: \(averageText)"
        } else {
            return base
        }
    }

    private var subtitleColor: Color {
        guard let count = resultCount else { return Color(hex: "#378ADD") }
        if count == 0 { return Color(hex: "#F09595") }
        if isCapped { return Color(hex: "#EF9F27") }
        return Color(hex: "#5DCAA5")
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
struct SearchRow: View {
    @Binding var searchText: String
    let hasResults: Bool
    let hasSearched: Bool
    let searchAsYouType: Bool
    let maxLetters: Int
    let onSearch: () -> Void
    let onReset: () -> Void

    private var isSearchDisabled: Bool {
        searchText.isEmpty
    }

    var body: some View {
        HStack(spacing: 8) {
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
                    let letterCount = searchText.filter { $0.isLetter }.count
                    let isAtLimit = letterCount >= maxLetters

                    Text("\(letterCount)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(isAtLimit ? .white : .secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(isAtLimit ? Color.red : Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(isAtLimit ? Color.red.opacity(0.6) : Color.clear, lineWidth: 1)
                        )
                        .scaleEffect(isAtLimit ? 1.08 : 1.0)
                        .animation(.easeInOut(duration: 0.18), value: isAtLimit)
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

                HStack(spacing: 5) {
                    Button { if minLength > 4 { minLength -= 1 } } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 20, height: 20)
                            .background(Color(.systemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(minLength <= 4)

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
    private let maxLetters = 25

    private let resultsCap = 5000
    @State private var resultsWereCapped = false

    private var groupedResults: [(count: Int, items: [MatchResult])] {
        let groups = Dictionary(grouping: results) { $0.usedLetterCount }
        return groups
            .map { (key: $0.key, value: $0.value.sorted { $0.word < $1.word }) }
            .sorted { $0.key > $1.key }
            .map { (count: $0.key, items: $0.value) }
    }

    var body: some View {
        VStack(spacing: 0) {

            AppBar(
                resultCount: hasSearched ? results.count : nil,
                showScrollTop: !results.isEmpty,
                onScrollTop: { scrollToTopTrigger.toggle() },
                onHelp: { showingHelp = true },
                maxLengthText: (results.isEmpty ? nil : String(results.max(by: { $0.word.count < $1.word.count })?.word.count ?? 0)),
                averageText: (results.isEmpty ? nil : String(format: "%.1f", (Double(results.reduce(0) { $0 + $1.word.count }) / Double(results.count)))),
                isCapped: resultsWereCapped
            )

            SearchRow(
                searchText: $searchText,
                hasResults: !results.isEmpty,
                hasSearched: hasSearched,
                searchAsYouType: searchAsYouType,
                maxLetters: maxLetters,
                onSearch: performSearch,
                onReset: {
                    results = []
                    hasSearched = false
                }
            )

            ControlsRow(
                fullMatchesOnly: $fullMatchesOnly,
                searchAsYouType: $searchAsYouType,
                deepSearchEnabled: $deepSearchEnabled,
                minLength: $minLength
            )

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
        .onChange(of: fullMatchesOnly) { _, _ in performSearch() }
        .onChange(of: minLength) { _, _ in
            leftoverCache = [:] // svuota la cache degli avanzi se cambia il min len.
            performSearch()
        }
        .onChange(of: deepSearchEnabled) { _, newValue in if newValue { triggerDeepSearch() } }
        .onChange(of: searchText) { _, newValue in handleSearchTextChange(newValue) }
    }

    // ─── Logic ───────────────────────────────────

    private func performSearch() {
        let input = searchText.uppercased().replacingOccurrences(of: " ", with: "")
        guard input.count >= 2 else {
            results = []
            resultsWereCapped = false
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
                if let count = tempCounts[char], count > 0 {
                    tempCounts[char]! -= 1
                } else {
                    canMake = false
                    break
                }
            }
            guard canMake else { continue }

            let leftover = tempCounts
                .flatMap { Array(repeating: $0.key, count: $0.value) }
                .sorted()
                .map(String.init)
                .joined()
            let isFull = leftover.isEmpty && word.count == input.count
            if fullMatchesOnly && !isFull { continue }

            output.append(MatchResult(
                id: word,
                word: word,
                isFullMatch: isFull,
                leftover: leftover,
                usedLetterCount: word.count
            ))
        }

        output.sort {
            if $0.isFullMatch != $1.isFullMatch { return $0.isFullMatch }
            return $0.usedLetterCount > $1.usedLetterCount
        }

        if output.count > resultsCap {
            resultsWereCapped = true
            results = Array(output.prefix(resultsCap))
        } else {
            resultsWereCapped = false
            results = output
        }

        hasSearched = true
        if deepSearchEnabled { triggerDeepSearch() }
    }
    
    private func triggerDeepSearch() {
        for result in results where result.leftover.count >= 2 {
            loadLeftover(result.leftover)
        }
    }

    // passa minLength alla query SQL
    private func loadLeftover(_ leftover: String) {
        guard leftover.count >= 2,
              leftoverCache[leftover] == nil,
              !loadingLeftovers.contains(leftover) else { return }
        loadingLeftovers.insert(leftover)
        let currentMinLength = minLength
        DispatchQueue.global(qos: .userInitiated).async {
            let matches = WordDatabase.shared.exactMatches(using: leftover, minLength: currentMinLength)
            DispatchQueue.main.async {
                loadingLeftovers.remove(leftover)
                leftoverCache[leftover] = matches
            }
        }
    }

    // pre-filtra a >= 4 hardcoded (costante assoluta)
    private func loadInitialData() {
        DispatchQueue.global(qos: .userInitiated).async {
            let words = WordDatabase.shared.allWords(minLength: 4)
            DispatchQueue.main.async { self.allWordsCache = words }
        }
    }

    private func handleSearchTextChange(_ newValue: String) {
        //  pulisci il testo (solo lettere e spazi)
        let cleaned = newValue.uppercased().filter { $0.isLetter || $0 == " " }
        
        // Conta solo le lettere per il limite
        let letterCount = cleaned.filter { $0.isLetter }.count
        
        // Se supera il limite di lettere, tronca mantenendo le prime maxLetters lettere
        if letterCount > maxLetters {
            var result = ""
            var lettersAdded = 0
            
            for char in cleaned {
                if char.isLetter {
                    if lettersAdded < maxLetters {
                        result.append(char)
                        lettersAdded += 1
                    }
                } else if char == " " {
                    // Le spazio possono rimanere, ma non contano per il limite
                    result.append(char)
                }
            }
            searchText = result
            return
        }
        
        // Aggiorna solo se diverso
        if cleaned != newValue {
            searchText = cleaned
        }
        
        // Gestisci la ricerca live
        if searchAsYouType {
            liveSearchWorkItem?.cancel()
            let work = DispatchWorkItem { performSearch() }
            liveSearchWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
        } else {
            if hasSearched {
                results = []
                hasSearched = false
            }
        }
    }
}

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
// MARK: - Subviews
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

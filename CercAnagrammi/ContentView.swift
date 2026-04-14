import SwiftUI
import SQLite3
import UIKit

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let red   = Double((int >> 16) & 0xFF) / 255
        let green = Double((int >> 8)  & 0xFF) / 255
        let blue  = Double(int         & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }

    // Backgrounds
    static let steelBase    = Color(hex: "#0C1B2E")
    static let steelSurface = Color(hex: "#0F2236")
    static let steelCard    = Color(hex: "#122840")
    static let steelBorder  = Color(hex: "#1E3D5C")

    // Accents
    static let accentBlue   = Color(hex: "#378ADD")
    static let accentGreen  = Color(hex: "#4CAF8A")
//    static let accentViolet = Color(hex: "#8B7EC8")
    static let accentViolet = Color(hex: "#9789D9")
    static let accentGold   = Color(hex: "#C9A84C")

    // Text
    static let textPrimary   = Color(hex: "#E6F1FB")
    static let textSecondary = Color(hex: "#6B8FAD")
    static let textMuted     = Color(hex: "#3A5A7A")
}

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

// ─────────────────────────────────────────────
// MARK: - Models
// ─────────────────────────────────────────────
struct MatchResult: Identifiable {
    let id: String
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
            case 0:  return "Nessuna parola trovata"
            case 1:  return isCapped ? "Prima parola (risultati troncati)" : "1 parola trovata"
            default: return isCapped ? "Prime \(count) parole" : "\(count) parole trovate"
            }
        }()
        if let maxLengthText, let averageText, resultCount != nil, resultCount! > 0 {
            return "\(base) • Max: \(maxLengthText) • Media: \(averageText)"
        }
        return base
    }

    private var subtitleColor: Color {
        guard let count = resultCount else { return .accentBlue }
        if count == 0 { return Color(hex: "#C0504A") }
        if isCapped { return Color(hex: "#C9943A") }
        return .accentGreen
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("CercAnagrammi")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.textPrimary)

                if resultCount != nil {
                    Text(subtitle)
                       // .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(subtitleColor)
                        .animation(.easeInOut(duration: 0.2), value: subtitle)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                if showScrollTop {
                    SteelBarButton(icon: "arrow.up.to.line", action: onScrollTop)
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                }
                SteelBarButton(icon: "questionmark", action: onHelp)
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showScrollTop)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(Color.steelBase)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.steelBorder.opacity(0.6))
                .frame(height: 0.5)
        }
    }
}

struct SteelBarButton: View {
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(Color.steelCard)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.steelBorder, lineWidth: 0.5)
                )
                .foregroundStyle(Color.textSecondary)
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

    private var isSearchDisabled: Bool { searchText.isEmpty }

    var body: some View {
        HStack(spacing: 8) {

            // ── Input field ──────────────────────────
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.textMuted)

                TextField("Scrivi qui…", text: $searchText)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled(true)
                    .submitLabel(.search)
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.textPrimary)
                    .tint(Color.accentBlue)
                    .onSubmit {
                        if !searchText.isEmpty { onSearch() }
                    }

                if !searchText.isEmpty {
                    let letterCount = searchText.filter { $0.isLetter }.count
                    let isAtLimit   = letterCount >= maxLetters

                    Text("\(letterCount)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(isAtLimit ? Color.textPrimary : Color.textSecondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(isAtLimit ? Color(hex: "#7A2020") : Color.steelCard)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(
                                    isAtLimit ? Color(hex: "#C0504A").opacity(0.7) : Color.steelBorder,
                                    lineWidth: 0.5
                                )
                        )
                        .scaleEffect(isAtLimit ? 1.08 : 1.0)
                        .animation(.easeInOut(duration: 0.18), value: isAtLimit)

                    Button {
                        searchText = ""
                        onReset()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.textMuted)
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.steelCard)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.steelBorder, lineWidth: 0.5)
            )
            .animation(.easeInOut(duration: 0.15), value: searchText.isEmpty)

            // ── Search button ────────────────────────
            Button { onSearch() } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isSearchDisabled
                              ? Color.steelCard
                              : Color.accentBlue.opacity(0.85))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(
                                    isSearchDisabled ? Color.steelBorder : Color.accentBlue,
                                    lineWidth: 0.5
                                )
                        )

                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isSearchDisabled ? Color.textMuted : Color.textPrimary)
                }
                .frame(width: 42, height: 42)
            }
            .buttonStyle(.plain)
            .disabled(isSearchDisabled)
            .sensoryFeedback(.impact(weight: .medium), trigger: hasSearched)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.steelSurface)
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
                SteelChip(title: "Solo 100%", isActive: fullMatchesOnly, activeColor: .accentGreen) { fullMatchesOnly.toggle() }
                SteelChip(title: "Live", isActive: searchAsYouType, activeColor: .accentBlue) { searchAsYouType.toggle() }
                SteelChip(title: "Avanzata", isActive: deepSearchEnabled, activeColor: .accentViolet) { deepSearchEnabled.toggle() }

                Rectangle()
                    .fill(Color.steelBorder)
                    .frame(width: 0.5, height: 18)
                    .padding(.horizontal, 2)

                HStack(spacing: 6) {
                    StepperButton(icon: "minus", disabled: minLength <= 4) {
                        if minLength > 4 { minLength -= 1 }
                    }

                    Text("Min \(minLength)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.textSecondary)
                        .frame(minWidth: 44)

                    StepperButton(icon: "plus", disabled: minLength >= 15) {
                        if minLength < 15 { minLength += 1 }
                    }
                }
                .sensoryFeedback(.selection, trigger: minLength)
            }
            .padding(.horizontal, 14)
        }
        .padding(.vertical, 9)
        .background(Color.steelSurface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.steelBorder.opacity(0.5))
                .frame(height: 0.5)
        }
    }
}

struct SteelChip: View {
    let title: String
    let isActive: Bool
    let activeColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isActive ? activeColor : Color.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isActive ? activeColor.opacity(0.14) : Color.steelCard)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            isActive ? activeColor.opacity(0.45) : Color.steelBorder,
                            lineWidth: 0.5
                        )
                )
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: isActive)
        .animation(.easeInOut(duration: 0.15), value: isActive)
    }
}

struct StepperButton: View {
    let icon: String
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
                .frame(width: 22, height: 22)
                .background(disabled ? Color.clear : Color.steelCard)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(
                            disabled ? Color.steelBorder.opacity(0.3) : Color.steelBorder,
                            lineWidth: 0.5
                        )
                )
                .foregroundStyle(disabled ? Color.textMuted : Color.textSecondary)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
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
    @State private var minLength: Int = 5
    @State private var deepSearchEnabled = false
    @State private var hasSearched = false

    @State private var loadingLeftovers: Set<String> = []
    @State private var leftoverCache: [String: [String]] = [:]
    @State private var allWordsCache: [String] = []
    @State private var liveSearchWorkItem: DispatchWorkItem?

    @State private var showingHelp = false
    @State private var definitionTerm: String?
    @State private var scrollToTopTrigger = false
    @State private var collapsedSections: Set<Int> = []

    private struct LeftoverPresentation: Identifiable {
        let id = UUID()
        let title: String
        let words: [String]
    }
    @State private var leftoverSheetItem: LeftoverPresentation?
    private let maxLetters = 25

    private let resultsCap = 500000 // vediamo se usarlo
    @State private var resultsWereCapped = false

    private let deepSearchQueue: OperationQueue = {  /// Deep Search Engine
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 4
        queue.qualityOfService = .userInitiated
        return queue
    }()
    
// ─────────────────────────────────────────────
// MARK: - Deep Search Tuning (Performance / Memory)
// ─────────────────────────────────────────────
//
// Questi parametri controllano il bilanciamento tra:
// - velocità
// - consumo di memoria
// - completezza dei risultati
//
// 🔹 maxDeepSearchTasks
// Numero massimo di "leftover" (sotto-anagrammi) analizzati per ogni ricerca.
//
// Effetti:
// - ↑ valore → più risultati ma più CPU/RAM e maggiore latenza
// - ↓ valore → app più veloce e stabile ma risultati meno completi
//
// Nota:
// I leftover vengono ordinati per lunghezza (più corti prima),
// quindi anche valori moderati producono risultati utili rapidamente.
//
// Valori tipici:
// - 50–80   → veloce e sicuro (device vecchi)
// - 80–150  → bilanciato (consigliato)
// - 200+    → più completo ma più pesante
//
//
// 🔹 maxCacheSize
// Numero massimo di risultati di deep search mantenuti in memoria.
//
// Struttura cache:
// [leftover: [parole]]
//
// Effetti:
// - ↑ valore → meno ricalcoli, UI più fluida, ma più RAM
// - ↓ valore → meno memoria, ma più query ripetute (piccoli lag)
//
// Valori tipici:
// - 100–300 → memoria contenuta
// - 300–600 → bilanciato (consigliato)
// - 1000+   → performance migliori ma rischio memory pressure
//
//
// ⚠️ Interazione tra i due:
// Più maxDeepSearchTasks aumenta → più la cache cresce → serve più maxCacheSize
//
// Esempi:
// - Fast & Safe → tasks: 80 / cache: 300
// - Balanced   → tasks: 120 / cache: 500
// - Power user → tasks: 250 / cache: 1000
//
//
// 🛑 Sicurezza:
// - Le operazioni sono limitate con OperationQueue (maxConcurrentOperationCount)
// - Le ricerche vengono cancellate quando cambia input
// - La cache è limitata per evitare crescita incontrollata
//
// 🎯 Obiettivo:
// evitare crash per memoria mantenendo una UX fluida e progressiva
//

    private let maxDeepSearchTasks = 120
    private let maxCacheSize = 500
    
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
                maxLengthText: results.isEmpty ? nil : String(results.max(by: { $0.word.count < $1.word.count })?.word.count ?? 0),
                averageText: results.isEmpty ? nil : String(format: "%.1f", Double(results.reduce(0) { $0 + $1.word.count }) / Double(results.count)),
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

                    ScrollViewReader { proxy in
                        List {
                            ForEach(groupedResults, id: \.count) { section in
                                Section(
                                    header:
                                        HStack {
                                            HStack(spacing: 6) {
                                                Text("\(section.count) Lettere")
                                                    .font(.system(size: 15, weight: .semibold))  // no design: .monospaced

                                                Text("(\(section.items.count))")
                                                    .font(.system(size: 12, weight: .medium))
                                                    .foregroundStyle(Color.textSecondary)
                                            }
                                            
                                            Spacer()

                                            Image(systemName: collapsedSections.contains(section.count) ? "chevron.down" : "chevron.up")
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundStyle(Color.textMuted)
                                                .animation(.easeInOut(duration: 0.2), value: collapsedSections)
                                        }
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            withAnimation(.easeInOut(duration: 0.25)) {
                                                if collapsedSections.contains(section.count) {
                                                    collapsedSections.remove(section.count)
                                                } else {
                                                    collapsedSections.insert(section.count)
                                                }
                                            }
                                        }
                                ) {
                                    ForEach(
                                        collapsedSections.contains(section.count) ? [] : section.items
                                    ) { result in
                                        ResultRow(
                                            result: result,
                                            deepSearchEnabled: deepSearchEnabled,
                                            leftoverCache: leftoverCache,
                                            loadingLeftovers: loadingLeftovers,
                                            onLoadLeftover: loadLeftover,
                                            onShowSheet: { title, matches in
                                                leftoverSheetItem = LeftoverPresentation(title: title, words: matches)
                                            },
                                            onWordTapped: { word in
                                                definitionTerm = word
                                            }
                                        )
                                        .id(result.id)
                                        .listRowBackground(Color.steelCard)
                                    }
                                }
                            }
                        }
                        .listStyle(.insetGrouped)
                        .scrollContentBackground(.hidden)
                        .background(Color.steelBase)
                        .onChange(of: scrollToTopTrigger) { _, _ in
                            if let topSection = groupedResults.first?.count {
                                collapsedSections.remove(topSection)
                            }
                            if let firstItem = groupedResults.first?.items.first {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    proxy.scrollTo(firstItem.id, anchor: .top)
                                }
                            }
                        }
//                        .onChange(of: scrollToTopTrigger) { _, _ in
//                            if let firstItem = groupedResults.first?.items.first {
//                                withAnimation(.easeInOut(duration: 0.3)) {
//                                    proxy.scrollTo(firstItem.id, anchor: .top)
//                                }
//                            }
//                        }
                    }
                }
            }
        }
        .background(Color.steelBase)
        .safeAreaInset(edge: .top) {
            Color.steelBase.frame(height: 0)
                .background(Color.steelBase.ignoresSafeArea(edges: .top))
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
        .onChange(of: minLength) { _, _ in leftoverCache = [:]; performSearch() }
        .onChange(of: searchText) { _, newValue in handleSearchTextChange(newValue) }
        // Cancella deep search quando cambia contesto
        .onChange(of: deepSearchEnabled) { _, newValue in
            if newValue {
                triggerDeepSearch()
            } else {
                deepSearchQueue.cancelAllOperations()
                loadingLeftovers.removeAll()
            }
        }
    }

    // ─── Logic ───────────────────────────────────

    private func performSearch() {
        // Cancella deep search quando cambia contesto
        deepSearchQueue.cancelAllOperations()
        loadingLeftovers.removeAll()
        
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
            // EARLY STOP
            if output.count >= resultsCap {
                resultsWereCapped = true
                break
            }
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

        results = output

        let allSections = Set(output.map { $0.usedLetterCount })
        if let topSection = allSections.max() {
            collapsedSections = allSections.subtracting([topSection])
        } else {
            collapsedSections = []
        }
        hasSearched = true
        if deepSearchEnabled { triggerDeepSearch() }
        }

    private func triggerDeepSearch() {
        deepSearchQueue.cancelAllOperations()  /// Cancella eventuali operazioni vecchie

        let uniqueLeftovers = Array(Set(    /// Deduplica leftover
            results
                .map { $0.leftover }
                .filter { $0.count >= 2 }
        ))

        let prioritized = uniqueLeftovers    /// Priorità: leftover più corti prima
            .sorted { $0.count < $1.count }
            .prefix(maxDeepSearchTasks)

        for leftover in prioritized {
            loadLeftover(leftover)
        }
    }
    
    private func loadLeftover(_ leftover: String) {
        guard leftover.count >= 2,
              leftoverCache[leftover] == nil,
              !loadingLeftovers.contains(leftover) else { return }

        loadingLeftovers.insert(leftover)
        let currentMinLength = minLength

        deepSearchQueue.addOperation {

            // Se l'operazione è stata cancellata → esci subito
            if self.deepSearchQueue.isSuspended { return }

            let matches = WordDatabase.shared.exactMatches(
                using: leftover,
                minLength: currentMinLength
            )

            if self.deepSearchQueue.operations.contains(where: { $0.isCancelled }) {
                return
            }

            OperationQueue.main.addOperation {
                // Se nel frattempo è cambiata la ricerca → ignora
                guard self.loadingLeftovers.contains(leftover) else { return }

                self.loadingLeftovers.remove(leftover)

                // Limita la cache (evita crescita infinita)
                if self.leftoverCache.count > self.maxCacheSize {
                    self.leftoverCache.removeAll()
                }

                self.leftoverCache[leftover] = matches
            }
        }
    }

    private func loadInitialData() {
        DispatchQueue.global(qos: .userInitiated).async {
            let words = WordDatabase.shared.allWords(minLength: 4)
            DispatchQueue.main.async { self.allWordsCache = words }
        }
    }

    private func handleSearchTextChange(_ newValue: String) {
        // Cancella deep search quando cambia contesto
        deepSearchQueue.cancelAllOperations()
        loadingLeftovers.removeAll()
 
        let cleaned = newValue.uppercased().filter { $0.isLetter || $0 == " " }
        let letterCount = cleaned.filter { $0.isLetter }.count

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
                    result.append(char)
                }
            }
            searchText = result
            return
        }

        if cleaned != newValue { searchText = cleaned }

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
                    .foregroundStyle(Color.textPrimary)
            }
            .buttonStyle(.plain)

            Spacer()

            if !result.isFullMatch && !result.leftover.isEmpty {
                let matches = leftoverCache[result.leftover]
                let hasMatches = !(matches?.isEmpty ?? true)
                let isPurple = deepSearchEnabled && hasMatches

                Text("+")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Color.textMuted)

                Button {
                    guard isPurple, let matches, !matches.isEmpty else { return }
                    onShowSheet(result.leftover, matches)
                } label: {
                    HStack(spacing: 4) {
                        Text(result.leftover)
                            .font(.system(.caption, design: .monospaced))
                        if deepSearchEnabled && loadingLeftovers.contains(result.leftover) {
                            ProgressView().scaleEffect(0.6)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(isPurple ? Color.accentViolet.opacity(0.15) : Color.steelBase)
                    .foregroundStyle(isPurple ? Color.accentViolet : Color.textSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(
                                isPurple ? Color.accentViolet.opacity(0.4) : Color.steelBorder,
                                lineWidth: 0.5
                            )
                    )
                }
                .buttonStyle(.plain)
                .onAppear { if deepSearchEnabled { onLoadLeftover(result.leftover) } }
            }

            if result.isFullMatch {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentGold)
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
                        .foregroundStyle(Color.textPrimary)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.steelCard)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.steelBase)
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
                .foregroundStyle(Color.textMuted)
                .padding(.bottom, 8)
            Text(searchText.isEmpty
                 ? "Inserisci le lettere da anagrammare\n(minimo \(minLength))"
                 : "Nessun risultato")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.steelBase)
    }
}

#Preview {
    ContentView()
}

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
            
            // --- HEADER & CONTROLS ---
            VStack(spacing: 14) {
                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    
                    TextField("Scrivi qui...", text: $searchText)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled(true)
                        .submitLabel(.search)
                        .onSubmit { performSearch() }
                    
                    // Gruppo di bottoni uniformi
                    HStack(spacing: 12) {  // Spaziatura uniforme tra i bottoni
                        // Bottone 1: Cerca / Cancella
                        if !searchText.isEmpty {
                            Button {
                                if !searchAsYouType && !hasSearched {
                                    performSearch()
                                } else {
                                    searchText = ""
                                    results = []
                                    hasSearched = false
                                }
                            } label: {
                                Image(systemName: (!searchAsYouType && !hasSearched) ? "arrow.right.circle.fill" : "xmark.circle.fill")
                                    .font(.system(size: 22))  // Dimensione fissa uniforme
                                    .foregroundStyle((!searchAsYouType && !hasSearched) ? .orange : .secondary)
                                    .symbolRenderingMode(.hierarchical)
                            }
                        }
                        
                        // Bottone 2: Scroll to Top (solo se ci sono risultati)
                        if !results.isEmpty {
                            Button(action: {
                                scrollToTopTrigger.toggle()
                            }) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 22))  // Stessa dimensione
                                    .foregroundStyle(.secondary)
                                    .symbolRenderingMode(.hierarchical)
                            }
                        }
                        
                        // Bottone 3: Help
                        Button(action: { showingHelp = true }) {
                            Image(systemName: "questionmark.circle.fill")
                                .font(.system(size: 22))  // Stessa dimensione
                                .foregroundStyle(.blue)
                                .symbolRenderingMode(.hierarchical)
                        }
                    }
                    .buttonStyle(.plain)  // Rimuove l'effetto di default
                }
                .padding(10)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
            }
            .background(.ultraThinMaterial)
            
            // parametri di ricerca
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ControlCapsule(title: "Solo 100%", icon: "target", isActive: fullMatchesOnly, activeColor: .green) {
                        fullMatchesOnly.toggle()
                    }
                    
                    ControlCapsule(title: "Ricerca Live", icon: "bolt.fill", isActive: searchAsYouType, activeColor: .blue) {
                        searchAsYouType.toggle()
                    }
                    
                    ControlCapsule(title: "Avanzata", icon: "arrow.triangle.branch", isActive: deepSearchEnabled, activeColor: .purple) {
                        deepSearchEnabled.toggle()
                    }
                    
                    MinLengthControl(minLength: $minLength)
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            
            // --- LIST ---
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
                                        onWordTapped: { word in
                                            definitionTerm = word
                                        }
                                    )
                                    .id(result.id)  // assegna ID per scroll to top
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .onChange(of: scrollToTopTrigger) { _, _ in
                        if let firstSection = groupedResults.first,
                           let firstItem = firstSection.items.first {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo(firstItem.id, anchor: .top)
                            }
                        }
                    }
                }
            }
            
            // --- FOOTER STATS ---
            if !results.isEmpty {
                StatsBar(results: results)
            }
        }
        .sheet(item: $leftoverSheetItem) { item in
            LeftoverSheet(title: item.title, words: item.words)
        }
        .fullScreenCover(isPresented: $showingHelp) {
            HelpView()
        }
        .fullScreenCover(isPresented: Binding<Bool>(
            get: { definitionTerm != nil },
            set: { newValue in if !newValue { definitionTerm = nil } }
        )) {
            if let term = definitionTerm {
                DictionaryDefinitionView(term: term)
            }
        }
        .onAppear { loadInitialData() }
        .onChange(of: fullMatchesOnly) { _, _ in performSearch() }
        .onChange(of: minLength) { _, _ in performSearch() }
        .onChange(of: deepSearchEnabled) { _, newValue in
            if newValue { triggerDeepSearch() }
        }
        .onChange(of: searchText) { _, newValue in
            handleSearchTextChange(newValue)
        }
    }

    // ─── Logic ───

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
            let wordLetters = Array(word)
            var tempCounts = inputCounts
            var canMake = true
            for char in wordLetters {
                if let count = tempCounts[char], count > 0 { tempCounts[char]! -= 1 } else { canMake = false; break }
            }

            if canMake {
                let leftover = tempCounts.flatMap { Array(repeating: $0.key, count: $0.value) }
                    .sorted()
                    .map(String.init)
                    .joined()
                let isFull = leftover.isEmpty && word.count == input.count
                if fullMatchesOnly && !isFull { continue }

                output.append(MatchResult(word: word, isFullMatch: isFull, leftover: leftover, usedLetterCount: word.count))
            }
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
        guard leftover.count >= 2, leftoverCache[leftover] == nil, !loadingLeftovers.contains(leftover) else { return }
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
        } else { hasSearched = false }
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
            Button {
                onWordTapped(result.word)
            } label: {
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
                Text("+")
                    .font(.system(.caption2, design: .monospaced))

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
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
            }
        }
    }
}

struct ControlCapsule: View {
    let title: String
    let icon: String
    let isActive: Bool
    let activeColor: Color
    let action: () -> Void
    
    private var inactiveBackground: Color {
        Color.primary.opacity(0.06)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 14, weight: .bold))
                
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background {
                if isActive {
                    activeColor.opacity(0.12)
                } else {
                    inactiveBackground
                }
            }
            .foregroundStyle(isActive ? activeColor : .primary.opacity(0.7))
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(
                        isActive ? activeColor.opacity(0.5) : .primary.opacity(0.1),
                        lineWidth: 1.5
                    )
            }
            .shadow(color: isActive ? activeColor.opacity(0.2) : .clear, radius: 4, x: 0, y: 2)
        }
        .buttonStyle(ScaledButtonStyle())
        .sensoryFeedback(.impact(weight: .light), trigger: isActive)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isActive)
    }
}

struct ScaledButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
    }
}

struct StepperButton: View {
    let icon: String; let enabled: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.footnote.weight(.semibold))
                .frame(width: 24, height: 24)
                .background(Color(.systemGray5))
                .foregroundStyle(enabled ? Color.primary : Color.secondary)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

struct StatsBar: View {
    let results: [MatchResult]
    
    var averageLength: Double {
        guard !results.isEmpty else { return 0 }
        let total = results.reduce(0) { $0 + $1.word.count }
        return Double(total) / Double(results.count)
    }

    var body: some View {
        let content = HStack(alignment: .center) {
            StatItem(
                value: "\(results.count)",
                label: "Trovate"
            )
            
            Spacer()
            Divider().frame(height: 20).opacity(0.5)
            Spacer()

            let maxLen = results.max(by: { $0.word.count < $1.word.count })?.word.count ?? 0
            StatItem(
                value: "\(maxLen)",
                label: "Lun. Max"
            )

            if !results.isEmpty {
                Spacer()
                Divider().frame(height: 20).opacity(0.5)
                Spacer()

                StatItem(
                    value: String(format: "%.1f", averageLength),
                    label: "Media"
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)

        return content
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
    }
}

struct StatItem: View {
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.body, design: .monospaced).bold())
                .foregroundStyle(.primary)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
        }
    }
}

struct LeftoverSheet: View {
    let title: String; let words: [String]
    @State private var selectedTerm: String?
    @State private var showNoDefinitionAlert = false
    @State private var lastMissingTerm: String = ""

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
            .navigationTitle("Match per: \(title)")
            .navigationBarTitleDisplayMode(.inline)
        }
        .fullScreenCover(isPresented: Binding<Bool>(
            get: { selectedTerm != nil },
            set: { newValue in if !newValue { selectedTerm = nil } }
        )) {
            if let term = selectedTerm {
                DictionaryDefinitionView(term: term)
            }
        }
//        .alert("Nessuna definizione trovata", isPresented: $showNoDefinitionAlert, actions: {
//            Button("Cerca sul web") {
//                let query = lastMissingTerm.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? lastMissingTerm
//                if let url = URL(string: "https://www.google.com/search?q=\(query)") {
//                    UIApplication.shared.open(url)
//                }
//            }
//            Button("OK", role: .cancel) { }
//        }, message: {
//            Text("\"\(lastMissingTerm)\" non è presente nel dizionario.")
//        })
    }
}

struct EmptyStateView: View {
    let searchText: String; let minLength: Int
    var body: some View {
        VStack {
            Spacer()
            Image(systemName: searchText.isEmpty ? "text.magnifyingglass" : "questionmark.circle")
                .font(.system(size: 50)).foregroundStyle(.quaternary).padding(.bottom, 8)
            Text(searchText.isEmpty ? "Inserisci le lettere da anagrammare\n(minimo \(minLength))" : "Nessun risultato")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
    }
}

struct MinLengthControl: View {
    @Binding var minLength: Int

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "textformat.size")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 14, weight: .bold))

            Text("Lunghezza Min.")
                .font(.system(size: 14, weight: .bold, design: .rounded))

            Text("\(minLength)")
                .font(.subheadline.monospacedDigit().weight(.medium))
                .padding(.leading, 2)

            Stepper("", value: $minLength, in: 3...15)
                .labelsHidden()
                .controlSize(.mini)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 3)
        .background(Color.primary.opacity(0.06))
        .foregroundStyle(.primary.opacity(0.7))
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1.5)
        }
        .shadow(color: .clear, radius: 4, x: 0, y: 2)
    }
}

#Preview {
    ContentView()
}

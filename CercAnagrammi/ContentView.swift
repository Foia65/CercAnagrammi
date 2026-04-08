import SwiftUI
import SQLite3

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

    @State private var showingLeftoverSheet: Bool = false
    @State private var currentLeftoverTitle: String = ""
    @State private var currentLeftoverResults: [String] = []
    
    @State private var loadingLeftovers: Set<String> = []
    @State private var leftoverCache: [String: [String]] = [:]
    @State private var allWordsCache: [String] = []
    @State private var liveSearchWorkItem: DispatchWorkItem?

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
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Scrivi qui...", text: $searchText)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled(true)
                        .submitLabel(.search)
                        .onSubmit { performSearch() }
                    
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
                                .foregroundStyle((!searchAsYouType && !hasSearched) ? .orange : .secondary)
                        }
                    }
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
                    
                    // Modernized Stepper Capsule
                    HStack(spacing: 8) {
                        Image(systemName: "textformat.size")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        
                        Text("\(minLength)")
                            .font(.subheadline.monospacedDigit().weight(.medium))
                        
                        Stepper("", value: $minLength, in: 3...15)
                            .labelsHidden()
                            .controlSize(.small) // Native small size fits better
                    }
                    .padding(.leading, 12)
                    .padding(.trailing, 4)
                    .padding(.vertical, 6)
                    .background(Color(.secondarySystemFill))
                    .clipShape(Capsule())
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            
            // Divider()
            
            // --- LIST ---
            if results.isEmpty {
                EmptyStateView(searchText: searchText, minLength: minLength)
            } else {
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
                                        currentLeftoverTitle = title
                                        currentLeftoverResults = matches
                                        showingLeftoverSheet = true
                                    }
                                )
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            
            // --- FOOTER STATS ---
            if !results.isEmpty {
                StatsBar(results: results)
            }
        }
        .sheet(isPresented: $showingLeftoverSheet) {
            LeftoverSheet(title: currentLeftoverTitle, words: currentLeftoverResults)
        }
        .onAppear { loadInitialData() }
        .onChange(of: fullMatchesOnly) { performSearch() }
        .onChange(of: minLength) { performSearch() }
        //        .onChange(of: deepSearchEnabled) { if $0 { triggerDeepSearch() } }
        //        .onChange(of: searchText) { handleSearchTextChange($0) }
        .onChange(of: deepSearchEnabled) { oldValue, newValue in
            if newValue { triggerDeepSearch() }
        }
        .onChange(of: searchText) { oldValue, newValue in
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

    var body: some View {
        HStack(spacing: 8) {
            Text(result.word).font(.system(.subheadline, design: .monospaced))
            Spacer()

            if !result.isFullMatch && !result.leftover.isEmpty {
                let matches = leftoverCache[result.leftover]
                let hasMatches = !(matches?.isEmpty ?? true)
                let isPurple = deepSearchEnabled && hasMatches
                Text("+")
                    .font(.system(.caption2, design: .monospaced))

                Button {
                    if isPurple { onShowSheet(result.leftover, matches ?? []) }
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
    
    // Custom "Off" color that looks better than standard grey
    private var inactiveBackground: Color {
        Color.primary.opacity(0.06)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .symbolRenderingMode(.hierarchical) // Adds depth to icons
                    .font(.system(size: 14, weight: .bold))
                
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded)) // Rounded feels more modern
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
                // The "Pro" touch: A thin, vibrant border when active
                Capsule()
                    .strokeBorder(
                        isActive ? activeColor.opacity(0.5) : .primary.opacity(0.1),
                        lineWidth: 1.5
                    )
            }
            // Subtle shadow only when active to simulate a "pressed" or "raised" look
            .shadow(color: isActive ? activeColor.opacity(0.2) : .clear, radius: 4, x: 0, y: 2)
        }
        .buttonStyle(ScaledButtonStyle()) // Custom style for haptic press effect
        .sensoryFeedback(.impact(weight: .light), trigger: isActive)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isActive)
    }
}

// Custom ButtonStyle to give that "Apple App Store" press effect
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
    
    // Calcolo della lunghezza media
    var averageLength: Double {
        guard !results.isEmpty else { return 0 }
        let total = results.reduce(0) { $0 + $1.word.count }
        return Double(total) / Double(results.count)
    }

    var body: some View {
        HStack(alignment: .center) {
            // Sezione: Risultati Trovati
            StatItem(
                value: "\(results.count)",
                label: "Trovate"
            )
            
            Spacer()
            Divider().frame(height: 20).opacity(0.5)
            Spacer()

            // Sezione: Lunghezza Massima
            let maxLen = results.max(by: { $0.word.count < $1.word.count })?.word.count ?? 0
            StatItem(
                value: "\(maxLen)",
                label: "Lun. Max"
            )

            if !results.isEmpty {
                Spacer()
                Divider().frame(height: 20).opacity(0.5)
                Spacer()

                // Sezione: Lunghezza Media
                StatItem(
                    value: String(format: "%.1f", averageLength),
                    label: "Media"
                )
            }
            
            Spacer()
            
            // Pulsante Help
            Button {
                // Azione per aprire l'help (es. sheet o navigation)
                print("Open Help")
            } label: {
                Image(systemName: "questionmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 28))
                    .foregroundStyle(.blue) // Colore d'accento Apple standard
            }
            .padding(.trailing, 8)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial) // Più professionale del grigio solido
        .clipShape(RoundedRectangle(cornerRadius: 12)) // Se la vuoi flottante
        // .background(Color(.secondarySystemBackground)) // Opzione alternativa solida
    }
}

// Sotto-componente per STATS
struct StatItem: View {
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.body, design: .monospaced).bold())
                .foregroundStyle(.primary)
            Text(label.uppercased()) // Uppercase leggero per un look più "Dashboard"
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
        }
    }
}

struct LeftoverSheet: View {
    let title: String; let words: [String]
    var body: some View {
        NavigationStack {
            List(words, id: \.self) { Text($0).font(.system(.body, design: .monospaced)) }
                .navigationTitle("Match per: \(title)")
                .navigationBarTitleDisplayMode(.inline)
        }
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

#Preview {
    ContentView()
}

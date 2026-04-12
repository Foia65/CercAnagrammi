import SwiftUI

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    headerSection

                    Image("Dark iPad")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, alignment: .init(horizontal: .center, vertical: .center))

                    definitionSection

                    imagePlaceholder(title: "Come funziona", subtitle: "Placeholder per una schermata dell’interfaccia principale.")

                    featuresSection

                    imagePlaceholder(title: "Esempio di risultati", subtitle: "Placeholder per una schermata con i risultati della ricerca.")

                    howToSection
                }
                .padding(20)
            }
            .background(Color.steelBase.ignoresSafeArea())
            .navigationTitle("Help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button {
                                    dismiss()
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 22, weight: .regular, design: .default))
                                                    .foregroundStyle(.primary)
                                                   // .frame(width: 35, height: 35)
                                                   // .background(Color(.secondarySystemBackground))
                                                    .clipShape(Circle())
                                }
                                .accessibilityLabel("Chiudi")
                            }
                        }
                        .background(.ultraThinMaterial)
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Cosa sono gli anagrammi")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Color.textPrimary)

            Text("Un anagramma è una parola o una frase ottenuta riorganizzando le lettere di un’altra parola o frase, usando le stesse lettere nello stesso numero. In pratica, le lettere restano le stesse, ma cambiano ordine e significato.")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("CercAnagrammi ti aiuta a trovare rapidamente parole compatibili con le lettere che inserisci, mostrando sia corrispondenze complete sia risultati parziali, così puoi esplorare combinazioni utili in modo semplice e veloce.")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var definitionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Come funziona l’app")

            Text("L’app confronta le lettere che scrivi con un archivio locale di **oltre 730.000 parole** e individua quelle che possono essere formate con le stesse lettere. Quando una parola usa tutte le lettere inserite, viene evidenziata come match completo. Quando restano lettere inutilizzate, l’app mostra il residuo per aiutarti a scoprire ulteriori possibilità.")
                .foregroundStyle(Color.textSecondary)
                .font(.system(size: 15))
                .fixedSize(horizontal: false, vertical: true)

            Text("Questo approccio è ideale per giochi di parole, esercizi linguistici, brainstorming creativo o semplicemente per esplorare nuove combinazioni lessicali.")
                .foregroundStyle(Color.textSecondary)
                .font(.system(size: 15))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Funzionalità")

            featureItem(
                title: "Ricerca di parole",
                text: "Inserisci un gruppo di lettere e avvia la ricerca per ottenere tutte le parole compatibili con il dizionario interno dell’app."
            )

            featureItem(
                title: "Solo 100%",
                text: "Filtra i risultati mostrando solo gli anagrammi completi, cioè le parole che usano tutte le lettere inserite senza avanzare nulla."
            )

            featureItem(
                title: "Live",
                text: "Abilita la ricerca in tempo reale per aggiornare i risultati mentre scrivi, senza dover premere manualmente il pulsante cerca."
            )

            featureItem(
                title: "Avanzata",
                text: "Attiva l’analisi approfondita dei residui per cercare ulteriori parole a partire dalle lettere non utilizzate."
            )

            featureItem(
                title: "Lunghezza minima",
                text: "Regola la lunghezza minima delle parole trovate per restringere o ampliare il set dei risultati."
            )

            featureItem(
                title: "Dettaglio residui",
                text: "Ogni risultato può mostrare le lettere rimaste, così puoi capire subito quanto il match sia completo e quali lettere restano disponibili."
            )

            featureItem(
                title: "Approfondimento parole",
                text: "Toccando una parola puoi aprire la sua definizione, utile per verificare il significato o scegliere il termine più adatto."
            )

            featureItem(
                title: "Prestazioni e stabilità",
                text: "L’app è pensata per restare fluida anche con ricerche complesse: la modalità Live aggiorna i risultati in modo dinamico, ma può essere disattivata se preferisci cercare manualmente. La lunghezza minima aiuta a ridurre il numero di parole analizzate, mentre il limite massimo preimpostato dei risultati evita carichi eccessivi. Questo approccio migliora la reattività e riduce il rischio di rallentamenti quando l’insieme dei risultati è molto ampio."
            )
        }
    }

    private var howToSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("HowTo")

            howToItem(number: "1", text: "Scrivi nel campo di ricerca le lettere da analizzare.")
            howToItem(number: "2", text: "Premi il pulsante di ricerca oppure attiva l'opzione \"Live\" per cercare automaticamente mentre digiti.")
            howToItem(number: "3", text: "Usa l'opzione \"Solo 100%\" se vuoi vedere solo gli anagrammi completi.")
            howToItem(number: "4", text: "Regola il parametro \"Min\" per cambiare la lunghezza minima delle parole trovate.")
            howToItem(number: "5", text: "Attiva \"Avanzata\" per esplorare i residui e trovare ulteriori parole collegate.")
            howToItem(number: "6", text: "Tocca una parola per visualizzarne la definizione.")
            howToItem(number: "7", text: "Se la ricerca produce troppi risultati, alza la lunghezza minima.")
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 20, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.textPrimary)
    }

    private func featureItem(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.accentBlue)

            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func howToItem(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.accentGold)
                .frame(width: 22, height: 22)
                .background(Color.steelCard)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.steelBorder, lineWidth: 0.5)
                )

            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func imagePlaceholder(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.textPrimary)

            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.steelCard.opacity(0.9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.steelBorder, style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                    )

                VStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 28, weight: .regular))
                        .foregroundStyle(Color.textMuted)

                    Text("Placeholder immagine")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.textSecondary)

                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.textMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
                .padding(.vertical, 26)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 180)
        }
    }
}

#Preview {
    HelpView()
}


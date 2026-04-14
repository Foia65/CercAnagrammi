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
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 20))

                    definitionSection
                    
                    helpImage("comandi")
                                        
                    featuresSection
                    
                    howToSection
                    
                    supportSection
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

            Text("CercAnagrammi fa ciò che dice il suo nome: **aiuta nella ricerca** di parole compatibili con le lettere inserite, mostrando sia corrispondenze complete sia risultati parziali. In questo modo **è possibile esplorare** combinazioni utili in modo semplice e veloce.")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var definitionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Come funziona")

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
            sectionTitle("Parametri di ricerca")
            // 1️⃣2️⃣3️⃣4️⃣5️⃣6️⃣7️⃣8️⃣9️⃣🔟
            featureItem(
                title: "1️⃣ Ricerca di parole",
                text: "Inserisci un gruppo di lettere e avvia la ricerca per ottenere tutte le parole compatibili con il dizionario interno dell’app. Man mano che scrivi, si aggiorna il conto delle lettere inserite"
            )

            featureItem(
                title: "2️⃣ Solo 100%",
                text: "Filtra i risultati mostrando solo gli anagrammi completi, cioè le parole che usano tutte le lettere inserite senza avanzare nulla. Questa è l'impostazione predefinita: disattivala per vedere i risultati parziali."
            )

            featureItem(
                title: "3️⃣ Live",
                text: "Abilita la ricerca in tempo reale per aggiornare i risultati mentre scrivi, senza dover premere manualmente il pulsante cerca. \n**Attenzione:** potrebbe rallentare l'App, soprattutto quando è attiva la \"ricerca avanzata\" (vedi punto 4)"
            )
            
            featureItem(
                title: "4️⃣ Avanzata",
                text: "Attiva l’analisi approfondita, per cercare ulteriori parole a partire dalle lettere non utilizzate."
            )

            featureItem(
                title: "5️⃣ Lunghezza minima",
                text: "Regola la lunghezza minima delle parole trovate per restringere o ampliare il set dei risultati. Impostare valori più alti può migliorare la velocità delle ricerche. Non è comunque possibile scendere sotto le 4 lettere"
            )

            sectionTitle("Risultati")
            .padding(.top, 30)
            
            helpImage("risultati")
            
            featureItem(
                title: "6️⃣ Statistiche",
                text: "Nella parte superiore vengono mostrati: il numero totale di parole trovate, la lunghezza massima e la lunghezza media dei risultati"
            )
            
            featureItem(
                title: "7️⃣ Parole trovate",
                text: "I risultati della ricerca sono raggruppati per lunghezza in ordine decrescente. Per vedere i dettagli, basta espandere un gruppo toccando il suo nome. Toccare di nuovo per comprimere. \nIl gruppo con le parole più lunghe viene presentato già espanso in cima alla lista.\n**BONUS:** Toccare una parola per accedere alla sua definizione (se disponibile nel dizionario interno del device)"
            )

            sectionTitle("Analisi dei risultati")
            .padding(.top, 30)

            helpImage("risultati 2")
            
            featureItem(
                title: "Dettaglio residui",
                text: "Quando non ottieni un match totale, ogni risultato mostra le lettere rimaste. Questo può essere utile per cercare combinazioni di senso compiuto"
            )

            featureItem(
                title: "8️⃣ Ricerca avanzata",
                text: "Se è attiva l'opzione \"Avanzata\" i residui vengono utilizzati per cercare ulteriori combinazioni. Se questa ricerca ha successo, il residuo viene evidenziato. Toccandolo, accedi alla lista delle parole trovate.\nAnche per queste parole è possibile ottenere la loro definizione, se disponibile nel dizionario interno del dispositivo.\n**ATTENZIONE**: anche la ricerca avanzata è guidata dal parametro della lunghezza minima, quindi se la ricerca non dà risultati verifica prima di tutto questa opzione."
            )

            helpImage("risultati 3")
                .padding(.top, 20)
            
            sectionTitle("Prestazioni e stabilità")
                .padding(.top, 40)

            Text("L’app è pensata per rimanere fluida anche con ricerche complesse, tuttavia ci sono alcuni aspetti da tenere in considerazione.\n\nIn particolare: la modalità **Live** aggiorna i risultati in modo dinamico, ma può appesantire  la ricerca se le parole analizzate sono molto lunghe o se l’insieme dei risultati è molto ampio. \nAnche mantenere una lunghezza minima alta aiuta a ridurre il numero di parole analizzate e rendere più veloce il processo. \nInfine, anche la ricerca avanzata può influire notevolmente sulla performance generale. \n\nTenere in mente questi aspetti aiuta a migliora la reattività e riduce il rischio di rallentamenti o di crash")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
    }

    private var howToSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("In sintesi")

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
            
            parseMarkdownText(text)  // ← chiama la funzione helper
                .font(.system(size: 14))
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    private func parseMarkdownText(_ input: String) -> Text {
        let lines = input.components(separatedBy: "\n")
        var components: [Text] = []
        
        for line in lines {
            components.append(parseLineWithBold(line))
        }
        
        return components.enumerated().reduce(Text("")) { result, componentData in
            let (index, component) = componentData
            if index < components.count - 1 {
                return Text("\(result)\(component)\n")
            } else {
                return Text("\(result)\(component)")
            }
        }
    }

    private func parseLineWithBold(_ line: String) -> Text {
        let parts = line.components(separatedBy: "**")
        var components: [Text] = []
        
        for (index, part) in parts.enumerated() {
            let text = Text(part)
            if index % 2 == 0 {
                components.append(text)
            } else {
                components.append(text.bold())
            }
        }
        
        return components.enumerated().reduce(Text("")) { result, componentData in
            let (_, component) = componentData
            return Text("\(result)\(component)")
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
    
    func helpImage(_ name: String) -> some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 2)
            )
    }
    
    private var supportSection: some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.bottom, 20)
            
            HStack(spacing: 14) {
                // Icona cerchiata
                ZStack {
                    Circle()
                        .fill(Color.accentBlue.opacity(0.12))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "questionmark.message")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Color.accentBlue)
                }
                
                VStack(alignment: .leading, spacing: 4) {                    
                    Text("Scrivici per assistenza o feedback")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.textSecondary)
                    
                    Link("info.foiasoft@gmail.com", destination: URL(string: "mailto:info.foiasoft@gmail.com")!)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.accentBlue)
                }
                
                Spacer()
            }
            .padding(16)
            .background(Color.steelCard.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.steelBorder, lineWidth: 0.5)
            )
        }
        .padding(.top, 16)
    }
}

#Preview {
    HelpView()
}

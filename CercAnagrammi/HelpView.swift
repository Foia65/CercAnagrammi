import SwiftUI

struct HelpView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    //                    HelpSection(
                    //                        title: "📝 Come funziona",
                    //                        items: [
                    //                            "Inserisci le lettere nel campo di ricerca",
                    //                            "L'app trova tutti gli anagrammi possibili",
                    //                            "I risultati sono raggruppati per lunghezza"
                    //                        ]
                    //                    )
                    //
                    //                    HelpSection(
                    //                        title: "⚡️ Funzionalità",
                    //                        items: [
                    //                            "Ricerca Live: risultati immediati mentre scrivi",
                    //                            "Solo 100%: mostra solo anagrammi che usano TUTTE le lettere",
                    //                            "Avanzata: trova anagrammi anche con le lettere rimanenti"
                    //                        ]
                    //                    )
                    //
                    //                    HelpSection(
                    //                        title: "💡 Suggerimenti",
                    //                        items: [
                    //                            "Minimo 3 lettere, massimo 15",
                    //                            "Solo lettere dell'alfabeto (no numeri)",
                    //                            "Clicca sulle lettere rimanenti (es. + abc) per approfondire"
                    //                        ]
                    //                    )
                    
                    Spacer(minLength: 100)
                    Text("Non avrai mica bisogno di aiuto")
                    Text("Dai, ce la puoi fare...")
                    
                }
                .padding()
                .frame(maxWidth: .infinity)
            }
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
        .presentationDetents([.medium, .large]) // iOS 16+
        .presentationDragIndicator(.visible)
    }
    
    struct HelpSection: View {
        let title: String
        let items: [String]
        
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(items, id: \.self) { item in
                        Label(item, systemImage: "circle.fill")
                            .font(.subheadline)
                            .labelStyle(.titleOnly)
                    }
                }
                .padding(.leading, 8)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
        }
    }
    
}
#Preview {
    HelpView()
}

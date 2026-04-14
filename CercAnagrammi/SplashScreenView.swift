import SwiftUI

struct SplashScreenView: View {
    
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Binding var isActive: Bool  // Binding per gestire la fine dell'animazione
    @State private var progress: CGFloat = 0.0
    
    var body: some View {
        ZStack {
            
            if horizontalSizeClass == .compact {
                Image("Dark iPhone")
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea(.all)
            }
            
            if horizontalSizeClass == .regular {
                Image("Dark iPad")
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea(.all)
            }
            
            VStack {
                Spacer()
                
                // Finta progress bar
                VStack(spacing: 8) {
                    ZStack(alignment: .leading) {
                        // Sfondo della progress bar (più scuro per contrasto)
                        Rectangle()
                            .frame(width: 200, height: 4)
                            .foregroundColor(.white.opacity(0.2))
                            .cornerRadius(2)
                        
                        // Progresso che si riempie (bianco brillante)
                        Rectangle()
                            .frame(width: 200 * progress, height: 4)
                            .foregroundColor(.white.opacity(0.9))
                            .cornerRadius(2)
                    }
                }
                
                // Versione e build (bianco per sfondo scuro)
                HStack(spacing: 4) {
                    Text("Versione:")
                    Text(Bundle.main.appVersionDisplay)
                    Text("Build:")
                    Text(Bundle.main.appBuild)
                }
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))
                .padding(30)
                .padding(.horizontal)
            }
            
        }
        .onAppear {
            // Anima la progress bar per 3.5 secondi
            withAnimation(.linear(duration: 3.5)) {
                progress = 1.0
            }
            
            // Nasconde lo splash screen dopo 3.5 secondi
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                isActive = false
            }
        }
    }
}

extension Bundle {
    var appVersionDisplay: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }
    
    var appBuild: String {
        infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }
}

#Preview {
    SplashScreenView(isActive: .constant(true))
}

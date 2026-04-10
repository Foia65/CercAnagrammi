import SwiftUI

struct SplashScreenView: View {
    
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Binding var isActive: Bool  // Binding per gestire la fine dell'animazione
    @State private var progress: CGFloat = 0.0
    
    var body: some View {
        ZStack {
            
            if horizontalSizeClass == .compact {
                Image("CercAnagrammi_Splash_iPhone")
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea(.all)
            }
            
            if horizontalSizeClass == .regular {
                Image("CercAnagrammi_Splash_iPad")
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea(.all)
            }
            
            VStack {
                Spacer()
                
                // Finta progress bar
                VStack(spacing: 8) {
                    ZStack(alignment: .leading) {
                        // Sfondo della progress bar
                        Rectangle()
                            .frame(width: 200, height: 4)
                            .foregroundColor(.white.opacity(0.3))
                            .cornerRadius(2)
                        
                        // Progresso che si riempie
                        Rectangle()
                            .frame(width: 200 * progress, height: 4)
                            .foregroundColor(.black.opacity(0.7))
                            .cornerRadius(2)
                    }
                    
                    // Testo percentuale (opzionale)
                    Text("\(Int(progress * 100))%")
                        .font(.caption2)
                        .foregroundColor(.black.opacity(0.6))
                }
                .padding(.bottom, 60)
                
                // Versione e build (come già presente)
                HStack(spacing: 4) {
                    Text("Version:")
                    Text(Bundle.main.appVersionDisplay)
                    Text("Build:")
                    Text(Bundle.main.appBuild)
                }
                .font(.footnote)
                .foregroundStyle(.black)
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

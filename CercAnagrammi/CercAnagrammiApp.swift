import SwiftUI

@main
struct CercAnagrammiApp: App {
    
    @State private var showSplashScreen = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                
                ContentView()
                
                if showSplashScreen {
                    SplashScreenView(isActive: $showSplashScreen)
                        .transition(.opacity)
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}

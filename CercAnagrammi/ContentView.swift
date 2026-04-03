//
//  ContentView.swift
//  CercAnagrammi
//
//  Created by Francesco Foianesi on 02/04/26.
//
//  SwiftUI main view for the app, used as a placeholder UI.
//

import SwiftUI

struct ContentView: View {
    /// The body property defines the view's layout and contents.
    var body: some View {
        VStack {
            // Display a globe icon with a large image scale and tinted foreground.
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            // Display a greeting text.
            Text("Hello, world!")
        }
        .padding() // Add padding around VStack content.
    }
}

#Preview {
    ContentView()
}

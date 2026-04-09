import SwiftUI
import UIKit

public struct DictionaryDefinitionView: UIViewControllerRepresentable {
    public typealias UIViewControllerType = UIReferenceLibraryViewController

    private let term: String

    public init(term: String) {
        self.term = term
    }

    public func makeUIViewController(context: Context) -> UIReferenceLibraryViewController {
        // UIReferenceLibraryViewController ignores terms it can't define and may
        // display blank on first presentation when embedded in a sheet.
        // We rely on fullScreenCover in SwiftUI side to avoid the first-blank issue.
        UIReferenceLibraryViewController(term: term)
    }

    public func updateUIViewController(_ uiViewController: UIReferenceLibraryViewController, context: Context) {
        // UIReferenceLibraryViewController doesn't provide an API to update the term.
        // To change the term, recreate the controller by toggling the presentation.
    }
}

public struct DictionaryDefinitionFullScreenCover: View {
    @Binding var term: String?

    public init(term: Binding<String?>) {
        self._term = term
    }

    public var body: some View {
        let isPresented = Binding<Bool>(
            get: { term != nil },
            set: { newValue in if !newValue { term = nil } }
        )

        return EmptyView()
            .fullScreenCover(isPresented: isPresented) {
                if let value = term {
                    DictionaryDefinitionView(term: value)
                        .edgesIgnoringSafeArea(.all)
                        .overlay(
                            Button(action: { term = nil }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title)
                                    .padding()
                                    .foregroundColor(.white)
                            }
                            .padding(),
                            alignment: .topTrailing
                        )
                }
            }
    }
}

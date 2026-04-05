//import SwiftData
//import Foundation
//
//enum AppContainer {
//    static let shared: ModelContainer = {
//        let storeURL = URL(fileURLWithPath: NSHomeDirectory())
//            .appendingPathComponent("Desktop/CercAnagrammi/CercAnagrammi/Resources/Words.db")
//
//        // 1. Check the file actually exists at that path
//        let exists = FileManager.default.fileExists(atPath: storeURL.path)
//        print("🗂️ DB path: \(storeURL.path)")
//        print("🗂️ DB file exists: \(exists)")
//
//        let config = ModelConfiguration(url: storeURL)
//
//        do {
//            let container = try ModelContainer(for: Word.self, configurations: config)
//
//            // 2. Try fetching a few words immediately to confirm data is readable
//            let context = ModelContext(container)
//            let request = FetchDescriptor<Word>(sortBy: [SortDescriptor(\Word.original)])
//            let words = try context.fetch(request)
//            print("📦 Words in DB: \(words.count)")
//            if let first = words.first {
//                print("📝 First word: \(first.original)")
//            }
//
//            return container
//        } catch {
//            fatalError("❌ Failed to create ModelContainer: \(error)")
//        }
//    }()
//}

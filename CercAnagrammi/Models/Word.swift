//
// Word.swift
//
// Defines the SwiftData model for a word/anagram.
// Represents a validated uppercase word with a unique original string,
// its hash for quick lookup, and its length.
// Used in both Populate CLI and the app target.
//

import Foundation
import SwiftData

/// Represents a word entity used in anagram processing and storage.
/// This model stores the original uppercase word, a unique hash key,
/// its length, and a stable UUID identifier.
@Model
final class Word {

    /// The original validated word string (uppercase A–Z only).
    /// This value is unique in the data store.
    @Attribute(.unique) var original: String

    /// SHA-256 hex digest of the original word.
    /// Used as a searchable key for fast lookups.
    var hash: String

    /// Number of characters in the original word.
    var length: Int

    /// Stable unique identifier for the word entity.
    var id: UUID

    /// Initializes a new Word instance.
    ///
    /// - Parameters:
    ///   - id: A stable UUID identifier (default is a new UUID).
    ///   - original: The original uppercase word string.
    ///   - hash: SHA-256 hex digest of the original word.
    ///   - length: Character count of the original word.
    init(
        id:        UUID   = UUID(),
        original:  String,
        hash:      String,
        length:    Int
    ) {
        self.id        = id
        self.original  = original
        self.hash      = hash
        self.length    = length
    }
}


import Foundation

/// Words the speech model would otherwise get wrong: colleagues' names, product
/// names, internal jargon.
///
/// Every speech backend supports biasing, but no two agree on the shape — Whisper
/// wants a sentence-like `prompt`, Deepgram wants repeated `keywords`, AssemblyAI
/// wants a `word_boost` array, Apple wants `contextualStrings`. This holds the
/// terms once and hands each the form it asks for.
///
/// It is also given to the text model, because biasing only improves the odds.
/// When the transcript still comes back with "e-vulpo", something downstream has
/// to know that "evulpo" was the intended spelling.
struct Vocabulary {
    let terms: [String]

    init(_ raw: [String]) {
        // A trailing blank row in the settings list is normal, and duplicates
        // waste a budget that is genuinely small.
        var seen = Set<String>()
        terms = raw
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0.lowercased()).inserted }
    }

    var isEmpty: Bool { terms.isEmpty }

    /// Whisper's prompt window is about 224 tokens and it silently drops the
    /// overflow, so the cap is applied here where it can be reasoned about
    /// rather than discovered as terms mysteriously not working.
    private static let promptCharacterBudget = 800
    private static let termLimit = 100

    /// For `prompt` fields: OpenAI-compatible transcription, whisper.cpp.
    ///
    /// Comma-separated rather than a sentence. Whisper treats the prompt as
    /// preceding context, and a bare list biases toward the words themselves
    /// instead of toward whatever sentence they were wrapped in.
    var promptText: String {
        var used = 0
        var kept: [String] = []
        for term in terms.prefix(Self.termLimit) {
            let cost = term.count + 2
            guard used + cost <= Self.promptCharacterBudget else { break }
            used += cost
            kept.append(term)
        }
        return kept.joined(separator: ", ")
    }

    /// For APIs taking discrete terms: Deepgram `keywords`, AssemblyAI
    /// `word_boost`, Apple's `contextualStrings`.
    var boostTerms: [String] {
        Array(terms.prefix(Self.termLimit))
    }

    /// A line for the improvement system prompt, or nil when there's nothing to
    /// say. Worded to correct near-misses without licensing the model to sprinkle
    /// these words into text that never contained them.
    var glossaryInstruction: String? {
        guard !isEmpty else { return nil }
        return """
        - These are correct spellings of names and terms the speaker uses: \
        \(promptText). Speech-to-text often mangles them. Where the transcript \
        clearly meant one of these, fix it to the spelling given here. Never \
        introduce one that was not said.
        """
    }
}

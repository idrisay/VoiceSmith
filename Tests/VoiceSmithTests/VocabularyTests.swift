import Testing
@testable import VoiceSmith

/// `Vocabulary` is the one place the per-provider budget is enforced, and every
/// failure mode it has is silent: an over-long prompt is dropped by Whisper
/// without complaint, and a duplicate spends a budget nobody can see. Reading the
/// code cannot tell you it stayed inside the limits — only running it can.
struct VocabularyTests {

    // MARK: - Cleaning the settings list

    @Test func dropsTheBlankRowSettingsLeavesBehind() {
        let vocabulary = Vocabulary(["evulpo", "", "   ", "\n"])
        #expect(vocabulary.terms == ["evulpo"])
    }

    @Test func trimsSurroundingWhitespace() {
        // Pasting a name out of an email brings the spaces with it.
        let vocabulary = Vocabulary(["  evulpo ", "\tAylin\n"])
        #expect(vocabulary.terms == ["evulpo", "Aylin"])
    }

    @Test func dropsDuplicatesRegardlessOfCase() {
        let vocabulary = Vocabulary(["Evulpo", "evulpo", "EVULPO"])
        #expect(vocabulary.terms == ["Evulpo"])
    }

    @Test func keepsTheFirstSpellingOfADuplicate() {
        // The user typed this one deliberately; a later stray casing must not
        // silently replace what they intended the model to write.
        let vocabulary = Vocabulary(["evulpo", "Evulpo"])
        #expect(vocabulary.terms == ["evulpo"])
    }

    @Test func isEmptyOnlyWhenNothingSurvivesCleaning() {
        #expect(Vocabulary([]).isEmpty)
        #expect(Vocabulary(["", "  "]).isEmpty)
        #expect(!Vocabulary(["evulpo"]).isEmpty)
    }

    @Test func preservesTheOrderTermsWereAddedIn() {
        let vocabulary = Vocabulary(["zeta", "alpha", "mu"])
        #expect(vocabulary.terms == ["zeta", "alpha", "mu"])
    }

    // MARK: - The prompt-shaped form

    @Test func promptIsACommaSeparatedList() {
        // Not a sentence: Whisper reads the prompt as preceding context, and a
        // bare list biases toward the words rather than the carrier sentence.
        #expect(Vocabulary(["evulpo", "Aylin"]).promptText == "evulpo, Aylin")
    }

    @Test func promptIsEmptyForAnEmptyVocabulary() {
        #expect(Vocabulary([]).promptText.isEmpty)
    }

    @Test func promptStaysInsideWhispersWindow() {
        // Whisper's prompt window is about 224 tokens and it drops the overflow
        // in silence, so going over does not fail — it just stops working.
        let vocabulary = Vocabulary((1...500).map { "term-number-\($0)" })
        #expect(vocabulary.promptText.count <= 800)
    }

    @Test func promptKeepsTheEarliestTermsWhenItHasToTruncate() {
        let vocabulary = Vocabulary((1...500).map { "term-number-\($0)" })
        #expect(vocabulary.promptText.hasPrefix("term-number-1, term-number-2, "))
        #expect(!vocabulary.promptText.contains("term-number-500"))
    }

    @Test func promptTruncationLeavesNoTrailingSeparator() {
        // A prompt ending in ", " reads as an unfinished list to the model.
        let vocabulary = Vocabulary((1...500).map { "term-number-\($0)" })
        #expect(!vocabulary.promptText.hasSuffix(", "))
        #expect(!vocabulary.promptText.hasSuffix(","))
    }

    @Test func aSingleOverlongTermYieldsAnEmptyPromptRatherThanABlownBudget() {
        let vocabulary = Vocabulary([String(repeating: "x", count: 5_000)])
        #expect(vocabulary.promptText.count <= 800)
    }

    // MARK: - The discrete-terms form

    @Test func boostTermsAreCapped() {
        // Deepgram and AssemblyAI take these one by one; an unbounded list turns
        // into an unbounded URL or request body.
        let vocabulary = Vocabulary((1...500).map { "term\($0)" })
        #expect(vocabulary.boostTerms.count <= 100)
    }

    @Test func boostTermsPassShortListsThroughUntouched() {
        let vocabulary = Vocabulary(["evulpo", "Aylin", "Ikatia"])
        #expect(vocabulary.boostTerms == ["evulpo", "Aylin", "Ikatia"])
    }

    // MARK: - The instruction handed to the text model

    @Test func thereIsNoGlossaryInstructionWithoutTerms() {
        #expect(Vocabulary([]).glossaryInstruction == nil)
        #expect(Vocabulary(["  "]).glossaryInstruction == nil)
    }

    @Test func theGlossaryInstructionCarriesTheTerms() {
        let instruction = Vocabulary(["evulpo", "Aylin"]).glossaryInstruction
        #expect(instruction?.contains("evulpo") == true)
        #expect(instruction?.contains("Aylin") == true)
    }

    @Test func theGlossaryInstructionForbidsInventingTerms() {
        // Without this clause the feature is a licence to hallucinate: the model
        // would be free to sprinkle these words into text that never had them.
        let instruction = Vocabulary(["evulpo"]).glossaryInstruction ?? ""
        #expect(instruction.contains("Never introduce one that was not said"))
    }
}

/// The vocabulary only matters if it reaches the model, and the improvement
/// prompt is assembled by string interpolation — the kind of place where a term
/// goes missing without anything failing.
struct ImprovementPromptTests {
    private var mode: ImprovementMode { ImprovementMode.builtIns[0] }

    @Test func theVocabularyReachesTheImprovementPrompt() {
        let prompt = Prompts.improvement(
            for: mode, language: "en-US", vocabulary: Vocabulary(["evulpo"])
        )
        #expect(prompt.contains("evulpo"))
    }

    @Test func anEmptyVocabularySaysNothingAboutSpellings() {
        // Behaviour for everyone who never opens the vocabulary editor has to be
        // byte-for-byte what it was before the feature existed.
        let withoutVocabulary = Prompts.improvement(
            for: mode, language: "en-US", vocabulary: Vocabulary([])
        )
        #expect(!withoutVocabulary.contains("correct spellings"))
        #expect(withoutVocabulary == Prompts.improvement(for: mode, language: "en-US"))
    }
}

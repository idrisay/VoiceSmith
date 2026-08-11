import Testing
@testable import VoiceSmith

/// `stripReasoning` stands between a reasoning model and whatever the user was
/// typing into. Every way it can be wrong is a paste they didn't ask for: the
/// model's private monologue dropped into a document, or a half-sentence
/// delivered as if it were the finished text. The failures are silent — the
/// response parses perfectly in each case — so only running it can tell you the
/// thinking was actually removed.
struct StripReasoningTests {

    // MARK: - The ordinary case

    @Test func returnsPlainTextUntouched() {
        let text = "Call the dentist tomorrow morning."
        #expect(OpenAICompatibleProvider.stripReasoning(text) == text)
    }

    @Test func dropsEverythingUpToTheClosingTag() {
        let reply = "<think>The user wants this tidied.</think>Call the dentist tomorrow."
        #expect(OpenAICompatibleProvider.stripReasoning(reply) == "Call the dentist tomorrow.")
    }

    @Test func keepsTheAnswerWhenTheThinkingMentionsATag() {
        // The reasoning talks about "</think>" as text. Splitting on the first
        // occurrence is what we want: everything before the real close is
        // reasoning either way.
        let reply = "<think>I should not write </think> literally.</think>Done."
        #expect(OpenAICompatibleProvider.stripReasoning(reply) == " literally.</think>Done.")
    }

    // MARK: - Tag styles beyond <think>

    @Test func recognisesTheOtherTagNamesOllamaBuildsUse() {
        for tag in ["thinking", "reasoning", "thought"] {
            let reply = "<\(tag)>weighing it up</\(tag)>The final text."
            #expect(OpenAICompatibleProvider.stripReasoning(reply) == "The final text.")
        }
    }

    @Test func matchesTagsRegardlessOfCase() {
        let reply = "<THINK>weighing it up</THINK>The final text."
        #expect(OpenAICompatibleProvider.stripReasoning(reply) == "The final text.")
    }

    // MARK: - Truncation

    @Test func yieldsNothingWhenTheBlockWasNeverClosed() {
        // A token limit, a dropped connection or a cancelled request cuts the
        // reply off mid-thought. There is no answer in it — only reasoning — so
        // returning the raw text would paste the monologue into the user's
        // document. Empty makes the caller report a failure instead.
        let reply = "<think>The user wants this tidied up, so I should"
        #expect(OpenAICompatibleProvider.stripReasoning(reply).isEmpty)
    }

    @Test func anUnclosedBlockIsRecognisedThroughLeadingWhitespace() {
        let reply = "\n  <think>still going"
        #expect(OpenAICompatibleProvider.stripReasoning(reply).isEmpty)
    }

    @Test func textThatMerelyMentionsATagIsNotTreatedAsThinking() {
        // Dictation about the tags themselves must survive: the block has to
        // open the reply, not merely appear in it.
        let text = "Remember to strip the <think> block before delivering."
        #expect(OpenAICompatibleProvider.stripReasoning(text) == text)
    }
}

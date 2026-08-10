import Foundation

/// A free, local check for "did this sound like it wanted to become something".
///
/// Classifying every dictation would mean a second model call on all of them,
/// roughly doubling cost for a feature that applies to maybe one in twenty. So
/// a phrase match gates it: no hint, no call, and the dictation behaves exactly
/// as it always has.
///
/// Tuned for precision over recall. A miss costs nothing — the text is already
/// delivered and the user carries on — while a false positive interrupts someone
/// who was only writing a sentence. That is why deceptively common openers like
/// "I need to" are deliberately absent: they appear constantly in ordinary
/// dictation and would fire on prose all day.
///
/// English only. Every added language is a hand-written phrase list that has to
/// be maintained and cannot be verified, so rather than half-covering a few, the
/// gate is honest about its scope: dictate in another language and the offer
/// simply never appears. Everything else — transcription, cleanup, the double-tap
/// to-do capture — is language-neutral and unaffected.
enum ActionHint {
    static func isPresent(in transcript: String) -> Bool {
        let text = transcript.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        return patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }

    /// Word-boundary patterns, run against diacritic-folded lowercase text.
    private static let patterns: [String] = [
        #"\bremind me\b"#,
        #"\bdon'?t forget\b"#,
        #"\bdo not forget\b"#,
        #"\bset (a|an) (reminder|alarm)\b"#,
        #"\badd (a|an) (reminder|event|meeting|appointment)\b"#,
        #"\bschedule (a|an|the)\b"#,
        #"\bbook (a|an|the) (meeting|appointment|room|call|flight|table)\b"#,
        #"\b(put|add) (it |this |that )?(in|on|to) (my |the )?calendar\b"#,
        #"\bmake (an )?appointment\b"#,
        #"\bto-?do list\b"#,
    ]
}

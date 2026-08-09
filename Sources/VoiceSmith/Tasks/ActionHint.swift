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
enum ActionHint {
    static func isPresent(in transcript: String) -> Bool {
        // Dotless ı is a letter in its own right, not an accented i, so
        // diacritic folding leaves it alone — "hatırlat" would never match a
        // stem written with a normal i. Mapped explicitly before folding
        // handles the rest (İ → i, ç → c, ş → s, ğ → g, ö → o, ü → u).
        let text = transcript
            .replacingOccurrences(of: "ı", with: "i")
            .replacingOccurrences(of: "I", with: "i")
            .folding(
                options: [.diacriticInsensitive, .caseInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
        if english.contains(where: { text.range(of: $0, options: .regularExpression) != nil }) {
            return true
        }
        // Turkish is agglutinative: "hatırlat" turns up as hatırlatır, hatırlatsana,
        // hatırlatmayı. Matching the stem anywhere catches the forms a word-boundary
        // pattern would miss, and folding above has already stripped the diacritics
        // that would otherwise make ı and i different characters.
        return turkishStems.contains { text.contains($0) }
    }

    /// Word-boundary patterns, run against diacritic-folded lowercase text.
    private static let english: [String] = [
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

    /// Stems, matched as substrings for the reason above.
    private static let turkishStems: [String] = [
        "hatirlat",     // remind
        "unutma",       // don't forget
        "takvime ekle", // add to calendar
        "toplanti ayarla",
        "randevu al",
        "etkinlik ekle",
        "yapilacak",    // to-do
    ]
}

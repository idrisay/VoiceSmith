# Changelog

Each released version, newest first. The release workflow reads the section
matching the tag and puts it at the top of the GitHub release notes, so the
heading format matters: `## <version>`.

## 1.6.1

**Every way VoiceSmith could fail without telling you.** All of them were quiet
by nature — the app carried on as if nothing had happened — so none would have
been reported as bugs. Nothing here changes how dictation works.

- **Pressing Escape mid-dictation no longer shows an error.** Cancelling a
  request in flight looks like a dropped connection from the inside, so
  stopping a dictation could end with a panel telling you that you were
  offline. You asked it to stop; it stops.
- **A reply cut off at the model's output limit is reported, not delivered.**
  A truncated response is perfectly well-formed and missing its ending, so half
  a sentence used to land in your document as if it were the finished text.
- **Reasoning models can't leak their thinking into your text.** A `<think>`
  block cut off before its closing tag was delivered whole — the model's private
  monologue pasted where your words should be. `<thinking>`, `<reasoning>` and
  `<thought>`, which some Ollama builds use instead, are now recognised too.
- **"Keep audio for 30 days" now means 30 days.** The sweep only ran at launch,
  and this app is built to sit in the menu bar for weeks — so the limit you
  chose quietly became "until you next restart". It now runs after every
  dictation.
- **Dictating over selected text won't paste a duplicate.** Replacing a
  selection exactly as long as what you said left the character count unchanged,
  which read as a failed write, so the text was pasted a second time on top of
  text that was already correct.
- **A key your Keychain refuses to store now says so.** A locked keychain failed
  the save silently and the field said "Stored". You found out at your next
  dictation, as "no API key" — which reads as though you never entered one.
- **A dictation shortcut that can't be serviced is reported as unavailable**
  rather than registered and left doing nothing when pressed.
- **Re-run in History shows you the new text.** The editor kept displaying the
  old version, so Re-run looked like it had done nothing — and your next
  keystroke wrote the stale text back over the improvement you'd asked for.
- **Turning double-tap Shift off stays off across an upgrade.** Upgrading from
  1.4 could switch a trigger you'd deliberately disabled back on.
- **Transcription failures and rewrite failures are told apart.** A network
  problem during the rewrite used to report itself as a transcription failure,
  which sent you looking at the wrong provider.

Whisper.cpp gets three fixes: a malformed argument that made some builds write
a stray text file next to your audio or fail outright, a hang when the binary
logged more than the pipe could hold, and a half-read recording being
transcribed as though it were the whole thing. Clearing the binary path in
Settings now goes back to finding it automatically, rather than looking for a
binary at no path at all.

Delivery no longer freezes the app's own interface, the recording popup
included, for the moment it takes to bring your target app back to the front.
That window was brief and only on the paste fallback, but it was visible.

## 1.6

**VoiceSmith is now MIT licensed.** Use it, change it, ship it, sell it — keep
the copyright notice and there's nothing else owed, no obligation to contribute
anything back, and no warranty.

Until now the repo had no license file, which doesn't mean "help yourself" — it
means the opposite. Default copyright applied, so the source was readable and
nothing more.

The app itself is unchanged from 1.5. If you're already running it, there is
nothing here worth updating for.

## 1.5

**VoiceSmith can now be taught the words it keeps getting wrong.** Colleagues'
names, your product, your team's jargon — add them once in **Settings › General
› Vocabulary** and they stop coming back as whichever real word sounded closest.

- **The words are given to the speech model before it listens**, so it
  recognises them rather than guessing. This works with every speech provider —
  Apple, Whisper.cpp, OpenAI, Groq, Deepgram, AssemblyAI — each of which wants
  the list in a different shape; VoiceSmith sends whichever one applies.
- **The text model gets them too**, and fixes the near-misses that still get
  through: "e-vulpo" becomes "evulpo". It corrects only what was clearly meant,
  and never introduces a term you didn't say.
- Re-improving an old note from history uses the vocabulary as well.
- An empty list changes nothing about how dictation works today.

## 1.4

- The action-detection phrase list is **English only**. The Turkish phrases
  added in 1.3 are gone: a hand-written list per language is something nobody
  can verify or maintain, and half-covering two languages was worse than being
  clear about the scope. Dictating in Turkish still works exactly as it did —
  only the "Sounds like an event" offer is English-gated.
- Dictation, cleanup, and double-tap to-do capture are untouched and remain
  language-neutral.

## 1.3

**VoiceSmith now notices when you've dictated an appointment or something to
do.** Say "remind me to call the dentist tomorrow" or "schedule a team sync
Thursday at three" and the popup offers to file it — in **Calendar** or in
**Reminders**, your choice.

- **Your text is inserted either way.** Detection runs *after* delivery, so it
  can never delay your words or lose them. Ignore the offer and it disappears.
- **Both destinations are always one click away.** "Remind me to book the room"
  and "schedule the room booking" are the same thought, so the guess only
  decides which button is emphasised.
- Once filed, the confirmation offers to open the app it went to.
- Works in English and Turkish. A local phrase match gates it, so ordinary
  dictation costs nothing extra — no phrase, no model call.
- Turn it off in Settings › General, and pick which calendar there too.
- Calendar access is asked for the first time you accept an event.

Notes are not a destination yet: Apple ships no public API for creating them.

### Triggers

- **Both double-tap triggers are yours to choose.** Setup now asks which taps
  you want, and Settings › Shortcut changes them later — `Shift`, `Control`,
  `Option`, `Command`, or off, for dictation and for to-do capture
  independently. `Shift` and `Option` remain the suggestions.
- Each choice carries its own warning where it matters: macOS offers "Press
  Control Twice" for its own Dictation, and JetBrains IDEs claim double-tap
  `Shift`.
- The two triggers can't share a modifier — a tap of either clears the other's
  pending tap, so both on one key would leave neither working.
- Existing settings carry over, including a trigger you had switched off.

## 1.2

**Dictate a to-do straight into Apple Reminders.** Double-tap `Option`, say what
needs doing, double-tap `Option` again. The text model pulls out the action items
and files them — no typing, and nothing pasted into whatever you were working in.

- **Several tasks from one sentence.** "Call the dentist and email Sarah the deck
  by Friday" becomes two reminders, the second dated. Relative dates — tomorrow,
  next Friday, end of the month — are resolved against the day you spoke.
- **Nothing is invented.** Most dictation isn't a to-do list, and when there's no
  action item in what you said, nothing is filed and the popup tells you what it
  heard instead.
- **Undo is right there.** The confirmation lists what was added and clears itself
  after a few seconds; hovering keeps it up. Reminders is the owner after that.
- **Choose the list** in Settings › General, or leave it on your default.
- Optionally file to-dos from *every* dictation — Delivery › Add to-dos to
  Reminders — rather than only from double-tap Option.
- Recording popup shows a **To-do** badge, so the two triggers can't be confused
  while you're still speaking.

Double-tap `Option` rather than Control: macOS offers "Press Control Twice" as a
Dictation shortcut, and two dictation triggers on one chord would collide badly.

Reminders access is requested the first time you use it.

## 1.1

- **Pin the language from the recording popup.** Auto-detection reads the audio
  and gets it wrong on short or accented recordings — usually producing a
  transcript in a language nobody spoke. The badge in the popup (Auto, EN, TR)
  switches it mid-sentence, and applies to the recording in progress.

## 1.0

First release. Menu bar dictation: double-tap `Shift`, speak, double-tap again,
and polished text appears in the field you were typing in. On-device speech by
default, with cloud speech and text providers on your own API keys.

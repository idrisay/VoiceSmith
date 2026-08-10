# Changelog

Each released version, newest first. The release workflow reads the section
matching the tag and puts it at the top of the GitHub release notes, so the
heading format matters: `## <version>`.

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

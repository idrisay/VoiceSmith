# Changelog

Each released version, newest first. The release workflow reads the section
matching the tag and puts it at the top of the GitHub release notes, so the
heading format matters: `## <version>`.

## 1.3

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

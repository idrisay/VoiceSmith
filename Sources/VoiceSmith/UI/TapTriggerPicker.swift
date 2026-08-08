import SwiftUI

/// Choosing which modifier a double-tap trigger listens to.
///
/// Shared by onboarding and Settings so the choice reads identically in both —
/// it is offered up front because a trigger that fights another app is
/// discovered on first use, not later, and revisitable because the app that
/// fights it may be installed next month.
struct TapTriggerPicker: View {
    let title: String
    let subtitle: String
    @Binding var selection: TapModifier
    /// Already spoken for by the other trigger. Both on one modifier would
    /// leave neither working: a tap of either clears the other's pending tap.
    let taken: TapModifier

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Picker(title, selection: $selection) {
                ForEach(TapModifier.allCases) { option in
                    // The clash is hidden rather than shown-and-disabled: a
                    // greyed row invites a click that can't be explained here.
                    if option != taken || option == .off {
                        Text(option.displayName).tag(option)
                    }
                }
            }
            .onChange(of: selection) { _, _ in
                NotificationCenter.default.post(name: .shortcutChanged, object: nil)
            }

            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let caution = selection.caution {
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                    Text(caution)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

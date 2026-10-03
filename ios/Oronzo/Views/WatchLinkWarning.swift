import OronzoCore
import SwiftUI

/// Names a problem the phone can see and the wrist cannot say.
///
/// The failure this exists for is the one `docs/runbook.md` records as the most expensive in the
/// project: a phone running a workout perfectly, a watch showing **"No workout"**, and nothing
/// anywhere to explain the disagreement — the companion registration can drop without a sound,
/// and there is no process on the wrist to draw a note about it (`docs/decisions.md`, "The third
/// occurrence, and the cause").
///
/// It is deliberately a note rather than a refusal. Every symptom the failure causes is a *stale
/// screen*, never a wrong one, so the workout carries on: the countdown on this phone is correct
/// regardless of what the watch is doing. Fixing it is one script afterwards, never a mid-set
/// operation.
///
/// Drawn on the session screen and on both plan surfaces, because on 3 October 2026 the
/// registration dropped at 10:23 with nobody looking, and the first place it could be seen was a
/// workout already in progress. The plan list and the plan summary are where the next workout is
/// chosen — the last moment the warning still changes what happens.
///
/// The rendering is the session screen's, moved out verbatim so the three surfaces cannot drift:
/// same figure, same colour, same spacing.
struct WatchLinkWarning: View {
    let note: String

    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .caption) private var captionSize = TypeScale.size(.caption, on: .phone)

    var body: some View {
        Label(note, systemImage: "applewatch.exclamationmark")
            .font(.system(size: captionSize, weight: .medium))
            .foregroundStyle(ColorRole.danger.color(colorScheme))
            .multilineTextAlignment(.center)
            .padding(.top, SpacingStep.tight.points)
    }
}

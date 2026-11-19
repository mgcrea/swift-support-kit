import SupportKit
import SwiftUI

/// The one-time ask `FeedbackPrompt` decided on: a question, a line, a button to
/// the feedback form and a way to close it.
///
/// **A card the app places, never an alert or a sheet.** The person has just got
/// the thing they came for, and this must not stand between them and it. It sits
/// where the app puts it until it is answered or closed, and both are the same
/// event: the prompt is resolved and nothing draws again.
///
/// **No background of its own**, for the reason `FeedbackLink` gives. The host
/// applies its chrome:
///
/// ```swift
/// FeedbackPromptCard(app: .silhouette, prompt: feedback, isPro: store.isUnlocked)
///     .padding(12)
///     .background(.quaternary, in: .rect(cornerRadius: 10))
/// ```
///
/// Chrome goes on the card and not around it. The card is no view at all while
/// the prompt is not pending, and inside a stack a modifier on no view draws
/// nothing and takes no room (measured: a padded, filled card in a `VStack` adds
/// zero points), where a wrapping container would leave an empty box. A `List`
/// section or a hosting view's root is not a stack: there, put the card behind
/// `if prompt.isPending && isPro`, the two things it checks itself.
///
/// The button opens the web form with `kind=idea`, through `openURL`. Nothing is
/// sent from the app, which is what keeps this inside every consuming app's
/// privacy label.
public struct FeedbackPromptCard: View {
  private let app: SupportApp
  private let prompt: FeedbackPrompt
  private let isPro: Bool

  @Environment(\.openURL) private var openURL

  /// - Parameter isPro: whether the person has Pro *now*. The prompt only counts
  ///   milestones reached as Pro, but a purchase can be refunded after the card
  ///   came due, and thanking somebody for a purchase they no longer have is
  ///   worse than not asking. It is hidden then, not resolved, so it returns
  ///   with the purchase.
  public init(app: SupportApp, prompt: FeedbackPrompt, isPro: Bool = true) {
    self.app = app
    self.prompt = prompt
    self.isPro = isPro
  }

  public var body: some View {
    if prompt.isPending, isPro {
      VStack(alignment: .leading, spacing: 6) {
        HStack(alignment: .firstTextBaseline) {
          Text(localized("What should \(app.displayName) do better?"))
            .font(.headline)
            .fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 8)
          Button {
            prompt.resolve()
          } label: {
            Image(systemName: "xmark")
          }
          .buttonStyle(.plain)
          .foregroundStyle(.secondary)
          // A glyph is a small thing to hit, on a phone most of all. The room
          // is given and taken back, so the target grows and the layout does not.
          .padding(10)
          .contentShape(.rect)
          .padding(-10)
          .accessibilityLabel(localized("Dismiss"))
        }
        Text(localized("Thanks for buying Pro. I read every message, and good ideas ship fast."))
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        Button(localized("Send Feedback")) {
          openURL(app.feedbackURL(kind: .idea))
          prompt.resolve()
        }
        // Named, because the default is not one style. In an iOS `List` row a
        // default button takes the whole row as its target: a tap on the
        // question, or one that just missed the close button, would open the
        // form and spend the one ask.
        .buttonStyle(.bordered)
        .padding(.top, 2)
      }
    }
  }
}

#if os(macOS)
  import SwiftUI

  /// What sits under the rule at the bottom of the panel.
  ///
  /// The fleet had two footer idioms and they looked incompatible. Three apps
  /// (armada, bastion, cupertino) draw **one row** — a tinted primary on the
  /// left, glyphs and Quit on the right — under a rule that says *what opens
  /// something sits left, what you go to sits right*. Two (almanac, dev-pulse)
  /// draw a **vertical list** of named buttons.
  ///
  /// The split is not a disagreement about layout. It is that the stacked pair
  /// have something the other three happen not to: a **verb**. "Collect now" and
  /// "Refresh Now" are neither the primary nor a route — they are work this
  /// panel does itself, and a verb cannot be reduced to a glyph nobody has to be
  /// taught. So both idioms are the same footer with one optional part:
  ///
  /// ```
  /// [verbs — stacked, named, only if the app has any]
  /// ───────
  /// [Open <App>]  ·······  [route] [route]  [Quit]
  /// [What's new in 1.2.0…  — only just after an update]
  /// ```
  ///
  /// Read against the two stacked panels, everything else they listed was
  /// already a route: almanac's Settings and Quit, dev-pulse's Briefing,
  /// Settings and Quit. Each keeps exactly one verb and the rest collapses into
  /// the row the other three already had.
  public struct MenuBarFooter {
    /// Work the panel does itself. Stacked above the row, because a verb needs
    /// its name. Usually empty.
    public let verbs: [MenuBarAction]

    /// Places you go. Glyphs in the action row, right of the gap.
    ///
    /// Two is the working ceiling, and it is a measurement rather than a taste:
    /// cupertino recorded a fourth *text* button truncating "Open Cupertino" to
    /// "Open Cuperti…" at this width. Glyphs cost a fraction of that, which is
    /// why the row can hold two of them and could not hold one more word.
    public let routes: [MenuBarAction]

    /// Shown once after an update, then gone.
    ///
    /// Deliberately not a permanent badge on the version text in the header —
    /// bastion's reasoning, and the reason the header's version opens *About*
    /// rather than this: the version answers "which build is this", What's New
    /// answers "what did it change", and they are different questions asked at
    /// different moments.
    public let whatsNew: WhatsNew?

    public init(
      verbs: [MenuBarAction] = [],
      routes: [MenuBarAction] = [],
      whatsNew: WhatsNew? = nil
    ) {
      self.verbs = verbs
      self.routes = routes
      self.whatsNew = whatsNew
    }

    /// The one-shot "What's new in 1.2.0…" row.
    public struct WhatsNew {
      public let version: String
      public let run: () -> Void

      public init(version: String, run: @escaping () -> Void) {
        self.version = version
        self.run = run
      }
    }
  }
#endif

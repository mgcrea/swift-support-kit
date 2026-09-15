#if os(macOS)
  import Testing

  @testable import SupportKitToolbar

  /// The one decision the label makes on its own.
  ///
  /// What the module is actually for — both lines surviving the macOS 27
  /// toolbar — is layout, and no unit test sees it; that is checked in a running
  /// app. What a test can hold is the rule for when the placeholder takes the
  /// second line, which every app used to decide separately.
  @Suite struct ToolbarCaptionLabelTests {
    /// Nil, empty and blank all fall back to the placeholder, so no control
    /// shows a caption over an empty line.
    @Test func blankValuesFallBackToThePlaceholder() {
      #expect(ToolbarCaptionLabel.displayedValue(nil) == nil)
      #expect(ToolbarCaptionLabel.displayedValue("") == nil)
      #expect(ToolbarCaptionLabel.displayedValue(" \n\t") == nil)
    }

    /// A value is drawn exactly as given. Values here are data — a model's name,
    /// Silhouette's "white · t 0.50" — and trimming would rewrite them.
    @Test func valuesAreDrawnVerbatim() {
      #expect(ToolbarCaptionLabel.displayedValue("Parakeet TDT v3") == "Parakeet TDT v3")
      #expect(ToolbarCaptionLabel.displayedValue(" white · t 0.50") == " white · t 0.50")
    }
  }
#endif

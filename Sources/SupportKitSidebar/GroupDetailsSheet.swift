import SwiftUI

/// New Group, or Edit Group: a name, a colour and a symbol. It knows no group model: it starts
/// from values and hands them to `save`, which answers nil once saved, or the sentence saying
/// why it was refused, shown under the name with the sheet left open.
///
/// `extra` adds sections of the caller's own after the symbols (Cadence's iCloud audio switch),
/// whose values the caller keeps and reads when `save` is called. `locksAppearance` shows the
/// colour and symbol without letting them change, for a group whose name alone can.
/// `symbolName` is what VoiceOver calls each of the app's symbols; the SF Symbols name is a
/// poor label.
public struct GroupDetailsSheet<Extra: View>: View {
  private let title: Text
  private let confirmTitle: Text
  private let symbols: [String]
  private let symbolName: (String) -> String
  private let locksAppearance: Bool
  private let size: CGSize
  private let save: (_ name: String, _ color: String, _ symbol: String) -> String?
  private let extra: Extra

  @Environment(\.dismiss) private var dismiss
  @State private var name: String
  @State private var color: String
  @State private var symbol: String
  @State private var refusal: String?

  /// - Parameter size: the sheet's size on the Mac, more than the default when `extra` adds
  ///   sections.
  public init(
    title: Text, confirmTitle: Text, name: String = "", color: String = "blue",
    symbol: String, symbols: [String], symbolName: @escaping (String) -> String = { $0 },
    size: CGSize = CGSize(width: 360, height: 420), locksAppearance: Bool = false,
    save: @escaping (_ name: String, _ color: String, _ symbol: String) -> String?,
    @ViewBuilder extra: () -> Extra
  ) {
    self.title = title
    self.confirmTitle = confirmTitle
    self.symbols = symbols
    self.symbolName = symbolName
    self.locksAppearance = locksAppearance
    self.size = size
    self.save = save
    self.extra = extra()
    _name = State(initialValue: name)
    _color = State(initialValue: color)
    _symbol = State(initialValue: symbol)
  }

  public var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField(localized("Name"), text: $name)
            .accessibilityIdentifier("group.name")
          if let refusal {
            Text(refusal)
              .font(.callout)
              .foregroundStyle(.red)
          }
        }
        Group {
          Section(localized("Color")) { GroupColorGrid(color: $color) }
          Section(localized("Symbol")) {
            GroupSymbolGrid(
              symbols: symbols, symbol: $symbol, color: color, symbolName: symbolName)
          }
        }
        .disabled(locksAppearance)
        extra
      }
      .formStyle(.grouped)
      .navigationTitle(title)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(localized("Cancel")) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button {
            refusal = save(name, color, symbol)
            if refusal == nil { dismiss() }
          } label: {
            confirmTitle
          }
          .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          .accessibilityIdentifier("group.save")
        }
      }
    }
    #if os(macOS)
      .frame(width: size.width, height: size.height)
    #endif
  }
}

extension GroupDetailsSheet where Extra == EmptyView {
  public init(
    title: Text, confirmTitle: Text, name: String = "", color: String = "blue",
    symbol: String, symbols: [String], symbolName: @escaping (String) -> String = { $0 },
    size: CGSize = CGSize(width: 360, height: 420), locksAppearance: Bool = false,
    save: @escaping (_ name: String, _ color: String, _ symbol: String) -> String?
  ) {
    self.init(
      title: title, confirmTitle: confirmTitle, name: name, color: color, symbol: symbol,
      symbols: symbols, symbolName: symbolName, size: size, locksAppearance: locksAppearance,
      save: save
    ) { EmptyView() }
  }
}

/// A group's colours as swatches, the one chosen ringed. Drawn by hand rather than as a
/// Picker: an iOS menu picker strips the colour from its images, which is the bug Valise
/// shipped and fixed.
public struct GroupColorGrid: View {
  @Binding private var color: String

  public init(color: Binding<String>) {
    _color = color
  }

  public var body: some View {
    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 8) {
      ForEach(GroupPalette.tokens, id: \.self) { token in
        Button {
          color = token
        } label: {
          Circle()
            .fill(GroupPalette.color(token))
            .frame(width: 22, height: 22)
            .overlay {
              if token == color {
                Circle().strokeBorder(.primary, lineWidth: 2).padding(-4)
              }
            }
            .padding(4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(GroupPalette.name(token))
        .accessibilityAddTraits(token == color ? .isSelected : [])
      }
    }
  }
}

/// A group's symbols, the one chosen drawn in the group's colour. `symbolName` is what
/// VoiceOver calls each one.
public struct GroupSymbolGrid: View {
  private let symbols: [String]
  @Binding private var symbol: String
  private let color: String
  private let symbolName: (String) -> String

  public init(
    symbols: [String], symbol: Binding<String>, color: String,
    symbolName: @escaping (String) -> String = { $0 }
  ) {
    self.symbols = symbols
    _symbol = symbol
    self.color = color
    self.symbolName = symbolName
  }

  public var body: some View {
    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 8) {
      ForEach(symbols, id: \.self) { name in
        Button {
          symbol = name
        } label: {
          Image(systemName: name)
            .font(.title3)
            .frame(width: 40, height: 32)
            .foregroundStyle(
              name == symbol
                ? AnyShapeStyle(GroupPalette.color(color)) : AnyShapeStyle(.secondary)
            )
            .background(
              name == symbol ? GroupPalette.color(color).opacity(0.15) : .clear,
              in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbolName(name))
        .accessibilityAddTraits(name == symbol ? .isSelected : [])
      }
    }
  }
}

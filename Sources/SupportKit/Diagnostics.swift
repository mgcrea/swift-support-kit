import Foundation

#if canImport(Darwin)
  import Darwin
#endif

/// The four facts a support request needs and none it does not.
///
/// Deliberately absent: username, hostname, any file or folder path, document
/// names, the serial number, and any persistent identifier at all. Two reports
/// from the same Mac are not linkable by anything this struct carries — which
/// is a property the privacy pages can claim only while it stays true.
///
/// Every field is a value the user could read off their own machine in under a
/// minute, which is the test for whether it belongs here. They also all end up
/// visible in a URL the user can read before pressing send, so anything
/// embarrassing to show them is by definition something not to collect.
public struct Diagnostics: Sendable, Equatable {
  /// `"1.4 (168)"` — short version and build, the pair an issue actually needs.
  public let appVersion: String
  /// `"macOS 26.4"` / `"iOS 26.0"`, composed rather than scraped. See `osVersionString`.
  public let osVersion: String
  /// `"Mac16,10"` / `"iPhone17,1"` — the model identifier, not a marketing name.
  public let hardware: String
  /// `"en"` — language only, never the region. See `languageCode`.
  public let language: String

  public init(appVersion: String, osVersion: String, hardware: String, language: String) {
    self.appVersion = appVersion
    self.osVersion = osVersion
    self.hardware = hardware
    self.language = language
  }

  /// What this machine reports right now.
  ///
  /// Not a stored property: a `Bundle` read and two `sysctl` calls are cheap,
  /// and caching them would only create a second thing to invalidate.
  public static var current: Diagnostics {
    Diagnostics(
      appVersion: bundleVersionString(),
      osVersion: osVersionString(),
      hardware: hardwareIdentifier(),
      language: languageCode()
    )
  }
}

// MARK: - The pieces, each with a trap worth naming

extension Diagnostics {
  /// `CFBundleShortVersionString (CFBundleVersion)`.
  ///
  /// Both, because either alone loses something: the short version is what the
  /// user sees and quotes, the build is what distinguishes two TestFlight
  /// submissions of "1.4". The fallbacks are deliberately obvious strings
  /// rather than empty — a report saying `unknown` is diagnosable, one with a
  /// blank field looks like the form dropped it.
  static func bundleVersionString(bundle: Bundle = .main) -> String {
    let info = bundle.infoDictionary
    let short = info?["CFBundleShortVersionString"] as? String ?? "unknown"
    let build = info?["CFBundleVersion"] as? String ?? "unknown"
    return "\(short) (\(build))"
  }

  /// `"macOS 26.4"`, composed from `operatingSystemVersion`.
  ///
  /// **Not** `ProcessInfo.operatingSystemVersionString`, which every hand-rolled
  /// copy of this in the app repos used and which returns
  /// `"Version 26.4 (Build 25E5xxx)"` — a string that is prose, carries a build
  /// number nobody asked for, and does not group in a database column.
  ///
  /// The patch component is dropped when zero so the common case reads
  /// `macOS 26.4` rather than `macOS 26.4.0`.
  static func osVersionString(processInfo: ProcessInfo = .processInfo) -> String {
    let v = processInfo.operatingSystemVersion
    let number =
      v.patchVersion == 0
      ? "\(v.majorVersion).\(v.minorVersion)"
      : "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    #if os(macOS)
      return "macOS \(number)"
    #elseif os(visionOS)
      return "visionOS \(number)"
    #elseif os(tvOS)
      return "tvOS \(number)"
    #elseif os(watchOS)
      return "watchOS \(number)"
    #else
      return "iOS \(number)"
    #endif
  }

  /// The model identifier, via sysctl — and the key is **not the same on both
  /// platforms**.
  ///
  /// On macOS `hw.model` gives `Mac16,10`, the thing you want. On iOS the same
  /// key gives a board identifier like `D74AP`, which is useless in a bug
  /// report, and it is `hw.machine` that gives `iPhone17,1`. Reading the wrong
  /// one does not error — it returns a plausible-looking wrong answer, which is
  /// the worst shape a bug can take.
  ///
  /// The Simulator lies on both: it reports the host Mac. `SIMULATOR_MODEL_IDENTIFIER`
  /// is the only thing that knows what is being simulated, so it wins when set.
  static func hardwareIdentifier(
    environment: [String: String] = ProcessInfo.processInfo.environment
  )
    -> String
  {
    if let simulated = environment["SIMULATOR_MODEL_IDENTIFIER"], !simulated.isEmpty {
      return simulated
    }
    #if os(macOS)
      let key = "hw.model"
    #else
      let key = "hw.machine"
    #endif
    return sysctlString(key) ?? "unknown"
  }

  /// The language, without the region.
  ///
  /// `en` rather than `en_GB`: the region tells triage nothing a bug report
  /// needs and narrows the crowd a report could have come from. `Locale.current.identifier`
  /// would carry it, so the code is taken explicitly.
  static func languageCode(locale: Locale = .current) -> String {
    locale.language.languageCode?.identifier ?? "und"
  }

  /// Two-call sysctl: ask for the size, then fill a buffer of exactly that size.
  ///
  /// Returns nil rather than trapping on any failure. A missing model string is
  /// a slightly worse bug report; a crash while opening the feedback form is a
  /// bug report that never gets written.
  private static func sysctlString(_ name: String) -> String? {
    #if canImport(Darwin)
      var size = 0
      guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
      var buffer = [UInt8](repeating: 0, count: size)
      guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
      // sysctl reports the size *including* the NUL terminator, and
      // `String(decoding:)` would keep it as a \0 character in the string —
      // invisible in a log, but a stray byte in a URL. Drop the terminator
      // before decoding rather than trimming afterwards.
      let bytes = buffer.prefix { $0 != 0 }
      return String(decoding: bytes, as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    #else
      return nil
    #endif
  }
}

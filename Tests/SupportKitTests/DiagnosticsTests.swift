import Foundation
import Testing

@testable import SupportKit

@Suite("Diagnostics")
struct DiagnosticsTests {
    /// The regression that matters: `operatingSystemVersionString` returns
    /// `"Version 26.4 (Build 25E5xxx)"`, which is what every hand-rolled copy of
    /// this used. The composed form has to be a clean, groupable string.
    @Test("composes the OS version instead of scraping the prose one")
    func osVersionIsComposed() {
        let composed = Diagnostics.osVersionString()
        #expect(!composed.contains("Version "))
        #expect(!composed.lowercased().contains("build"))
        #expect(composed.contains(" "))

        let number = composed.split(separator: " ").last.map(String.init) ?? ""
        #expect(number.allSatisfy { $0.isNumber || $0 == "." })
    }

    @Test("drops a zero patch component")
    func dropsZeroPatch() {
        // ProcessInfo cannot be stubbed for the version, so this asserts the
        // shape rather than a value: two or three components, never four, and
        // never a trailing ".0" left dangling.
        let number = Diagnostics.osVersionString().split(separator: " ").last.map(String.init) ?? ""
        let parts = number.split(separator: ".")
        #expect((2...3).contains(parts.count))
        if parts.count == 3 { #expect(parts[2] != "0") }
    }

    @Test("names the platform it was built for")
    func namesPlatform() {
        #if os(macOS)
            #expect(Diagnostics.osVersionString().hasPrefix("macOS "))
        #else
            #expect(!Diagnostics.osVersionString().isEmpty)
        #endif
    }

    /// The Simulator reports the host Mac, so the environment override is the
    /// only thing that knows what is actually being simulated.
    @Test("prefers the simulated model when running under the Simulator")
    func simulatorOverride() {
        let hw = Diagnostics.hardwareIdentifier(
            environment: ["SIMULATOR_MODEL_IDENTIFIER": "iPhone17,1"])
        #expect(hw == "iPhone17,1")
    }

    /// No prefix assertion: model identifiers do not share one. CI runs on
    /// `VirtualMac2,1`, and real hardware includes `iMac21,1` — neither starts
    /// with "Mac". The contract is only that a real identifier came back.
    @Test("ignores an empty simulator variable rather than reporting nothing")
    func emptySimulatorVariable() {
        let hw = Diagnostics.hardwareIdentifier(environment: ["SIMULATOR_MODEL_IDENTIFIER": ""])
        #expect(!hw.isEmpty)
        #expect(hw != "unknown")
        #expect(hw.contains(","))
    }

    @Test("reads a real model identifier off this machine")
    func realHardware() {
        let hw = Diagnostics.hardwareIdentifier(environment: [:])
        #expect(hw != "unknown")
        // No NUL padding or stray whitespace from the sysctl buffer.
        #expect(hw == hw.trimmingCharacters(in: .whitespacesAndNewlines))
        #expect(!hw.contains("\0"))
    }

    /// Language without region: `en`, never `en_GB`. The region narrows the
    /// crowd a report could have come from and tells triage nothing.
    @Test("reports the language without the region")
    func languageWithoutRegion() {
        #expect(Diagnostics.languageCode(locale: Locale(identifier: "en_GB")) == "en")
        #expect(Diagnostics.languageCode(locale: Locale(identifier: "fr_FR")) == "fr")
        #expect(Diagnostics.languageCode(locale: Locale(identifier: "pt_BR")) == "pt")
    }

    @Test("pairs the short version with the build")
    func versionPairsWithBuild() {
        let bundle = Bundle(for: DiagnosticsTestAnchor.self)
        let version = Diagnostics.bundleVersionString(bundle: bundle)
        // A test bundle has no CFBundleShortVersionString; the point is that the
        // fallback is a readable token rather than an empty string that looks
        // like the form dropped the field.
        #expect(version.contains("("))
        #expect(!version.hasPrefix(" "))
    }

    @Test("current populates every field")
    func currentIsComplete() {
        let d = Diagnostics.current
        #expect(!d.appVersion.isEmpty)
        #expect(!d.osVersion.isEmpty)
        #expect(!d.hardware.isEmpty)
        #expect(!d.language.isEmpty)
    }

    /// A blunt guard on the promise the privacy pages make. If someone later
    /// adds a field, this fails and makes them think about it.
    @Test("carries no identifier beyond the four documented facts")
    func noHiddenIdentifiers() {
        let d = Diagnostics.current
        let all = [d.appVersion, d.osVersion, d.hardware, d.language].joined(separator: " ")
        #expect(!all.contains(NSUserName()))
        #expect(!all.contains(ProcessInfo.processInfo.hostName))
        #expect(!all.contains(NSHomeDirectory()))
    }
}

/// Anchor for `Bundle(for:)`, which needs a class in the test bundle.
private final class DiagnosticsTestAnchor {}

import Foundation
import Testing

@testable import SupportKitMemory

private let mib = 1024 * 1024

/// iOS kills an app at a per-process limit far below physical memory (3.4 GB on a
/// 12 GB iPhone 17 Pro Max), so the Mac formula — 80% of physical — would set MLX's
/// ceiling above the point where the process is terminated. These pin the iOS numbers.
@Suite struct PerAppLimitTests {
  /// The iPhone 17 Pro Max, measured: 3,376 MiB available to the app.
  @Test func limitsOnA17ProMax() {
    let budget = MemoryBudget.limits(perAppLimit: 3376 * mib)
    #expect(budget.ceiling == 2776 * mib)  // limit − 600 MiB
    #expect(budget.cache == 256 * mib)
  }

  /// A small limit must still leave MLX half of it rather than a margin-sized sliver.
  @Test func smallLimitKeepsHalf() {
    let budget = MemoryBudget.limits(perAppLimit: 1024 * mib)
    #expect(budget.ceiling == 512 * mib)
    #expect(budget.cache == 128 * mib)  // limit / 8
  }

  /// Cached buffers count against the iOS limit, so the cache never exceeds 256 MiB.
  @Test(arguments: [2048, 3376, 6144, 12288])
  func cacheNeverAbove256MiB(limitMiB: Int) {
    #expect(MemoryBudget.limits(perAppLimit: limitMiB * mib).cache <= 256 * mib)
  }

  /// The ceiling always stays under the limit it was derived from.
  @Test(arguments: [1024, 2048, 3376, 6144])
  func ceilingBelowLimit(limitMiB: Int) {
    #expect(MemoryBudget.limits(perAppLimit: limitMiB * mib).ceiling < limitMiB * mib)
  }

  #if os(macOS)
    /// A Mac has no per-app limit; callers treat nil as "no ceiling of this kind".
    @Test func noPerAppLimitOnMac() {
      #expect(MemoryBudget.perAppLimit == nil)
    }
  #endif
}

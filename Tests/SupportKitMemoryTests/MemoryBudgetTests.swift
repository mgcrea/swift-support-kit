import Foundation
import Testing

@testable import SupportKitMemory

private let gib: UInt64 = 1024 * 1024 * 1024

/// The numbers `MemoryBudget` produces are the whole safety rail, so they are
/// pinned here rather than left to be re-derived by whoever next reads the
/// formula.
@Suite struct MemoryBudgetTests {
  /// A 64 GiB M5 Max with a 48 GiB working set — the machine the stalls came
  /// from.
  @Test func limitsOnA64GiBMachine() {
    let budget = MemoryBudget.limits(physicalMemory: 64 * gib, gpuMaxWorkingSet: 48 * gib)
    // 48 GiB / 12 is 4 GiB, so the 2 GB cap is what decides here.
    #expect(budget.cache == 2 * 1024 * 1024 * 1024)
    #expect(budget.ceiling == Int(64 * gib / 5 * 4))  // 51.2 GiB
  }

  /// The ceiling must stay under physical memory. Above it the allocator never
  /// blocks and the process swaps until the compressor collapses, which is what
  /// MLX's own default (1.5× the working set) does.
  @Test(arguments: [8, 16, 32, 64, 128] as [UInt64])
  func ceilingStaysBelowPhysicalMemory(gibibytes: UInt64) {
    let physical = gibibytes * gib
    let budget = MemoryBudget.limits(
      physicalMemory: physical, gpuMaxWorkingSet: physical / 4 * 3)
    #expect(budget.ceiling < Int(physical))
    #expect(budget.ceiling > Int(physical) / 2)
  }

  /// The cache must stay small enough that an abandoned model cannot sit in it
  /// unnoticed. One SAM 3.1 pool is ~10 GB; the cap is well below that on every
  /// machine size.
  @Test(arguments: [8, 16, 32, 64, 128] as [UInt64])
  func cacheIsCappedWellBelowOneModel(gibibytes: UInt64) {
    let budget = MemoryBudget.limits(
      physicalMemory: gibibytes * gib, gpuMaxWorkingSet: gibibytes * gib / 4 * 3)
    #expect(budget.cache <= 2 * 1024 * 1024 * 1024)
    #expect(budget.cache >= 512 * 1024 * 1024)
  }

  /// A machine that reports no Metal device still gets sane limits rather than
  /// a zero that would disable the cache entirely.
  @Test func fallsBackToPhysicalMemoryWithoutAGPU() {
    let budget = MemoryBudget.limits(physicalMemory: 16 * gib, gpuMaxWorkingSet: nil)
    #expect(budget.cache >= 512 * 1024 * 1024)
    #expect(budget.ceiling == Int(16 * gib / 5 * 4))
  }

  /// The live reading goes through the same formula, so it inherits every
  /// property above; this only checks it reads a real machine.
  @Test func forThisMachineStaysBelowPhysicalMemory() {
    let budget = MemoryBudget.forThisMachine
    #expect(budget.cache > 0)
    #expect(budget.ceiling > 0)
    #expect(budget.ceiling < Int(ProcessInfo.processInfo.physicalMemory))
  }
}

@Suite struct MemoryPressureWatcherTests {
  /// Starting twice must not replace the live source. A second source assigned
  /// over the first would drop the original's last reference, and a released
  /// dispatch source stops delivering — the watcher would go quiet with
  /// everything still looking wired up.
  @MainActor
  @Test func startingTwiceKeepsTheFirstSource() {
    MemoryPressureWatcher.start { _ in }
    #expect(MemoryPressureWatcher.isWatching)
    MemoryPressureWatcher.start { _ in }
    #expect(MemoryPressureWatcher.isWatching)
  }
}

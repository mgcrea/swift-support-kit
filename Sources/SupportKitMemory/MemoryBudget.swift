import Foundation
import Metal

/// How much memory an app running on-device inference may hold, sized to the
/// machine it runs on.
///
/// Written for MLX, whose two limits both default to numbers that are
/// hazardous on a Mac that is also running a browser, a simulator and a
/// container VM:
///
/// - `cacheLimit` defaults to the GPU's `recommendedMaxWorkingSetSize` — about
///   48 GiB on a 64 GiB Mac. MLX returns a freed model's buffers to that cache
///   rather than to the OS, so the number is how much dead weight a process may
///   keep. Contour reached a 48.0 GiB footprint, exactly that ceiling, with only
///   ~9.5 GiB of it in use.
/// - `memoryLimit` defaults to **1.5×** that, which is more than the machine
///   has. MLX then never waits on anything; it allocates until the compressor
///   gives out and the whole machine stalls until it is power-cycled. That
///   happened twice in one afternoon in Contour's test host.
///
/// The budget changes the failure mode deliberately. Past `ceiling` MLX blocks
/// on allocation, so a runaway shows up as one app's inference stalling or
/// failing, not as a Mac that needs a hard reboot.
///
/// The package does not depend on MLX, and never should: every app that links
/// the Help menu would otherwise fetch mlx-swift to get it. The app hands the
/// two numbers over itself:
///
/// ```swift
/// let budget = MemoryBudget.forThisMachine
/// MLX.Memory.cacheLimit = budget.cache
/// MLX.Memory.memoryLimit = budget.ceiling
/// ```
///
/// Apply it in the test host too. Contour once exempted XCTest because parallel
/// parity tests throttled under the ceiling, and the exemption let the next
/// parallel run take the whole machine down. The fix for that was running the
/// model-loading tests one at a time, not lifting the limits.
public struct MemoryBudget: Equatable, Sendable {
  /// Bytes an allocator may keep cached after freeing.
  public let cache: Int
  /// Bytes an allocator may have outstanding before allocation starts blocking.
  public let ceiling: Int

  public init(cache: Int, ceiling: Int) {
    self.cache = cache
    self.ceiling = ceiling
  }

  /// The budget for this machine: its physical memory and its default Metal
  /// device's recommended working set.
  public static var forThisMachine: MemoryBudget {
    limits(
      physicalMemory: ProcessInfo.processInfo.physicalMemory,
      gpuMaxWorkingSet: MTLCreateSystemDefaultDevice()?.recommendedMaxWorkingSetSize)
  }

  /// Pure, so the numbers are testable without a GPU. `forThisMachine` is the
  /// only part that reads the hardware.
  ///
  /// - Parameter gpuMaxWorkingSet: `nil` on a machine with no Metal device,
  ///   which falls back to physical memory rather than to a zero that would
  ///   disable the cache.
  public static func limits(physicalMemory: UInt64, gpuMaxWorkingSet: UInt64?) -> MemoryBudget {
    let workingSet = gpuMaxWorkingSet ?? physicalMemory

    // A twelfth of the working set, held between 512 MB and 2 GB. Enough to keep
    // per-frame scratch buffers hot across a video run without leaving room for a
    // whole abandoned model to hide in there. MLX's own notes say caches as small
    // as a couple of MB often perform identically, so this is already generous.
    let cache = min(max(workingSet / 12, 512 * 1024 * 1024), 2 * 1024 * 1024 * 1024)

    // 80% of physical memory. The remaining fifth is not slack for the app — it is
    // what WindowServer, the compressor and everything else need for the machine
    // to stay usable while the app sits at its limit.
    let ceiling = physicalMemory / 5 * 4

    return MemoryBudget(cache: Int(cache), ceiling: Int(ceiling))
  }
}

import Foundation

#if os(iOS)
  import os
#endif

extension MemoryBudget {
  /// The budget for a process that the system terminates at `limit` bytes, as iOS does.
  ///
  /// Everything MLX holds counts against that limit, cached buffers included, so the
  /// cache is kept small (256 MiB, or an eighth of a small limit) and the ceiling
  /// leaves 600 MiB for the rest of the app — views, decoded images, the exporter.
  /// On a small limit the margin would eat most of it, so the ceiling never drops
  /// below half.
  public static func limits(perAppLimit limit: Int) -> MemoryBudget {
    let margin = 600 * 1024 * 1024
    let cache = min(256 * 1024 * 1024, limit / 8)
    let ceiling = max(limit - margin, limit / 2)
    return MemoryBudget(cache: cache, ceiling: ceiling)
  }

  /// Bytes this process may hold before iOS terminates it: what it holds now plus
  /// what the system says is still available. Read it once, at launch, before
  /// anything large is allocated — it is a property of the device and the app's
  /// entitlements, not of the moment. `nil` on macOS, which has no such limit.
  public static var perAppLimit: Int? {
    #if os(iOS)
      return currentFootprint() + Int(os_proc_available_memory())
    #else
      return nil
    #endif
  }

  #if os(iOS)
    private static func currentFootprint() -> Int {
      var info = task_vm_info_data_t()
      var count = mach_msg_type_number_t(
        MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
      let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
          task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
      }
      return result == KERN_SUCCESS ? Int(info.phys_footprint) : 0
    }
  #endif
}

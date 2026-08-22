import Dispatch
import MiraioApplication

@MainActor
final class MemoryPressureBridge {
  private let lifecycle: ApplicationLifecycleAuthority
  private let source: DispatchSourceMemoryPressure

  init(lifecycle: ApplicationLifecycleAuthority) {
    self.lifecycle = lifecycle
    source = DispatchSource.makeMemoryPressureSource(
      eventMask: [.warning, .critical],
      queue: .main
    )
    source.setEventHandler { [weak self] in
      guard let self else { return }
      Task { await self.lifecycle.submit(.memoryPressure) }
    }
    source.activate()
  }

  deinit {
    source.cancel()
  }
}

import SwiftUI

@main
struct MiraioApp: App {
  @Environment(\.scenePhase) private var scenePhase

  private let composition: AppComposition
  private let memoryPressureBridge: MemoryPressureBridge

  init() {
    let composition = AppComposition()
    self.composition = composition
    memoryPressureBridge = MemoryPressureBridge(lifecycle: composition.lifecycle)
  }

  var body: some Scene {
    WindowGroup {
      MiraioRootView()
        .task(id: scenePhase) {
          await composition.scenePhaseChanged(to: scenePhase)
        }
    }
    .defaultSize(width: 960, height: 640)
  }
}

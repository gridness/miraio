import MiraioApplication
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
      MiraioRootView(
        model: composition.catalogueModel,
        authentication: composition.authenticationModel,
        artwork: composition.artwork
      )
        .task(id: scenePhase) {
          await composition.scenePhaseChanged(to: scenePhase)
          if scenePhase == .active {
            await composition.catalogueModel.loadCatalogue(intent: .networkRecovery)
          }
        }
    }
    .defaultSize(width: 960, height: 640)
  }
}

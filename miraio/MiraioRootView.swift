import SwiftUI

struct MiraioRootView: View {
  var body: some View {
    VStack(spacing: 16) {
      Image(systemName: "play.rectangle.on.rectangle")
        .font(.system(size: 44, weight: .medium))
        .foregroundStyle(.indigo)
        .accessibilityHidden(true)

      Text("Miraio")
        .font(.largeTitle.weight(.semibold))

      Text("Native Anime365 catalogue and playback")
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(nsColor: .windowBackgroundColor))
    .accessibilityIdentifier("miraio.root")
  }
}

#Preview {
  MiraioRootView()
    .frame(width: 960, height: 640)
}

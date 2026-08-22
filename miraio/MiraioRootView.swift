import CoreGraphics
import MiraioApplication
import MiraioDomain
import SwiftUI

struct MiraioRootView: View {
  @Bindable var model: CatalogueViewModel
  let artwork: any ArtworkLoading

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ZStack {
      Color(red: 0.035, green: 0.04, blue: 0.065)
        .ignoresSafeArea()

      HStack(spacing: 18) {
        sourceList
          .frame(width: 210)
          .glassEffect(.regular, in: .rect(cornerRadius: 22))

        ZStack {
          CatalogueDestination(model: model, artwork: artwork)
            .opacity(model.destination == .catalogue ? 1 : 0)
            .allowsHitTesting(model.destination == .catalogue)
            .accessibilityHidden(model.destination != .catalogue)

          SearchDestination(model: model, artwork: artwork)
            .opacity(model.destination == .search ? 1 : 0)
            .allowsHitTesting(model.destination == .search)
            .accessibilityHidden(model.destination != .search)

          WatchHistoryDestination()
            .opacity(model.destination == .watchHistory ? 1 : 0)
            .allowsHitTesting(model.destination == .watchHistory)
            .accessibilityHidden(model.destination != .watchHistory)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        if model.selectedSeriesID != nil {
          SeriesInspector(model: model, artwork: artwork)
            .frame(width: 360)
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
            .transition(
              reduceMotion
                ? .opacity
                : .move(edge: .trailing).combined(with: .opacity)
            )
        }
      }
      .padding(18)
    }
    .foregroundStyle(.white)
    .tint(.indigo)
    .animation(reduceMotion ? nil : .snappy(duration: 0.24), value: model.selectedSeriesID)
  }

  private var sourceList: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(spacing: 10) {
        Image(systemName: "sparkles.tv.fill")
          .font(.title2)
          .accessibilityHidden(true)
        Text("Miraio")
          .font(.title2.weight(.semibold))
      }
      .padding(.horizontal, 14)

      VStack(spacing: 5) {
        sourceButton(.catalogue, title: "Catalogue", symbol: "rectangle.grid.2x2")
        sourceButton(.search, title: "Search", symbol: "magnifyingglass")
        sourceButton(.watchHistory, title: "Watch History", symbol: "clock.arrow.circlepath")
      }

      Spacer()

      VStack(alignment: .leading, spacing: 5) {
        Text("PUBLIC DISCOVERY")
          .font(.caption2.weight(.bold))
          .tracking(1.2)
          .foregroundStyle(.white.opacity(0.55))
        Text("Anime365 Catalogue")
          .font(.caption)
          .foregroundStyle(.white.opacity(0.72))
      }
      .padding(14)
    }
    .padding(.vertical, 16)
  }

  private func sourceButton(
    _ destination: MiraioDestination,
    title: LocalizedStringKey,
    symbol: String
  ) -> some View {
    Button {
      model.destination = destination
    } label: {
      Label(title, systemImage: symbol)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .frame(minHeight: 36)
        .background(
          model.destination == destination ? .white.opacity(0.14) : .clear,
          in: RoundedRectangle(cornerRadius: 10)
        )
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .padding(.horizontal, 8)
    .accessibilityIdentifier("source.\(destination.rawValue)")
  }
}

private struct CatalogueDestination: View {
  @Bindable var model: CatalogueViewModel
  let artwork: any ArtworkLoading

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 30) {
        destinationHeader
        if let notice = model.catalogueNotice {
          CatalogueNoticeView(notice: notice)
        }
        continueWatchingHero

        HStack(alignment: .firstTextBaseline) {
          Text("Explore")
            .font(.system(size: 30, weight: .semibold, design: .rounded))
          Spacer()
          Text("Recently updated Series")
            .font(.caption)
            .foregroundStyle(.white.opacity(0.58))
        }

        if model.catalogue.isEmpty && !model.isCatalogueLoading {
          EmptyCatalogueView()
        } else {
          LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 168, maximum: 220), spacing: 18)],
            spacing: 24
          ) {
            ForEach(model.catalogue) { series in
              SeriesCard(series: series, artwork: artwork) {
                Task { await model.select(series) }
              }
            }
          }
        }

        if model.isCatalogueLoading {
          ProgressView("Loading Catalogue…")
            .controlSize(.small)
        } else if model.catalogueCursor != nil {
          Button("Load More", systemImage: "arrow.down.circle") {
            Task { await model.loadNextCataloguePage() }
          }
          .buttonStyle(.glass)
        }
      }
      .padding(12)
    }
  }

  private var destinationHeader: some View {
    HStack(alignment: .firstTextBaseline) {
      VStack(alignment: .leading, spacing: 5) {
        Text("Catalogue")
          .font(.system(size: 38, weight: .semibold, design: .rounded))
        Text("Series available through Anime365")
          .foregroundStyle(.white.opacity(0.65))
      }
      Spacer()
      Button("Refresh", systemImage: "arrow.clockwise") {
        Task { await model.loadCatalogue(intent: .explicitReload) }
      }
      .buttonStyle(.glass)
      .keyboardShortcut("r", modifiers: .command)
    }
  }

  private var continueWatchingHero: some View {
    HStack(spacing: 24) {
      ZStack {
        RoundedRectangle(cornerRadius: 22)
          .fill(.indigo.opacity(0.3))
        Image(systemName: "play.rectangle.on.rectangle.fill")
          .font(.system(size: 58, weight: .light))
          .foregroundStyle(.white.opacity(0.75))
      }
      .frame(width: 150, height: 110)
      .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 8) {
        Text("CONTINUE WATCHING")
          .font(.caption.weight(.bold))
          .tracking(1.4)
          .foregroundStyle(.white.opacity(0.62))
        Text("Your next Episode will appear here")
          .font(.system(size: 24, weight: .semibold, design: .rounded))
        Text("Continue Watching is derived only from local Watch History.")
          .foregroundStyle(.white.opacity(0.65))
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer()
    }
    .padding(22)
    .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 26))
  }
}

private struct SearchDestination: View {
  @Bindable var model: CatalogueViewModel
  let artwork: any ArtworkLoading

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 24) {
        Text("Find a Series")
          .font(.system(size: 38, weight: .semibold, design: .rounded))
        Text("Search uses Anime365’s documented server title query.")
          .foregroundStyle(.white.opacity(0.65))

        TextField("Series title", text: $model.searchText)
          .textFieldStyle(.plain)
          .font(.title2)
          .padding(.horizontal, 18)
          .frame(minHeight: 52)
          .glassEffect(.regular, in: .rect(cornerRadius: 18))
          .accessibilityLabel("Search Catalogue")
          .accessibilityIdentifier("catalogue.search")

        if let notice = model.searchNotice {
          CatalogueNoticeView(notice: notice)
        }

        if model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          ContentUnavailableView(
            "Search the Catalogue",
            systemImage: "magnifyingglass",
            description: Text("Enter a Series name. Results come from Anime365.")
          )
          .foregroundStyle(.white)
        } else if model.searchResults.isEmpty && !model.isSearchLoading {
          ContentUnavailableView.search(text: model.searchText)
            .foregroundStyle(.white)
        } else {
          LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 245, maximum: 340), spacing: 16)],
            spacing: 16
          ) {
            ForEach(model.searchResults) { series in
              SearchResultCard(series: series, artwork: artwork) {
                Task { await model.select(series) }
              }
            }
          }
        }

        if model.isSearchLoading {
          ProgressView("Searching…")
        } else if model.searchCursor != nil {
          Button("Load More Results", systemImage: "arrow.down.circle") {
            Task { await model.loadNextSearchPage() }
          }
          .buttonStyle(.glass)
        }
      }
      .padding(22)
    }
    .task(id: model.searchText) {
      await model.search()
    }
  }
}

private struct WatchHistoryDestination: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      Text("Watch History")
        .font(.system(size: 38, weight: .semibold, design: .rounded))
      Text("Local, profile-specific playback progress")
        .foregroundStyle(.white.opacity(0.65))
      ContentUnavailableView(
        "No Watch History Yet",
        systemImage: "clock.arrow.circlepath",
        description: Text("Episodes will appear here after playback advances.")
      )
      .foregroundStyle(.white)
      Spacer()
    }
    .padding(22)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

private struct SeriesCard: View {
  let series: Series
  let artwork: any ArtworkLoading
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 10) {
        SeriesArtwork(series: series, artwork: artwork, width: 180, height: 250)
        SeriesTitle(series: series)
          .font(.headline)
          .lineLimit(3)
          .multilineTextAlignment(.leading)
        SeriesMetadata(series: series)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("series.\(series.id.rawValue)")
  }
}

private struct SearchResultCard: View {
  let series: Series
  let artwork: any ArtworkLoading
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 14) {
        SeriesArtwork(series: series, artwork: artwork, width: 76, height: 104)
        VStack(alignment: .leading, spacing: 6) {
          SeriesTitle(series: series)
            .font(.headline)
            .multilineTextAlignment(.leading)
          SeriesMetadata(series: series)
          Text("Server-backed Series result")
            .font(.caption)
            .foregroundStyle(.white.opacity(0.48))
        }
        Spacer()
        Image(systemName: "chevron.right")
          .foregroundStyle(.white.opacity(0.45))
      }
      .padding(12)
      .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("search.series.\(series.id.rawValue)")
  }
}

private struct SeriesInspector: View {
  @Bindable var model: CatalogueViewModel
  let artwork: any ArtworkLoading

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        HStack {
          Text("NOW SELECTING")
            .font(.caption2.weight(.bold))
            .tracking(1.4)
            .foregroundStyle(.white.opacity(0.58))
          Spacer()
          Button {
            model.closeInspector()
          } label: {
            Image(systemName: "xmark")
          }
          .buttonStyle(.glass)
          .keyboardShortcut(.cancelAction)
          .accessibilityLabel("Close Series inspector")
        }

        if let series = model.selectedDetails?.series {
          SeriesArtwork(series: series, artwork: artwork, width: 320, height: 190)
          SeriesTitle(series: series)
            .font(.title2.weight(.semibold))
          SeriesMetadata(series: series)
          Divider().overlay(.white.opacity(0.2))

          if model.isInspectorLoading {
            ProgressView("Loading Episodes…")
          } else if model.selectedDetails?.episodes.isEmpty != false {
            ContentUnavailableView(
              "Episodes Unavailable",
              systemImage: "exclamationmark.triangle",
              description: Text("The Series is preserved. Retry its current metadata.")
            )
            .foregroundStyle(.white)
            Button("Retry Series", systemImage: "arrow.clockwise") {
              Task { await model.select(series) }
            }
            .buttonStyle(.glassProminent)
          } else {
            episodeChoices
            translationChoices
            Button("Playback Unavailable", systemImage: "play.slash") {}
              .buttonStyle(.glassProminent)
              .disabled(true)
            Text("Playback becomes available only after protected playback integration is qualified.")
              .font(.caption)
              .foregroundStyle(.white.opacity(0.58))
              .fixedSize(horizontal: false, vertical: true)
          }
        } else if model.isInspectorLoading {
          ProgressView("Loading Series…")
        }
      }
      .padding(20)
    }
  }

  private var episodeChoices: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("EPISODE")
        .font(.caption2.weight(.bold))
        .tracking(1.2)
        .foregroundStyle(.white.opacity(0.55))
      ForEach(model.selectedDetails?.episodes ?? []) { episode in
        Button {
          model.select(episode)
        } label: {
          HStack {
            EpisodeTitle(episode: episode)
            Spacer()
            if model.selectedEpisodeID == episode.id {
              Image(systemName: "checkmark")
            }
          }
          .padding(10)
          .background(
            model.selectedEpisodeID == episode.id ? .indigo.opacity(0.3) : .white.opacity(0.055),
            in: RoundedRectangle(cornerRadius: 11)
          )
        }
        .buttonStyle(.plain)
        .disabled(episode.isActive == false)
      }
    }
  }

  @ViewBuilder
  private var translationChoices: some View {
    if let episodeID = model.selectedEpisodeID,
      let translations = model.selectedDetails?.translations(for: episodeID),
      !translations.isEmpty
    {
      VStack(alignment: .leading, spacing: 8) {
        Text("TRANSLATION")
          .font(.caption2.weight(.bold))
          .tracking(1.2)
          .foregroundStyle(.white.opacity(0.55))
        ForEach(translations) { translation in
          Button {
            model.selectedTranslationID = translation.id
          } label: {
            HStack {
              TranslationTitle(translation: translation)
              Spacer()
              if model.selectedTranslationID == translation.id {
                Image(systemName: "checkmark")
              }
            }
            .padding(10)
            .background(
              model.selectedTranslationID == translation.id
                ? .indigo.opacity(0.3)
                : .white.opacity(0.055),
              in: RoundedRectangle(cornerRadius: 11)
            )
          }
          .buttonStyle(.plain)
          .disabled(translation.isActive == false)
        }
      }
    } else {
      Label("No active Translations", systemImage: "captions.bubble")
        .foregroundStyle(.white.opacity(0.62))
    }
  }
}

private struct SeriesArtwork: View {
  let series: Series
  let artwork: any ArtworkLoading
  let width: CGFloat
  let height: CGFloat

  @Environment(\.displayScale) private var displayScale
  @State private var image: CGImage?

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 16)
        .fill(.indigo.opacity(0.22))
      if let image {
        Image(decorative: image, scale: displayScale)
          .resizable()
          .scaledToFill()
      } else {
        Image(systemName: "sparkles.tv")
          .font(.system(size: min(width, height) * 0.24, weight: .ultraLight))
          .foregroundStyle(.white.opacity(0.45))
      }
    }
    .frame(maxWidth: width, minHeight: height, maxHeight: height)
    .clipShape(RoundedRectangle(cornerRadius: 16))
    .task(id: request) {
      guard let request else { return }
      image = try? await artwork.image(for: request).cgImage
    }
  }

  private var request: ArtworkRequest? {
    guard let url = series.posterURL else { return nil }
    return ArtworkRequest(
      url: url,
      pixelWidth: max(1, Int(width * displayScale)),
      pixelHeight: max(1, Int(height * displayScale)),
      scale: Double(displayScale)
    )
  }
}

private struct SeriesTitle: View {
  let series: Series

  var body: some View {
    if let title = series.title() {
      Text(verbatim: title)
    } else {
      Text(verbatim: "\(String(localized: "Series ID")) \(series.id.rawValue)")
    }
  }
}

private struct SeriesMetadata: View {
  let series: Series

  var body: some View {
    let values = [series.typeTitle, series.year.map(String.init), series.season]
      .compactMap(\.self)
    if values.isEmpty {
      Text("Catalogue metadata unavailable")
        .font(.caption)
        .foregroundStyle(.white.opacity(0.5))
    } else {
      Text(verbatim: values.joined(separator: " · "))
        .font(.caption)
        .foregroundStyle(.white.opacity(0.62))
    }
  }
}

private struct EpisodeTitle: View {
  let episode: Episode

  var body: some View {
    if let title = episode.title, !title.isEmpty {
      Text(verbatim: title)
    } else if let fullLabel = episode.fullLabel, !fullLabel.isEmpty {
      Text(verbatim: fullLabel)
    } else {
      Text(verbatim: "\(String(localized: "Episode ID")) \(episode.id.rawValue)")
    }
  }
}

private struct TranslationTitle: View {
  let translation: MiraioDomain.Translation

  var body: some View {
    let values = [translation.authors, translation.type, translation.language, translation.quality]
      .compactMap(\.self)
    if values.isEmpty {
      Text(verbatim: "\(String(localized: "Translation ID")) \(translation.id.rawValue)")
    } else {
      Text(verbatim: values.joined(separator: " · "))
        .multilineTextAlignment(.leading)
    }
  }
}

private struct CatalogueNoticeView: View {
  let notice: CatalogueNotice

  var body: some View {
    Label {
      switch notice {
      case .refreshing:
        Text("Showing saved Catalogue data while one refresh runs.")
      case .visiblyStale:
        Text("Catalogue refresh failed. Older saved Series are preserved.")
      case .partialFailure:
        Text("Some Catalogue data is unavailable. Valid Series are preserved.")
      case .offline:
        Text("You’re offline. Usable saved Catalogue data remains available.")
      }
    } icon: {
      Image(systemName: notice == .refreshing ? "arrow.clockwise" : "wifi.exclamationmark")
    }
    .font(.callout)
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.black.opacity(0.46), in: RoundedRectangle(cornerRadius: 12))
    .accessibilityAddTraits(.isStaticText)
  }
}

private struct EmptyCatalogueView: View {
  var body: some View {
    ContentUnavailableView(
      "Catalogue Unavailable",
      systemImage: "rectangle.grid.2x2",
      description: Text("No usable snapshot is available. Refresh when you’re online.")
    )
    .foregroundStyle(.white)
    .frame(maxWidth: .infinity, minHeight: 240)
  }
}

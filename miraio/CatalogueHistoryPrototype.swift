//
//  CatalogueHistoryPrototype.swift
//  miraio
//
//  THROWAWAY PROTOTYPE: three native macOS information-architecture variants.
//  Question: how should Catalogue discovery, Series/Episode traversal,
//  Translation choice, and profile-specific Watch History fit together?
//  Keep this work on prototype/catalogue-watch-history-ia; do not ship it.
//

import SwiftUI

private enum IAPrototypeVariant: String, CaseIterable, Identifiable {
    case sourceList = "A"
    case columnBrowser = "B"
    case dashboardInspector = "C"

    var id: Self { self }

    var name: String {
        switch self {
        case .sourceList: "Source list + destination"
        case .columnBrowser: "Catalogue column browser"
        case .dashboardInspector: "Dashboard + inspector"
        }
    }
}

private enum IAPrototypeScenario: String, CaseIterable, Identifiable {
    case catalogue
    case search
    case series
    case history
    case stale
    case unavailable

    var id: Self { self }

    var name: String {
        switch self {
        case .catalogue: "Catalogue"
        case .search: "Search"
        case .series: "Series → Episode"
        case .history: "Watch History"
        case .stale: "Stale Catalogue"
        case .unavailable: "Unavailable History Entry"
        }
    }

    var symbol: String {
        switch self {
        case .catalogue: "rectangle.grid.2x2"
        case .search: "magnifyingglass"
        case .series: "list.bullet.rectangle.portrait"
        case .history: "clock.arrow.circlepath"
        case .stale: "wifi.exclamationmark"
        case .unavailable: "questionmark.folder"
        }
    }
}

private enum HistoryFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case resumable = "Continue"
    case completed = "Completed"

    var id: Self { self }
}

private struct PrototypeSeries: Identifiable, Hashable {
    let id: Int
    let name: String
    let subtitle: String
    let detail: String
    let tint: Color
    let episodes: [PrototypeEpisode]
}

private struct PrototypeEpisode: Identifiable, Hashable {
    let id: Int
    let number: Int
    let name: String
    let duration: String
    let translations: [String]
}

private struct PrototypeHistoryEntry: Identifiable {
    let id: Int
    let seriesID: Int
    let seriesName: String?
    let episodeID: Int
    let episodeLabel: String?
    let progress: Double?
    let lastPlayed: String
    let completed: Bool
    let tint: Color
}

private enum PrototypeData {
    static let series: [PrototypeSeries] = [
        PrototypeSeries(
            id: 101,
            name: "Frieren: Beyond Journey’s End",
            subtitle: "Fantasy · Adventure",
            detail: "After the party defeats the Demon King, an elven mage begins to understand the brief lives of her companions.",
            tint: .indigo,
            episodes: [
                PrototypeEpisode(id: 10101, number: 1, name: "The Journey’s End", duration: "24 min", translations: ["AniLibria · Russian dub", "JAM · Russian dub", "Original · English subtitles"]),
                PrototypeEpisode(id: 10102, number: 2, name: "It Didn’t Have to Be Magic", duration: "24 min", translations: ["AniLibria · Russian dub", "Original · English subtitles"]),
                PrototypeEpisode(id: 10103, number: 3, name: "Killing Magic", duration: "24 min", translations: ["AniLibria · Russian dub", "JAM · Russian dub", "Original · English subtitles"]),
                PrototypeEpisode(id: 10104, number: 4, name: "The Land Where Souls Rest", duration: "25 min", translations: ["AniLibria · Russian dub", "JAM · Russian dub", "Original · English subtitles"]),
            ]
        ),
        PrototypeSeries(
            id: 102,
            name: "The Apothecary Diaries",
            subtitle: "Mystery · Drama",
            detail: "A sharp-eyed apothecary solves mysteries inside the imperial palace.",
            tint: .green,
            episodes: [
                PrototypeEpisode(id: 10207, number: 7, name: "Homecoming", duration: "23 min", translations: ["AniDub · Russian dub", "Original · English subtitles"]),
                PrototypeEpisode(id: 10208, number: 8, name: "Wheat Stalks", duration: "23 min", translations: ["AniDub · Russian dub", "Original · English subtitles"]),
            ]
        ),
        PrototypeSeries(
            id: 103,
            name: "Delicious in Dungeon",
            subtitle: "Fantasy · Comedy",
            detail: "An adventuring party cooks its way through a dangerous underground kingdom.",
            tint: .orange,
            episodes: [
                PrototypeEpisode(id: 10301, number: 1, name: "Hot Pot / Tart", duration: "26 min", translations: ["Studio Band · Russian dub", "Original · English subtitles"]),
                PrototypeEpisode(id: 10302, number: 2, name: "Roast Basilisk", duration: "25 min", translations: ["Studio Band · Russian dub", "Original · English subtitles"]),
            ]
        ),
        PrototypeSeries(
            id: 104,
            name: "Odd Taxi",
            subtitle: "Mystery · Crime",
            detail: "A solitary taxi driver becomes entangled in a missing-person case.",
            tint: .blue,
            episodes: [
                PrototypeEpisode(id: 10412, number: 12, name: "Not Enough", duration: "24 min", translations: ["JAM · Russian dub", "Original · English subtitles"]),
                PrototypeEpisode(id: 10413, number: 13, name: "Where To?", duration: "24 min", translations: ["JAM · Russian dub", "Original · English subtitles"]),
            ]
        ),
        PrototypeSeries(
            id: 105,
            name: "Pluto",
            subtitle: "Science Fiction · Mystery",
            detail: "A detective investigates a chain of murders connecting humans and the world’s most advanced robots.",
            tint: .purple,
            episodes: [
                PrototypeEpisode(id: 10501, number: 1, name: "Episode 1", duration: "71 min", translations: ["AniLibria · Russian dub", "Original · English subtitles"]),
            ]
        ),
        PrototypeSeries(
            id: 106,
            name: "Vinland Saga",
            subtitle: "Historical · Drama",
            detail: "A young warrior’s pursuit of vengeance changes across a brutal age.",
            tint: .brown,
            episodes: [
                PrototypeEpisode(id: 10601, number: 1, name: "Somewhere Not Here", duration: "29 min", translations: ["AniLibria · Russian dub", "Original · English subtitles"]),
            ]
        ),
    ]

    static let history: [PrototypeHistoryEntry] = [
        PrototypeHistoryEntry(id: 1, seriesID: 101, seriesName: "Frieren: Beyond Journey’s End", episodeID: 10104, episodeLabel: "Episode 4 · The Land Where Souls Rest", progress: 0.31, lastPlayed: "8 minutes ago", completed: false, tint: .indigo),
        PrototypeHistoryEntry(id: 2, seriesID: 102, seriesName: "The Apothecary Diaries", episodeID: 10208, episodeLabel: "Episode 8 · Wheat Stalks", progress: 0.74, lastPlayed: "Yesterday", completed: false, tint: .green),
        PrototypeHistoryEntry(id: 3, seriesID: 104, seriesName: "Odd Taxi", episodeID: 10413, episodeLabel: "Episode 13 · Where To?", progress: nil, lastPlayed: "Tuesday", completed: true, tint: .blue),
        PrototypeHistoryEntry(id: 4, seriesID: 917, seriesName: nil, episodeID: 91742, episodeLabel: nil, progress: 0.42, lastPlayed: "Last week", completed: false, tint: .gray),
    ]
}

struct CatalogueHistoryPrototype: View {
    @State private var variant: IAPrototypeVariant
    @State private var scenario: IAPrototypeScenario
    @State private var searchText = "frieren"
    @State private var selectedSeriesID = 101
    @State private var selectedEpisodeID = 10104
    @State private var translation = "AniLibria · Russian dub"
    @State private var historyFilter = HistoryFilter.all
    @State private var dashboardMode: IAPrototypeScenario = .catalogue
    @State private var isInspectorPresented = true

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let requestedVariant = Self.argument(after: "--prototype-variant", in: arguments)
        let requestedScenario = Self.argument(after: "--prototype-scenario", in: arguments)
        let initialScenario = IAPrototypeScenario(rawValue: requestedScenario ?? "") ?? .catalogue
        _variant = State(initialValue: IAPrototypeVariant(rawValue: requestedVariant ?? "") ?? .sourceList)
        _scenario = State(initialValue: initialScenario)
        _dashboardMode = State(initialValue: initialScenario == .history || initialScenario == .unavailable ? .history : .catalogue)
    }

    var body: some View {
        VStack(spacing: 0) {
            prototypeBanner

            Group {
                switch variant {
                case .sourceList:
                    sourceListVariant
                case .columnBrowser:
                    columnBrowserVariant
                case .dashboardInspector:
                    dashboardInspectorVariant
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            stateReadout
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            variantSwitcher
                .padding(.bottom, 10)
        }
        .onChange(of: scenario) { _, newValue in
            switch newValue {
            case .catalogue, .search, .series, .stale:
                dashboardMode = .catalogue
            case .history, .unavailable:
                dashboardMode = .history
            }
        }
    }

    private static func argument(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    private var selectedSeries: PrototypeSeries {
        PrototypeData.series.first(where: { $0.id == selectedSeriesID }) ?? PrototypeData.series[0]
    }

    private var selectedEpisode: PrototypeEpisode {
        selectedSeries.episodes.first(where: { $0.id == selectedEpisodeID }) ?? selectedSeries.episodes[0]
    }

    private var primarySource: IAPrototypeScenario {
        switch scenario {
        case .catalogue, .series, .stale: .catalogue
        case .search: .search
        case .history, .unavailable: .history
        }
    }

    private var primarySourceBinding: Binding<IAPrototypeScenario> {
        Binding(
            get: { dashboardMode },
            set: { newValue in
                dashboardMode = newValue
                scenario = newValue
            }
        )
    }

    private var prototypeBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "hammer.fill")
            Text("THROWAWAY INFORMATION-ARCHITECTURE PROTOTYPE")
                .font(.caption.weight(.bold))
            Divider().frame(height: 14)
            Text("Scenario controls are prototype chrome, not proposed app UI")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Picker("Scenario", selection: $scenario) {
                ForEach(IAPrototypeScenario.allCases) { scenario in
                    Label(scenario.name, systemImage: scenario.symbol).tag(scenario)
                }
            }
            .labelsHidden()
            .frame(width: 230)
            Text("⌥⌘← / ⌥⌘→ changes variant")
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(.yellow.opacity(0.13))
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: - Variant A: familiar top-level destinations

    private var sourceListVariant: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Miraio")
                        .font(.title2.weight(.semibold))
                    Label("Subscriber", systemImage: "person.crop.circle.badge.checkmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)

                VStack(spacing: 2) {
                    sourceButton(.catalogue)
                    sourceButton(.search)
                    sourceButton(.history)
                }

                Spacer()

                Button("Profile & Subscription", systemImage: "person.crop.circle") {}
                    .buttonStyle(.plain)
                    .padding(14)
            }
            .padding(.top, 16)
            .frame(width: 220)
            .background(.bar)

            Divider()

            sourceListDestination
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func sourceButton(_ destination: IAPrototypeScenario) -> some View {
        Button {
            scenario = destination
        } label: {
            Label(destination.name, systemImage: destination.symbol)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(primarySource == destination ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var sourceListDestination: some View {
        switch scenario {
        case .catalogue:
            catalogueGrid(title: "Catalogue", subtitle: "Browse Series available through Anime365")
        case .search:
            searchDestination
        case .series:
            seriesDestination
        case .history:
            historyDestination
        case .stale:
            VStack(spacing: 0) {
                staleBanner
                catalogueGrid(title: "Catalogue", subtitle: "Saved snapshot · refresh currently unavailable")
            }
        case .unavailable:
            unavailableHistoryDestination
        }
    }

    // MARK: - Variant B: Finder-style simultaneous hierarchy

    private var columnBrowserVariant: some View {
        VStack(spacing: 0) {
            if scenario == .stale { staleBanner }

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Search Catalogue", text: $searchText)
                        .textFieldStyle(.roundedBorder)

                    Picker("Source", selection: primarySourceBinding) {
                        Text("Catalogue").tag(IAPrototypeScenario.catalogue)
                        Text("Watch History").tag(IAPrototypeScenario.history)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    if scenario == .unavailable {
                        browserUnavailableEntry
                    } else if dashboardMode == .history || scenario == .history {
                        browserHistoryEntries
                    } else {
                        browserSeriesList
                    }

                    Spacer()
                }
                .padding(12)
                .frame(width: 255)
                .background(.bar)

                Divider()

                browserEpisodeColumn
                    .frame(width: 300)

                Divider()

                episodeDetail(heading: "Episode selection")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: selectedSeriesID) { _, _ in
            selectedEpisodeID = selectedSeries.episodes[0].id
            translation = selectedSeries.episodes[0].translations[0]
        }
    }

    private var browserSeriesList: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(filteredSeries) { series in
                    Button {
                        select(series)
                        scenario = .series
                    } label: {
                        HStack(spacing: 9) {
                            posterSwatch(series, width: 38, height: 54)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(series.name).lineLimit(2)
                                Text(series.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(6)
                        .background(selectedSeriesID == series.id ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var browserHistoryEntries: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(PrototypeData.history.filter { $0.seriesName != nil }) { entry in
                    Button {
                        if let series = PrototypeData.series.first(where: { $0.id == entry.seriesID }) {
                            select(series)
                            if series.episodes.contains(where: { $0.id == entry.episodeID }) {
                                selectedEpisodeID = entry.episodeID
                            }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(entry.seriesName ?? "Unavailable Series")
                                .lineLimit(2)
                            Text(entry.episodeLabel ?? "Episode \(entry.episodeID)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let progress = entry.progress { ProgressView(value: progress) }
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var browserUnavailableEntry: some View {
        Button {
            scenario = .unavailable
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                Label("Catalogue details unavailable", systemImage: "questionmark.folder")
                    .font(.headline)
                Text("Episode 91742 · 42% watched")
                    .foregroundStyle(.secondary)
                ProgressView(value: 0.42)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private var browserEpisodeColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text(selectedSeries.name)
                    .font(.headline)
                    .lineLimit(2)
                Text("Episodes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)

            Divider()

            List(selectedSeries.episodes, selection: $selectedEpisodeID) { episode in
                Button {
                    selectedEpisodeID = episode.id
                    translation = episode.translations[0]
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Episode \(episode.number)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(episode.name)
                        Text(episode.duration)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .tag(episode.id)
            }
            .listStyle(.sidebar)
        }
    }

    // MARK: - Variant C: returnable dashboard with on-demand inspector

    private var dashboardInspectorVariant: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text("Miraio")
                        .font(.title2.weight(.semibold))

                    Picker("Destination", selection: primarySourceBinding) {
                        Text("Discover").tag(IAPrototypeScenario.catalogue)
                        Text("Watch History").tag(IAPrototypeScenario.history)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 240)

                    Spacer()

                    TextField("Search Catalogue", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)

                    Button(isInspectorPresented ? "Hide Inspector" : "Show Inspector", systemImage: "sidebar.right") {
                        isInspectorPresented.toggle()
                    }
                }
                .padding(14)
                .background(.bar)

                if scenario == .stale { staleBanner }

                ScrollView {
                    if scenario == .unavailable {
                        unavailableHistoryDestination
                    } else if dashboardMode == .history || scenario == .history {
                        dashboardHistory
                    } else {
                        dashboardDiscover
                    }
                }
            }

            if isInspectorPresented {
                Divider()
                Group {
                    if scenario == .unavailable {
                        dashboardUnavailableInspector
                    } else {
                        dashboardInspector
                    }
                }
                    .frame(width: 340)
            }
        }
        .animation(.easeOut(duration: 0.16), value: isInspectorPresented)
    }

    private var dashboardDiscover: some View {
        VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Continue watching")
                    .font(.title2.weight(.semibold))
                HStack(spacing: 12) {
                    ForEach(PrototypeData.history.prefix(2)) { entry in
                        compactHistoryCard(entry)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(scenario == .search ? "Search results" : "Explore the Catalogue")
                        .font(.title2.weight(.semibold))
                    Spacer()
                    if scenario == .search {
                        Text("Server-backed title search")
                            .foregroundStyle(.secondary)
                    }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 14)], spacing: 16) {
                    ForEach(filteredSeries) { series in
                        Button {
                            select(series)
                            scenario = .series
                            isInspectorPresented = true
                        } label: {
                            seriesCard(series)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(22)
    }

    private var dashboardHistory: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Watch History")
                        .font(.largeTitle.weight(.semibold))
                    Text("Stored locally for this Anime365 Profile")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                historyFilterPicker
            }

            ForEach(filteredHistory) { entry in
                Button {
                    if let series = PrototypeData.series.first(where: { $0.id == entry.seriesID }) {
                        select(series)
                        if series.episodes.contains(where: { $0.id == entry.episodeID }) {
                            selectedEpisodeID = entry.episodeID
                        }
                        isInspectorPresented = true
                    } else {
                        scenario = .unavailable
                    }
                } label: {
                    historyRow(entry)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(22)
    }

    private var dashboardInspector: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Now selected")
                    .font(.headline)
                Spacer()
                Button("Close", systemImage: "xmark") { isInspectorPresented = false }
                    .labelStyle(.iconOnly)
            }

            posterSwatch(selectedSeries, width: 128, height: 176)
                .frame(maxWidth: .infinity)

            Text(selectedSeries.name)
                .font(.title2.weight(.semibold))
            Text(selectedSeries.detail)
                .foregroundStyle(.secondary)

            Divider()

            Picker("Episode", selection: $selectedEpisodeID) {
                ForEach(selectedSeries.episodes) { episode in
                    Text("Episode \(episode.number) · \(episode.name)").tag(episode.id)
                }
            }

            translationPicker

            Button("Watch Episode \(selectedEpisode.number)", systemImage: "play.fill") {}
                .buttonStyle(.borderedProminent)

            Text("Playback opens as the native player and returns here without losing browse context.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var dashboardUnavailableInspector: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Watch History Entry")
                    .font(.headline)
                Spacer()
                Button("Close", systemImage: "xmark") { isInspectorPresented = false }
                    .labelStyle(.iconOnly)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.gray.gradient)
                Image(systemName: "questionmark.folder")
                    .font(.system(size: 38))
                    .foregroundStyle(.white)
            }
            .frame(width: 180, height: 116)
            .frame(maxWidth: .infinity)

            Text("Catalogue details unavailable")
                .font(.title2.weight(.semibold))
            Text("Episode 91742")
                .font(.title3)
            ProgressView(value: 0.42)
            Text("42% watched · last played last week")
                .foregroundStyle(.secondary)

            Divider()

            Label("No current Series name, poster, Episode label, or Translation can be attached.", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Retry Catalogue Refresh", systemImage: "arrow.clockwise") {}
                .buttonStyle(.borderedProminent)

            Menu("More", systemImage: "ellipsis.circle") {
                Button("Remove from Watch History", systemImage: "trash", role: .destructive) {}
            }

            Spacer()
        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Shared scenario surfaces (content, not shared layout)

    private var filteredSeries: [PrototypeSeries] {
        guard scenario == .search, !searchText.isEmpty else { return PrototypeData.series }
        let query = searchText.lowercased()
        return PrototypeData.series.filter { $0.name.lowercased().contains(query) || $0.subtitle.lowercased().contains(query) }
    }

    private var filteredHistory: [PrototypeHistoryEntry] {
        switch historyFilter {
        case .all: PrototypeData.history
        case .resumable: PrototypeData.history.filter { $0.progress != nil }
        case .completed: PrototypeData.history.filter(\.completed)
        }
    }

    private func select(_ series: PrototypeSeries) {
        selectedSeriesID = series.id
        selectedEpisodeID = series.episodes[0].id
        translation = series.episodes[0].translations[0]
    }

    private func catalogueGrid(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            destinationHeader(title, subtitle: subtitle) {
                TextField("Search Catalogue", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
            }

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 16)], spacing: 18) {
                    ForEach(PrototypeData.series) { series in
                        Button {
                            select(series)
                            scenario = .series
                        } label: {
                            seriesCard(series)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)

                Button("Load more", systemImage: "arrow.down.circle") {}
                    .padding(.bottom, 22)
            }
        }
    }

    private var searchDestination: some View {
        VStack(alignment: .leading, spacing: 0) {
            destinationHeader("Search", subtitle: "Anime365 server-backed title search") {
                TextField("Series title", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 300)
                    .onSubmit { scenario = .search }
            }

            if filteredSeries.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Loaded results for “\(searchText)”")
                            .foregroundStyle(.secondary)
                        ForEach(filteredSeries) { series in
                            Button {
                                select(series)
                                scenario = .series
                            } label: {
                                HStack(spacing: 14) {
                                    posterSwatch(series, width: 62, height: 88)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(series.name).font(.headline)
                                        Text(series.subtitle).foregroundStyle(.secondary)
                                        Text(series.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                                }
                                .padding(10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                    .padding(20)
                }
            }
        }
    }

    private var seriesDestination: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 22) {
                    posterSwatch(selectedSeries, width: 180, height: 250)
                    VStack(alignment: .leading, spacing: 10) {
                        Button("Back to Catalogue", systemImage: "chevron.left") { scenario = .catalogue }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        Text(selectedSeries.name)
                            .font(.largeTitle.weight(.semibold))
                        Text(selectedSeries.subtitle)
                            .foregroundStyle(.secondary)
                        Text(selectedSeries.detail)
                            .frame(maxWidth: 520, alignment: .leading)
                    }
                }

                Divider()

                Text("Episodes")
                    .font(.title2.weight(.semibold))

                ForEach(selectedSeries.episodes) { episode in
                    episodeRow(episode)
                }
            }
            .padding(24)
        }
    }

    private var historyDestination: some View {
        VStack(alignment: .leading, spacing: 0) {
            destinationHeader("Watch History", subtitle: "Canonical local progress for this Anime365 Profile") {
                historyFilterPicker
            }
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(filteredHistory) { entry in
                        Button {
                            if let series = PrototypeData.series.first(where: { $0.id == entry.seriesID }) {
                                select(series)
                                if series.episodes.contains(where: { $0.id == entry.episodeID }) {
                                    selectedEpisodeID = entry.episodeID
                                }
                                scenario = .series
                            } else {
                                scenario = .unavailable
                            }
                        } label: {
                            historyRow(entry)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
        }
    }

    private var unavailableHistoryDestination: some View {
        VStack(spacing: 18) {
            Image(systemName: "questionmark.folder")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Catalogue details unavailable")
                .font(.title2.weight(.semibold))
            Text("Episode 91742 is still kept in this Anime365 Profile’s Watch History at 42%. Miraio has no current Catalogue title, poster, or Translation data to attach to it.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 520)
            ProgressView(value: 0.42)
                .frame(width: 280)
            HStack {
                Button("Retry Catalogue Refresh", systemImage: "arrow.clockwise") {}
                    .buttonStyle(.borderedProminent)
                Menu("More", systemImage: "ellipsis.circle") {
                    Button("Remove from Watch History", systemImage: "trash", role: .destructive) {}
                }
            }
            Text("Detailed recovery timing and messages remain a separate Wayfinder decision.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }

    private var staleBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
            VStack(alignment: .leading, spacing: 2) {
                Text("Showing a saved Catalogue snapshot")
                    .font(.callout.weight(.semibold))
                Text("Last refreshed 12 minutes ago. A refresh failed; saved Series remain usable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Try Again", systemImage: "arrow.clockwise") {}
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
        .background(.orange.opacity(0.13))
        .overlay(alignment: .bottom) { Divider() }
    }

    private func destinationHeader<Trailing: View>(
        _ title: String,
        subtitle: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.largeTitle.weight(.semibold))
                Text(subtitle)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            trailing()
        }
        .padding(20)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func seriesCard(_ series: PrototypeSeries) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            posterSwatch(series, width: nil, height: 190)
            Text(series.name)
                .font(.headline)
                .lineLimit(2)
            Text(series.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func posterSwatch(_ series: PrototypeSeries, width: CGFloat?, height: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9)
                .fill(series.tint.gradient)
            VStack(spacing: 8) {
                Image(systemName: "sparkles.tv")
                    .font(.title)
                Text(series.name)
                    .font(.caption.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 8)
            }
            .foregroundStyle(.white)
        }
        .frame(width: width, height: height)
        .accessibilityLabel("Poster placeholder for \(series.name)")
    }

    private func episodeRow(_ episode: PrototypeEpisode) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Episode \(episode.number)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(episode.name)
                    .font(.headline)
                Text(episode.duration)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Picker("Translation", selection: $translation) {
                ForEach(episode.translations, id: \.self) { Text($0) }
            }
            .frame(width: 240)
            Button("Watch", systemImage: "play.fill") {
                selectedEpisodeID = episode.id
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
    }

    private func episodeDetail(heading: String) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(heading)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(selectedSeries.name)
                .font(.title.weight(.semibold))
            Text("Episode \(selectedEpisode.number) · \(selectedEpisode.name)")
                .font(.title3)
            Text(selectedSeries.detail)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 540, alignment: .leading)

            Divider()
            translationPicker

            Button("Watch Episode \(selectedEpisode.number)", systemImage: "play.fill") {}
                .buttonStyle(.borderedProminent)

            Text("The player takes over only after an Episode and Translation are chosen.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(24)
    }

    private var translationPicker: some View {
        Picker("Translation", selection: $translation) {
            ForEach(selectedEpisode.translations, id: \.self) { Text($0) }
        }
        .frame(maxWidth: 360)
    }

    private var historyFilterPicker: some View {
        Picker("History filter", selection: $historyFilter) {
            ForEach(HistoryFilter.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 260)
    }

    private func historyRow(_ entry: PrototypeHistoryEntry) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 8)
                .fill(entry.tint.gradient)
                .frame(width: 92, height: 58)
                .overlay {
                    Image(systemName: entry.seriesName == nil ? "questionmark" : "play.rectangle")
                        .font(.title2)
                        .foregroundStyle(.white)
                }
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.seriesName ?? "Catalogue details unavailable")
                    .font(.headline)
                Text(entry.episodeLabel ?? "Episode \(entry.episodeID)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let progress = entry.progress {
                    ProgressView(value: progress)
                        .frame(maxWidth: 360)
                } else if entry.completed {
                    Label("Previously completed", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(entry.lastPlayed)
                .font(.caption)
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
    }

    private func compactHistoryCard(_ entry: PrototypeHistoryEntry) -> some View {
        Button {
            dashboardMode = .history
            scenario = entry.seriesName == nil ? .unavailable : .history
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(entry.tint.gradient)
                    .frame(height: 84)
                    .overlay { Image(systemName: "play.fill").font(.title2).foregroundStyle(.white) }
                Text(entry.seriesName ?? "Unavailable Series")
                    .font(.headline)
                    .lineLimit(1)
                Text(entry.episodeLabel ?? "Episode \(entry.episodeID)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let progress = entry.progress { ProgressView(value: progress) }
            }
            .frame(width: 250, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Prototype chrome

    private var stateReadout: some View {
        VStack(spacing: 0) {
            Divider()
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 13) {
                    Label("Full prototype state", systemImage: "waveform.path.ecg")
                        .font(.caption.weight(.semibold))
                    Text("Scenario: \(scenario.name)")
                    Text("Anime365ProfileID: 1042")
                    Text("Catalogue: \(scenario == .stale ? "stale snapshot" : scenario == .unavailable ? "metadata unavailable" : "fresh")")
                    Text("Watch History: local canonical")
                    Spacer()
                }
                HStack(spacing: 13) {
                    Text("SeriesID: \(scenario == .unavailable ? "917" : String(selectedSeries.id))")
                    Text("EpisodeID: \(scenario == .unavailable ? "91742" : String(selectedEpisode.id))")
                    Text("Translation: \(scenario == .unavailable ? "unavailable" : translation)")
                    Spacer()
                }
            }
            .font(.caption.monospaced())
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(.bar)
        }
    }

    private var variantSwitcher: some View {
        HStack(spacing: 10) {
            Button {
                cycleVariant(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command, .option])

            Text("\(variant.rawValue) · \(variant.name)")
                .font(.callout.weight(.semibold))
                .frame(minWidth: 250)

            Button {
                cycleVariant(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(.black.opacity(0.88), in: Capsule())
        .foregroundStyle(.white)
        .shadow(radius: 12, y: 5)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Prototype variant switcher")
    }

    private func cycleVariant(by offset: Int) {
        let variants = IAPrototypeVariant.allCases
        guard let current = variants.firstIndex(of: variant) else { return }
        variant = variants[(current + offset + variants.count) % variants.count]
    }
}

#Preview {
    CatalogueHistoryPrototype()
        .frame(width: 1_200, height: 800)
}

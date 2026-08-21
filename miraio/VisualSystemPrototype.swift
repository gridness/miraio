//
//  VisualSystemPrototype.swift
//  miraio
//
//  THROWAWAY PROTOTYPE: three app-wide macOS visual-system candidates.
//  Question: how should Miraio use Liquid Glass, type, color, material, and
//  motion across its fixed navigation, content, inspector, auth, and player?
//  Keep this work on prototype/macos-visual-system; do not ship it.
//

import SwiftUI

private enum VisualVariant: String, CaseIterable, Identifiable {
    case quietNative = "A"
    case cinematicCanvas = "B"
    case editorialUtility = "C"

    var id: Self { self }

    var name: String {
        switch self {
        case .quietNative: "Quiet native"
        case .cinematicCanvas: "Cinematic canvas"
        case .editorialUtility: "Editorial utility"
        }
    }

    var glassRule: String {
        switch self {
        case .quietNative: "System navigation + transient controls"
        case .cinematicCanvas: "Floating navigation + media controls"
        case .editorialUtility: "System controls only"
        }
    }
}

private enum VisualScreen: String, CaseIterable, Identifiable {
    case catalogue
    case search
    case series
    case history
    case authentication
    case playback

    var id: Self { self }

    var symbol: String {
        switch self {
        case .catalogue: "rectangle.grid.2x2"
        case .search: "magnifyingglass"
        case .series: "sidebar.right"
        case .history: "clock.arrow.circlepath"
        case .authentication: "person.crop.circle.badge.checkmark"
        case .playback: "play.rectangle.fill"
        }
    }
}

private enum PrototypeLanguage: String, CaseIterable, Identifiable {
    case english = "EN"
    case russian = "RU"

    var id: Self { self }
}

private struct VisualSeries: Identifiable {
    let id: Int
    let title: String
    let subtitleEN: String
    let subtitleRU: String
    let episodeEN: String
    let episodeRU: String
    let progress: Double?
    let palette: [Color]
    let symbol: String
}

private enum VisualData {
    static let series = [
        VisualSeries(
            id: 101,
            title: "Frieren: Beyond Journey’s End",
            subtitleEN: "Fantasy · Adventure",
            subtitleRU: "Фэнтези · Приключения",
            episodeEN: "Episode 4 · The Land Where Souls Rest",
            episodeRU: "Серия 4 · Земля, где покоятся души",
            progress: 0.31,
            palette: [.indigo, .cyan.opacity(0.72)],
            symbol: "sparkles"
        ),
        VisualSeries(
            id: 102,
            title: "The Apothecary Diaries",
            subtitleEN: "Mystery · Drama",
            subtitleRU: "Детектив · Драма",
            episodeEN: "Episode 8 · Wheat Stalks",
            episodeRU: "Серия 8 · Колосья пшеницы",
            progress: 0.74,
            palette: [.green.opacity(0.88), .yellow.opacity(0.68)],
            symbol: "leaf.fill"
        ),
        VisualSeries(
            id: 103,
            title: "Delicious in Dungeon",
            subtitleEN: "Fantasy · Comedy",
            subtitleRU: "Фэнтези · Комедия",
            episodeEN: "Episode 2 · Roast Basilisk",
            episodeRU: "Серия 2 · Жареный василиск",
            progress: nil,
            palette: [.orange, .pink.opacity(0.76)],
            symbol: "fork.knife"
        ),
        VisualSeries(
            id: 104,
            title: "Odd Taxi",
            subtitleEN: "Mystery · Crime",
            subtitleRU: "Детектив · Криминал",
            episodeEN: "Episode 13 · Where To?",
            episodeRU: "Серия 13 · Куда ехать?",
            progress: 1,
            palette: [.blue.opacity(0.88), .purple.opacity(0.78)],
            symbol: "car.side.fill"
        ),
        VisualSeries(
            id: 105,
            title: "Pluto",
            subtitleEN: "Science Fiction · Mystery",
            subtitleRU: "Научная фантастика · Детектив",
            episodeEN: "Episode 1",
            episodeRU: "Серия 1",
            progress: nil,
            palette: [.purple.opacity(0.88), .black.opacity(0.8)],
            symbol: "atom"
        ),
        VisualSeries(
            id: 106,
            title: "Vinland Saga",
            subtitleEN: "Historical · Drama",
            subtitleRU: "Исторический · Драма",
            episodeEN: "Episode 1 · Somewhere Not Here",
            episodeRU: "Серия 1 · Где-то не здесь",
            progress: nil,
            palette: [.brown, .orange.opacity(0.72)],
            symbol: "sailboat.fill"
        ),
    ]
}

struct VisualSystemPrototype: View {
    @State private var variant: VisualVariant
    @State private var screen: VisualScreen
    @State private var language: PrototypeLanguage
    @State private var reduceMotion = false
    @State private var increaseContrast = false
    @State private var selectedSeriesID = 101
    @State private var historyFilter = 0
    @State private var translation = "AniLibria · Russian dub"
    @State private var isPlaybackHUDVisible = true
    @State private var isPlaybackInspectorVisible = false
    @State private var searchText = "frieren"

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let requestedVariant = Self.argument(after: "--prototype-variant", in: arguments)
        let requestedScreen = Self.argument(after: "--prototype-screen", in: arguments)
        let requestedLanguage = Self.argument(after: "--prototype-language", in: arguments)
        _variant = State(initialValue: VisualVariant(rawValue: requestedVariant ?? "") ?? .quietNative)
        _screen = State(initialValue: VisualScreen(rawValue: requestedScreen ?? "") ?? .catalogue)
        _language = State(initialValue: PrototypeLanguage(rawValue: requestedLanguage?.uppercased() ?? "") ?? .english)
    }

    var body: some View {
        VStack(spacing: 0) {
            prototypeControls

            Group {
                switch variant {
                case .quietNative:
                    quietNativeRoot
                case .cinematicCanvas:
                    cinematicCanvasRoot
                case .editorialUtility:
                    editorialUtilityRoot
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
    }

    private static func argument(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    private var selectedSeries: VisualSeries {
        VisualData.series.first(where: { $0.id == selectedSeriesID }) ?? VisualData.series[0]
    }

    private func copy(_ english: String, _ russian: String) -> String {
        language == .english ? english : russian
    }

    private func screenName(_ value: VisualScreen) -> String {
        switch value {
        case .catalogue: copy("Catalogue", "Каталог")
        case .search: copy("Search", "Поиск")
        case .series: copy("Series inspector", "Инспектор сериала")
        case .history: copy("Watch History", "История просмотров")
        case .authentication: copy("Authentication", "Вход")
        case .playback: copy("Playback", "Просмотр")
        }
    }

    private var prototypeControls: some View {
        HStack(spacing: 10) {
            Label("THROWAWAY VISUAL-SYSTEM PROTOTYPE", systemImage: "paintbrush.pointed.fill")
                .font(.caption.weight(.bold))
            Divider().frame(height: 16)

            Picker("Screen", selection: $screen) {
                ForEach(VisualScreen.allCases) { value in
                    Label(screenName(value), systemImage: value.symbol).tag(value)
                }
            }
            .labelsHidden()
            .frame(width: 210)

            Picker("Language", selection: $language) {
                ForEach(PrototypeLanguage.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 86)

            Toggle(copy("Reduce motion", "Меньше движения"), isOn: $reduceMotion)
                .toggleStyle(.checkbox)
            Toggle(copy("Increase contrast", "Выше контраст"), isOn: $increaseContrast)
                .toggleStyle(.checkbox)

            Spacer()
            Text("⌥⌘← / ⌥⌘→")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(.yellow.opacity(0.15))
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: - A · Quiet native

    private var quietNativeRoot: some View {
        NavigationSplitView {
            sidebarContents(compact: false)
                .navigationSplitViewColumnWidth(min: 190, ideal: 216, max: 245)
        } detail: {
            HStack(spacing: 0) {
                quietNativeDestination
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if screen == .series {
                    Divider()
                    quietInspector
                        .frame(width: 330)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var quietNativeDestination: some View {
        Group {
            switch screen {
            case .catalogue, .series:
                quietCatalogue
            case .search:
                quietSearch
            case .history:
                quietHistory
            case .authentication:
                authSurface(mode: .quiet)
            case .playback:
                playbackSurface(mode: .quiet)
            }
        }
    }

    private var quietCatalogue: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(copy("Catalogue", "Каталог"))
                            .font(.largeTitle.weight(.semibold))
                        Text(copy("Series available through Anime365", "Сериалы, доступные через Anime365"))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(copy("Refresh", "Обновить"), systemImage: "arrow.clockwise") { }
                }

                sectionHeading(copy("Continue Watching", "Продолжить просмотр"), trailing: copy("From local Watch History", "Из локальной истории просмотров"))
                HStack(spacing: 14) {
                    ForEach(VisualData.series.prefix(2)) { series in
                        quietContinueCard(series)
                    }
                }

                sectionHeading(copy("Explore the Catalogue", "Открывайте каталог"), trailing: copy("Recently updated", "Недавно обновлено"))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 18)], spacing: 22) {
                    ForEach(VisualData.series) { series in
                        Button { open(series) } label: { quietPosterCard(series) }
                            .buttonStyle(.plain)
                    }
                }
            }
            .padding(28)
        }
    }

    private var quietSearch: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(copy("Search the Catalogue", "Поиск по каталогу"))
                .font(.largeTitle.weight(.semibold))
            TextField(copy("Series title", "Название сериала"), text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 520)

            Text(copy("Loaded results for “\(searchText)”", "Результаты для «\(searchText)»"))
                .foregroundStyle(.secondary)

            ForEach(VisualData.series.prefix(3)) { series in
                Button { open(series) } label: {
                    HStack(spacing: 14) {
                        poster(series, width: 60, height: 84, radius: 10)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(series.title).font(.headline)
                            Text(copy(series.subtitleEN, series.subtitleRU)).foregroundStyle(.secondary)
                            Text(copy("Exact server-backed Series result", "Точный результат поиска сериала на сервере"))
                                .font(.caption).foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider()
            }
            Spacer()
        }
        .padding(28)
    }

    private var quietHistory: some View {
        VStack(alignment: .leading, spacing: 22) {
            destinationHeading(copy("Watch History", "История просмотров"), copy("Canonical local progress for this Anime365 Profile", "Локальный источник прогресса для этого профиля Anime365")) {
                Picker("History filter", selection: $historyFilter) {
                    Text(copy("All", "Все")).tag(0)
                    Text(copy("Continue", "Продолжить")).tag(1)
                    Text(copy("Completed", "Завершено")).tag(2)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: language == .english ? 280 : 340)
            }

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(VisualData.series.prefix(4)) { series in
                        quietHistoryRow(series)
                    }
                }
            }
            Spacer()
        }
        .padding(28)
    }

    private var quietInspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(copy("Series", "Сериал")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Button { screen = .catalogue } label: { Image(systemName: "xmark") }
                        .buttonStyle(.glass)
                        .accessibilityLabel(copy("Close Series inspector", "Закрыть инспектор сериала"))
                }
                poster(selectedSeries, width: nil, height: 180, radius: 16)
                Text(selectedSeries.title).font(.title2.weight(.semibold))
                Text(copy(selectedSeries.subtitleEN, selectedSeries.subtitleRU)).foregroundStyle(.secondary)
                Divider()
                Text(copy("Episode", "Серия")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(copy(selectedSeries.episodeEN, selectedSeries.episodeRU)).font(.headline)
                Picker(copy("Translation", "Перевод"), selection: $translation) {
                    Text("AniLibria · Russian dub").tag("AniLibria · Russian dub")
                    Text("Original · English subtitles").tag("Original · English subtitles")
                }
                Button(copy("Watch Episode", "Смотреть серию"), systemImage: "play.fill") { screen = .playback }
                    .buttonStyle(.glassProminent)
                    .tint(.indigo)
                    .controlSize(.large)
                Text(copy("Dismissing this inspector preserves the Catalogue position.", "После закрытия инспектора позиция в каталоге сохраняется."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - B · Cinematic canvas

    private var cinematicCanvasRoot: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.06, green: 0.08, blue: 0.15), Color(red: 0.13, green: 0.10, blue: 0.22), Color.black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(selectedSeries.palette[0].opacity(0.28))
                .frame(width: 620, height: 620)
                .blur(radius: 95)
                .offset(x: 330, y: -210)

            HStack(spacing: 18) {
                cinematicSidebar
                    .frame(width: 205)
                    .glassEffect(.regular, in: .rect(cornerRadius: 22))

                cinematicDestination
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if screen == .series {
                    cinematicInspector
                        .frame(width: 340)
                        .glassEffect(.regular, in: .rect(cornerRadius: 24))
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(18)
        }
        .foregroundStyle(.white)
    }

    private var cinematicSidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles.tv.fill").font(.title2)
                Text("Miraio").font(.title2.weight(.semibold))
            }
            .padding(.horizontal, 14)

            VStack(spacing: 5) {
                cinematicSourceButton(.catalogue)
                cinematicSourceButton(.search)
                cinematicSourceButton(.history)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 4) {
                Text("IVAN").font(.caption2.weight(.bold)).tracking(1.2)
                Text(copy("Subscriber", "Подписчик")).font(.caption).foregroundStyle(.white.opacity(0.7))
            }
            .padding(14)
        }
        .padding(.vertical, 16)
    }

    private func cinematicSourceButton(_ value: VisualScreen) -> some View {
        Button { screen = value } label: {
            Label(screenName(value), systemImage: value.symbol)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .frame(minHeight: 34)
                .background(topLevelScreen == value ? .white.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    private var cinematicDestination: some View {
        Group {
            switch screen {
            case .catalogue, .series:
                cinematicCatalogue
            case .search:
                cinematicSearch
            case .history:
                cinematicHistory
            case .authentication:
                authSurface(mode: .cinematic)
            case .playback:
                playbackSurface(mode: .cinematic)
            }
        }
    }

    private var cinematicCatalogue: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 26)
                        .fill(LinearGradient(colors: selectedSeries.palette + [.black.opacity(0.82)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(height: 285)
                        .overlay(alignment: .topTrailing) {
                            Image(systemName: selectedSeries.symbol)
                                .font(.system(size: 126, weight: .ultraLight))
                                .foregroundStyle(.white.opacity(0.18))
                                .padding(34)
                        }

                    VStack(alignment: .leading, spacing: 9) {
                        Text(copy("CONTINUE WATCHING", "ПРОДОЛЖИТЬ ПРОСМОТР"))
                            .font(.caption.weight(.bold)).tracking(1.5).foregroundStyle(.white.opacity(0.72))
                        Text(selectedSeries.title)
                            .font(.system(size: 36, weight: .semibold, design: .rounded))
                        Text(copy(selectedSeries.episodeEN, selectedSeries.episodeRU))
                            .foregroundStyle(.white.opacity(0.78))
                        HStack(spacing: 12) {
                            Button(copy("Resume", "Продолжить"), systemImage: "play.fill") { screen = .playback }
                                .buttonStyle(.glassProminent)
                                .tint(.indigo)
                            ProgressView(value: selectedSeries.progress ?? 0)
                                .frame(width: 180)
                        }
                    }
                    .padding(28)
                }

                HStack(alignment: .firstTextBaseline) {
                    Text(copy("Explore", "Смотрите новое"))
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                    Spacer()
                    Text(copy("Recently updated", "Недавно обновлено"))
                        .font(.caption).foregroundStyle(.white.opacity(0.62))
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(VisualData.series) { series in
                            Button { open(series) } label: { cinematicPosterCard(series) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(12)
        }
    }

    private var cinematicSearch: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(copy("Find a Series", "Найти сериал"))
                .font(.system(size: 36, weight: .semibold, design: .rounded))
            TextField(copy("Series title", "Название сериала"), text: $searchText)
                .textFieldStyle(.plain)
                .font(.title2)
                .padding(.horizontal, 18)
                .frame(height: 52)
                .glassEffect(.regular, in: .rect(cornerRadius: 18))
                .accessibilityLabel(copy("Search Catalogue", "Поиск по каталогу"))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 15)], spacing: 15) {
                ForEach(VisualData.series.prefix(4)) { series in
                    Button { open(series) } label: { cinematicSearchTile(series) }
                        .buttonStyle(.plain)
                }
            }
            Spacer()
        }
        .padding(22)
    }

    private var cinematicHistory: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(copy("Watch History", "История просмотров"))
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                Text(copy("Your local, profile-specific path through the Catalogue", "Ваш локальный путь по каталогу для этого профиля"))
                    .foregroundStyle(.white.opacity(0.68))
                ForEach(VisualData.series.prefix(4)) { series in
                    cinematicHistoryRow(series)
                }
            }
            .padding(22)
        }
    }

    private var cinematicInspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(copy("NOW SELECTING", "ВЫБОР ПРОСМОТРА"))
                        .font(.caption2.weight(.bold)).tracking(1.4).foregroundStyle(.white.opacity(0.62))
                    Spacer()
                    Button { screen = .catalogue } label: { Image(systemName: "xmark") }
                        .buttonStyle(.glass)
                }
                poster(selectedSeries, width: nil, height: 190, radius: 18)
                Text(selectedSeries.title).font(.title2.weight(.semibold))
                Text(copy(selectedSeries.subtitleEN, selectedSeries.subtitleRU)).foregroundStyle(.white.opacity(0.68))
                Divider().overlay(.white.opacity(0.22))
                Text(copy(selectedSeries.episodeEN, selectedSeries.episodeRU)).font(.headline)
                Picker(copy("Translation", "Перевод"), selection: $translation) {
                    Text("AniLibria · Russian dub").tag("AniLibria · Russian dub")
                    Text("Original · English subtitles").tag("Original · English subtitles")
                }
                .colorScheme(.dark)
                Button(copy("Watch", "Смотреть"), systemImage: "play.fill") { screen = .playback }
                    .buttonStyle(.glassProminent)
                    .tint(.indigo)
                    .controlSize(.large)
            }
            .padding(20)
        }
    }

    // MARK: - C · Editorial utility

    private var editorialUtilityRoot: some View {
        HStack(spacing: 0) {
            editorialRail
                .frame(width: 176)

            Rectangle().fill(increaseContrast ? Color.primary.opacity(0.42) : Color.primary.opacity(0.12)).frame(width: 1)

            editorialDestination
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if screen == .series {
                Rectangle().fill(increaseContrast ? Color.primary.opacity(0.42) : Color.primary.opacity(0.12)).frame(width: 1)
                editorialInspector
                    .frame(width: 320)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var editorialRail: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 2) {
                Text("MIRAIO").font(.headline.weight(.black)).tracking(2.4)
                Text(copy("ANIME365 CLIENT", "КЛИЕНТ ANIME365"))
                    .font(.caption2.weight(.medium)).foregroundStyle(.secondary).tracking(1.1)
            }
            .padding(.horizontal, 14)

            VStack(spacing: 2) {
                editorialSourceButton(.catalogue, index: "01")
                editorialSourceButton(.search, index: "02")
                editorialSourceButton(.history, index: "03")
            }
            Spacer()
            Divider()
            VStack(alignment: .leading, spacing: 3) {
                Text(copy("PROFILE", "ПРОФИЛЬ")).font(.caption2.weight(.bold)).tracking(1.1).foregroundStyle(.secondary)
                Text("Ivan").font(.callout.weight(.semibold))
                Text(copy("Subscription active", "Подписка активна")).font(.caption).foregroundStyle(.secondary)
            }
            .padding(14)
        }
        .padding(.vertical, 16)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private func editorialSourceButton(_ value: VisualScreen, index: String) -> some View {
        Button { screen = value } label: {
            HStack(spacing: 9) {
                Text(index).font(.caption2.monospaced()).foregroundStyle(.tertiary)
                Text(screenName(value)).font(.callout.weight(topLevelScreen == value ? .semibold : .regular))
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .background(topLevelScreen == value ? Color.accentColor.opacity(increaseContrast ? 0.24 : 0.12) : .clear)
            .overlay(alignment: .leading) {
                if topLevelScreen == value { Rectangle().fill(Color.accentColor).frame(width: 3) }
            }
        }
        .buttonStyle(.plain)
    }

    private var editorialDestination: some View {
        Group {
            switch screen {
            case .catalogue, .series:
                editorialCatalogue
            case .search:
                editorialSearch
            case .history:
                editorialHistory
            case .authentication:
                authSurface(mode: .editorial)
            case .playback:
                playbackSurface(mode: .editorial)
            }
        }
    }

    private var editorialCatalogue: some View {
        VStack(alignment: .leading, spacing: 0) {
            editorialHeader(copy("Catalogue", "Каталог"), deck: copy("Continue where you left off, then browse the current Series index.", "Продолжайте с места остановки, затем изучайте актуальный список сериалов."))

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(copy("CONTINUE", "ПРОДОЛЖИТЬ")).font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(.secondary)
                    editorialFeature(selectedSeries)
                }
                .padding(22)
                .frame(width: 330)

                Divider()

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(VisualData.series.enumerated()), id: \.element.id) { index, series in
                            Button { open(series) } label: { editorialSeriesRow(series, index: index + 1) }
                                .buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private var editorialSearch: some View {
        VStack(alignment: .leading, spacing: 0) {
            editorialHeader(copy("Search", "Поиск"), deck: copy("Exact server-backed Series lookup.", "Точный серверный поиск сериалов."))
            HStack(spacing: 10) {
                TextField(copy("Series title", "Название сериала"), text: $searchText)
                    .textFieldStyle(.roundedBorder)
                Button(copy("Search", "Найти")) { }.keyboardShortcut(.return, modifiers: [])
            }
            .padding(20)
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(VisualData.series.prefix(3).enumerated()), id: \.element.id) { index, series in
                        editorialSeriesRow(series, index: index + 1)
                        Divider()
                    }
                }
            }
        }
    }

    private var editorialHistory: some View {
        VStack(alignment: .leading, spacing: 0) {
            editorialHeader(copy("Watch History", "История просмотров"), deck: copy("Local, profile-specific playback progress.", "Локальный прогресс просмотра для этого профиля."))
            HStack {
                Picker("History filter", selection: $historyFilter) {
                    Text(copy("All", "Все")).tag(0)
                    Text(copy("Continue", "Продолжить")).tag(1)
                    Text(copy("Completed", "Завершено")).tag(2)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: language == .english ? 270 : 340)
                Spacer()
                Text(copy("4 ENTRIES", "4 ЗАПИСИ")).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            .padding(16)
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(VisualData.series.prefix(4).enumerated()), id: \.element.id) { index, series in
                        editorialHistoryRow(series, index: index + 1)
                        Divider()
                    }
                }
            }
        }
    }

    private var editorialInspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(copy("SERIES / EPISODE", "СЕРИАЛ / СЕРИЯ"))
                        .font(.caption2.weight(.bold)).tracking(1.25).foregroundStyle(.secondary)
                    Spacer()
                    Button { screen = .catalogue } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless)
                }
                poster(selectedSeries, width: nil, height: 154, radius: 3)
                Text(selectedSeries.title).font(.title3.weight(.bold))
                Text(copy(selectedSeries.subtitleEN, selectedSeries.subtitleRU)).font(.callout).foregroundStyle(.secondary)
                Divider()
                Text(copy("SELECTED EPISODE", "ВЫБРАННАЯ СЕРИЯ")).font(.caption2.weight(.bold)).tracking(1.1).foregroundStyle(.secondary)
                Text(copy(selectedSeries.episodeEN, selectedSeries.episodeRU)).font(.headline)
                Picker(copy("Translation", "Перевод"), selection: $translation) {
                    Text("AniLibria · Russian dub").tag("AniLibria · Russian dub")
                    Text("Original · English subtitles").tag("Original · English subtitles")
                }
                Button(copy("WATCH EPISODE", "СМОТРЕТЬ СЕРИЮ"), systemImage: "play.fill") { screen = .playback }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            .padding(18)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Shared surfaces, rendered in each system

    private enum SurfaceMode: Equatable { case quiet, cinematic, editorial }

    private func authSurface(mode: SurfaceMode) -> some View {
        ZStack {
            if mode == .cinematic {
                LinearGradient(colors: [.indigo.opacity(0.42), .purple.opacity(0.16), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
            } else {
                Color.clear
            }

            VStack(spacing: 18) {
                Image(systemName: "sparkles.tv.fill")
                    .font(.system(size: 38, weight: .medium))
                    .foregroundStyle(mode == .cinematic ? .white : Color.accentColor)
                VStack(spacing: 6) {
                    Text(copy("Sign in to Miraio", "Войти в Miraio"))
                        .font(mode == .editorial ? .title2.weight(.bold) : .title.weight(.semibold))
                    Text(copy("Use your Anime365 Profile to validate Subscription Eligibility.", "Используйте профиль Anime365 для проверки доступности подписки."))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(mode == .cinematic ? .white.opacity(0.68) : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                TextField(copy("Email", "Электронная почта"), text: .constant("ivan@example.com"))
                    .textFieldStyle(.roundedBorder)
                SecureField(copy("Password", "Пароль"), text: .constant("prototype-only"))
                    .textFieldStyle(.roundedBorder)
                Button(copy("Sign In", "Войти")) { screen = .catalogue }
                    .modifier(ProminentSurfaceButtonStyle(useGlass: mode == .cinematic))
                    .tint(.indigo)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                Divider()
                Label(copy("Subscription Eligibility is checked after authentication", "Доступность подписки проверяется после входа"), systemImage: "checkmark.shield")
                    .font(.caption)
                    .foregroundStyle(mode == .cinematic ? .white.opacity(0.68) : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(mode == .editorial ? 24 : 30)
            .frame(width: language == .english ? 420 : 470)
            .background {
                if mode == .quiet {
                    RoundedRectangle(cornerRadius: 18).fill(Color(nsColor: .controlBackgroundColor))
                } else if mode == .editorial {
                    Rectangle().fill(Color(nsColor: .controlBackgroundColor))
                }
            }
            .modifier(AuthGlassModifier(enabled: mode == .cinematic))
        }
        .foregroundStyle(mode == .cinematic ? .white : .primary)
    }

    private func playbackSurface(mode: SurfaceMode) -> some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.025, green: 0.03, blue: 0.05), Color(red: 0.11, green: 0.08, blue: 0.18), .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: selectedSeries.symbol)
                .font(.system(size: 160, weight: .ultraLight))
                .foregroundStyle(.white.opacity(0.08))

            VStack {
                HStack {
                    Button { screen = .catalogue } label: { Label(copy("Back", "Назад"), systemImage: "chevron.left") }
                        .modifier(SurfaceButtonStyle(useGlass: mode != .editorial))
                    Spacer()
                    Text(selectedSeries.title).font(.headline)
                    Spacer()
                    Button { isPlaybackInspectorVisible.toggle() } label: { Label(copy("Playback Options", "Параметры просмотра"), systemImage: "slider.horizontal.3") }
                        .modifier(SurfaceButtonStyle(useGlass: mode != .editorial))
                }
                .padding(18)

                Spacer()

                VStack(spacing: 8) {
                    Text(copy("The smallest moments are the ones I remember.", "Я запоминаю именно самые короткие мгновения."))
                        .font(.system(size: 24, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .shadow(color: .black, radius: 3, y: 2)
                    Text(copy("External ASS · supplemental renderer", "Внешние ASS-субтитры · дополнительный рендерер"))
                        .font(.caption).foregroundStyle(.white.opacity(0.62))
                }
                .padding(.horizontal, 100)

                Spacer()

                if isPlaybackHUDVisible {
                    playbackHUD(mode: mode)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    Button(copy("Show controls", "Показать элементы управления")) { isPlaybackHUDVisible = true }
                        .modifier(SurfaceButtonStyle(useGlass: mode != .editorial))
                        .padding(.bottom, 20)
                }
            }

            if isPlaybackInspectorVisible {
                HStack {
                    Spacer()
                    playbackInspector(mode: mode)
                        .frame(width: 310)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .foregroundStyle(.white)
    }

    private func playbackHUD(mode: SurfaceMode) -> some View {
        VStack(spacing: 12) {
            ProgressView(value: 0.31).tint(.white)
            HStack(spacing: 16) {
                Button { } label: { Image(systemName: "gobackward.15") }
                Button { } label: { Image(systemName: "pause.fill").font(.title2) }
                Button { } label: { Image(systemName: "goforward.15") }
                Text("08:02 / 24:18").font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.72))
                Spacer()
                Menu(copy("Translation", "Перевод"), systemImage: "captions.bubble") {
                    Button("AniLibria · Russian dub") { }
                    Button("Original · English subtitles") { }
                }
                Button { isPlaybackInspectorVisible = true } label: { Image(systemName: "slider.horizontal.3") }
                Button { isPlaybackHUDVisible = false } label: { Image(systemName: "chevron.down") }
            }
            .buttonStyle(.borderless)
        }
        .padding(mode == .editorial ? 14 : 18)
        .background {
            if mode == .editorial {
                Rectangle().fill(.black.opacity(0.88))
            }
        }
        .modifier(PlaybackGlassModifier(enabled: mode != .editorial))
        .padding(mode == .editorial ? 0 : 18)
    }

    private func playbackInspector(mode: SurfaceMode) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(copy("Playback Options", "Параметры просмотра")).font(.headline)
                Spacer()
                Button { isPlaybackInspectorVisible = false } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
            }
            Picker(copy("Translation", "Перевод"), selection: $translation) {
                Text("AniLibria · Russian dub").tag("AniLibria · Russian dub")
                Text("Original · English subtitles").tag("Original · English subtitles")
            }
            LabeledContent(copy("Source", "Источник"), value: "Automatic")
            LabeledContent(copy("Quality", "Качество"), value: "Auto · 1080p")
            LabeledContent(copy("Subtitles", "Субтитры"), value: "External ASS")
            Divider()
            Text(copy("Picture in Picture is unavailable while external ASS subtitles are selected.", "Режим «Картинка в картинке» недоступен при выборе внешних ASS-субтитров."))
                .font(.caption).foregroundStyle(.white.opacity(0.68)).fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(18)
        .background {
            if mode == .editorial { Rectangle().fill(.black.opacity(0.92)) }
        }
        .modifier(PlaybackGlassModifier(enabled: mode != .editorial))
        .padding(18)
    }

    // MARK: - Component details

    private var topLevelScreen: VisualScreen {
        screen == .series ? .catalogue : screen
    }

    private var navigationSelection: Binding<VisualScreen> {
        Binding(
            get: { topLevelScreen },
            set: { screen = $0 }
        )
    }

    private func sidebarContents(compact: Bool) -> some View {
        List(selection: navigationSelection) {
            Section {
                Label(copy("Catalogue", "Каталог"), systemImage: "rectangle.grid.2x2").tag(VisualScreen.catalogue)
                Label(copy("Search", "Поиск"), systemImage: "magnifyingglass").tag(VisualScreen.search)
                Label(copy("Watch History", "История просмотров"), systemImage: "clock.arrow.circlepath").tag(VisualScreen.history)
            }
            Section(copy("Profile", "Профиль")) {
                Label("Ivan", systemImage: "person.crop.circle.badge.checkmark")
                Label(copy("Subscription active", "Подписка активна"), systemImage: "checkmark.seal")
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles.tv.fill").foregroundStyle(.indigo)
                Text("Miraio").font(.title3.weight(.semibold))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    private func sectionHeading(_ title: String, trailing: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title2.weight(.semibold))
            Spacer()
            Text(trailing).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func destinationHeading<Trailing: View>(_ title: String, _ subtitle: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.largeTitle.weight(.semibold))
                Text(subtitle).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            trailing()
        }
    }

    private func quietContinueCard(_ series: VisualSeries) -> some View {
        Button { open(series) } label: {
            HStack(spacing: 14) {
                poster(series, width: 112, height: 72, radius: 10)
                VStack(alignment: .leading, spacing: 5) {
                    Text(series.title).font(.headline).lineLimit(1)
                    Text(copy(series.episodeEN, series.episodeRU)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    ProgressView(value: series.progress ?? 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(increaseContrast ? Color.primary.opacity(0.34) : Color.primary.opacity(0.07)))
        }
        .buttonStyle(.plain)
    }

    private func quietPosterCard(_ series: VisualSeries) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            poster(series, width: nil, height: 178, radius: 12)
            Text(series.title).font(.headline).lineLimit(2, reservesSpace: true)
            Text(copy(series.subtitleEN, series.subtitleRU)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func quietHistoryRow(_ series: VisualSeries) -> some View {
        Button { open(series) } label: {
            HStack(spacing: 14) {
                poster(series, width: 102, height: 64, radius: 10)
                VStack(alignment: .leading, spacing: 5) {
                    Text(series.title).font(.headline)
                    Text(copy(series.episodeEN, series.episodeRU)).font(.caption).foregroundStyle(.secondary)
                    if let progress = series.progress { ProgressView(value: progress).frame(maxWidth: 420) }
                }
                Spacer()
                Text(copy("Yesterday", "Вчера")).font(.caption).foregroundStyle(.secondary)
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func cinematicPosterCard(_ series: VisualSeries) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            poster(series, width: 174, height: 236, radius: 16)
            Text(series.title).font(.headline).lineLimit(1)
            Text(copy(series.subtitleEN, series.subtitleRU)).font(.caption).foregroundStyle(.white.opacity(0.62)).lineLimit(1)
        }
        .frame(width: 174, alignment: .leading)
    }

    private func cinematicSearchTile(_ series: VisualSeries) -> some View {
        HStack(spacing: 12) {
            poster(series, width: 76, height: 104, radius: 12)
            VStack(alignment: .leading, spacing: 6) {
                Text(series.title).font(.headline).lineLimit(2)
                Text(copy(series.subtitleEN, series.subtitleRU)).font(.caption).foregroundStyle(.white.opacity(0.66))
            }
            Spacer()
        }
        .padding(12)
        .background(.white.opacity(increaseContrast ? 0.16 : 0.08), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(increaseContrast ? 0.32 : 0.10)))
    }

    private func cinematicHistoryRow(_ series: VisualSeries) -> some View {
        Button { open(series) } label: {
            HStack(spacing: 16) {
                poster(series, width: 142, height: 84, radius: 13)
                VStack(alignment: .leading, spacing: 6) {
                    Text(series.title).font(.title3.weight(.semibold))
                    Text(copy(series.episodeEN, series.episodeRU)).foregroundStyle(.white.opacity(0.66))
                    if let progress = series.progress { ProgressView(value: progress).tint(.white).frame(maxWidth: 420) }
                }
                Spacer()
                Image(systemName: "play.circle.fill").font(.title).foregroundStyle(.white.opacity(0.84))
            }
            .padding(14)
            .background(.white.opacity(increaseContrast ? 0.16 : 0.08), in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    private func editorialHeader(_ title: String, deck: String) -> some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 7) {
                Text(title.uppercased()).font(.system(size: 30, weight: .black, design: .default)).tracking(-0.8)
                Text(deck).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(copy("REFRESH", "ОБНОВИТЬ"), systemImage: "arrow.clockwise") { }
                .buttonStyle(.borderless)
                .font(.caption.weight(.bold))
        }
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .bottom) { Divider() }
    }

    private func editorialFeature(_ series: VisualSeries) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            poster(series, width: nil, height: 174, radius: 3)
            Text(series.title).font(.title3.weight(.bold))
            Text(copy(series.episodeEN, series.episodeRU)).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ProgressView(value: series.progress ?? 0)
            Button(copy("RESUME", "ПРОДОЛЖИТЬ"), systemImage: "play.fill") { screen = .playback }
                .buttonStyle(.borderedProminent)
        }
    }

    private func editorialSeriesRow(_ series: VisualSeries, index: Int) -> some View {
        HStack(spacing: 14) {
            Text(String(format: "%02d", index)).font(.caption.monospaced()).foregroundStyle(.tertiary).frame(width: 24)
            poster(series, width: 62, height: 82, radius: 3)
            VStack(alignment: .leading, spacing: 4) {
                Text(series.title).font(.headline)
                Text(copy(series.subtitleEN, series.subtitleRU)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(copy("OPEN", "ОТКРЫТЬ")).font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 102)
        .contentShape(Rectangle())
    }

    private func editorialHistoryRow(_ series: VisualSeries, index: Int) -> some View {
        HStack(spacing: 14) {
            Text(String(format: "%02d", index)).font(.caption.monospaced()).foregroundStyle(.tertiary).frame(width: 24)
            poster(series, width: 92, height: 56, radius: 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(series.title).font(.headline)
                Text(copy(series.episodeEN, series.episodeRU)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let progress = series.progress {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(Int(progress * 100))%").font(.caption.monospacedDigit())
                    ProgressView(value: progress).frame(width: 120)
                }
            } else {
                Text(copy("NOT STARTED", "НЕ НАЧАТО")).font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 78)
    }

    private func poster(_ series: VisualSeries, width: CGFloat?, height: CGFloat, radius: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius)
                .fill(LinearGradient(colors: series.palette, startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle()
                .fill(.white.opacity(0.14))
                .frame(width: height * 0.72, height: height * 0.72)
                .offset(x: height * 0.20, y: -height * 0.18)
            Image(systemName: series.symbol)
                .font(.system(size: min(height * 0.28, 58), weight: .light))
                .foregroundStyle(.white.opacity(0.9))
            LinearGradient(colors: [.clear, .black.opacity(0.34)], startPoint: .center, endPoint: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: radius))
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: radius))
        .accessibilityLabel(copy("Poster placeholder for \(series.title)", "Заглушка постера: \(series.title)"))
    }

    private func open(_ series: VisualSeries) {
        selectedSeriesID = series.id
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.24)) {
            screen = .series
        }
    }

    // MARK: - Prototype chrome

    private var stateReadout: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 14) {
                Label("VISIBLE REVIEW STATE", systemImage: "eye.fill")
                    .font(.caption2.weight(.bold)).tracking(0.8)
                Text("Variant: \(variant.rawValue) · \(variant.name)")
                Text("Screen: \(screenName(screen))")
                Text("Language: \(language.rawValue)")
                Text("Motion: \(reduceMotion ? "reduced" : "standard")")
                Text("Contrast: \(increaseContrast ? "increased" : "standard")")
                Spacer()
                Text("Glass: \(variant.glassRule)")
            }
            .font(.caption.monospaced())
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(.bar)
        }
    }

    private var variantSwitcher: some View {
        HStack(spacing: 10) {
            Button { cycleVariant(by: -1) } label: { Image(systemName: "chevron.left") }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                .accessibilityLabel("Previous visual system")

            VStack(spacing: 1) {
                Text("\(variant.rawValue) · \(variant.name)").font(.callout.weight(.semibold))
                Text(variant.glassRule).font(.caption2).foregroundStyle(.white.opacity(0.68))
            }
            .frame(minWidth: 290)

            Button { cycleVariant(by: 1) } label: { Image(systemName: "chevron.right") }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                .accessibilityLabel("Next visual system")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(.black.opacity(0.9), in: Capsule())
        .foregroundStyle(.white)
        .shadow(radius: 12, y: 5)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Prototype visual-system switcher")
    }

    private func cycleVariant(by offset: Int) {
        let variants = VisualVariant.allCases
        guard let current = variants.firstIndex(of: variant) else { return }
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.24)) {
            variant = variants[(current + offset + variants.count) % variants.count]
        }
    }
}

private struct AuthGlassModifier: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.glassEffect(.regular, in: .rect(cornerRadius: 26))
        } else {
            content
        }
    }
}

private struct PlaybackGlassModifier: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.glassEffect(.regular, in: .rect(cornerRadius: 22))
        } else {
            content
        }
    }
}

private struct SurfaceButtonStyle: ViewModifier {
    let useGlass: Bool

    func body(content: Content) -> some View {
        if useGlass {
            content.buttonStyle(.glass)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

private struct ProminentSurfaceButtonStyle: ViewModifier {
    let useGlass: Bool

    func body(content: Content) -> some View {
        if useGlass {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.borderedProminent)
        }
    }
}

#Preview {
    VisualSystemPrototype()
        .frame(width: 1_320, height: 860)
}

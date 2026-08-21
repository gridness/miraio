//
//  PlaybackExperiencePrototype.swift
//  miraio
//
//  THROWAWAY PROTOTYPE: three native playback experience variants for Wayfinder.
//  Keep this work on prototype/native-playback-subtitles; do not ship it.
//

import AVKit
import SwiftUI

private enum PrototypeVariant: String, CaseIterable, Identifiable {
    case nativeFirst = "A"
    case inspector = "B"
    case headsUp = "C"

    var id: Self { self }

    var name: String {
        switch self {
        case .nativeFirst: "Native first"
        case .inspector: "Playback inspector"
        case .headsUp: "Hover HUD + inspector"
        }
    }
}

private enum SubtitleStressCase: String, CaseIterable, Identifiable {
    case dialogue = "Dialogue"
    case overlap = "Overlap + sign"
    case styledSign = "Styled sign"
    case advancedEffects = "Karaoke / drawing"

    var id: Self { self }
}

struct PlaybackExperiencePrototype: View {
    // Apple-owned sample media. It exercises AVPlayerView, not Anime365 delivery.
    private static let sampleURL = URL(
        string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8"
    )!

    @State private var variant = PrototypeVariant.nativeFirst
    @State private var translation = "AniLibria · Russian dub"
    @State private var source = "Auto"
    @State private var quality = "Auto"
    @State private var audio = "Russian"
    @State private var subtitles = "Russian · external ASS"
    @State private var subtitleCase = SubtitleStressCase.dialogue
    @State private var recoveryNotice: String?
    @State private var isHoveringPlayback = false
    @State private var isInspectorPresented = false
    @State private var player = AVPlayer(url: Self.sampleURL)
    @FocusState private var isPlaybackFocused: Bool

    private let translations = [
        "AniLibria · Russian dub",
        "JAM · Russian dub",
        "Original · Japanese",
    ]
    private let sources = ["Auto", "Source 1", "Source 2"]
    private let qualities = ["Auto", "Up to 1080p", "Up to 720p", "Up to 480p"]
    private let audioOptions = ["Russian", "Japanese"]
    private let subtitleOptions = ["Russian · external ASS", "English · embedded", "Off"]

    var body: some View {
        VStack(spacing: 0) {
            prototypeBanner

            Group {
                switch variant {
                case .nativeFirst:
                    nativeFirstVariant
                case .inspector:
                    inspectorVariant
                case .headsUp:
                    headsUpVariant
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
        .onDisappear {
            player.pause()
        }
    }

    private var prototypeBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "hammer.fill")
            Text("THROWAWAY PLAYBACK PROTOTYPE")
                .font(.caption.weight(.bold))
            Divider().frame(height: 14)
            Text("Apple sample media + synthetic subtitle cases; Anime365 native delivery remains contract-gated")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text("⌥⌘← / ⌥⌘→ changes variant")
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .frame(height: 36)
        .background(.yellow.opacity(0.13))
        .overlay(alignment: .bottom) { Divider() }
    }

    // Variant A keeps AVPlayerView visually dominant and collapses app-owned
    // choices into one compact title bar plus a Playback Options menu.
    private var nativeFirstVariant: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Frieren: Beyond Journey’s End")
                        .font(.headline)
                    Text("Episode 4 · The Land Where Souls Rest")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Picker("Translation", selection: $translation) {
                    ForEach(translations, id: \.self) { Text($0) }
                }
                .labelsHidden()
                .frame(width: 220)

                playbackOptionsMenu
            }
            .padding(14)
            .background(.bar)

            nativePlayer

            HStack {
                rendererStatus
                Spacer()
                subtitleStressPicker
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(.bar)
        }
    }

    // Variant B trades picture size for persistent discoverability and makes
    // every app-owned choice explicit in a familiar macOS inspector.
    private var inspectorVariant: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Frieren: Beyond Journey’s End")
                            .font(.title3.weight(.semibold))
                        Text("Episode 4 · The Land Where Souls Rest")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    rendererStatus
                }
                .padding(14)
                .background(.bar)

                nativePlayer
            }

            Divider()

            inspectorPanel
        }
    }

    // Winning direction: C is transient on playback hover or keyboard focus;
    // B remains available as an on-demand persistent inspector.
    private var headsUpVariant: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .top) {
                nativePlayer

                if isHoveringPlayback || isPlaybackFocused {
                    headsUpControls
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .focusable()
            .focused($isPlaybackFocused)
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.16)) {
                    isHoveringPlayback = hovering
                }
            }

            if isInspectorPresented {
                Divider()
                inspectorPanel
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.18), value: isInspectorPresented)
    }

    private var headsUpControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                compactChoice("Translation", value: translation) {
                    choiceButtons(values: translations, selection: $translation)
                }
                compactChoice("Source", value: source) {
                    choiceButtons(values: sources, selection: $source)
                }
                compactChoice("Quality", value: quality) {
                    choiceButtons(values: qualities, selection: $quality)
                }
                compactChoice("Subtitles", value: subtitles) {
                    choiceButtons(values: subtitleOptions, selection: $subtitles)
                }
                Spacer()
                recoveryButton
                Button(
                    isInspectorPresented ? "Hide Inspector" : "Inspector",
                    systemImage: "sidebar.right"
                ) {
                    isInspectorPresented.toggle()
                }
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 10, y: 4)

            HStack {
                rendererStatus
                Spacer()
                subtitleStressPicker
            }
            .padding(.horizontal, 10)
        }
        .padding(16)
    }

    private var inspectorPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label("Playback", systemImage: "slider.horizontal.3")
                    .font(.headline)

                optionPicker("Translation", selection: $translation, values: translations)
                optionPicker("Source", selection: $source, values: sources)
                optionPicker("Quality", selection: $quality, values: qualities)
                optionPicker("Audio", selection: $audio, values: audioOptions)
                optionPicker("Subtitles", selection: $subtitles, values: subtitleOptions)

                Divider()
                subtitleStressMenu

                Divider()
                recoveryButton
            }
            .padding(18)
        }
        .frame(width: 300)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var nativePlayer: some View {
        NativePlayerView(
            player: player,
            subtitles: subtitles,
            stressCase: subtitleCase
        )
        .background(.black)
        .accessibilityLabel("Native AVPlayerView playback surface")
    }

    private var playbackOptionsMenu: some View {
        Menu {
            Section("Source") {
                choiceButtons(values: sources, selection: $source)
            }
            Section("Quality") {
                choiceButtons(values: qualities, selection: $quality)
            }
            Section("Audio") {
                choiceButtons(values: audioOptions, selection: $audio)
            }
            Section("Subtitles") {
                choiceButtons(values: subtitleOptions, selection: $subtitles)
            }
            Divider()
            recoveryButton
        } label: {
            Label("Playback Options", systemImage: "slider.horizontal.3")
        }
    }

    private func optionPicker(_ label: String, selection: Binding<String>, values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker(label, selection: selection) {
                ForEach(values, id: \.self) { Text($0) }
            }
            .labelsHidden()
        }
    }

    private func compactChoice<MenuContent: View>(
        _ label: String,
        value: String,
        @ViewBuilder content: () -> MenuContent
    ) -> some View {
        Menu(content: content) {
            Text("\(label): \(value)")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .fixedSize()
    }

    private func choiceButtons(values: [String], selection: Binding<String>) -> some View {
        ForEach(values, id: \.self) { value in
            Button {
                selection.wrappedValue = value
            } label: {
                if selection.wrappedValue == value {
                    Label(value, systemImage: "checkmark")
                } else {
                    Text(value)
                }
            }
        }
    }

    private var rendererStatus: some View {
        Label(rendererLabel, systemImage: rendererSymbol)
            .font(.caption.weight(.medium))
            .foregroundStyle(rendererColor)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(rendererColor.opacity(0.12), in: Capsule())
    }

    private var rendererLabel: String {
        if subtitles == "Russian · external ASS" {
            return subtitleCase == .advancedEffects
                ? "ASS renderer · graceful degradation"
                : "ASS-aware supplemental renderer"
        }
        if subtitles == "Off" { return "Subtitles off" }
        return "Native AVKit legible track"
    }

    private var rendererSymbol: String {
        subtitleCase == .advancedEffects && subtitles == "Russian · external ASS"
            ? "exclamationmark.triangle.fill"
            : "captions.bubble.fill"
    }

    private var rendererColor: Color {
        subtitleCase == .advancedEffects && subtitles == "Russian · external ASS"
            ? .orange
            : .secondary
    }

    private var subtitleStressPicker: some View {
        Picker("Subtitle case", selection: $subtitleCase) {
            ForEach(SubtitleStressCase.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 480)
    }

    private var subtitleStressMenu: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Subtitle stress case")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Subtitle stress case", selection: $subtitleCase) {
                ForEach(SubtitleStressCase.allCases) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden()
        }
    }

    private var recoveryButton: some View {
        Button("Simulate fallback", systemImage: "arrow.trianglehead.2.clockwise.rotate.90") {
            source = "Source 2"
            quality = "Up to 720p"
            recoveryNotice = "Source 1 became unavailable. Continued on Source 2 at up to 720p."
        }
    }

    private var stateReadout: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 14) {
                Label("Full prototype state", systemImage: "waveform.path.ecg")
                    .font(.caption.weight(.semibold))

                Text("Translation: \(translation)")
                Text("Source: \(source)")
                Text("Quality: \(quality)")
                Text("Audio: \(audio)")
                Text("Subtitles: \(subtitles)")

                Spacer()
            }
            .font(.caption.monospaced())
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(.bar)

            if let recoveryNotice {
                HStack {
                    Label(recoveryNotice, systemImage: "info.circle.fill")
                    Spacer()
                    Button("Dismiss") { self.recoveryNotice = nil }
                        .buttonStyle(.plain)
                }
                .font(.caption)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(.blue.opacity(0.12))
            }
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
                .frame(minWidth: 190)

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
        let all = PrototypeVariant.allCases
        guard let current = all.firstIndex(of: variant) else { return }
        variant = all[(current + offset + all.count) % all.count]
    }
}

#if os(macOS)
private struct NativePlayerView: NSViewRepresentable {
    let player: AVPlayer
    let subtitles: String
    let stressCase: SubtitleStressCase

    final class Coordinator {
        var subtitleHost: NSHostingView<PrototypeSubtitleOverlay>?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.player = player
        playerView.controlsStyle = .floating
        playerView.allowsPictureInPicturePlayback = true
        playerView.updatesNowPlayingInfoCenter = true
        playerView.speeds = AVPlaybackSpeed.systemDefaultSpeeds

        let host = NSHostingView(rootView: overlay)
        host.translatesAutoresizingMaskIntoConstraints = false
        playerView.contentOverlayView?.addSubview(host)
        if let contentOverlayView = playerView.contentOverlayView {
            NSLayoutConstraint.activate([
                host.leadingAnchor.constraint(equalTo: contentOverlayView.leadingAnchor),
                host.trailingAnchor.constraint(equalTo: contentOverlayView.trailingAnchor),
                host.topAnchor.constraint(equalTo: contentOverlayView.topAnchor),
                host.bottomAnchor.constraint(equalTo: contentOverlayView.bottomAnchor),
            ])
        }
        context.coordinator.subtitleHost = host
        return playerView
    }

    func updateNSView(_ playerView: AVPlayerView, context: Context) {
        if playerView.player !== player { playerView.player = player }
        context.coordinator.subtitleHost?.rootView = overlay
    }

    private var overlay: PrototypeSubtitleOverlay {
        PrototypeSubtitleOverlay(
            isVisible: subtitles == "Russian · external ASS",
            stressCase: stressCase
        )
    }
}
#else
private struct NativePlayerView: View {
    let player: AVPlayer
    let subtitles: String
    let stressCase: SubtitleStressCase

    var body: some View {
        VideoPlayer(player: player) {
            PrototypeSubtitleOverlay(
                isVisible: subtitles == "Russian · external ASS",
                stressCase: stressCase
            )
        }
    }
}
#endif

private struct PrototypeSubtitleOverlay: View {
    let isVisible: Bool
    let stressCase: SubtitleStressCase

    var body: some View {
        GeometryReader { proxy in
            if isVisible {
                switch stressCase {
                case .dialogue:
                    subtitleText("We’ll pick up exactly where you stopped.")
                        .position(x: proxy.size.width / 2, y: proxy.size.height * 0.90)

                case .overlap:
                    subtitleText("Even now, the old road remembers us.")
                        .position(x: proxy.size.width / 2, y: proxy.size.height * 0.90)
                    signText("Northern checkpoint")
                        .rotationEffect(.degrees(-3))
                        .position(x: proxy.size.width * 0.74, y: proxy.size.height * 0.28)

                case .styledSign:
                    signText("魔法都市 · The City of Magic")
                        .font(.system(size: 24, weight: .black, design: .serif))
                        .foregroundStyle(.yellow)
                        .rotationEffect(.degrees(2))
                        .position(x: proxy.size.width * 0.56, y: proxy.size.height * 0.24)
                    subtitleText("The lettering belongs to the scene, not the transport bar.")
                        .position(x: proxy.size.width / 2, y: proxy.size.height * 0.90)

                case .advancedEffects:
                    HStack(spacing: 0) {
                        Text("ka").foregroundStyle(.yellow)
                        Text("ra").foregroundStyle(.orange)
                        Text("o").foregroundStyle(.pink)
                        Text("ke").foregroundStyle(.white)
                    }
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .shadow(color: .black, radius: 2)
                    .position(x: proxy.size.width / 2, y: proxy.size.height * 0.78)

                    Text("Prototype shows readable static fallback; per-syllable animation and ASS drawings may degrade.")
                        .font(.caption.weight(.semibold))
                        .padding(7)
                        .background(.orange.opacity(0.85), in: Capsule())
                        .position(x: proxy.size.width / 2, y: proxy.size.height * 0.88)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func subtitleText(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 25, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 6))
            .shadow(color: .black, radius: 2)
    }

    private func signText(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 20, weight: .bold, design: .serif))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 5))
            .shadow(color: .black, radius: 2)
    }
}

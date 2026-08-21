import AppKit
import AVFoundation
@preconcurrency import AVKit

@MainActor
final class PrototypeViewController: NSViewController, @preconcurrency AVPlayerViewPictureInPictureDelegate {
    private let player: AVQueuePlayer
    private let playerLooper: AVPlayerLooper
    private let playerView = AVPlayerView()
    private let subtitleOverlay = SubtitleOverlayView()
    private let renderer: ASSRenderer

    private let stateLabel = NSTextField(wrappingLabelWithString: "")
    private let semanticLabel = NSTextField(wrappingLabelWithString: "")
    private let pipLabel = NSTextField(wrappingLabelWithString: "Not started")
    private let boostButton = NSButton(checkboxWithTitle: "Boost ordinary dialogue 25%", target: nil, action: nil)
    private let engineControl = NSSegmentedControl(
        labels: ["AVKit only", "libass", "Apple captions"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )

    private var timeObserver: Any?
    private var renderCount = 0
    private var lastSemanticText = ""

    init(videoURL: URL, subtitleData: Data) throws {
        let player = AVQueuePlayer()
        self.player = player
        playerLooper = AVPlayerLooper(
            player: player,
            templateItem: AVPlayerItem(url: videoURL)
        )
        renderer = try ASSRenderer(script: subtitleData)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 1_180, height: 720))
        preferredContentSize = view.frame.size

        playerView.translatesAutoresizingMaskIntoConstraints = false
        playerView.player = player
        playerView.controlsStyle = .floating
        playerView.showsFullScreenToggleButton = true
        playerView.allowsPictureInPicturePlayback = true
        playerView.pictureInPictureDelegate = self
        playerView.allowsVideoFrameAnalysis = false

        let inspector = makeInspector()
        let split = NSSplitView()
        split.translatesAutoresizingMaskIntoConstraints = false
        split.isVertical = true
        split.dividerStyle = .thin
        split.addArrangedSubview(playerView)
        split.addArrangedSubview(inspector)
        view.addSubview(split)
        NSLayoutConstraint.activate([
            split.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            split.topAnchor.constraint(equalTo: view.topAnchor),
            split.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            playerView.widthAnchor.constraint(greaterThanOrEqualToConstant: 680),
            inspector.widthAnchor.constraint(equalToConstant: 340)
        ])
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard let host = playerView.contentOverlayView, subtitleOverlay.superview == nil else { return }
        subtitleOverlay.translatesAutoresizingMaskIntoConstraints = true
        host.addSubview(subtitleOverlay)
        layoutSubtitleOverlay()

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 30),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                self?.render(at: time)
            }
        }
        render(at: .zero)
        player.play()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        layoutSubtitleOverlay()
    }

    private func layoutSubtitleOverlay() {
        guard let host = playerView.contentOverlayView else { return }
        let videoBounds = host.convert(playerView.videoBounds, from: playerView)
        if videoBounds.width > 0, videoBounds.height > 0 {
            subtitleOverlay.frame = videoBounds
        }
    }

    private func makeInspector() -> NSView {
        let title = NSTextField(labelWithString: "ASS boundary prototype")
        title.font = .systemFont(ofSize: 20, weight: .semibold)

        let question = NSTextField(wrappingLabelWithString:
            "Question: can a real ASS engine remain a bounded, player-time-driven overlay while AVKit keeps playback—and what survives native Picture in Picture?"
        )
        question.textColor = .secondaryLabelColor

        engineControl.selectedSegment = 1
        engineControl.target = self
        engineControl.action = #selector(engineChanged)
        boostButton.target = self
        boostButton.action = #selector(boostChanged)

        let seekButtons = NSStackView(views: [
            makeSeekButton("Dialogue", seconds: 0.5),
            makeSeekButton("Sign", seconds: 4.5),
            makeSeekButton("Overlap", seconds: 8.5),
            makeSeekButton("Style", seconds: 12.5),
            makeSeekButton("Karaoke", seconds: 16.5),
            makeSeekButton("Motion", seconds: 20.5)
        ])
        seekButtons.orientation = .horizontal
        seekButtons.distribution = .fillEqually
        seekButtons.spacing = 4

        let piiTitle = sectionTitle("Picture in Picture")
        let pipHelp = NSTextField(wrappingLabelWithString:
            "Start PiP from AVKit’s native controls. The delegate records lifecycle here; visually confirm whether the selected supplemental overlay appears in the PiP window."
        )
        pipHelp.textColor = .secondaryLabelColor

        let semanticTitle = sectionTitle("Semantic accessibility output")
        semanticLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        semanticLabel.setAccessibilityLabel("Active semantic subtitle text")

        let stateTitle = sectionTitle("Rendered state")
        stateLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)

        let caveat = NSTextField(wrappingLabelWithString:
            "PROTOTYPE: Homebrew dylibs, generated local media, no Anime365 resources, no persistence. This branch is evidence—not production code."
        )
        caveat.textColor = .systemOrange

        let stack = NSStackView(views: [
            title,
            question,
            engineControl,
            boostButton,
            sectionTitle("Jump to fixture"),
            seekButtons,
            piiTitle,
            pipHelp,
            pipLabel,
            semanticTitle,
            semanticLabel,
            stateTitle,
            stateLabel,
            caveat
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .windowBackgroundColor
        scroll.documentView = stack
        NSLayoutConstraint.activate([
            stack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.heightAnchor.constraint(greaterThanOrEqualTo: scroll.contentView.heightAnchor)
        ])
        return scroll
    }

    private func sectionTitle(_ value: String) -> NSTextField {
        let label = NSTextField(labelWithString: value)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        return label
    }

    private func makeSeekButton(_ title: String, seconds: Double) -> NSButton {
        let button = NSButton(title: title, target: self, action: #selector(seek(_:)))
        button.bezelStyle = .rounded
        button.tag = Int(seconds * 10)
        return button
    }

    @objc private func seek(_ sender: NSButton) {
        let seconds = Double(sender.tag) / 10
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                self?.render(at: time)
            }
        }
    }

    @objc private func engineChanged() {
        switch engineControl.selectedSegment {
        case 0: subtitleOverlay.mode = .avkitOnly
        case 1: subtitleOverlay.mode = .libass
        default: subtitleOverlay.mode = .appleCaption
        }
        boostButton.isEnabled = engineControl.selectedSegment == 1
        render(at: player.currentTime())
    }

    @objc private func boostChanged() {
        render(at: player.currentTime())
    }

    private func render(at time: CMTime) {
        layoutSubtitleOverlay()
        guard subtitleOverlay.bounds.width > 0, subtitleOverlay.bounds.height > 0 else { return }
        if engineControl.selectedSegment == 0 {
            renderCount += 1
            semanticLabel.stringValue = "(native media only)"
            stateLabel.stringValue = """
            Playback Session time: \(format(time))
            Engine: AVKit only (paired energy baseline)
            Overlay pixels: none
            Render call: skipped
            Render callbacks: \(renderCount)
            Player rate: \(String(format: "%.2f", player.rate))×
            """
            return
        }
        do {
            let result = try renderer.render(
                size: subtitleOverlay.bounds.size,
                time: time,
                readabilityBoost: boostButton.state == .on
            )
            renderCount += 1
            lastSemanticText = result.semanticText

            if engineControl.selectedSegment == 1 {
                subtitleOverlay.showLibass(image: result.image, semanticText: result.semanticText)
            } else {
                subtitleOverlay.showAppleCaption(at: time, semanticText: result.semanticText)
            }
            semanticLabel.stringValue = result.semanticText.isEmpty ? "(none)" : result.semanticText
            stateLabel.stringValue = """
            Playback Session time: \(format(time))
            Engine: \(engineControl.selectedSegment == 1 ? "libass \(renderer.version)" : "AVCaptionRenderer (flattened mapping)")
            Fixture events: \(renderer.eventCount)
            Advanced effects detected: \(renderer.hasAdvancedEffects ? "yes" : "no")
            Overlay pixels: \(Int(subtitleOverlay.bounds.width)) × \(Int(subtitleOverlay.bounds.height))
            Render call: \(String(format: "%.2f", result.elapsedMilliseconds)) ms
            libass change kind: \(result.changeKind)
            Render callbacks: \(renderCount)
            Player rate: \(String(format: "%.2f", player.rate))×
            """
        } catch {
            stateLabel.stringValue = "Render error: \(error.localizedDescription)"
        }
    }

    private func format(_ time: CMTime) -> String {
        let seconds = max(0, CMTimeGetSeconds(time))
        return String(format: "%05.2fs", seconds)
    }

    func playerViewWillStartPicture(inPicture playerView: AVPlayerView) {
        pipLabel.stringValue = "PiP starting — inspect the PiP window now"
    }

    func playerViewDidStartPicture(inPicture playerView: AVPlayerView) {
        pipLabel.stringValue = "PiP active — is the selected overlay visible?"
    }

    func playerView(
        _ playerView: AVPlayerView,
        failedToStartPictureInPictureWithError error: Error
    ) {
        pipLabel.stringValue = "PiP failed: \(error.localizedDescription)"
    }

    func playerViewWillStopPicture(inPicture playerView: AVPlayerView) {
        pipLabel.stringValue = "PiP stopping"
    }

    func playerViewDidStopPicture(inPicture playerView: AVPlayerView) {
        pipLabel.stringValue = "PiP stopped"
    }
}

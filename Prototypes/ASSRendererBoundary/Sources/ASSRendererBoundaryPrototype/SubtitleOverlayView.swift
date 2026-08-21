import AppKit
import AVFoundation

@MainActor
final class SubtitleOverlayView: NSView {
    enum Mode {
        case avkitOnly
        case libass
        case appleCaption
    }

    private let imageView = NSImageView()
    private let nativeCaptionView = NativeCaptionView()

    var mode: Mode = .libass {
        didSet { updateVisibility() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleAxesIndependently
        imageView.setAccessibilityElement(false)
        nativeCaptionView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        addSubview(nativeCaptionView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            nativeCaptionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            nativeCaptionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            nativeCaptionView.topAnchor.constraint(equalTo: topAnchor),
            nativeCaptionView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("Episode subtitles")
        updateVisibility()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showLibass(image: CGImage, semanticText: String) {
        imageView.image = NSImage(cgImage: image, size: bounds.size)
        setAccessibilityValue(semanticText.isEmpty ? "No active subtitle" : semanticText)
    }

    func showAppleCaption(at time: CMTime, semanticText: String) {
        nativeCaptionView.time = time
        nativeCaptionView.needsDisplay = true
        setAccessibilityValue(semanticText.isEmpty ? "No active subtitle" : semanticText)
    }

    private func updateVisibility() {
        imageView.isHidden = mode != .libass
        nativeCaptionView.isHidden = mode != .appleCaption
        isHidden = mode == .avkitOnly
    }
}

@MainActor
private final class NativeCaptionView: NSView {
    private let renderer: AVCaptionRenderer = {
        let renderer = AVCaptionRenderer()
        renderer.captions = NativeCaptionFixture.captions
        return renderer
    }()

    var time: CMTime = .zero

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        renderer.bounds = bounds.insetBy(dx: 0, dy: 64)
        renderer.render(in: context, for: time)
    }
}

@MainActor
private enum NativeCaptionFixture {
    static let captions: [AVCaption] = [
        caption("Core dialogue · точное время", start: 0, end: 4),
        caption("AUTHORED POSITION — flattened to a native caption region", start: 4, end: 8),
        caption("First overlapping line", start: 8, end: 12),
        caption("Second layer — authored style is unavailable", start: 8, end: 12),
        emphasizedCaption("Bold/color survive; ASS outline and shadow do not", start: 12, end: 16),
        revealCaption("Karaoke progress becomes character reveal", start: 16, end: 20),
        caption("Advanced motion omitted; readable text retained", start: 20, end: 24)
    ]

    private static func range(start: Double, end: Double) -> CMTimeRange {
        CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            end: CMTime(seconds: end, preferredTimescale: 600)
        )
    }

    private static func caption(_ text: String, start: Double, end: Double) -> AVCaption {
        AVCaption(text, timeRange: range(start: start, end: end))
    }

    private static func emphasizedCaption(_ text: String, start: Double, end: Double) -> AVCaption {
        let caption = AVMutableCaption(text, timeRange: range(start: start, end: end))
        let wholeText = NSRange(location: 0, length: (text as NSString).length)
        caption.setFontWeight(.bold, in: wholeText)
        caption.setFontStyle(.italic, in: wholeText)
        caption.setTextColor(NSColor.systemTeal.cgColor, in: wholeText)
        return caption
    }

    private static func revealCaption(_ text: String, start: Double, end: Double) -> AVCaption {
        let caption = AVMutableCaption(text, timeRange: range(start: start, end: end))
        caption.animation = .characterReveal
        return caption
    }
}

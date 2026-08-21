import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation

enum FixtureVideo {
    static let size = CGSize(width: 960, height: 540)
    static let durationSeconds = 24
    static let framesPerSecond = 10

    static func makeIfNeeded() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Miraio-ASS-boundary-PROTOTYPE-v2.mov")
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }

        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(size.width),
                AVVideoHeightKey: Int(size.height),
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 900_000,
                    AVVideoExpectedSourceFrameRateKey: framesPerSecond
                ]
            ]
        )
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height)
            ]
        )
        guard writer.canAdd(input) else {
            throw PrototypeError.fixture("AVAssetWriter rejected its video input")
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? PrototypeError.fixture("AVAssetWriter could not start")
        }
        writer.startSession(atSourceTime: .zero)
        guard let pool = adaptor.pixelBufferPool else {
            throw PrototypeError.fixture("AVAssetWriter did not create a pixel buffer pool")
        }

        let frameCount = durationSeconds * framesPerSecond
        for frameIndex in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.002)
            }
            var optionalBuffer: CVPixelBuffer?
            let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &optionalBuffer)
            guard status == kCVReturnSuccess, let buffer = optionalBuffer else {
                throw PrototypeError.fixture("Could not allocate fixture video frame")
            }
            paint(buffer: buffer, frameIndex: frameIndex, frameCount: frameCount)
            let time = CMTime(value: CMTimeValue(frameIndex), timescale: CMTimeScale(framesPerSecond))
            guard adaptor.append(buffer, withPresentationTime: time) else {
                throw writer.error ?? PrototypeError.fixture("Could not append fixture video frame")
            }
        }

        input.markAsFinished()
        let completion = DispatchSemaphore(value: 0)
        writer.finishWriting {
            completion.signal()
        }
        completion.wait()
        guard writer.status == .completed else {
            throw writer.error ?? PrototypeError.fixture("Could not finish fixture video")
        }
        return url
    }

    private static func paint(buffer: CVPixelBuffer, frameIndex: Int, frameCount: Int) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { return }

        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let progress = Double(frameIndex) / Double(frameCount)
        guard let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue |
                CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return }

        let background = CGColor(
            red: 0.11 + 0.08 * progress,
            green: 0.10,
            blue: 0.16 + 0.06 * (1 - progress),
            alpha: 1
        )
        context.setFillColor(background)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let markerWidth = CGFloat(width) * 0.22
        let markerX = CGFloat(progress) * (CGFloat(width) - markerWidth)
        context.setFillColor(CGColor(red: 0.12, green: 0.85, blue: 0.66, alpha: 0.34))
        context.fill(CGRect(x: markerX, y: 0, width: markerWidth, height: CGFloat(height)))
    }
}

enum PrototypeError: LocalizedError {
    case fixture(String)
    case renderer(String)

    var errorDescription: String? {
        switch self {
        case .fixture(let message), .renderer(let message): message
        }
    }
}

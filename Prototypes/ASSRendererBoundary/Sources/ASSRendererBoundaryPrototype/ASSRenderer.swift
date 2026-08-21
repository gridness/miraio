import ASSBridge
import CoreGraphics
import CoreMedia
import Foundation

final class ASSRenderer {
    struct Result {
        let image: CGImage
        let semanticText: String
        let changeKind: Int
        let elapsedMilliseconds: Double
    }

    private let context: OpaquePointer

    let eventCount: Int
    let hasAdvancedEffects: Bool
    let version: String

    init(script: Data) throws {
        var errorCode: Int32 = 0
        let context = script.withUnsafeBytes { bytes in
            miraio_ass_create(
                bytes.baseAddress?.assumingMemoryBound(to: CChar.self),
                bytes.count,
                &errorCode
            )
        }
        guard let context else {
            throw PrototypeError.renderer("libass initialization failed (error \(errorCode))")
        }
        self.context = context
        eventCount = Int(miraio_ass_event_count(context))
        hasAdvancedEffects = miraio_ass_has_advanced_effects(context)

        let encodedVersion = miraio_ass_library_version()
        let minorBCD = (encodedVersion >> 20) & 0xFF
        let patchBCD = (encodedVersion >> 12) & 0xFF
        let minor = ((minorBCD >> 4) * 10) + (minorBCD & 0xF)
        let patch = ((patchBCD >> 4) * 10) + (patchBCD & 0xF)
        version = "\((encodedVersion >> 28) & 0xF).\(minor).\(patch)"
    }

    deinit {
        miraio_ass_destroy(context)
    }

    func render(size: CGSize, time: CMTime, readabilityBoost: Bool) throws -> Result {
        let width = max(1, Int(size.width.rounded()))
        let height = max(1, Int(size.height.rounded()))
        let milliseconds = Int64((CMTimeGetSeconds(time) * 1_000).rounded())
        var frame = MiraioASSFrame()
        var errorCode: Int32 = 0
        let started = ContinuousClock.now
        let succeeded = miraio_ass_render(
            context,
            Int32(width),
            Int32(height),
            milliseconds,
            readabilityBoost,
            &frame,
            &errorCode
        )
        let elapsed = ContinuousClock.now - started
        guard succeeded, let pixels = frame.pixels else {
            throw PrototypeError.renderer("libass render failed (error \(errorCode))")
        }

        let data = Data(bytes: pixels, count: Int(frame.bytes_per_row * frame.height))
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(
                width: Int(frame.width),
                height: Int(frame.height),
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: Int(frame.bytes_per_row),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
                    .union(.byteOrder32Big),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else {
            throw PrototypeError.renderer("Could not construct the rendered subtitle image")
        }

        var semanticBuffer = [CChar](repeating: 0, count: 2_048)
        miraio_ass_semantic_text(context, milliseconds, &semanticBuffer, semanticBuffer.count)
        let terminator = semanticBuffer.firstIndex(of: 0) ?? semanticBuffer.endIndex
        let semanticBytes = semanticBuffer[..<terminator].map(UInt8.init(bitPattern:))
        let semanticText = String(decoding: semanticBytes, as: UTF8.self)

        return Result(
            image: image,
            semanticText: semanticText,
            changeKind: Int(frame.change_kind),
            elapsedMilliseconds: elapsed.timeInterval * 1_000
        )
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
    }
}

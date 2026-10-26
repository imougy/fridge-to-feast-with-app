import AVFoundation
import CoreGraphics
import CoreTransferable
import UIKit
import UniformTypeIdentifiers
import FridgeToFeastCore

/// A video picked from the photo library, transferred as a file copy.
struct MovieFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return MovieFile(url: copy)
        }
    }
}

/// Turns a sweep video into CapturedPhotos: sample frames on device,
/// score their sharpness, and let the core KeyframeSelector pick the
/// keepers. Downstream the pipeline cannot tell a video frame from a
/// still photo, which is the design — video changes capture, not the flow.
enum VideoFrameExtractor {
    /// How often to sample a candidate frame, in seconds.
    static let sampleInterval = 0.35

    static func extract(from videoURL: URL, kind: PhotoKind) async -> [CapturedPhoto] {
        let asset = AVURLAsset(url: videoURL)
        guard let duration = try? await asset.load(.duration) else { return [] }
        let seconds = CMTimeGetSeconds(duration)
        guard seconds.isFinite, seconds > 0 else { return [] }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 1280)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)

        var times: [CMTime] = []
        var t = 0.2
        while t < seconds {
            times.append(CMTime(seconds: t, preferredTimescale: 600))
            t += sampleInterval
        }
        guard !times.isEmpty else { return [] }

        var candidates: [FrameCandidate] = []
        for await result in generator.images(for: times) {
            guard case .success(let requestedTime, let image, _) = result,
                  let jpeg = UIImage(cgImage: image).jpegData(compressionQuality: 0.8)
            else { continue }
            candidates.append(FrameCandidate(
                timestamp: CMTimeGetSeconds(requestedTime),
                sharpness: sharpness(of: image),
                imageData: jpeg))
        }
        let frames = KeyframeSelector.select(from: candidates)
        return KeyframeSelector.photos(from: frames, kind: kind)
    }

    /// A cheap blur meter: downscale to a small grayscale buffer and
    /// measure neighbor-difference energy. Sharp frames have strong
    /// edges and score high; motion-blurred frames score low.
    static func sharpness(of image: CGImage) -> Double {
        let width = 160
        let height = max(1, Int(Double(width) * Double(image.height) / Double(image.width)))
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(
            data: &pixels, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return 0 }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var energy = 0.0
        for y in 0..<height {
            for x in 0..<width {
                let i = y * width + x
                let p = Double(pixels[i])
                if x + 1 < width { let d = p - Double(pixels[i + 1]); energy += d * d }
                if y + 1 < height { let d = p - Double(pixels[i + width]); energy += d * d }
            }
        }
        return energy / Double(width * height)
    }
}

import Foundation

/// One candidate frame pulled from a sweep video, before selection.
/// The app layer (AVFoundation) decodes and scores these; the selection
/// itself is pure logic in this file so it is testable without any
/// media frameworks.
public struct FrameCandidate: Sendable {
    /// Seconds into the video.
    public var timestamp: Double
    /// Higher means sharper. Scored by the app layer; the scale is
    /// arbitrary because selection only compares frames within one video.
    public var sharpness: Double
    public var imageData: Data

    public init(timestamp: Double, sharpness: Double, imageData: Data) {
        self.timestamp = timestamp
        self.sharpness = sharpness
        self.imageData = imageData
    }
}

public struct KeyframeConfig: Sendable {
    /// Most frames the pipeline will segment from one sweep.
    public var maxFrames: Int
    /// Frames closer together than this are treated as the same view;
    /// the sharper one wins.
    public var minGapSeconds: Double
    /// A frame is eligible only if its sharpness is at least this
    /// fraction of the sharpest frame's. This is the motion-blur guard.
    public var sharpnessFloorRatio: Double

    public init(maxFrames: Int = 8, minGapSeconds: Double = 0.7,
                sharpnessFloorRatio: Double = 0.45) {
        self.maxFrames = maxFrames
        self.minGapSeconds = minGapSeconds
        self.sharpnessFloorRatio = sharpnessFloorRatio
    }
}

/// Picks the frames from a sweep video that are worth segmenting.
///
/// A sweep is 5–10 seconds of a moving camera: most frames are blurry or
/// near-duplicates of their neighbors. Selection is three passes:
/// 1. Drop frames below the sharpness floor (motion blur).
/// 2. Collapse frames that are too close in time, keeping the sharper.
/// 3. If still over the cap, thin evenly so the whole sweep is covered,
///    not just its sharpest beginning.
public enum KeyframeSelector {
    public static func select(from candidates: [FrameCandidate],
                              config: KeyframeConfig = KeyframeConfig()) -> [FrameCandidate] {
        guard let best = candidates.map(\.sharpness).max(), best > 0 else { return [] }
        let floor = best * config.sharpnessFloorRatio
        let eligible = candidates
            .filter { $0.sharpness >= floor }
            .sorted { $0.timestamp < $1.timestamp }

        var picked: [FrameCandidate] = []
        for frame in eligible {
            if let last = picked.last,
               frame.timestamp - last.timestamp < config.minGapSeconds {
                if frame.sharpness > last.sharpness {
                    picked[picked.count - 1] = frame
                }
                continue
            }
            picked.append(frame)
        }

        guard picked.count > config.maxFrames, config.maxFrames > 1 else { return picked }
        let stride = Double(picked.count - 1) / Double(config.maxFrames - 1)
        return (0..<config.maxFrames).map { picked[Int((Double($0) * stride).rounded())] }
    }

    /// Converts selected frames into pipeline photos of the given kind.
    /// Downstream, a video frame is indistinguishable from a still photo —
    /// that is the design: video changes capture, not the pipeline.
    public static func photos(from frames: [FrameCandidate], kind: PhotoKind, sourceID: UUID? = nil) -> [CapturedPhoto] {
        frames.map { CapturedPhoto(kind: kind, imageData: $0.imageData, videoTimestamp: $0.timestamp, sourceID: sourceID) }
    }
}

//
//  DetectionRecorder.swift
//  VideoHumanDetection
//
//  Created by Eric Hsu on 2021/11/22.
//

import AVFoundation
import Photos
import ProgressHUD
import UIKit
import VideoToolbox

// MARK: - PredictionInfo

struct PredictionInfo {
    let label: String
    let frame: CGRect
    let color: UIColor
}

// MARK: - DetectionRecorder

final class DetectionRecorder {
    // MARK: Lifecycle

    init(asset: AVAsset) {
        self.asset = asset
    }

    // MARK: Internal

    lazy var tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("tmp.mp4")

    let asset: AVAsset

    var predictions: [Int: [PredictionInfo]] = [:]

    var exportSession: AVAssetExportSession? {
        didSet {
            DispatchQueue.main.async {
                self.exportSession != nil ? ProgressHUD.show() : ProgressHUD.dismiss()
            }
        }
    }

    func exportVideos() {
        print("start to export")

        var startTime: Double = -1
        var endTime: Double = -1
        var chunks: [CMTimeRange] = []
        let maxDuration = asset.duration.seconds
        for t in predictions.keys {
            if startTime < Double(t), endTime > Double(t) {
                continue
            } else {
                startTime = Double(t)
                endTime = min(Double(t) + 10, maxDuration)
                print("new pair", startTime, endTime)
                let range = CMTimeRange(
                    start: CMTime(seconds: startTime, preferredTimescale: 30),
                    end: CMTime(seconds: endTime, preferredTimescale: 30)
                )
                chunks.append(range)
                // TODO: export videos by chunks
            }
        }

        exportVideo(start: .zero, end: asset.duration)
    }

    func exportVideo(start: CMTime, end: CMTime) {
        let timescale: Int32 = 30 // asset.tracks(withMediaType: .video).first?.naturalTimeScale ?? 30
        let composition = AVMutableComposition()

        let videoComposition = AVMutableVideoComposition()
        videoComposition.frameDuration = CMTimeMake(value: 1, timescale: timescale)
        videoComposition.renderScale = 1.0

        let compositionCommentaryTrack: AVMutableCompositionTrack? = composition.addMutableTrack(withMediaType: AVMediaType.audio, preferredTrackID: kCMPersistentTrackID_Invalid)

        let compositionVideoTrack: AVMutableCompositionTrack? = composition.addMutableTrack(withMediaType: AVMediaType.video, preferredTrackID: kCMPersistentTrackID_Invalid)

        var naturalSize = CGSize.zero
        if let clipVideoTrack: AVAssetTrack = asset.tracks(withMediaType: AVMediaType.video).first {
            try? compositionVideoTrack?.insertTimeRange(CMTimeRangeMake(start: .zero, duration: asset.duration), of: clipVideoTrack, at: .zero)
            naturalSize = clipVideoTrack.naturalSize
        }

        if let audioTrack = asset.tracks(withMediaType: AVMediaType.audio).first {
            try? compositionCommentaryTrack?.insertTimeRange(CMTimeRangeMake(start: .zero, duration: asset.duration), of: audioTrack, at: .zero)
        }

        if asset.orientation == .portrait {
            naturalSize = CGSize(width: naturalSize.height, height: naturalSize.width)
        }

        videoComposition.renderSize = naturalSize
        let instructionTimeRange = CMTimeRangeMake(start: .zero, duration: asset.duration)
        let instruction = WatermarkCompositionInstruction(timeRange: instructionTimeRange, predictions: predictions)
        videoComposition.instructions = [instruction]
        videoComposition.customVideoCompositorClass = BoundingBoxCompositor.self

        let videoPath = tempURL.path
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: videoPath) {
            try! fileManager.removeItem(atPath: videoPath)
        }

        print("video path \(videoPath)")

        exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)
        exportSession?.outputFileType = AVFileType.mp4
        exportSession?.outputURL = URL(fileURLWithPath: videoPath)
        exportSession?.videoComposition = videoComposition
        exportSession?.timeRange = CMTimeRange(start: start, end: end)
        var exportProgress: Float = 0
        let queue = DispatchQueue(label: "Export Progress Queue")
        queue.async {
            while self.exportSession != nil {
                exportProgress = (self.exportSession?.progress)!
                print("current progress = \(exportProgress), \(self.exportSession?.status.rawValue)")
                DispatchQueue.main.async {
                    ProgressHUD.showProgress(exportProgress.cgFloat)
                }
                sleep(1)
            }
        }

        exportSession?.exportAsynchronously {
            if self.exportSession?.status == AVAssetExportSession.Status.failed {
                print("Failed \(self.exportSession?.error)")
                ProgressHUD.dismiss()
                ProgressHUD.showError()
            } else if self.exportSession?.status == AVAssetExportSession.Status.completed {
                self.exportSession = nil

                print("Export completed")

                do {
                    try PHPhotoLibrary.shared().performChangesAndWait {
                        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: self.tempURL)
                    }
                    DispatchQueue.main.async {
                        ProgressHUD.showSucceed()
                    }
                } catch {
                    print(error)
                }
            }
        }
    }
}

extension AVAsset {
    var orientation: AVCaptureVideoOrientation {
        if let videoTrack = tracks(withMediaType: .video).first {
            let txf = videoTrack.preferredTransform
            let size = videoTrack.naturalSize
            if size.width == txf.tx, size.height == txf.ty {
                return .landscapeLeft
            } else if txf.tx == 0, txf.ty == 0 {
                return .landscapeRight
            } else if txf.tx == 0, txf.ty == size.width {
                return .portraitUpsideDown
            } else {
                return .portrait
            }
        }
        return .portrait
    }
}

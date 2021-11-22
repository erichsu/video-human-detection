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

// MARK: - DetectInfo

struct DetectInfo {
    let time: CMTime
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
    lazy var assetWriter = try? AVAssetWriter(url: tempURL, fileType: .mp4)
    lazy var assetWriterInput = AVAssetWriterInput(
        mediaType: .video,
        outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            // For simplicity, assume 16:9 aspect ratio.
            // For a production use case, modify this as necessary to match the source content.
            AVVideoWidthKey: 1920,
            AVVideoHeightKey: 1080,
            AVVideoCompressionPropertiesKey: [
                kVTCompressionPropertyKey_AverageBitRate: 6000000,
                kVTCompressionPropertyKey_ProfileLevel: kVTProfileLevel_H264_High_4_2
            ]
        ],
        sourceFormatHint: asset.tracks(withMediaType: .video).first?.formatDescriptions.first as! CMFormatDescription
    )
    lazy var adapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: assetWriterInput, sourcePixelBufferAttributes: nil)
    var isRecording = false
    let asset: AVAsset

    var detectedObjects: [DetectInfo] = []
    let boundingBoxViews = [BoundingBoxView]().then {
        for _ in 0 ..< 10 {
            $0.append(BoundingBoxView())
        }
    }

    var exportSession: AVAssetExportSession? {
        didSet {
            DispatchQueue.main.async {
                self.exportSession != nil ? ProgressHUD.show() : ProgressHUD.dismiss()
            }
        }
    }

    func startRecord() {
        guard !isRecording else { return }
        if FileManager.default.fileExists(atPath: tempURL.path) {
            try! FileManager.default.removeItem(atPath: tempURL.path)
        }
        print("recording to \(tempURL)")
        isRecording = true

        print("start writing")
        if assetWriter?.startWriting() == false {
            print("writing fails \(assetWriter?.error)")
        }
        assetWriter?.startSession(atSourceTime: .zero)
    }

    func stopRecord() {
        isRecording = false

        assetWriterInput.markAsFinished()
        print("finishing writing \(assetWriter?.status.rawValue)")
        assetWriter?.finishWriting {
            print("finished writing \(self.assetWriter?.status.rawValue)")
        }
    }

    func appendBuffer(_ buffer: CMSampleBuffer) {
        if isRecording, assetWriterInput.isReadyForMoreMediaData == true {
//
//            let seconds = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
//            let time = CMTime(seconds: seconds, preferredTimescale: CMTimeScale(600))
//            adapter.append(pixelBuffer, withPresentationTime: time)

            assetWriterInput.append(buffer)
        }
    }

    func exportVideos() {
        print("start to export")
    }

    func exportVideo(start: CMTime, end: CMTime) {
        let timescale: Int32 = 30 // asset.tracks(withMediaType: .video).first!.naturalTimeScale
        let composition = AVMutableComposition()

        let videoComposition = AVMutableVideoComposition()
        videoComposition.frameDuration = CMTimeMake(value: 1, timescale: timescale)
        videoComposition.renderScale = 1.0

        let compositionCommentaryTrack: AVMutableCompositionTrack? = composition.addMutableTrack(withMediaType: AVMediaType.audio, preferredTrackID: kCMPersistentTrackID_Invalid)

        let compositionVideoTrack: AVMutableCompositionTrack? = composition.addMutableTrack(withMediaType: AVMediaType.video, preferredTrackID: kCMPersistentTrackID_Invalid)

        let clipVideoTrack: AVAssetTrack = asset.tracks(withMediaType: AVMediaType.video)[0]
        let audioTrack: AVAssetTrack? = asset.tracks(withMediaType: AVMediaType.audio)[0]
        try? compositionCommentaryTrack?.insertTimeRange(CMTimeRangeMake(start: .zero, duration: asset.duration), of: audioTrack!, at: .zero)
        try? compositionVideoTrack?.insertTimeRange(CMTimeRangeMake(start: .zero, duration: asset.duration), of: clipVideoTrack, at: .zero)

        var naturalSize = clipVideoTrack.naturalSize
        if asset.orientation == .portrait {
            naturalSize = CGSize(width: naturalSize.height, height: naturalSize.width)
        }

        videoComposition.renderSize = naturalSize

        let scale = CGFloat(1.0)

        var transform = CGAffineTransform(scaleX: CGFloat(scale), y: CGFloat(scale))

        switch asset.orientation {
        case .landscapeRight: break
            // isPortrait = false
        case .landscapeLeft:
            transform = transform.translatedBy(x: naturalSize.width, y: naturalSize.height)
            transform = transform.rotated(by: .pi)
        case .portrait:
            transform = transform.translatedBy(x: naturalSize.width, y: 0)
            transform = transform.rotated(by: CGFloat(Float.pi / 2))
        case .portraitUpsideDown: break
        @unknown default:
            break
        }

        let frontLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack!)
        frontLayerInstruction.setTransform(transform, at: .zero)

        let mainInstruction = AVMutableVideoCompositionInstruction()
        mainInstruction.timeRange = CMTimeRangeMake(start: .zero, duration: composition.duration)
        mainInstruction.layerInstructions = [frontLayerInstruction]

        videoComposition.instructions = [mainInstruction]
    }


        let parentLayer = CALayer()
        parentLayer.frame = CGRect(x: 0, y: 0, width: naturalSize.width, height: naturalSize.height)

        let videoLayer = CALayer()
        videoLayer.frame = parentLayer.frame

        parentLayer.addSublayer(videoLayer)

        for i in 0 ..< boundingBoxViews.count {
            if i < predictions.count {
                boundingBoxViews[i].show(
                    frame: CGRect(x: 48, y: 152, width: 277, height: 409),
                    label: "person",
                    color: .red
                )

            }
        }
        let boxView = BoundingBoxView()
        boxView.addToLayer(parentLayer)
        boxView.show(
            frame: CGRect(x: 48, y: 152, width: 277, height: 409),
            label: "person",
            color: .red
        )

        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parentLayer)

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
                print("current progress == \(exportProgress)")
                DispatchQueue.main.async {
                    ProgressHUD.showProgress(exportProgress.cgFloat)
                }
                sleep(1)
            }
        }

        exportSession?.exportAsynchronously(completionHandler: {
            if self.exportSession?.status == AVAssetExportSession.Status.failed {
                print("Failed \(self.exportSession?.error)")
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
        })
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

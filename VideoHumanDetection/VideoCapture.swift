//
//  VideoCapture.swift
//  VideoHumanDetection
//
//  Created by Eric Hsu on 2021/11/21.
//

import AVFoundation
import CoreVideo
import UIKit

// MARK: - VideoCaptureDelegate

protocol VideoCaptureDelegate: AnyObject {
    func videoCapture(_ capture: VideoCapture, didCaptureVideoFrame: CMSampleBuffer)
}

// MARK: - VideoCapture

class VideoCapture: NSObject {
    // MARK: Internal

    weak var delegate: VideoCaptureDelegate?
    lazy var previewLayer = AVSampleBufferDisplayLayer()
    var reader: AVAssetReader?
    var readerOutput: AVAssetReaderTrackOutput?
    let queue = DispatchQueue(label: "org.yao.asset-reader-queue")

    var videoDimension: CGSize? {
        guard let videoTrack = asset?.tracks(withMediaType: .video).first else { return nil }
        let videoDesc = videoTrack.formatDescriptions.first as! CMVideoFormatDescription
        let dimension = CMVideoFormatDescriptionGetPresentationDimensions(videoDesc, usePixelAspectRatio: true, useCleanAperture: true)
        return dimension
    }
    private var asset: AVAsset?

    func setup(
        _ asset: AVAsset?,
        completion: @escaping (Bool) -> Void
    ) {
        self.asset = asset
        queue.async {
            let success = self.setupAsset(asset)
            DispatchQueue.main.async {
                completion(success)
            }
        }
    }

    func start() {

        if reader?.status != .reading {
            reader?.startReading()
            queue.async {
                while self.reader?.status == .reading, let buffer = self.readerOutput?.copyNextSampleBuffer() {
                    self.delegate?.videoCapture(self, didCaptureVideoFrame: buffer)
                    DispatchQueue.main.async {
                        self.previewLayer.enqueue(buffer)
                    }
                }
            }
        }
    }

    func stop() {
        print("try to stop reading")
        if reader?.status == .reading {
            reader?.cancelReading()
            print("reading canceled")
        }
        self.previewLayer.flushAndRemoveImage()
    }

    // MARK: Private

    private func setupAsset(_ asset: AVAsset?) -> Bool {
        guard let asset = asset else { return false }
        do {
            let assetReader = try AVAssetReader(asset: asset)
            reader = assetReader

            guard let videoTrack = asset.tracks(withMediaType: .video).first else { return false }
            let settings: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: kCVPixelFormatType_32BGRA)
            ]

            let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: settings)
            readerOutput = output
            assetReader.add(output)

            return true
        } catch {
            print(error)
            return false
        }
    }
}

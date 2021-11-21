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

    func setUp(
        _ asset: AVAsset?,
        completion: @escaping (Bool) -> Void
    ) {
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
                while let buffer = self.readerOutput?.copyNextSampleBuffer() {
                    self.delegate?.videoCapture(self, didCaptureVideoFrame: buffer)
                    self.previewLayer.enqueue(buffer)
                }
            }
        }
    }

    func stop() {
        if reader?.status == .reading {
            reader?.cancelReading()
        }
    }

//    func setUpCamera(sessionPreset: AVCaptureSession.Preset) -> Bool {
//        captureSession.beginConfiguration()
//        captureSession.sessionPreset = sessionPreset
//
//        guard let captureDevice = AVCaptureDevice.default(for: AVMediaType.video) else {
//            print("Error: no video devices available")
//            return false
//        }
//
//        guard let videoInput = try? AVCaptureDeviceInput(device: captureDevice) else {
//            print("Error: could not create AVCaptureDeviceInput")
//            return false
//        }
//
//        if captureSession.canAddInput(videoInput) {
//            captureSession.addInput(videoInput)
//        }
//
//        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
//        previewLayer.videoGravity = AVLayerVideoGravity.resizeAspect
//        previewLayer.connection?.videoOrientation = .portrait
//        self.previewLayer = previewLayer
//
//        let settings: [String: Any] = [
//            kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: kCVPixelFormatType_32BGRA)
//        ]
//
//        videoOutput.videoSettings = settings
//        videoOutput.alwaysDiscardsLateVideoFrames = true
//        videoOutput.setSampleBufferDelegate(self, queue: queue)
//        if captureSession.canAddOutput(videoOutput) {
//            captureSession.addOutput(videoOutput)
//        }
//
//        // We want the buffers to be in portrait orientation otherwise they are
//        // rotated by 90 degrees. Need to set this _after_ addOutput()!
//        videoOutput.connection(with: AVMediaType.video)?.videoOrientation = .portrait
//
//        captureSession.commitConfiguration()
//
//        return true
//    }

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
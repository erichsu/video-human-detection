//
//  BoundingBoxCompositor.swift
//  VideoHumanDetection
//
//  Created by Eric Hsu on 2021/11/22.
//

import AVFoundation
import Foundation
import UIKit

// MARK: - BoundingBoxCompositor

class BoundingBoxCompositor: NSObject, AVVideoCompositing {
    var duration: CMTime?

    var sourcePixelBufferAttributes: [String: Any]? {
        ["\(kCVPixelBufferPixelFormatTypeKey)": kCVPixelFormatType_32BGRA]
    }

    var requiredPixelBufferAttributesForRenderContext: [String: Any] {
        ["\(kCVPixelBufferPixelFormatTypeKey)": kCVPixelFormatType_32BGRA]
    }

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        // do anything in here you need to before you start writing frames
    }

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let trackId = request.sourceTrackIDs.first?.int32Value else {
            return request.finishCancelledRequest()
        }
        let buffer = request.sourceFrame(byTrackID: trackId)
        let instruction = request.videoCompositionInstruction
        let currentTime = Int(request.compositionTime.seconds)

        if let inst = instruction as? WatermarkCompositionInstruction, let predictions = inst.predictions[currentTime], !predictions.isEmpty {
            // lock the buffer, create a new context and draw the watermark image
            CVPixelBufferLockBaseAddress(buffer!, CVPixelBufferLockFlags.readOnly)
            let newContext = CGContext(data: CVPixelBufferGetBaseAddress(buffer!), width: CVPixelBufferGetWidth(buffer!), height: CVPixelBufferGetHeight(buffer!), bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer!), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)

            for prediction in predictions.prefix(3) {
                let width = CVPixelBufferGetWidth(buffer!)
                let height = CVPixelBufferGetHeight(buffer!)
                let scale = CGAffineTransform.identity.scaledBy(x: CGFloat(width), y: CGFloat(height))
                let transform = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: CGFloat(-height))
                let frame = prediction.frame.applying(scale).applying(transform)
                newContext?.setStrokeColor(UIColor.blue.cgColor)
                newContext?.setLineWidth(10)
                newContext?.addRect(frame)
                newContext?.drawPath(using: .stroke)
            }
            CVPixelBufferUnlockBaseAddress(buffer!, CVPixelBufferLockFlags.readOnly)
        }
        request.finish(withComposedVideoFrame: buffer!)
    }

    func cancelAllPendingVideoCompositionRequests() {
        // anything you want to do when the compositing is canceled
    }
}

// MARK: - WatermarkCompositionInstruction

class WatermarkCompositionInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    // MARK: Lifecycle

    init(timeRange: CMTimeRange, predictions: [Int: [PredictionInfo]]) {
        self.timeRange = timeRange
        self.predictions = predictions
    }

    // MARK: Internal

    var predictions: [Int: [PredictionInfo]]

    var timeRange: CMTimeRange

    var enablePostProcessing: Bool = true

    var containsTweening: Bool = true

    var requiredSourceTrackIDs: [NSValue]?

    var passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid
}

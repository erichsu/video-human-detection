//
//  ViewController.swift
//  VideoHumanDetection
//
//  Created by Eric Hsu on 2021/11/22.
//

import CoreMedia
import CoreML
import PhotosUI
import RxCocoa
import RxSwift
import SnapKit
import SwifterSwift
import Then
import UIKit
import Vision

// MARK: - ViewController

final class ViewController: UIViewController {
    // MARK: Internal

    let coreMLModel = MobileNetV2_SSDLite()
    let maxBoundingBoxViews = 10
    let bag = DisposeBag()

    lazy var videoCapture = VideoCapture()

    lazy var visionRequest: VNCoreMLRequest = {
        let request = VNCoreMLRequest(model: visionModel, completionHandler: {
            [weak self] request, error in
                self?.processObservations(for: request, error: error)
        })
        request.imageCropAndScaleOption = .scaleFill
        return request
    }()

    lazy var visionModel: VNCoreMLModel = {
        do {
            return try VNCoreMLModel(for: coreMLModel.model)
        } catch {
            fatalError("Failed to create VNCoreMLModel: \(error)")
        }
    }()

    lazy var recorder = DetectionRecorder(asset: selectedAsset!)

    var boundingBoxViews = [BoundingBoxView]()
    var currentBuffer: CVPixelBuffer?
    var latestBuffer: CMSampleBuffer!
    var currentTimeCode: CMTime?
    var colors: [String: UIColor] = [:]
    var selectedAsset: AVURLAsset?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupSubviews()
        setupBoundingBoxViews()
        requestPhotoLibraryPermission()
    }

    func predict(sampleBuffer: CMSampleBuffer) {
        latestBuffer = sampleBuffer
        if currentBuffer == nil, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            currentBuffer = pixelBuffer

            if let timeInfos = try? sampleBuffer.sampleTimingInfos(), let time = timeInfos.first {
                currentTimeCode = time.presentationTimeStamp
            }

            // Get additional info from the camera.
            var options: [VNImageOption: Any] = [:]
            if let cameraIntrinsicMatrix = CMGetAttachment(sampleBuffer, key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, attachmentModeOut: nil) {
                options[.cameraIntrinsics] = cameraIntrinsicMatrix
            }

            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: options)
            do {
                try handler.perform([visionRequest])
            } catch {
                print("Failed to perform Vision request: \(error)")
            }

            currentBuffer = nil
        }
    }

    // MARK: Private

    // MARK: Subviews

    private lazy var previewImageView = UIImageView().then {
        $0.backgroundColor = .lightGray
    }

    private lazy var openButton = UIButton().then {
        $0.setImage(UIImage(systemName: "photo"), for: .normal)
        $0.setTitle("Open video", for: .normal)
        $0.setTitleColor(UIColor.tintColor, for: .normal)
    }

    private lazy var startButton = UIButton().then {
        $0.setImage(UIImage(systemName: "play"), for: .normal)
        $0.setTitle("Preview", for: .normal)
        $0.setTitleColor(UIColor.tintColor, for: .normal)
    }

    private lazy var exportButton = UIButton().then {
        $0.setImage(UIImage(systemName: "square.and.arrow.up"), for: .normal)
        $0.setTitle("Export", for: .normal)
        $0.setTitleColor(UIColor.tintColor, for: .normal)
    }

    private func requestPhotoLibraryPermission() {
        guard PHPhotoLibrary.authorizationStatus() != .authorized else { return }
        PHPhotoLibrary.requestAuthorization { _ in }
    }

    private func setupSubviews() {
        let bottomStack = UIStackView(
            arrangedSubviews: [openButton, startButton, exportButton],
            axis: .horizontal,
            distribution: .equalCentering
        )
        view.addSubviews([previewImageView, bottomStack])
        previewImageView.snp.makeConstraints {
            $0.edges.equalToSuperview()
        }
        bottomStack.snp.makeConstraints {
            $0.left.bottom.right.equalTo(view.safeAreaLayoutGuide).inset(20)
        }

        openButton.rx.tap
            .bind(with: self) { `self`, _ in self.openLibrary() }
            .disposed(by: bag)

        startButton.rx.tap
            .bind(with: self) { `self`, _ in
                self.startReadAsset()
            }
            .disposed(by: bag)

        exportButton.rx.tap
            .bind(with: self) { _, _ in
//                ProgressHUD.show()
//                self.startReadAsset()
                self.recorder.exportVideos()
            }
            .disposed(by: bag)
    }

    private func openLibrary() {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = PHPickerFilter.any(of: [.videos])
        let picker = PHPickerViewController(configuration: configuration)

        picker.delegate = self
        present(picker, animated: true)
    }

    private func startReadAsset() {
        videoCapture.stop()
        videoCapture.delegate = self
        videoCapture.setup(selectedAsset) { success in
            if success {
                self.previewImageView.layer.sublayers?.forEach { $0.removeFromSuperlayer() }

                self.previewImageView.layer.addSublayer(self.videoCapture.previewLayer)
                self.videoCapture.previewLayer.frame = self.previewImageView.bounds
                print("loaded preview layer")

                for box in self.boundingBoxViews {
                    box.addToLayer(self.previewImageView.layer)
                }
                self.videoCapture.start()
            }
        }
    }

    private func setupBoundingBoxViews() {
        for _ in 0 ..< maxBoundingBoxViews {
            boundingBoxViews.append(BoundingBoxView())
        }

        // The label names are stored inside the MLModel's metadata.
        guard let userDefined = coreMLModel.model.modelDescription.metadata[MLModelMetadataKey.creatorDefinedKey] as? [String: String],
              let allLabels = userDefined["classes"]
        else {
            fatalError("Missing metadata")
        }

        let labels = allLabels.components(separatedBy: ",")

        // Assign random colors to the classes.
        for label in labels {
            colors[label] = UIColor(red: CGFloat.random(in: 0...1),
                                    green: CGFloat.random(in: 0...1),
                                    blue: CGFloat.random(in: 0...1),
                                    alpha: 1)
        }
    }

    private func processObservations(for request: VNRequest, error: Error?) {
        DispatchQueue.main.async {
            if let results = request.results as? [VNRecognizedObjectObservation] {
                let personObjects = results
                    .filter { $0.labels[0].identifier == "person" }
//                print("find persons: \(personObjects.count)")

                self.show(predictions: personObjects)
            } else {
                self.show(predictions: [])
            }
        }
    }

    private func show(predictions: [VNRecognizedObjectObservation]) {
        for i in 0 ..< boundingBoxViews.count {
            if i < predictions.count {
                let prediction = predictions[i]

                let fittedSize = videoCapture.videoDimension?.aspectFit(to: view.bounds.size) ?? .zero
                let width = fittedSize.width
                let height = fittedSize.height

                let offsetY = (view.bounds.height - height) / 2
                let scale = CGAffineTransform.identity.scaledBy(x: width, y: height)
                let transform = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -height - offsetY)
                let rect = prediction.boundingBox.applying(scale).applying(transform)

                // The labels array is a list of VNClassificationObservation objects,
                // with the highest scoring class first in the list.
                let bestClass = prediction.labels[0].identifier
                let confidence = prediction.labels[0].confidence

                // Show the bounding box.
                let label = String(format: "%@ %.1f", bestClass, confidence * 100)
                let color = colors[bestClass] ?? UIColor.red
//                print("label:\(label), rect:\(rect), \(currentTimeCode.seconds ?? .zero)")

                let currentTime = Int(currentTimeCode?.seconds ?? 0)
                if recorder.predictions[currentTime] != nil {
                    recorder.predictions[currentTime]?.append(PredictionInfo(label: label, frame: prediction.boundingBox, color: color))
                } else {
                    recorder.predictions[currentTime] = [PredictionInfo(label: label, frame: prediction.boundingBox, color: color)]
                }

                boundingBoxViews[i].show(frame: rect, label: label, color: color)

            } else {
                boundingBoxViews[i].hide()
            }
        }
    }
}

// MARK: PHPickerViewControllerDelegate

extension ViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        guard let result = results.first else { return }
        guard let typeIdentifier = result.itemProvider.registeredTypeIdentifiers.first else { return }

        result.itemProvider.loadInPlaceFileRepresentation(forTypeIdentifier: typeIdentifier) { url, _, error in

            if let url = url {
                print("loading....\(url)")
                DispatchQueue.main.sync {
                    self.selectedAsset = AVURLAsset(url: url)
                    picker.dismiss(animated: true)
                }
            } else {
                print("loading failed", error as Any)
            }
        }
    }
}

// MARK: VideoCaptureDelegate

extension ViewController: VideoCaptureDelegate {
    func videoCapture(_ capture: VideoCapture, didCaptureVideoFrame sampleBuffer: CMSampleBuffer) {
        predict(sampleBuffer: sampleBuffer)
    }
}

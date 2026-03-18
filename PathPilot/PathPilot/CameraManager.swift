//
//  CameraManager.swift
//  PathPilot
//
//  Created by Marius Horn on 11/02/2026.
//

import AVFoundation
import Combine
import SwiftUI

enum ObstacleDirection: String {
    case left
    case center
    case right

    var spokenPhrase: String {
        switch self {
        case .left:
            return "left"
        case .center:
            return "ahead"
        case .right:
            return "right"
        }
    }
}

enum ObstacleUrgency: Int {
    case low
    case medium
    case high
}

struct ObstacleAlert {
    let message: String
    let direction: ObstacleDirection
    let urgency: ObstacleUrgency
}

@MainActor
final class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var isAuthorized = false
    @Published var isSessionRunning = false
    @Published var isDetectionEnabled: Bool = true {
        didSet { detectionEnabledUnsafe = isDetectionEnabled }
    }
    @Published var isPosterModeEnabled: Bool = false {
        didSet { posterModeEnabledUnsafe = isPosterModeEnabled }
    }
    @Published var isReadingPoster: Bool = false {
        didSet { isReadingPosterUnsafe = isReadingPoster }
    }
    @Published var detectedLabel: String = "Monitoring path"
    @Published var statusText: String = "Starting camera"
    @Published var activeWarningText: String = "Path clear"
    @Published var posterText: String = ""

    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    nonisolated(unsafe) private let detector = ObjectDetector(modelName: "yolov8n", labels: ObjectDetector.cocoLabels)
    nonisolated(unsafe) private let posterReader = PosterReader()
    private let alertManager = AlertManager()
    private let speechManager = SpeechManager()

    nonisolated(unsafe) private var lastClassificationTimeUnsafe = Date.distantPast
    nonisolated(unsafe) private var isDetecting = false
    nonisolated(unsafe) private var detectionEnabledUnsafe = true
    nonisolated(unsafe) private var posterModeEnabledUnsafe = false
    nonisolated(unsafe) private var isReadingPosterUnsafe = false
    nonisolated(unsafe) private var pendingPosterReadUnsafe = false

    nonisolated(unsafe) private let classificationInterval: TimeInterval = 0.45
    nonisolated(unsafe) private let detectionQueue = DispatchQueue(label: "detection.queue")
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private var isConfigured = false
    private var posterScanTask: Task<Void, Never>?

    private var stableAlertKey = ""
    private var stableAlertCount = 0
    private let stableRequiredCount = 2
    private let centerCorridor = 0.22...0.78
    private let strongCorridor = 0.36...0.64
    private let posterScanRegion = CGRect(x: 0.14, y: 0.18, width: 0.72, height: 0.62)

    func requestPermissionAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isAuthorized = true
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    self.isAuthorized = granted
                    if granted {
                        self.startSession()
                    }
                }
            }
        default:
            isAuthorized = false
            statusText = "Camera permission required"
        }
    }

    func toggleDetection() {
        isDetectionEnabled.toggle()
        updateStatusForCurrentMode()
    }

    func startPosterMode() {
        guard !isReadingPoster else { return }
        stableAlertKey = ""
        stableAlertCount = 0
        pendingPosterReadUnsafe = false
        posterScanTask?.cancel()
        posterText = ""
        isPosterModeEnabled = true
        alertManager.stopSpeaking()
        speechManager.stopSpeaking()
        updateStatusForCurrentMode()
        schedulePosterScan()
    }

    func scanPoster() {
        guard isPosterModeEnabled, !isReadingPoster else { return }
        posterScanTask?.cancel()
        pendingPosterReadUnsafe = true
        posterText = ""
        alertManager.stopSpeaking()
        speechManager.stopSpeaking()
        isReadingPoster = true
        updateStatusForCurrentMode()
    }

    func abortPosterRead() {
        pendingPosterReadUnsafe = false
        posterScanTask?.cancel()
        posterText = ""
        isReadingPoster = false
        isPosterModeEnabled = false
        stableAlertKey = ""
        stableAlertCount = 0
        alertManager.stopSpeaking()
        speechManager.stopSpeaking()
        updateStatusForCurrentMode()
    }

    private func startSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.alertManager.prepare()
                self.statusText = "Starting camera"
            }

            if !self.isConfigured {
                self.configureSession()
                self.isConfigured = true
            }

            if !self.session.isRunning {
                self.session.startRunning()
            }

            let runningNow = self.session.isRunning
            Task { @MainActor in
                withAnimation(.easeOut(duration: 0.2)) {
                    self.isSessionRunning = runningNow
                    self.statusText = runningNow ? "Monitoring path" : "Camera unavailable"
                    self.activeWarningText = "Path clear"
                    self.detectedLabel = runningNow ? "Monitoring path" : "Camera unavailable"
                }
            }
        }
    }

    private func schedulePosterScan() {
        posterScanTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))

            guard
                let self,
                !Task.isCancelled,
                self.isPosterModeEnabled,
                !self.isReadingPoster,
                self.posterText.isEmpty
            else {
                return
            }

            self.scanPoster()
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .vga640x480

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            session.commitConfiguration()
            return
        }

        session.addInput(input)
        try? device.lockForConfiguration()
        if device.activeFormat.videoSupportedFrameRateRanges.contains(where: { $0.minFrameRate <= 15 && 15 <= $0.maxFrameRate }) {
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 15)
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 15)
        }
        device.unlockForConfiguration()

        if session.canAddOutput(videoOutput) {
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "video.frames.queue"))
            session.addOutput(videoOutput)
        }

        session.commitConfiguration()
    }

    private func handleDetections(_ detections: [Detection]) {
        guard !isPosterModeEnabled, !isReadingPoster else { return }

        guard let bestAlert = bestAlert(from: detections) else {
            stableAlertKey = ""
            stableAlertCount = 0
            activeWarningText = "Path clear"
            detectedLabel = "Monitoring path"
            return
        }

        let key = "\(bestAlert.direction.rawValue)|\(bestAlert.urgency.rawValue)|\(bestAlert.message)"
        if key == stableAlertKey {
            stableAlertCount += 1
        } else {
            stableAlertKey = key
            stableAlertCount = 1
        }

        activeWarningText = bestAlert.message
        detectedLabel = bestAlert.message

        guard stableAlertCount >= stableRequiredCount else { return }
        alertManager.deliver(bestAlert)
    }

    private func bestAlert(from detections: [Detection]) -> ObstacleAlert? {
        let candidates = detections.compactMap(obstacleCandidate(from:))
        guard let top = candidates.max(by: { $0.riskScore < $1.riskScore }) else {
            return nil
        }

        let message: String
        switch top.urgency {
        case .high:
            message = top.direction == .center ? "Stop, obstacle ahead" : "Stop, obstacle \(top.direction.spokenPhrase)"
        case .medium:
            message = top.direction == .center ? "Obstacle ahead" : "Obstacle \(top.direction.spokenPhrase)"
        case .low:
            message = top.direction == .center ? "Caution ahead" : "Caution \(top.direction.spokenPhrase)"
        }

        return ObstacleAlert(
            message: message,
            direction: top.direction,
            urgency: top.urgency
        )
    }

    private func updateStatusForCurrentMode() {
        if isReadingPoster {
            statusText = "Reading poster"
            activeWarningText = "Scanning for important text"
            detectedLabel = "Scanning poster or paper"
            return
        }

        if isPosterModeEnabled, !posterText.isEmpty {
            statusText = "Poster highlights ready"
            activeWarningText = "Review important text"
            detectedLabel = "Poster highlights"
            return
        }

        if isPosterModeEnabled {
            statusText = "Poster mode ready"
            activeWarningText = "Align poster inside frame"
            detectedLabel = "Ready to scan poster"
            return
        }

        if isDetectionEnabled {
            statusText = "Monitoring path"
            activeWarningText = "Path clear"
            detectedLabel = "Monitoring path"
        } else {
            statusText = "Alerts paused"
            activeWarningText = "Alerts paused"
            detectedLabel = "Alerts paused"
        }
    }

    private func obstacleCandidate(from detection: Detection) -> ObstacleCandidate? {
        let label = canonicalLabel(for: detection.label)
        guard let label else { return nil }

        let direction = direction(for: detection.bbox)
        let area = detection.area
        let centerX = detection.bbox.midX
        let corridorBoost: Float

        if strongCorridor.contains(centerX) {
            corridorBoost = 1.45
        } else if centerCorridor.contains(centerX) {
            corridorBoost = 1.2
        } else {
            corridorBoost = 0.9
        }

        let labelWeight = label == "vehicle" ? Float(1.25) : Float(1.0)
        let confidenceWeight = max(0.65, detection.confidence)
        let riskScore = area * corridorBoost * labelWeight * confidenceWeight

        let urgency: ObstacleUrgency
        if area >= 0.13 || (direction == .center && area >= 0.08) {
            urgency = .high
        } else if area >= 0.055 || (direction == .center && area >= 0.035) {
            urgency = .medium
        } else if centerCorridor.contains(centerX) && area >= 0.02 {
            urgency = .low
        } else {
            return nil
        }

        return ObstacleCandidate(
            label: label,
            direction: direction,
            urgency: urgency,
            riskScore: riskScore
        )
    }

    private func canonicalLabel(for label: String) -> String? {
        switch label.lowercased() {
        case "person":
            return "person"
        case "car", "bus", "truck", "motorcycle", "bicycle":
            return "vehicle"
        case "chair", "bench", "couch", "potted plant", "fire hydrant":
            return "obstacle"
        default:
            return nil
        }
    }

    private func direction(for box: CGRect) -> ObstacleDirection {
        let centerX = box.midX
        if centerX < 0.36 { return .right }
        if centerX > 0.64 { return .left }
        return .center
    }

    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        if pendingPosterReadUnsafe {
            pendingPosterReadUnsafe = false

            detectionQueue.async { [weak self] in
                guard let self else { return }

                self.posterReader.read(pixelBuffer: pixelBuffer, regionOfInterest: self.posterScanRegion) { [weak self] text in
                    guard let self else { return }
                    let highlights = text.isEmpty ? "No important text found." : text

                    Task { @MainActor in
                        self.posterText = highlights
                        self.isReadingPoster = false
                        self.updateStatusForCurrentMode()
                        self.speechManager.speak(text: highlights)
                    }
                }
            }
            return
        }

        let now = Date()
        if !detectionEnabledUnsafe || posterModeEnabledUnsafe || isReadingPosterUnsafe { return }
        if isDetecting { return }
        if now.timeIntervalSince(lastClassificationTimeUnsafe) < classificationInterval { return }
        lastClassificationTimeUnsafe = now
        isDetecting = true

        detectionQueue.async { [weak self] in
            guard let self else { return }
            guard let detector = self.detector else {
                Task { @MainActor in
                    self.detectedLabel = "Model unavailable"
                    self.statusText = "Detection unavailable"
                }
                self.isDetecting = false
                return
            }

            detector.detect(pixelBuffer: pixelBuffer) { [weak self] detections in
                guard let self else { return }
                Task { @MainActor in
                    self.handleDetections(detections)
                }
                self.isDetecting = false
            }
        }
    }
}

private struct ObstacleCandidate {
    let label: String
    let direction: ObstacleDirection
    let urgency: ObstacleUrgency
    let riskScore: Float
}

//
//  CameraManager.swift
//  PathPilot
//
//  Created by Marius Horn on 11/02/2026.
//

import AVFoundation
import SwiftUI
import Combine

@MainActor
final class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    @Published var isAuthorized = false
    @Published var capturedImage: UIImage? = nil
    @Published var isSessionRunning = false
    @Published var detectedLabel: String = "—"
    @Published var isDetectionEnabled: Bool = true {
        didSet { detectionEnabledUnsafe = isDetectionEnabled }
    }
    @Published var isReadingPoster: Bool = false {
        didSet { isReadingPosterUnsafe = isReadingPoster }
    }
    @Published var posterText: String = ""

    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    nonisolated(unsafe) private let detector: ObjectDetector? = ObjectDetector(modelName: "yolov8n", labels: ObjectDetector.cocoLabels)
    private let posterReader = PosterReader()
    private let speechManager = SpeechManager()

    nonisolated(unsafe) private var lastClassificationTimeUnsafe = Date.distantPast
    private let classificationInterval: TimeInterval = 0.7
    nonisolated(unsafe) private var isDetecting: Bool = false
    nonisolated(unsafe) private let detectionQueue = DispatchQueue(label: "detection.queue")
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private var isConfigured = false
    nonisolated(unsafe) private var detectionEnabledUnsafe: Bool = true
    nonisolated(unsafe) private var isReadingPosterUnsafe: Bool = false
    nonisolated(unsafe) private var pendingPosterReadUnsafe: Bool = false
    private let isCriticalOnlyMode = true
    private let posterScanRegion = CGRect(x: 0.12, y: 0.12, width: 0.76, height: 0.76)

    // Stability + speech gates
    private var stableIdentifier: String = ""
    private var stableCount: Int = 0
    private let stableRequiredCount = 2
    private let minAreaToSpeak: Float = 0.02

    private let priorityWeights: [String: Float] = [
        "person": 3.0,
        "stop sign": 2.5,
        "vehicle": 2.0
    ]

    private let maxSpokenObjects = 3

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
        }
    }

    private func startSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.configureAudioSession()
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
                }
            }
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

        // Add video output (needed for live classification)
        if session.canAddOutput(videoOutput) {
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "video.frames.queue"))
            session.addOutput(videoOutput)
        }

        session.commitConfiguration()
    }
    
    private func handleDetections(_ detections: [Detection]) {
        let filtered = detections.compactMap { criticalDetection(from: $0) }
        guard !filtered.isEmpty else {
            stableIdentifier = ""
            stableCount = 0
            return
        }

        let sorted = filtered.sorted { score($0) > score($1) }
        guard let top = sorted.first else { return }

        guard top.area >= minAreaToSpeak else {
            stableIdentifier = ""
            stableCount = 0
            return
        }

        let name = top.label.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if name == stableIdentifier {
            stableCount += 1
        } else {
            stableIdentifier = name
            stableCount = 1
        }
        guard stableCount >= stableRequiredCount else { return }

        let topItems = Array(sorted.prefix(maxSpokenObjects))
        var phrases: [String] = []
        phrases.reserveCapacity(topItems.count)

        for item in topItems {
            let direction = directionFor(box: item.bbox)
            let distance = distanceWord(for: item.area)
            let phrase: String
            if distance.isEmpty {
                phrase = "\(item.label) \(direction)"
            } else {
                phrase = "\(distance) \(item.label) \(direction)"
            }
            phrases.append(phrase)
        }

        speechManager.speakSummary(phrases)
    }

    private func score(_ detection: Detection) -> Float {
        let label = detection.label.lowercased()
        let weight = priorityWeights[label] ?? 1.0
        return detection.confidence * detection.area * weight
    }

    private func criticalDetection(from detection: Detection) -> Detection? {
        let normalized = detection.label.lowercased()
        if !isCriticalOnlyMode { return detection }

        let mappedLabel: String
        switch normalized {
        case "person", "stop sign", "vehicle":
            mappedLabel = normalized
        case "car", "bus", "truck", "motorcycle", "bicycle":
            mappedLabel = "vehicle"
        default:
            return nil
        }

        return Detection(
            label: mappedLabel,
            confidence: detection.confidence,
            bbox: detection.bbox,
            area: detection.area
        )
    }

    private func directionFor(box: CGRect) -> String {
        let centerX = box.midX
        if centerX < 0.33 { return "left" }
        if centerX > 0.66 { return "right" }
        return "ahead"
    }

    private func distanceWord(for area: Float) -> String {
        if area >= 0.06 { return "very close" }
        if area >= 0.02 { return "near" }
        return ""
    }


    
    //TESTER
    private func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try audioSession.setActive(true)
        } catch {
            print("AudioSession error:", error)
        }
    }
//TEST
    func testSpeak() {
        speechManager.speak(text: "Audio test. PathPilot is speaking.")
    }

    func readPoster() {
        guard !isReadingPoster else { return }
        isReadingPoster = true
        posterText = "Reading poster..."
        pendingPosterReadUnsafe = true
    }

    func abortPosterRead() {
        pendingPosterReadUnsafe = false
        isReadingPoster = false
        posterText = ""
        speechManager.stopSpeaking()
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
                    Task { @MainActor in
                        self.posterText = text.isEmpty ? "No text found." : text
                        self.speechManager.speak(text: self.posterText) { [weak self] in
                            Task { @MainActor in
                                self?.posterText = ""
                            }
                        }
                        self.isReadingPoster = false
                    }
                }
            }
            return
        }

        let now = Date()
        if !detectionEnabledUnsafe || isReadingPosterUnsafe { return }
        if isDetecting { return }
        if now.timeIntervalSince(lastClassificationTimeUnsafe) < classificationInterval { return }
        lastClassificationTimeUnsafe = now
        isDetecting = true

        detectionQueue.async { [weak self] in
            guard let self else { return }
            guard let detector = self.detector else {
                Task { @MainActor in self.detectedLabel = "No model loaded" }
                self.isDetecting = false
                return
            }

            detector.detect(pixelBuffer: pixelBuffer) { [weak self] detections in
                guard let self else { return }
                Task { @MainActor in
                    let criticalDetections = detections.compactMap { self.criticalDetection(from: $0) }
                    if let top = criticalDetections.max(by: { $0.confidence < $1.confidence }) {
                        self.detectedLabel = "\(top.label) (\(Int(top.confidence * 100))%)"
                    } else {
                        self.detectedLabel = "—"
                    }
                    self.handleDetections(criticalDetections)
                }
                self.isDetecting = false
            }
        }
    }
}

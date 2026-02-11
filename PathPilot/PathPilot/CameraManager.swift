//
//  CameraManager.swift
//  PathPilot
//
//  Created by Marius Horn on 11/02/2026.
//

import AVFoundation
import SwiftUI
import Combine

final class CameraManager: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {

    @Published var isAuthorized = false
    @Published var capturedImage: UIImage? = nil
    @Published var isSessionRunning = false
    @Published var detectedLabel: String = "—"

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let classifier = VisionClassifier()
    private let videoOutput = AVCaptureVideoDataOutput()
    
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var lastSpokenObject: String = ""
    private var lastSpokenTime = Date.distantPast
    private let speechCooldown: TimeInterval = 3.0
    private var lastClassificationTime = Date.distantPast
    private let classificationInterval: TimeInterval = 0.4   // run vision 2–3x/sec
    private let minConfidence: Float = 0.80 // 80% required to speak
    
    private var lastIdentifierSpoken: String = ""
    private var stableIdentifier: String = ""
    private var stableCount: Int = 0

    private let stableRequiredCount = 2          // must appear 2 times in a row
    private let speakThreshold: Float = 0.65     // 65% confidence



    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private var isConfigured = false

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
        sessionQueue.async {
            DispatchQueue.main.async {
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
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.2)) {
                    self.isSessionRunning = runningNow
                }
            }
        }
    }


    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .high

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            session.commitConfiguration()
            return
        }

        session.addInput(input)

        // Add photo output (needed for taking photos)
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }

        // Add video output (needed for live classification)
        if session.canAddOutput(videoOutput) {
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "video.frames.queue"))
            session.addOutput(videoOutput)
        }

        session.commitConfiguration()
    }
    
    private func speak(_ text: String) {
        if speechSynthesizer.isSpeaking { return }
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.5

        speechSynthesizer.speak(utterance)
    }

    private func handleDetection(identifier: String, confidence: Float) {
        let name = identifier.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // 1) Confidence gate
        guard confidence >= speakThreshold else {
            stableIdentifier = ""
            stableCount = 0
            return
        }

        // 2) Stability gate (same label must repeat)
        if name == stableIdentifier {
            stableCount += 1
        } else {
            stableIdentifier = name
            stableCount = 1
        }

        guard stableCount >= stableRequiredCount else { return }

        // 3) Cooldown + no-repeat gate
        let now = Date()
        if name == lastIdentifierSpoken && now.timeIntervalSince(lastSpokenTime) <= speechCooldown { return }

        lastIdentifierSpoken = name
        lastSpokenTime = now

        // Speak the actual label (dynamic)
        speak("Obstacle. \(identifier).")
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
        speak("Audio test. PathPilot is speaking.")
    }




    // MARK: - Capture Photo

    func takePhoto() {
        sessionQueue.async {
            guard self.session.isRunning else { return }

            // Ensure photo output has an active connection
            guard self.photoOutput.connection(with: .video) != nil else { return }

            let settings = AVCapturePhotoSettings()
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }


    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {

        // Throttle to avoid lag + spam
        let now = Date()
        guard now.timeIntervalSince(lastClassificationTime) >= classificationInterval else { return }
        lastClassificationTime = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        classifier.classify(pixelBuffer: pixelBuffer) { [weak self] identifier, confidence in
            guard let self else { return }

            DispatchQueue.main.async {
                self.detectedLabel = "\(identifier) (\(Int(confidence * 100))%)"
                self.handleDetection(identifier: identifier, confidence: confidence)
            }
        }
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard error == nil else { return }
        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else { return }

        DispatchQueue.main.async {
            self.capturedImage = image
        }
    }


}



// SwiftUI camera preview
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill

        if let connection = view.videoPreviewLayer.connection, connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        // Nothing needed; PreviewView keeps the layer sized correctly.
    }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

    override func layoutSubviews() {
        super.layoutSubviews()
        videoPreviewLayer.frame = bounds
    }
}


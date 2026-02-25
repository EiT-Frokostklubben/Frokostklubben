//
//  ContentView.swift
//  PathPilot
//
//  Created by Marius Horn on 11/02/2026.
//
import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject private var camera = CameraManager()

    var body: some View {
        ZStack {
            // Camera preview
            CameraPreview(session: camera.session)
                .ignoresSafeArea()

            // Top overlays: detected label + test sound
            VStack {
                HStack(alignment: .top) {
                    // Detected label (top-left)
                    Text(camera.detectedLabel)
                        .padding(10)
                        .background(.black.opacity(0.7))
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                        .padding(.leading, 12)
                        .padding(.top, 12)
                        .accessibilityLabel("Detected object")
                        .accessibilityValue(camera.detectedLabel)

                    Spacer()

                    // Controls (top-right)
                    HStack(spacing: 8) {
                        Button(camera.isDetectionEnabled ? "Stop" : "Start") {
                            camera.isDetectionEnabled.toggle()
                        }
                        .padding(10)
                        .background(.black.opacity(0.7))
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                        .accessibilityLabel(camera.isDetectionEnabled ? "Stop detection" : "Start detection")
                        .accessibilityHint("Toggles real time object detection")

                        Button("Read Poster") {
                            camera.readPoster()
                        }
                        .padding(10)
                        .background(.black.opacity(0.7))
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                        .accessibilityLabel("Read poster")
                        .accessibilityHint("Captures and reads text aloud")

                        Button("Test Sound") {
                            camera.testSpeak()
                        }
                        .padding(10)
                        .background(.black.opacity(0.7))
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                        .accessibilityLabel("Test sound")
                        .accessibilityHint("Plays a short audio message")
                    }
                    .padding(.trailing, 12)
                    .padding(.top, 12)
                }

                Spacer()

                if camera.isReadingPoster {
                    Text("Reading poster…")
                        .padding(12)
                        .background(.black.opacity(0.7))
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                        .padding(.bottom, 24)
                        .accessibilityLabel("Reading poster")
                }
            }

            // Loading overlay
            if camera.isAuthorized && !camera.isSessionRunning && camera.capturedImage == nil {
                Text("Starting camera…")
                    .padding()
                    .background(.black.opacity(0.7))
                    .foregroundStyle(.white)
                    .cornerRadius(12)
                    .padding()
                    .transition(.opacity)
            }

            // Permission overlay
            if !camera.isAuthorized {
                VStack(spacing: 12) {
                    Text("Camera access is required")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)

                    Text("Enable camera permission to use PathPilot.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)

                    Button("Request Camera Permission") {
                        camera.requestPermissionAndStart()
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityHint("Allows camera access to start detection")
                }
                .padding()
                .background(.black.opacity(0.7))
                .foregroundStyle(.white)
                .cornerRadius(16)
                .padding()
            }

            // Poster text overlay (for sighted debugging)
            if !camera.posterText.isEmpty {
                ZStack {
                    Color.black.opacity(0.6)
                        .ignoresSafeArea()

                    ScrollView {
                        Text(camera.posterText)
                            .foregroundStyle(.white)
                            .padding()
                            .multilineTextAlignment(.leading)
                    }

                    VStack {
                        HStack {
                            Spacer()
                            Button {
                                camera.posterText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 34))
                                    .foregroundStyle(.white)
                                    .padding()
                            }
                        }
                        Spacer()
                    }
                }
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
                return
            }
            #endif
            camera.requestPermissionAndStart()
        }
    }
}

#Preview {
    ContentView()
}


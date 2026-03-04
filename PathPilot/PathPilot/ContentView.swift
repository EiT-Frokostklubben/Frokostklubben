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

            VStack {
                HStack {
                    Text(camera.detectedLabel)
                        .font(.title3.weight(.semibold))
                        .padding(12)
                        .background(.black.opacity(0.8))
                        .foregroundStyle(.white)
                        .cornerRadius(14)
                        .padding(.leading, 12)
                        .padding(.top, 12)
                        .accessibilityLabel("Detected object")
                        .accessibilityValue(camera.detectedLabel)
                    Spacer()
                }

                Spacer()

                if camera.isReadingPoster {
                    ZStack {
                        GeometryReader { geometry in
                            let width = geometry.size.width * 0.76
                            let height = geometry.size.height * 0.76
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.white, style: StrokeStyle(lineWidth: 2, dash: [8]))
                                .frame(width: width, height: height)
                                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                        }
                        .ignoresSafeArea()

                        Text("Reading poster… align text inside the box")
                            .padding(12)
                            .background(.black.opacity(0.8))
                            .foregroundStyle(.white)
                            .cornerRadius(12)
                            .padding(.bottom, 10)
                            .accessibilityLabel("Reading poster")
                    }
                }

                // Bottom dock
                HStack(spacing: 12) {
                    Button(camera.isDetectionEnabled ? "Stop" : "Start") {
                        camera.isDetectionEnabled.toggle()
                    }
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .background(.black.opacity(0.85))
                    .foregroundStyle(.white)
                    .font(.title3.weight(.semibold))
                    .cornerRadius(16)
                    .accessibilityLabel(camera.isDetectionEnabled ? "Stop detection" : "Start detection")
                    .accessibilityHint("Toggles real time object detection")

                    Button("Read Poster") {
                        camera.readPoster()
                    }
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .background(.black.opacity(0.85))
                    .foregroundStyle(.white)
                    .font(.title3.weight(.semibold))
                    .cornerRadius(16)
                    .accessibilityLabel("Read poster")
                    .accessibilityHint("Captures and reads text aloud")

                    Button("Test Sound") {
                        camera.testSpeak()
                    }
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .background(.black.opacity(0.85))
                    .foregroundStyle(.white)
                    .font(.title3.weight(.semibold))
                    .cornerRadius(16)
                    .accessibilityLabel("Test sound")
                    .accessibilityHint("Plays a short audio message")
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 24)
            }

            // Loading overlay
            if camera.isAuthorized && !camera.isSessionRunning {
                Text("Starting camera…")
                    .padding()
                    .background(.black.opacity(0.8))
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
                .background(.black.opacity(0.8))
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
                                camera.abortPosterRead()
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

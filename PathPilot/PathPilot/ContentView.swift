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
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                        .padding(.leading, 12)
                        .padding(.top, 12)

                    Spacer()

                    // Test Sound button (top-right)
                    Button("Test Sound") {
                        camera.testSpeak()
                    }
                    .padding(10)
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
                    .padding(.trailing, 12)
                    .padding(.top, 12)
                }

                Spacer()

                // Capture button (bottom)
                Button(action: {
                    camera.takePhoto()
                }) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 72, height: 72)
                        .overlay(
                            Circle().stroke(Color.black.opacity(0.8), lineWidth: 2)
                        )
                        .shadow(radius: 4)
                }
                .padding(.bottom, 40)
            }

            // Loading overlay
            if camera.isAuthorized && !camera.isSessionRunning && camera.capturedImage == nil {
                Text("Starting camera…")
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
                    .padding()
                    .transition(.opacity)
            }

            // Permission overlay
            if !camera.isAuthorized {
                VStack(spacing: 12) {
                    Text("Camera access is required")
                        .font(.headline)

                    Text("Enable camera permission to use PathPilot.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)

                    Button("Request Camera Permission") {
                        camera.requestPermissionAndStart()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(16)
                .padding()
            }

            // Photo overlay
            if let image = camera.capturedImage {
                ZStack {
                    Color.black.opacity(0.6)
                        .ignoresSafeArea()

                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding()

                    VStack {
                        HStack {
                            Spacer()
                            Button {
                                camera.capturedImage = nil
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



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
        GeometryReader { geometry in
            ZStack {
                // Camera preview
                CameraPreview(session: camera.session)
                    .frame(width: geometry.size.height, height: geometry.size.width)
                    .rotationEffect(.degrees(90))
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    .ignoresSafeArea()

                HStack(spacing: 0) {
                    guideZone(title: "Left", color: .blue)
                        .frame(width: geometry.size.width * 0.27)
                    guideZone(title: "Ahead", color: .green)
                        .frame(width: geometry.size.width * 0.46)
                    guideZone(title: "Right", color: .orange)
                        .frame(width: geometry.size.width * 0.27)
                }
                .padding(.vertical, 12)
                .allowsHitTesting(false)

                HStack(alignment: .bottom, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(camera.activeWarningText)
                                .font(.title2.weight(.semibold))
                            Text(camera.statusText)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Navigation status")
                        .accessibilityValue("\(camera.activeWarningText). \(camera.statusText)")

                        Text(camera.detectedLabel)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityLabel("Current warning")
                            .accessibilityValue(camera.detectedLabel)

                        Text("The app warns with vibration and short audio when an obstacle is detected in the walking path.")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.8))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(16)
                    .frame(maxWidth: 320, alignment: .leading)
                    .background(.black.opacity(0.82))
                    .cornerRadius(18)

                    Spacer()

                    VStack(spacing: 12) {
                        Button(camera.isDetectionEnabled ? "Pause Alerts" : "Resume Alerts") {
                            camera.toggleDetection()
                        }
                        .frame(width: 220, height: 62)
                        .background(.black.opacity(0.85))
                        .foregroundStyle(.white)
                        .font(.title3.weight(.semibold))
                        .cornerRadius(16)
                        .accessibilityHint("Toggles obstacle warnings")

                        Button("Test Alert") {
                            camera.testAlert()
                        }
                        .frame(width: 220, height: 62)
                        .background(.black.opacity(0.85))
                        .foregroundStyle(.white)
                        .font(.title3.weight(.semibold))
                        .cornerRadius(16)
                        .accessibilityHint("Plays a sample obstacle warning")
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 20)

                if camera.isAuthorized && !camera.isSessionRunning {
                    Text("Starting camera…")
                        .padding()
                        .background(.black.opacity(0.8))
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                        .padding()
                        .transition(.opacity)
                }

                if !camera.isAuthorized {
                    VStack(spacing: 12) {
                        Text("Camera access is required")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)

                        Text("Enable camera permission to start obstacle warnings.")
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
            }
        }
        .statusBarHidden(true)
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
                return
            }
            #endif
            camera.requestPermissionAndStart()
        }
    }

    private func guideZone(title: String, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 18)
            .stroke(color.opacity(0.95), style: StrokeStyle(lineWidth: 3, dash: [10]))
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(color.opacity(0.07))
            )
            .overlay(alignment: .top) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.72))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .padding(.top, 10)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 10)
    }
}

#Preview {
    ContentView()
}

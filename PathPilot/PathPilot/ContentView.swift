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

                if camera.isPosterModeEnabled {
                    posterGuide(in: geometry)
                } else {
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
                }

                if camera.isAuthorized && camera.posterText.isEmpty {
                    statusChip
                        .padding(.top, 18)
                        .padding(.leading, 18)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }

                if camera.isAuthorized {
                    controlDock
                        .padding(.trailing, 18)
                        .padding(.bottom, 20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }

                if camera.isAuthorized && !camera.isSessionRunning {
                    Text("Starting camera...")
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

                if !camera.posterText.isEmpty {
                    posterTextOverlay
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

    private var statusChip: some View {
        HStack(spacing: 10) {
            Image(systemName: statusChipIconName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(statusAccentColor)
                .frame(width: 28, height: 28)
                .background(statusAccentColor.opacity(0.16))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(camera.activeWarningText)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(camera.statusText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.76))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: 236, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.10), radius: 8, x: 0, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Navigation status")
        .accessibilityValue("\(camera.activeWarningText). \(camera.statusText)")
    }

    private var controlDock: some View {
        VStack(spacing: 10) {
            Button(camera.isDetectionEnabled ? "Pause Alerts" : "Resume Alerts") {
                camera.toggleDetection()
            }
            .modifier(ControlButtonChrome(tone: .secondary))
            .accessibilityHint("Toggles obstacle warnings")

            Button(posterActionTitle) {
                if camera.isPosterModeEnabled {
                    camera.scanPoster()
                } else {
                    camera.startPosterMode()
                }
            }
            .modifier(ControlButtonChrome(tone: .primary))
            .disabled(camera.isReadingPoster || !camera.isSessionRunning)
            .accessibilityHint(posterActionHint)

            if camera.isPosterModeEnabled {
                Button("Cancel Poster") {
                    camera.abortPosterRead()
                }
                .modifier(ControlButtonChrome(tone: .secondary))
                .accessibilityHint("Exits poster reading mode")
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.22))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var statusChipIconName: String {
        if camera.isReadingPoster {
            return "text.viewfinder"
        }
        if camera.isPosterModeEnabled {
            return "doc.text.viewfinder"
        }
        if !camera.isDetectionEnabled {
            return "pause.circle.fill"
        }
        if camera.activeWarningText.lowercased().contains("stop") {
            return "exclamationmark.triangle.fill"
        }
        return "figure.walk.motion"
    }

    private var statusAccentColor: Color {
        if camera.isReadingPoster || camera.isPosterModeEnabled {
            return Color(red: 0.73, green: 0.92, blue: 1.0)
        }
        if !camera.isDetectionEnabled {
            return Color.white.opacity(0.72)
        }
        if camera.activeWarningText.lowercased().contains("stop") {
            return Color(red: 1.0, green: 0.63, blue: 0.50)
        }
        return Color(red: 0.85, green: 0.96, blue: 0.82)
    }

    private var posterActionTitle: String {
        if camera.isReadingPoster {
            return "Reading..."
        }
        return camera.isPosterModeEnabled ? "Scan Poster" : "Read Poster"
    }

    private var posterActionHint: String {
        if camera.isPosterModeEnabled {
            return "Captures the poster inside the frame and reads the main text"
        }
        return "Enters poster reading mode"
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

    private func posterGuide(in geometry: GeometryProxy) -> some View {
        let guideWidth = min(geometry.size.width * 0.76, 560)
        let guideHeight = min(geometry.size.height * 0.58, 420)

        return ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 28)
                .stroke(.white.opacity(0.95), style: StrokeStyle(lineWidth: 3, dash: [12, 10]))
                .frame(width: guideWidth, height: guideHeight)
                .background(
                    RoundedRectangle(cornerRadius: 28)
                        .fill(.black.opacity(0.08))
                        .frame(width: guideWidth, height: guideHeight)
                )

            HStack(spacing: 10) {
                Image(systemName: "doc.text.viewfinder")
                    .font(.headline.weight(.semibold))
                Text(camera.isReadingPoster ? "Scanning poster..." : "Align the poster or paper, then tap Scan Poster")
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.black.opacity(0.78))
            .foregroundStyle(.white)
            .clipShape(Capsule())
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private var posterTextOverlay: some View {
        ZStack {
            Color.black.opacity(0.78)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Poster Highlights")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                        Text("Apple Vision OCR kept the most important lines from the poster or paper.")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.white.opacity(0.75))
                    }

                    Spacer()

                    Button {
                        camera.abortPosterRead()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .accessibilityLabel("Close poster highlights")
                }

                ScrollView {
                    Text(camera.posterText)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(24)
            .frame(maxWidth: 720)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(.black.opacity(0.92))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(.white.opacity(0.12), lineWidth: 1)
                    )
            )
            .padding(24)
        }
        .transition(.opacity)
        .zIndex(10)
    }
}

private enum ControlButtonTone {
    case primary
    case secondary
}

private struct ControlButtonChrome: ViewModifier {
    let tone: ControlButtonTone

    func body(content: Content) -> some View {
        content
            .frame(width: 206, height: 52)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(backgroundFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(borderColor, lineWidth: 1)
                    )
            )
            .foregroundStyle(.white)
            .font(.subheadline.weight(.semibold))
            .shadow(color: .black.opacity(tone == .primary ? 0.12 : 0.08), radius: 8, x: 0, y: 4)
    }

    private var backgroundFill: Color {
        switch tone {
        case .primary:
            return Color.white.opacity(0.14)
        case .secondary:
            return Color.black.opacity(0.54)
        }
    }

    private var borderColor: Color {
        switch tone {
        case .primary:
            return Color.white.opacity(0.20)
        case .secondary:
            return Color.white.opacity(0.10)
        }
    }
}

#Preview {
    ContentView()
}

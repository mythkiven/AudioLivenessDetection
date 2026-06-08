import AudioLivenessDetection
import SwiftUI

#if os(iOS)
@MainActor
final class DemoViewModel: ObservableObject {
    @Published var statusText = "Tap Start to begin detection"
    @Published var lastResult = "—"
    @Published var detailText = ""
    @Published var isRunning = false

    private let service = AudioLivenessService.shared
    private var capture: MicrophoneCapture?

    init() {
        service.onLivenessResult = { [weak self] report in
            Task { @MainActor in
                self?.handleReport(report)
            }
        }
    }

    func start() {
        guard !isRunning else { return }

        service.applyDetectionEnabled(true, intervalSec: 10)
        capture = MicrophoneCapture { [weak self] pcm in
            self?.service.feedPCM(
                pcm,
                format: PCMFrameFormat(
                    sampleRate: 32_000,
                    channels: 1,
                    bytesPerSample: 2,
                    samples: pcm.count / 2
                )
            )
        }

        do {
            try capture?.start()
            isRunning = true
            statusText = "Listening… analysis every 10s"
        } catch {
            statusText = "Mic error: \(error.localizedDescription)"
        }
    }

    func stop() {
        capture?.stop()
        capture = nil
        service.stopDetection()
        isRunning = false
        statusText = "Stopped"
    }

    private func handleReport(_ report: LivenessDetectionReport) {
        lastResult = report.result.displayName
        detailText = """
        classified: \(report.isClassified)
        score: \(String(format: "%.3f", report.replayScore))
        voiceRatio: \(String(format: "%.2f", report.voiceRatio))
        evidence: \(report.evidenceCount)
        LF: \(String(format: "%.4f", report.lowFreqRatio))
        HF: \(String(format: "%.5f", report.highFreqRatio))
        fCV: \(String(format: "%.3f", report.spectralFluxCV))
        """
    }
}

struct ContentView: View {
    @StateObject private var viewModel = DemoViewModel()

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Text(viewModel.statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                VStack(spacing: 8) {
                    Text("Latest Result")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(viewModel.lastResult)
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(color(for: viewModel.lastResult))
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))

                Text(viewModel.detailText)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                HStack(spacing: 16) {
                    Button("Start") { viewModel.start() }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.isRunning)

                    Button("Stop") { viewModel.stop() }
                        .buttonStyle(.bordered)
                        .disabled(!viewModel.isRunning)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Audio Liveness")
        }
    }

    private func color(for result: String) -> Color {
        switch result {
        case "Live": return .green
        case "Replay": return .red
        default: return .orange
        }
    }
}

#endif

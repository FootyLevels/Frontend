import SwiftUI

/// Shared waiting card for the legacy import workflow. Only upload bytes have
/// measurable progress; preparation keeps an indeterminate indicator.
struct UploadProgressOverlay: View {
    let phase: ProjectsListViewModel.UploadPhase?

    var body: some View {
        if let phase {
            VStack(spacing: 16) {
                SLActivityIndicator(size: 28)
                switch phase {
                case .importing:
                    Text("Preparing video…").font(.headline)
                    Text("Getting your clip ready to upload.")
                        .font(.footnote).foregroundStyle(SL.muted)
                case .uploading(let fraction):
                    Text("Uploading your video").font(.headline)
                    ProgressView(value: fraction).tint(SL.green)
                    Text("\(Int(fraction * 100))%")
                        .font(.subheadline.monospacedDigit())
                case .processing:
                    Text("Preparing playback…").font(.headline)
                    Text("Your upload is complete. The server is preparing your video and key frames.")
                        .font(.footnote).foregroundStyle(SL.muted)
                }
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(SL.ink)
            .padding(24)
            .frame(maxWidth: 300)
            .slPanel(fill: SL.header, radius: 20)
            .shadow(color: SL.green.opacity(0.16), radius: 24, y: 8)
            .accessibilityElement(children: .combine)
        }
    }
}

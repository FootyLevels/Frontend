import SwiftUI

/// The dark card shown over a screen while a picked video is prepared and
/// uploaded. Shared by every tab that can import a video.
struct UploadProgressOverlay: View {
    let phase: ProjectsListViewModel.UploadPhase?

    var body: some View {
        if let phase {
            VStack(spacing: 14) {
                switch phase {
                case .importing:
                    ProgressView().tint(Color(hex: "EEF5E2"))
                    Text("Preparing video…")
                case .uploading(let fraction):
                    ProgressView(value: fraction)
                        .tint(SL.lime)
                        .frame(width: 180)
                    Text("Uploading \(Int(fraction * 100))%")
                case .processing:
                    ProgressView().tint(Color(hex: "EEF5E2"))
                    Text("Transcoding and picking key frames…")
                    Text("This runs on the server and can take a minute.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: "B9C9B0"))
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(Color(hex: "EEF5E2"))
            .padding(24)
            .background(Color(hex: "183D2C"), in: RoundedRectangle(cornerRadius: 12))
            .shadow(color: Color(hex: "183D2C").opacity(0.3), radius: 20, y: 6)
        }
    }
}

import AVKit
import SwiftUI

struct ClipImportEditor: View {
    let clip: PendingClip
    let onCancel: () -> Void
    let onSubmit: (String, String, Double, Double) -> Void
    @State private var title = "Practice clip"
    @State private var label = ""
    @State private var start = 0.0
    @State private var end = 1.0
    @State private var player: AVPlayer?

    private var valid: Bool {
        let count = title.trimmingCharacters(in: .whitespacesAndNewlines).count
        return (1...120).contains(count) && label.count <= 80 && end - start >= 1 && end - start <= 60
    }

    var body: some View {
        NavigationStack {
            Form {
                if let player { VideoPlayer(player: player).frame(height: 210) }
                Section("Your clip") {
                    TextField("Title", text: $title).accessibilityIdentifier("clipTitle")
                    TextField("Label (optional)", text: $label)
                    Text("Only the selected video is uploaded. Audio is removed.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Choose up to 60 seconds") {
                    Text("Start: \(start, specifier: "%.1f") seconds")
                    Slider(value: $start, in: 0...max(0.01, clip.duration - 1), step: 0.1)
                        .onChange(of: start) { _, value in
                            end = min(clip.duration, max(value + 1, min(end, value + 60)))
                            player?.seek(to: CMTime(seconds: value, preferredTimescale: 600))
                        }
                    Text("End: \(end, specifier: "%.1f") seconds")
                    Slider(value: $end, in: min(start + 1, clip.duration)...max(start + 1, min(clip.duration, start + 60)), step: 0.1)
                    Text("\(end - start, specifier: "%.1f") seconds · prepared as a private MP4, maximum 50 MB")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Button("Upload private clip") {
                    player?.pause()
                    onSubmit(title, label, start, end)
                }
                .disabled(!valid)
                .accessibilityIdentifier("submitPrivateClip")
            }
            .navigationTitle("Prepare your clip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { player?.pause(); onCancel() }
                }
            }
            .task { end = min(60, clip.duration); player = AVPlayer(url: clip.url) }
            .onDisappear { player?.pause() }
        }
        .tint(SL.tint)
    }
}

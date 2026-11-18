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
        return (1...120).contains(count) && label.count <= 80 && end - start >= ClipTrim.shortest && end - start <= ClipTrim.longest
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
                    if let range = ClipTrim.startRange(duration: clip.duration) {
                        Slider(value: $start, in: range, step: ClipTrim.step)
                            .onChange(of: start) { _, value in
                                end = ClipTrim.end(end, start: value, duration: clip.duration)
                                player?.seek(to: CMTime(seconds: value, preferredTimescale: 600))
                            }
                    }
                    Text("End: \(end, specifier: "%.1f") seconds")
                    if let range = ClipTrim.endRange(start: start, duration: clip.duration) {
                        Slider(value: $end, in: range, step: ClipTrim.step)
                    }
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
            .task { end = min(ClipTrim.longest, clip.duration); player = AVPlayer(url: clip.url) }
            .onDisappear { player?.pause() }
        }
        .tint(SL.tint)
    }
}

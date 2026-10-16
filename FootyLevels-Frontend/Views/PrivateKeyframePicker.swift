import AVFoundation
import SwiftUI

/// Uses the already verified local video; no signed URL reaches the image view.
struct PrivateKeyframePicker: View {
    let media: CloudPreparedMedia
    let playback: PlaybackController
    let canGenerate: Bool
    let checkSession: () throws -> Void
    let onGenerate: (Int, [Double]) -> Void
    @State private var frame = 0.0
    @State private var box: [Double] = [0,0,1,1]
    @State private var image: UIImage?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CHOOSE A POSE").font(.caption).foregroundStyle(SL.muted)
            Text("Choose a moment, then draw a box around the full player, including hands and feet.").font(.callout)
            Text("Source time: \((frame/30).formatted(.number.precision(.fractionLength(2)))) s").font(.callout.monospacedDigit())
            Slider(value: $frame, in: 0...Double(media.frameCount-1), step: 1).accessibilityLabel("Selected pose time")
            if let image {
                SubjectBoxCanvas(image: image, box: $box).aspectRatio(Double(media.width)/Double(media.height), contentMode: .fit)
            } else if let error { Text(error).foregroundStyle(SL.errorText).font(.callout) }
            else { ProgressView("Loading selected frame…") }
            HStack {
                Button("Use full frame") { box = [0,0,1,1] }.buttonStyle(.slSecondary)
                Button("Generate 3D pose") {
                    playback.pause(); onGenerate(Int(frame), box)
                }.buttonStyle(.slPrimary).disabled(!canGenerate || image == nil || !CloudKeyframeSelection.validBox(box))
            }
            Text("Draw a tight box when other players are visible. This creates a static pose, not a motion clip.")
                .font(.footnote).foregroundStyle(SL.muted)
        }
        .task(id: Int(frame)) { await loadFrame(Int(frame)) }
        .onDisappear { image = nil }
        .onChange(of: frame) { _, value in playback.pause(); playback.seek(to: value/30) }
        .onChange(of: media.frameCount) { _, count in frame = min(frame, Double(count-1)) }
    }

    private func loadFrame(_ index: Int) async {
        image = nil; error = nil; box = [0,0,1,1]
        guard let asset = playback.player.currentItem?.asset else { return }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 720)
        generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
        defer { generator.cancelAllCGImageGeneration() }
        do {
            try checkSession()
            let result = try await generator.image(at: CMTime(value: Int64(index), timescale: 30))
            try Task.checkCancellation(); try checkSession()
            guard Int(frame) == index, abs(result.actualTime.seconds-Double(index)/30) < 1.0/60 else {
                throw CloudPlaybackError.invalidResult
            }
            image = UIImage(cgImage: result.image)
        } catch {
            if !Task.isCancelled { image = nil; self.error = "This frame couldn't be loaded. Select another moment." }
        }
    }
}

/// The same normalized subject-box interaction used by the existing crop editor.
private struct SubjectBoxCanvas: View {
    let image: UIImage
    @Binding var box: [Double]
    var body: some View {
        Image(uiImage: image).resizable().scaledToFit().overlay { SubjectBoxOverlay(box: $box) }
            .clipShape(RoundedRectangle(cornerRadius: 8)).accessibilityLabel("Draw a box around the player")
    }
}

struct SubjectBoxOverlay: View {
    @Binding var box: [Double]
    var body: some View {
            GeometryReader { geometry in
                let size = geometry.size
                let rect = CGRect(x: box[0]*size.width, y: box[1]*size.height,
                    width: max(0,box[2]-box[0])*size.width, height: max(0,box[3]-box[1])*size.height)
                ZStack(alignment: .topLeading) {
                    Path { path in path.addRect(CGRect(origin: .zero,size: size)); path.addRect(rect) }
                        .fill(SL.ink.opacity(0.4),style: FillStyle(eoFill: true))
                    Rectangle().stroke(SL.accentLine,lineWidth: 2).frame(width: rect.width,height: rect.height)
                        .offset(x: rect.minX,y: rect.minY)
                }.contentShape(Rectangle()).highPriorityGesture(DragGesture(minimumDistance: 2).onChanged { value in
                    func clamp(_ v: CGFloat, _ limit: CGFloat) -> Double { Double(min(1,max(0,v/max(1,limit)))) }
                    box = [clamp(min(value.startLocation.x,value.location.x),size.width),
                        clamp(min(value.startLocation.y,value.location.y),size.height),
                        clamp(max(value.startLocation.x,value.location.x),size.width),
                        clamp(max(value.startLocation.y,value.location.y),size.height)]
                })
            }
    }
}

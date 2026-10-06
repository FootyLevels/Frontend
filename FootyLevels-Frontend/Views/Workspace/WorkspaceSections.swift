import SwiftUI

// MARK: - Insight

/// The coaching note under the inspector.
struct InsightCard: View {
    let mode: ProjectDetailViewModel.Mode
    let project: SkillLabProject
    let frame: KeyFrame?
    let frameNumber: Int
    let canSelectPlayer: Bool
    let onSelectPlayer: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "viewfinder")
                .font(.system(size: 18))
                .foregroundStyle(SL.iconTileText)
                .frame(width: 34, height: 34)
                .background(SL.iconTile, in: RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Eyebrow(text: mode == .motion ? "WATCH THE RELATIONSHIP" : String(format: "MOMENT %02d", frameNumber),
                            color: Color(hex: "81916F"))
                    Spacer()
                    if mode == .frames, canSelectPlayer {
                        Button(action: onSelectPlayer) {
                            HStack(spacing: 4) {
                                Image(systemName: "viewfinder")
                                Text("Select player")
                                Image(systemName: "arrow.up.right")
                            }
                            .font(.system(size: 11))
                            .foregroundStyle(Color(hex: "657958"))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text(title)
                    .font(SL.display(15, .bold))
                    .tracking(-0.3)
                    .foregroundStyle(SL.ink)
                Text(message)
                    .font(.system(size: 12))
                    .lineSpacing(3)
                    .foregroundStyle(Color(hex: "7A8370"))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .slPanel(fill: SL.insight, border: SL.line, radius: 8)
    }

    private var title: String {
        mode == .motion ? "Feet, body, ball. Together." : frame?.label ?? "Key frame"
    }

    private var message: String {
        if mode == .motion {
            return project.motion?.groundAligned == true
                ? "Ground aligned to the visible turf. Rolling contact is corrected; ball depth during bounces remains estimated. Pause and orbit to inspect the supporting foot."
                : "Pause at the feint, then orbit to compare the support foot, hips, and ball. The grid is a visual reference; ground contact and ball depth are estimated."
        }
        if let note = frame?.note, !note.isEmpty { return note }
        return "Compare the original frame with the reconstruction. Look for the position of the feet, hips, and shoulders."
    }
}

// MARK: - Key frames

struct KeyFramesSection: View {
    let project: SkillLabProject
    let selectedFrameId: String?
    let onChoose: (KeyFrame) -> Void

    private var selectedIndex: Int {
        project.frames.firstIndex { $0.id == selectedFrameId } ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("The moments that make the move")
                            .font(SL.display(16, .bold))
                            .tracking(-0.5)
                            .foregroundStyle(SL.ink)
                        Text(String(format: "%02d", project.frames.count))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color(hex: "768968"))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color(hex: "EAF0DF"), in: RoundedRectangle(cornerRadius: 4))
                    }
                    Text("Choose a frame to inspect. Add your own moments as you watch.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: "8B9480"))
                }
                Spacer()
                HStack(spacing: 6) {
                    navigationButton("chevron.left", label: "Previous key frame", disabled: selectedIndex == 0) {
                        onChoose(project.frames[selectedIndex - 1])
                    }
                    navigationButton("chevron.right", label: "Next key frame",
                                     disabled: selectedIndex >= project.frames.count - 1) {
                        onChoose(project.frames[selectedIndex + 1])
                    }
                }
            }

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(Array(project.frames.enumerated()), id: \.element.id) { index, frame in
                            FrameCard(frame: frame, order: index + 1, isSelected: frame.id == selectedFrameId) {
                                onChoose(frame)
                            }
                            .id(frame.id)
                        }
                    }
                    .padding(2)
                }
                .onChange(of: selectedFrameId) { _, id in
                    guard let id else { return }
                    withAnimation { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
    }

    private func navigationButton(_ icon: String, label: String, disabled: Bool,
                                  action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(SL.ink)
                .frame(width: 30, height: 30)
                .overlay(Circle().stroke(SL.line))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
        .accessibilityLabel(label)
    }
}

private struct FrameCard: View {
    let frame: KeyFrame
    let order: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    SL.frameImage
                    AsyncImage(url: try? SkillLabClient.shared.url(for: frame.imageUrl)) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        ProgressView()
                    }
                }
                .frame(width: 120, height: 150)
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [.clear, Color(hex: "182B28").opacity(0.3)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 35)
                }
                .overlay(alignment: .topLeading) {
                    Text(String(format: "%02d", order))
                        .font(.system(size: 9))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Color(hex: "152B24").opacity(0.56), in: Circle())
                        .padding(7)
                }
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(SL.tickText)
                            .frame(width: 20, height: 20)
                            .background(SL.tick, in: Circle())
                            .padding(7)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    Text(String(format: "%.2fs", frame.timestamp))
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(8)
                }
                .clipped()

                VStack(alignment: .leading, spacing: 6) {
                    Text(frame.label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SL.ink)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Circle().fill(SL.frameDot(frame.status)).frame(width: 5, height: 5)
                        Text(SL.frameStatusText(frame.status))
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(Color(hex: "869179"))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .frame(width: 120, alignment: .leading)
            }
            .background(SL.card)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? SL.cardSelected : SL.cardBorder, lineWidth: isSelected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Inspect \(frame.label) at \(String(format: "%.2f", frame.timestamp)) seconds")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Pipeline bar

struct PipelineBar: View {
    let project: SkillLabProject
    let readyCount: Int
    let isRunning: Bool
    let isSample: Bool
    let providerReady: Bool
    let busy: Bool
    let onGenerate: () -> Void
    let onConnect: () -> Void

    private var allReady: Bool { readyCount == project.frames.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "cube")
                    .font(.system(size: 20))
                    .foregroundStyle(Color(hex: "67844B"))
                    .frame(width: 40, height: 40)
                    .background(SL.pipelineIcon, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color(hex: "D1DFB9")))
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(SL.display(15, .semibold))
                        .tracking(-0.4)
                        .foregroundStyle(SL.ink)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "889477"))
                }
            }

            if !isSample {
                Button {
                    providerReady ? onGenerate() : onConnect()
                } label: {
                    HStack(spacing: 8) {
                        if isRunning {
                            ProgressView().tint(.white).controlSize(.small)
                        } else {
                            Image(systemName: "cube")
                        }
                        Text(buttonTitle)
                        if !isRunning { Image(systemName: "arrow.right") }
                    }
                }
                .buttonStyle(.slPrimaryWide)
                .disabled(busy || isRunning || allReady)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .slPanel(fill: SL.pipeline, border: SL.pipelineBorder, radius: 8)
    }

    private var title: String {
        if isRunning { return "Reconstruction in progress…" }
        return allReady ? "Your breakdown is ready." : "A few frames. A whole new perspective."
    }

    private var subtitle: String {
        if isRunning {
            if let motion = project.motion, motion.isActive {
                return "Whole video · \(motion.stage ?? "queued")"
            }
            if let job = project.job {
                return "\((job.completed ?? 0) + (job.failed ?? 0)) of \(job.total ?? project.frames.count) processed · Models appear as they finish."
            }
        }
        return "\(readyCount) of \(project.frames.count) models reconstructed with Meta SAM 3D Body."
    }

    private var buttonTitle: String {
        if isRunning { return "Reconstructing" }
        if allReady { return "All models ready" }
        return providerReady ? "Generate missing models" : "Connect reconstruction"
    }
}

// MARK: - Footnote

struct WorkspaceFootnote: View {
    let canRemove: Bool
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "info.circle")
                    .font(.system(size: 12))
                Text("3D poses are estimates from a single image. Hidden limbs and foot contact may be inaccurate. Motion uses SAM 3 tracking, SAM 3D Body poses, and a SAM 3D Objects football. Ball depth assumes a 22 cm diameter; spin is not reconstructed. Camera movement is not separated from player movement.")
            }
            .font(.system(size: 10))
            .lineSpacing(3)
            .foregroundStyle(Color(hex: "969D8D"))

            if canRemove {
                HStack {
                    Spacer()
                    Button(role: .destructive, action: onRemove) {
                        Label("Remove selected frame", systemImage: "trash")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(SL.errorText)
                }
            }
        }
    }
}

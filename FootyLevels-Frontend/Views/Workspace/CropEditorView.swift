import SwiftUI

/// "Choose the player": drag a box around the full body on a key frame.
///
/// The box matters: the backend feeds it straight to SAM 3D Body as the subject
/// crop, so a loose box on a busy frame can reconstruct the wrong person.
struct CropEditorView: View {
    let frame: KeyFrame
    let aspectRatio: Double
    /// Returns false if the save failed; the error is shown by the caller.
    let onSave: ([Double]) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var box: [Double]
    @State private var dragStart: CGPoint?
    @State private var isSaving = false

    init(frame: KeyFrame, aspectRatio: Double, onSave: @escaping ([Double]) async -> Bool) {
        self.frame = frame
        self.aspectRatio = aspectRatio
        self.onSave = onSave
        _box = State(initialValue: frame.bbox.count == 4 ? frame.bbox : [0, 0, 1, 1])
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Drag a box around the full body, including hands and feet. Leave a small margin and exclude other players.")
                        .font(.system(size: 13))
                        .lineSpacing(3)
                        .foregroundStyle(Color(hex: "7B886D"))

                    canvas
                        .frame(maxHeight: 440)
                        .frame(maxWidth: .infinity)

                    numbers

                    if frame.isReady {
                        Text("Saving a new box discards this frame’s current model.")
                            .font(.system(size: 11))
                            .foregroundStyle(SL.noticeText)
                    }

                    HStack {
                        Button("Use full frame") { box = [0, 0, 1, 1] }
                            .buttonStyle(.slSecondary)
                        Spacer()
                        Button {
                            Task {
                                isSaving = true
                                let saved = await onSave(box)
                                isSaving = false
                                if saved { dismiss() }
                            }
                        } label: {
                            Text(isSaving ? "Saving…" : "Save subject box")
                        }
                        .buttonStyle(.slPrimary)
                        .disabled(isSaving || !Self.isValid(box))
                    }
                }
                .padding(20)
            }
            .background(Color(hex: "F8F9F1"))
            .navigationTitle("Choose the player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var canvas: some View {
        Color.black
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay {
                AsyncImage(url: try? SkillLabClient.shared.url(for: frame.imageUrl)) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    ProgressView().tint(.white)
                }
            }
            .overlay {
                GeometryReader { geometry in
                    let size = geometry.size
                    let rect = Self.rect(box, in: size)
                    ZStack(alignment: .topLeading) {
                        // Dim everything outside the box, so it's obvious what
                        // the model will actually see.
                        Path { path in
                            path.addRect(CGRect(origin: .zero, size: size))
                            path.addRect(rect)
                        }
                        .fill(Color(hex: "12200C").opacity(0.4), style: FillStyle(eoFill: true))

                        Rectangle()
                            .fill(Color(hex: "B5D83A").opacity(0.1))
                            .overlay(Rectangle().stroke(Color(hex: "E4F683"), lineWidth: 2))
                            .frame(width: rect.width, height: rect.height)
                            .offset(x: rect.minX, y: rect.minY)
                    }
                    .contentShape(Rectangle())
                    // High priority so drawing beats the scroll view claiming
                    // the same vertical drag.
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 2)
                            .onChanged { value in
                                let start = dragStart ?? value.startLocation
                                dragStart = start
                                box = Self.normalisedBox(from: start, to: value.location, in: size)
                            }
                            .onEnded { _ in dragStart = nil }
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .accessibilityLabel("Draw a box around the player to reconstruct")
    }

    private var numbers: some View {
        HStack(spacing: 10) {
            ForEach(Array(["Left", "Top", "Right", "Bottom"].enumerated()), id: \.offset) { index, label in
                VStack(alignment: .leading, spacing: 4) {
                    Text(label)
                        .font(.system(size: 10))
                        .foregroundStyle(Color(hex: "79876C"))
                    TextField(label, value: Binding(
                        get: { Int((box[index] * 100).rounded()) },
                        set: { box[index] = Double(Swift.min(Swift.max($0, 0), 100)) / 100 }
                    ), format: .number)
                    .keyboardType(.numberPad)
                    .font(.system(size: 13))
                    .padding(6)
                    .background(.white, in: RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(SL.line))
                    .accessibilityLabel("Crop \(label.lowercased()) percent")
                }
                .frame(maxWidth: 72)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Geometry

    private static func rect(_ box: [Double], in size: CGSize) -> CGRect {
        guard box.count == 4 else { return CGRect(origin: .zero, size: size) }
        return CGRect(x: box[0] * size.width, y: box[1] * size.height,
                      width: Swift.max(0, box[2] - box[0]) * size.width,
                      height: Swift.max(0, box[3] - box[1]) * size.height)
    }

    private static func normalisedBox(from a: CGPoint, to b: CGPoint, in size: CGSize) -> [Double] {
        func clamp(_ value: CGFloat, _ limit: CGFloat) -> Double {
            Double(Swift.min(Swift.max(value / Swift.max(limit, 1), 0), 1))
        }
        return [clamp(Swift.min(a.x, b.x), size.width), clamp(Swift.min(a.y, b.y), size.height),
                clamp(Swift.max(a.x, b.x), size.width), clamp(Swift.max(a.y, b.y), size.height)]
    }

    /// Mirrors the server's `FramePatch` validation, so an invalid box can't
    /// be submitted just to come back as a 422.
    private static func isValid(_ box: [Double]) -> Bool {
        box.count == 4 && box.allSatisfy { (0...1).contains($0) }
            && box[2] - box[0] >= 0.03 && box[3] - box[1] >= 0.03
    }
}

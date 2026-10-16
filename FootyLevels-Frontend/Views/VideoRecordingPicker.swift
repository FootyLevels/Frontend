import AVFoundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct VideoRecordingPicker: UIViewControllerRepresentable {
    let onCancel: () -> Void
    let onRecorded: (URL) -> Void
    let onError: (String) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.movie.identifier]
        picker.cameraCaptureMode = .video
        picker.videoMaximumDuration = 60
        picker.videoQuality = .typeMedium
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: VideoRecordingPicker
        init(_ parent: VideoRecordingPicker) { self.parent = parent }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.onCancel() }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            guard let original = info[.mediaURL] as? URL else { parent.onError("Couldn't read the recording."); return }
            do {
                let dir = FileManager.default.temporaryDirectory.appendingPathComponent("recorded-" + UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                    attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
                let file = dir.appendingPathComponent("recording." + original.pathExtension)
                try FileManager.default.copyItem(at: original, to: file)
                parent.onRecorded(file)
            } catch { parent.onError("Couldn't save the recording. Check available device storage.") }
        }
    }

    @MainActor
    static func permissionError() async -> String? {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            return "This device has no available camera. You can still import a video from Photos."
        }
        let camera = await AVCaptureDevice.requestAccess(for: .video)
        guard camera else { return "Camera access is off. Allow FootyLevels in Settings, or import from Photos." }
        let microphone = await AVCaptureDevice.requestAccess(for: .audio)
        guard microphone else { return "Microphone access is off. Allow FootyLevels in Settings, or import from Photos." }
        return nil
    }
}

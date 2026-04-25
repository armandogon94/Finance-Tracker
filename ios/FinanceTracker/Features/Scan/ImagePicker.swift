//
//  ImagePicker.swift
//  Slice 7 — two image-source paths backing the Scan flow:
//
//  • LibraryPicker uses PhotosUI's PhotosPicker. Modern API, sandboxed
//    photo access, no manual permission dance.
//  • CameraPicker wraps UIImagePickerController(sourceType: .camera) via
//    UIViewControllerRepresentable. Required because PhotosPicker still
//    can't trigger live capture.
//
//  Both write the chosen UIImage into the binding the parent provides.
//  ScanView's job is to compress that image and hand it to ScanService.
//

import SwiftUI
import PhotosUI
import UIKit

// MARK: - Library

/// Tiny PhotosPicker wrapper that loads the selection as a UIImage.
struct LibraryPicker: View {
    @Binding var isPresented: Bool
    var onPick: (UIImage) -> Void

    @State private var selection: PhotosPickerItem?

    var body: some View {
        // PhotosPicker is presented by toggling a Boolean — but the API
        // expects to be a button itself. We render an empty body and rely
        // on the parent to surface this view inside a `.photosPicker(...)`
        // modifier instead. Simpler: expose a static modifier helper.
        EmptyView()
    }
}

extension View {
    /// Attach a PhotosPicker that fires `onPick` with the chosen image.
    /// The parent owns the bool binding so it can flip it from a button.
    func libraryPicker(
        isPresented: Binding<Bool>,
        onPick: @escaping (UIImage) -> Void
    ) -> some View {
        modifier(LibraryPickerModifier(isPresented: isPresented, onPick: onPick))
    }
}

private struct LibraryPickerModifier: ViewModifier {
    @Binding var isPresented: Bool
    var onPick: (UIImage) -> Void
    @State private var selection: PhotosPickerItem?

    func body(content: Content) -> some View {
        content
            .photosPicker(
                isPresented: $isPresented,
                selection: $selection,
                matching: .images,
                preferredItemEncoding: .compatible
            )
            .onChange(of: selection) { _, newItem in
                guard let item = newItem else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        onPick(image)
                    }
                    selection = nil
                }
            }
    }
}

// MARK: - Camera

/// SwiftUI sheet wrapping UIImagePickerController(sourceType: .camera).
/// Falls back to library on the simulator where there's no camera.
struct CameraPicker: UIViewControllerRepresentable {
    var onPick: (UIImage) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        // Sim has no camera — show the library so the flow is still testable.
        p.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        p.allowsEditing = false
        p.delegate = context.coordinator
        return p
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onPick: (UIImage) -> Void
        let onCancel: () -> Void
        init(onPick: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage {
                onPick(img)
            } else {
                onCancel()
            }
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}

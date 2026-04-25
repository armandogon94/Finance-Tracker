//
//  ImageCompressor.swift
//  Pure helper that prepares a UIImage for upload to the OCR endpoint.
//
//  Why this exists:
//    iPhone main camera shoots 12 MP / ~5 MB JPEGs. The backend's
//    Tesseract fallback path times out around 2 MB, and Claude Vision
//    charges for tokens roughly proportional to image dimensions. So
//    every receipt gets clamped to maxDimension on the long edge and
//    re-encoded as JPEG at the given quality before it leaves the device.
//

import UIKit

enum ImageCompressor {

    /// Resize (preserving aspect ratio) so the long edge is at most
    /// `maxDimension` and re-encode as JPEG at `quality` ∈ [0…1].
    /// Returns nil only if JPEG encoding fails (very rare; opaque images
    /// always encode). The function is `static` and pure — safe to call
    /// from any actor.
    static func compress(
        _ image: UIImage,
        maxDimension: CGFloat = 2048,
        quality: CGFloat = 0.7
    ) -> Data? {
        let resized = resize(image, maxDimension: maxDimension)
        return resized.jpegData(compressionQuality: quality)
    }

    /// Resize without re-encoding. Useful for the in-memory thumbnail
    /// shown on the review screen — we don't want to round-trip through
    /// JPEG twice.
    static func resize(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        // Already small enough → return as-is. Avoids needless re-encode
        // for receipts shot on older devices or already-cropped images.
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1 // we already accounted for scale above
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

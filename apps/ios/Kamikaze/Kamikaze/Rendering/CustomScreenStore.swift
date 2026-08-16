import Observation
import RealityKit
import UIKit

/// The player's own screen image (e.g. a screenshot of their real home
/// screen), persisted across launches and applied by the phone factory when
/// the PHOTO screen cosmetic is selected.
@MainActor
@Observable
final class CustomScreenStore {
    static let shared = CustomScreenStore()

    /// Bumped on every image change; the scene stamp includes it so a new
    /// photo swaps into live stages immediately.
    private(set) var revision = 0
    private(set) var image: UIImage?
    private var cachedTexture: (revision: Int, resource: TextureResource)?
    private var cachedFlippedTexture: (revision: Int, resource: TextureResource)?

    private init() {
        image = UIImage(contentsOfFile: Self.fileURL.path)
    }

    var hasImage: Bool { image != nil }

    func setImageData(_ data: Data) {
        guard let raw = UIImage(data: data) else { return }
        image = Self.normalized(raw, maxDimension: 1024)
        revision += 1
        try? image?.jpegData(compressionQuality: 0.85)?.write(to: Self.fileURL, options: .atomic)
    }

    func clear() {
        image = nil
        revision += 1
        try? FileManager.default.removeItem(at: Self.fileURL)
    }

    /// Texture for the current image, cached per revision. The paintable
    /// asset's screen UVs expect a vertically flipped image (its source
    /// texture ships pre-flipped, a GLTF-pipeline convention), so scenes ask
    /// for the variant matching their mesh.
    func texture(flippedVertically: Bool = false) -> TextureResource? {
        if flippedVertically {
            if let cachedFlippedTexture, cachedFlippedTexture.revision == revision {
                return cachedFlippedTexture.resource
            }
        } else if let cachedTexture, cachedTexture.revision == revision {
            return cachedTexture.resource
        }
        guard let image else { return nil }
        let oriented: UIImage
        if flippedVertically {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            oriented = UIGraphicsImageRenderer(size: image.size, format: format).image { context in
                context.cgContext.translateBy(x: 0, y: image.size.height)
                context.cgContext.scaleBy(x: 1, y: -1)
                image.draw(in: CGRect(origin: .zero, size: image.size))
            }
        } else {
            oriented = image
        }
        guard let cgImage = oriented.cgImage,
              let resource = try? TextureResource(image: cgImage, options: .init(semantic: .color))
        else { return nil }
        if flippedVertically {
            cachedFlippedTexture = (revision, resource)
        } else {
            cachedTexture = (revision, resource)
        }
        return resource
    }

    private static var fileURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("custom-screen.jpg")
    }

    /// Re-renders unconditionally: TextureResource reads the raw CGImage and
    /// ignores UIImage EXIF orientation, so the pixels must be baked upright.
    private static func normalized(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let scale = min(1, maxDimension / max(size.width, size.height, 1))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

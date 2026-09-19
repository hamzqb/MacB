import AppKit
import ImageIO
import MacBCore
import PDFKit
import UniformTypeIdentifiers

/// Makes new files from files on the shelf: a JPEG copy, a smaller copy, one
/// PDF out of several.
///
/// The original is only ever read. Every result is written to a temporary
/// file first and then moved to its final name with an exclusive rename, which
/// the kernel refuses if anything already has that name — so no conversion can
/// overwrite a file, not even one that appeared a moment after the name was
/// chosen, or a second conversion racing the first.
enum ShelfConverter {
    enum Failure: LocalizedError {
        case unreadable(String)
        case unwritable(String)

        var errorDescription: String? {
            switch self {
            case .unreadable(let name): return "\(name) okunamadı."
            case .unwritable(let name): return "\(name) yazılamadı."
            }
        }
    }

    /// A JPEG of the same picture, with its metadata.
    static func jpegCopy(of source: URL) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            guard let image = CGImageSourceCreateWithURL(source as CFURL, nil) else {
                throw Failure.unreadable(source.lastPathComponent)
            }
            let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any] ?? [:]
            return try write(near: source, name: { ShelfConversion.jpegURL(for: source, exists: $0) }) { temporary in
                guard let output = CGImageDestinationCreateWithURL(temporary as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
                    return false
                }
                let quality = [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary
                if properties[kCGImagePropertyHasAlpha] as? Bool == true {
                    // JPEG has no transparency: without a background, clear
                    // pixels come out black, which ruins every screenshot of a
                    // window with a shadow.
                    guard let decoded = CGImageSourceCreateImageAtIndex(image, 0, nil),
                          let flat = flattened(decoded) else { return false }
                    var merged = properties
                    merged[kCGImageDestinationLossyCompressionQuality] = 0.9
                    merged[kCGImagePropertyHasAlpha] = false
                    CGImageDestinationAddImage(output, flat, merged as CFDictionary)
                } else {
                    CGImageDestinationAddImageFromSource(output, image, 0, quality)
                }
                return CGImageDestinationFinalize(output)
            }
        }.value
    }

    /// A copy no longer than 1600 pixels on its long side, upright, and without
    /// the original's metadata — so it does not carry where a photo was taken
    /// into an e-mail.
    static func reducedCopy(of source: URL) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            guard let image = CGImageSourceCreateWithURL(source as CFURL, nil) else {
                throw Failure.unreadable(source.lastPathComponent)
            }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: Int(ShelfConversion.reducedLongSide)
            ]
            guard let reduced = CGImageSourceCreateThumbnailAtIndex(image, 0, options as CFDictionary),
                  let flat = flattened(reduced) else {
                throw Failure.unreadable(source.lastPathComponent)
            }
            return try write(near: source, name: { ShelfConversion.reducedURL(for: source, exists: $0) }) { temporary in
                guard let output = CGImageDestinationCreateWithURL(temporary as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
                    return false
                }
                CGImageDestinationAddImage(output, flat, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
                return CGImageDestinationFinalize(output)
            }
        }.value
    }

    /// One PDF with every page of `sources`, in order.
    static func merge(_ sources: [URL]) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            guard let first = sources.first else { throw Failure.unreadable("PDF") }
            let merged = PDFDocument()
            for source in sources {
                guard let document = PDFDocument(url: source) else { throw Failure.unreadable(source.lastPathComponent) }
                guard !document.isLocked else { throw Failure.unreadable(source.lastPathComponent + " (parolalı)") }
                for index in 0..<document.pageCount {
                    if let page = document.page(at: index) { merged.insert(page, at: merged.pageCount) }
                }
            }
            return try write(near: first, name: { ShelfConversion.mergedURL(for: sources, exists: $0) ?? first }) {
                merged.write(to: $0)
            }
        }.value
    }

    /// Opens the AirDrop sheet for these files.
    @MainActor static func airDrop(_ urls: [URL]) -> Bool {
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop),
              service.canPerform(withItems: urls) else { return false }
        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: urls)
        return true
    }

    // MARK: - Writing without overwriting

    /// Writes with `produce` into a hidden temporary file beside `source`, then
    /// gives it the first free name `name` offers.
    ///
    /// `renamex_np` with `RENAME_EXCL` fails with `EEXIST` rather than replace
    /// anything, so a name taken in the meantime just moves on to the next
    /// number. A temporary file left over by a failure is MacB's own and goes
    /// to the Trash, like everything else MacB lets go of.
    private static func write(near source: URL, name: ((URL) -> Bool) -> URL,
                              produce: (URL) -> Bool) throws -> URL {
        let directory = source.deletingLastPathComponent()
        let temporary = directory.appendingPathComponent(".macb-\(UUID().uuidString).tmp")
        guard produce(temporary), FileManager.default.fileExists(atPath: temporary.path) else {
            discard(temporary)
            throw Failure.unwritable(source.lastPathComponent)
        }
        var tried = Set<String>()
        for _ in 0..<500 {
            let candidate = name { tried.contains($0.path) || FileManager.default.fileExists(atPath: $0.path) }
            tried.insert(candidate.path)
            if renamex_np(temporary.path, candidate.path, UInt32(RENAME_EXCL)) == 0 { return candidate }
            guard errno == EEXIST else { break }
        }
        discard(temporary)
        throw Failure.unwritable(source.lastPathComponent)
    }

    private static func discard(_ temporary: URL) {
        guard FileManager.default.fileExists(atPath: temporary.path) else { return }
        try? FileManager.default.trashItem(at: temporary, resultingItemURL: nil)
    }

    /// The image drawn over white, without an alpha channel.
    private static func flattened(_ image: CGImage) -> CGImage? {
        guard image.alphaInfo != .none, image.alphaInfo != .noneSkipLast, image.alphaInfo != .noneSkipFirst else {
            return image
        }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: image.colorSpace ?? space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
                ?? CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                             bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            return nil
        }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage()
    }
}

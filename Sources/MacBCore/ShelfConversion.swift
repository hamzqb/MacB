import CoreGraphics
import Foundation

/// What can be made from files on the shelf, and what the results are called.
///
/// Every conversion writes a new file beside the original and leaves the
/// original exactly as it was. Nothing here overwrites: a name that is taken
/// gets a number, the way Finder names a duplicate.
public enum ShelfConversion {
    /// Image formats ImageIO reads that are worth offering a JPEG of.
    public static let convertibleImageExtensions: Set<String> = [
        "heic", "heif", "png", "tif", "tiff", "bmp", "gif", "webp", "jpg", "jpeg", "avif"
    ]

    /// The longest side of a "smaller" copy, in pixels. Big enough to read a
    /// screenshot or look at a photo on a screen; small enough to attach.
    public static let reducedLongSide: CGFloat = 1600

    public static func isImage(_ url: URL) -> Bool {
        convertibleImageExtensions.contains(url.pathExtension.lowercased())
    }

    public static func isPDF(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "pdf"
    }

    /// Whether a JPEG copy makes sense: a file that is already JPEG only gets
    /// the "smaller" option.
    public static func canConvertToJPEG(_ url: URL) -> Bool {
        isImage(url) && !["jpg", "jpeg"].contains(url.pathExtension.lowercased())
    }

    /// The size a reduced copy is drawn at: scaled so its longer side is at most
    /// `longSide`, never enlarged, never rounded down to zero.
    public static func reducedSize(for size: CGSize, longSide: CGFloat = reducedLongSide) -> CGSize {
        let longest = max(size.width, size.height)
        guard longest > longSide, longest > 0 else { return size }
        let scale = longSide / longest
        return CGSize(width: max(1, (size.width * scale).rounded()),
                      height: max(1, (size.height * scale).rounded()))
    }

    /// A free name in `directory` for `stem` with `pathExtension`.
    ///
    /// "Foto.jpg", then "Foto 2.jpg", "Foto 3.jpg". `exists` is asked rather
    /// than the disk so the rule can be checked without one.
    public static func freeURL(in directory: URL, stem: String, pathExtension: String,
                               exists: (URL) -> Bool) -> URL {
        let cleanStem = stem.isEmpty ? "Dosya" : stem
        var candidate = directory.appendingPathComponent(cleanStem).appendingPathExtension(pathExtension)
        var number = 2
        while exists(candidate) {
            candidate = directory.appendingPathComponent("\(cleanStem) \(number)").appendingPathExtension(pathExtension)
            number += 1
        }
        return candidate
    }

    /// Where the JPEG copy of `source` goes.
    public static func jpegURL(for source: URL, exists: (URL) -> Bool) -> URL {
        freeURL(in: source.deletingLastPathComponent(),
                stem: source.deletingPathExtension().lastPathComponent,
                pathExtension: "jpg", exists: exists)
    }

    /// Where the reduced copy of `source` goes.
    public static func reducedURL(for source: URL, exists: (URL) -> Bool) -> URL {
        freeURL(in: source.deletingLastPathComponent(),
                stem: source.deletingPathExtension().lastPathComponent + " (küçük)",
                pathExtension: "jpg", exists: exists)
    }

    /// Where a merged PDF goes: beside the first document, named after it.
    public static func mergedURL(for sources: [URL], exists: (URL) -> Bool) -> URL? {
        guard let first = sources.first else { return nil }
        return freeURL(in: first.deletingLastPathComponent(),
                       stem: first.deletingPathExtension().lastPathComponent + " (birleşik)",
                       pathExtension: "pdf", exists: exists)
    }
}

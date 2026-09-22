import AppKit
import ImageIO
import SwiftUI

/// ImageIO reads and downsamples on this actor, never in a SwiftUI body or on
/// the main actor. The cache holds decoded thumbnails, not full-size originals.
actor ClipboardImageCache {
    static let shared = ClipboardImageCache()
    private let images = NSCache<NSString, CGImage>()

    init() {
        images.totalCostLimit = 48 * 1_024 * 1_024
        images.countLimit = 512
    }

    func image(for item: ClipboardItem, pixels: Int) -> CGImage? {
        guard !Task.isCancelled else { return nil }
        let key = Self.key(for: item, pixels: pixels) as NSString
        if let image = images.object(forKey: key) { return image }
        return autoreleasepool {
            let options = [kCGImageSourceShouldCache: false] as CFDictionary
            let source: CGImageSource?
            if let data = item.imageData {
                source = CGImageSourceCreateWithData(data as CFData, options)
            } else if let name = item.payloadReferences?["image"], HistoryRepository.isPayloadName(name),
                let directory = item.payloadDirectory
            {
                source = CGImageSourceCreateWithURL(directory.appendingPathComponent(name) as CFURL, options)
            } else {
                return nil
            }
            guard !Task.isCancelled, let source,
                let image = CGImageSourceCreateThumbnailAtIndex(
                    source, 0,
                    [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: max(1, pixels),
                        kCGImageSourceShouldCacheImmediately: true,
                    ] as CFDictionary)
            else { return nil }
            images.setObject(image, forKey: key, cost: image.bytesPerRow * image.height)
            return image
        }
    }

    nonisolated static func key(for item: ClipboardItem, pixels: Int) -> String {
        "\(item.contentHash):\(pixels)"
    }
}

/// Workspace lookups can touch Launch Services and the filesystem. Keep them
/// off the scrolling thread and share the resulting small raster icons.
actor WorkspaceIconCache {
    enum Source: Hashable, Sendable {
        case application(String)
        case file(URL)
    }

    private final class Entry {
        let image: CGImage?
        init(_ image: CGImage?) { self.image = image }
    }

    static let shared = WorkspaceIconCache()
    private let images = NSCache<NSString, Entry>()

    init() {
        images.countLimit = 256
        images.totalCostLimit = 16 * 1_024 * 1_024
    }

    func image(for source: Source, pixels: Int) -> CGImage? {
        guard !Task.isCancelled else { return nil }
        let path: String
        switch source {
        case .application(let identifier): path = "app:\(identifier)"
        case .file(let url): path = "file:\(url.path)"
        }
        let key = "\(path):\(pixels)" as NSString
        if let entry = images.object(forKey: key) { return entry.image }
        return autoreleasepool {
            let url: URL?
            switch source {
            case .application(let identifier):
                url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)
            case .file(let file): url = file
            }
            var image: CGImage?
            if let url, !Task.isCancelled {
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                let size = max(1, pixels)
                var rect = CGRect(x: 0, y: 0, width: size, height: size)
                if let original = icon.cgImage(forProposedRect: &rect, context: nil, hints: nil),
                    let context = CGContext(
                        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                {
                    context.interpolationQuality = .high
                    context.draw(original, in: CGRect(x: 0, y: 0, width: size, height: size))
                    image = context.makeImage()
                }
            }
            guard !Task.isCancelled else { return nil }
            images.setObject(Entry(image), forKey: key, cost: image.map { $0.bytesPerRow * $0.height } ?? 1)
            return image
        }
    }
}

struct ClipboardImageView: View {
    let item: ClipboardItem
    let pixels: Int
    var mode: ContentMode = .fit
    @State private var image: CGImage?
    @State private var loadedKey: String?

    private var key: String { ClipboardImageCache.key(for: item, pixels: pixels) }

    var body: some View {
        Group {
            if loadedKey == key, let image {
                Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: mode)
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        }
        .task(id: key, priority: .utility) {
            let result = await ClipboardImageCache.shared.image(for: item, pixels: pixels)
            guard !Task.isCancelled else { return }
            image = result
            loadedKey = key
        }
    }
}

struct WorkspaceIconView: View {
    let source: WorkspaceIconCache.Source
    let pixels: Int
    var fallback = "doc"
    @State private var image: CGImage?
    @State private var loadedRequest: Request?

    private struct Request: Hashable {
        let source: WorkspaceIconCache.Source
        let pixels: Int
    }
    private var request: Request { Request(source: source, pixels: pixels) }

    var body: some View {
        Group {
            if loadedRequest == request, let image {
                Image(decorative: image, scale: 1).resizable().scaledToFit()
            } else {
                Image(systemName: fallback).symbolRenderingMode(.hierarchical).foregroundStyle(.secondary)
            }
        }
        .task(id: request, priority: .utility) {
            let result = await WorkspaceIconCache.shared.image(for: source, pixels: pixels)
            guard !Task.isCancelled else { return }
            image = result
            loadedRequest = request
        }
    }
}

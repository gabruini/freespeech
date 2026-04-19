// Swift 5.0
//
//  ThumbnailService.swift
//

import Foundation
import AppKit

final class ThumbnailService {
    static let shared = ThumbnailService()

    private let memoryCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 512
        return cache
    }()

    private let fileManager = FileManager.default
    private let storage = FileStorageService.shared

    private init() {}

    func persistThumbnail(_ image: NSImage, for videoFilename: String) {
        do {
            let directory = try storage.ensureVideoEntryDirectoryExists(for: videoFilename)
            let thumbnailURL = directory.appendingPathComponent("thumbnail.jpg")
            guard let tiff = image.tiffRepresentation,
                  let bitmapRep = NSBitmapImageRep(data: tiff),
                  let imageData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.82]) else {
                print("Could not convert thumbnail image to JPEG data")
                return
            }
            try imageData.write(to: thumbnailURL, options: .atomic)
        } catch {
            print("Error saving thumbnail: \(error)")
        }
    }

    func loadThumbnailImage(for videoFilename: String) -> NSImage? {
        let cacheKey = videoFilename as NSString
        if let cachedImage = memoryCache.object(forKey: cacheKey) {
            return cachedImage
        }

        let thumbnailURL = storage.getVideoThumbnailURL(for: videoFilename)
        if fileManager.fileExists(atPath: thumbnailURL.path),
           let image = NSImage(contentsOf: thumbnailURL) {
            memoryCache.setObject(image, forKey: cacheKey)
            return image
        }

        // Backward compatibility: generate once for old video entries, then persist.
        let videoURL = storage.getVideoURL(for: videoFilename)
        guard fileManager.fileExists(atPath: videoURL.path),
              let generated = generateVideoThumbnail(from: videoURL) else {
            return nil
        }
        persistThumbnail(generated, for: videoFilename)
        memoryCache.setObject(generated, forKey: cacheKey)
        return generated
    }

    func invalidate(videoFilename: String) {
        memoryCache.removeObject(forKey: videoFilename as NSString)
    }
}

// Swift 5.0
//
//  FileStorageService.swift
//

import Foundation

final class FileStorageService {
    static let shared = FileStorageService()

    private let fileManager = FileManager.default

    let documentsDirectory: URL
    let videosDirectory: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Freespeech")
        if !FileManager.default.fileExists(atPath: docs.path) {
            do {
                try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
                print("Successfully created Freespeech directory")
            } catch {
                print("Error creating directory: \(error)")
            }
        }
        self.documentsDirectory = docs

        let videos = docs.appendingPathComponent("Videos")
        if !FileManager.default.fileExists(atPath: videos.path) {
            do {
                try FileManager.default.createDirectory(at: videos, withIntermediateDirectories: true)
                print("Successfully created Freespeech/Videos directory")
            } catch {
                print("Error creating videos directory: \(error)")
            }
        }
        self.videosDirectory = videos
    }

    // MARK: - Path helpers

    func getDocumentsDirectory() -> URL { documentsDirectory }
    func getVideosDirectory() -> URL { videosDirectory }

    func getVideoEntryDirectory(for videoFilename: String) -> URL {
        let baseName = (videoFilename as NSString).deletingPathExtension
        return videosDirectory.appendingPathComponent(baseName, isDirectory: true)
    }

    func getManagedVideoURL(for filename: String) -> URL {
        getVideoEntryDirectory(for: filename).appendingPathComponent(filename)
    }

    func getVideoThumbnailURL(for filename: String) -> URL {
        getVideoEntryDirectory(for: filename).appendingPathComponent("thumbnail.jpg")
    }

    func getVideoTranscriptURL(for filename: String) -> URL {
        getVideoEntryDirectory(for: filename).appendingPathComponent("transcript.md")
    }

    func getVideoPronunciationURL(for filename: String) -> URL {
        getVideoEntryDirectory(for: filename).appendingPathComponent("pronunciation.json")
    }

    func getVideoAssessmentURL(for filename: String) -> URL {
        getVideoEntryDirectory(for: filename).appendingPathComponent("pronunciation-assessment.json")
    }

    @discardableResult
    func ensureVideoEntryDirectoryExists(for videoFilename: String) throws -> URL {
        let directory = getVideoEntryDirectory(for: videoFilename)
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    /// Resolves the video URL across current and legacy layouts.
    func getVideoURL(for filename: String) -> URL {
        let managedVideoURL = getManagedVideoURL(for: filename)
        if fileManager.fileExists(atPath: managedVideoURL.path) {
            return managedVideoURL
        }

        let flatVideosURL = videosDirectory.appendingPathComponent(filename)
        if fileManager.fileExists(atPath: flatVideosURL.path) {
            return flatVideosURL
        }

        let rootVideosURL = documentsDirectory.appendingPathComponent(filename)
        if fileManager.fileExists(atPath: rootVideosURL.path) {
            return rootVideosURL
        }

        return managedVideoURL
    }

    func hasVideoAsset(for filename: String) -> Bool {
        let managedVideoURL = getManagedVideoURL(for: filename)
        if fileManager.fileExists(atPath: managedVideoURL.path) { return true }

        let flatVideosURL = videosDirectory.appendingPathComponent(filename)
        if fileManager.fileExists(atPath: flatVideosURL.path) { return true }

        let rootVideosURL = documentsDirectory.appendingPathComponent(filename)
        return fileManager.fileExists(atPath: rootVideosURL.path)
    }

    /// Deletes every known on-disk asset (managed + legacy) for a given video entry.
    func deleteVideoAssets(for videoFilename: String) {
        let managedDirectory = getVideoEntryDirectory(for: videoFilename)
        let managedVideoURL = managedDirectory.appendingPathComponent(videoFilename)
        let managedThumbnailURL = managedDirectory.appendingPathComponent("thumbnail.jpg")
        let managedTranscriptURL = managedDirectory.appendingPathComponent("transcript.md")
        let managedPronunciationURL = managedDirectory.appendingPathComponent("pronunciation.json")
        let flatVideosURL = videosDirectory.appendingPathComponent(videoFilename)
        let rootVideosURL = documentsDirectory.appendingPathComponent(videoFilename)

        let candidateURLs = [managedVideoURL, managedThumbnailURL, managedTranscriptURL, managedPronunciationURL, flatVideosURL, rootVideosURL]
        for url in candidateURLs where fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.removeItem(at: url)
            } catch {
                print("Error deleting video asset \(url.lastPathComponent): \(error)")
            }
        }

        if fileManager.fileExists(atPath: managedDirectory.path) {
            do {
                try fileManager.removeItem(at: managedDirectory)
            } catch {
                print("Error deleting video entry directory: \(error)")
            }
        }
    }
}

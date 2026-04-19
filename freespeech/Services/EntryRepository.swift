// Swift 5.0
//
//  EntryRepository.swift
//

import Foundation

final class EntryRepository {
    static let shared = EntryRepository()

    private let fileManager = FileManager.default
    private let storage = FileStorageService.shared
    private let transcripts = TranscriptService.shared

    private init() {}

    func parseCanonicalEntryFilename(_ filename: String) -> (uuid: UUID, timestamp: Date)? {
        guard filename.hasPrefix("["),
              filename.hasSuffix("].md"),
              let divider = filename.range(of: "]-[") else {
            return nil
        }

        let uuidStart = filename.index(after: filename.startIndex)
        let uuidString = String(filename[uuidStart..<divider.lowerBound])
        guard let uuid = UUID(uuidString: uuidString) else {
            return nil
        }

        let timestampStart = divider.upperBound
        let timestampEnd = filename.index(filename.endIndex, offsetBy: -4) // before ".md"
        let timestampString = String(filename[timestampStart..<timestampEnd])
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        guard let timestamp = formatter.date(from: timestampString) else {
            return nil
        }

        return (uuid: uuid, timestamp: timestamp)
    }

    func isEntryNewer(_ lhs: HumanEntry, than rhs: HumanEntry) -> Bool {
        let lhsTimestamp = parseCanonicalEntryFilename(lhs.filename)?.timestamp ?? .distantPast
        let rhsTimestamp = parseCanonicalEntryFilename(rhs.filename)?.timestamp ?? .distantPast
        if lhsTimestamp == rhsTimestamp {
            return lhs.filename > rhs.filename
        }
        return lhsTimestamp > rhsTimestamp
    }

    /// Scans the documents directory for canonical `.md` entries and returns only those
    /// that have a paired `.mov` asset (current or legacy layout).
    func loadExistingEntries() -> [HumanEntry] {
        let documentsDirectory = storage.documentsDirectory
        print("Looking for entries in: \(documentsDirectory.path)")
        print("Looking for videos in: \(storage.videosDirectory.path)")

        let fileURLs: [URL]
        do {
            fileURLs = try fileManager.contentsOfDirectory(at: documentsDirectory, includingPropertiesForKeys: nil)
        } catch {
            print("Error loading directory contents: \(error)")
            return []
        }

        let mdFiles = fileURLs.filter { $0.pathExtension == "md" }
        print("Found \(mdFiles.count) .md files")

        let entriesWithDates: [(entry: HumanEntry, date: Date)] = mdFiles.compactMap { fileURL in
            let filename = fileURL.lastPathComponent

            guard let parsed = parseCanonicalEntryFilename(filename) else {
                return nil
            }

            let videoFilename = filename.replacingOccurrences(of: ".md", with: ".mov")
            guard storage.hasVideoAsset(for: videoFilename) else {
                // Legacy text-only entries are preserved on disk but hidden from the UI.
                return nil
            }

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMM d"
            let displayDate = dateFormatter.string(from: parsed.timestamp)

            let entry = HumanEntry(
                id: parsed.uuid,
                date: displayDate,
                filename: filename,
                videoFilename: videoFilename,
                languageCode: transcripts.parseTranscriptLanguageCode(for: videoFilename)
            )
            return (entry, parsed.timestamp)
        }

        let loaded = entriesWithDates
            .sorted {
                if $0.date == $1.date {
                    return $0.entry.filename > $1.entry.filename
                }
                return $0.date > $1.date
            }
            .map { $0.entry }

        print("Successfully loaded \(loaded.count) video entries")
        return loaded
    }
}

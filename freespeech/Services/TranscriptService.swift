// Swift 5.0
//
//  TranscriptService.swift
//

import Foundation

final class TranscriptService {
    static let shared = TranscriptService()

    private let fileManager = FileManager.default
    private let storage = FileStorageService.shared

    private init() {}

    // MARK: - YAML front-matter

    func stripYAMLFrontMatter(_ text: String) -> String {
        guard text.hasPrefix("---\n") else { return text }
        let afterOpening = text.index(text.startIndex, offsetBy: 4)
        guard let closingRange = text.range(of: "\n---\n", range: afterOpening..<text.endIndex) else {
            return text
        }
        let afterFrontMatter = closingRange.upperBound
        return String(text[afterFrontMatter...])
    }

    func parseTranscriptLanguageCode(for videoFilename: String) -> String? {
        let transcriptURL = storage.getVideoTranscriptURL(for: videoFilename)
        guard fileManager.fileExists(atPath: transcriptURL.path),
              let content = try? String(contentsOf: transcriptURL, encoding: .utf8),
              content.hasPrefix("---\n") else {
            return nil
        }
        let afterOpening = content.index(content.startIndex, offsetBy: 4)
        guard let closingRange = content.range(of: "\n---\n", range: afterOpening..<content.endIndex) else {
            return nil
        }
        let frontMatter = String(content[afterOpening..<closingRange.lowerBound])
        for line in frontMatter.components(separatedBy: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2 && parts[0].trimmingCharacters(in: .whitespaces) == "language" {
                return parts[1].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    // MARK: - Transcript body

    func loadTranscriptText(for videoFilename: String) -> String? {
        let transcriptURL = storage.getVideoTranscriptURL(for: videoFilename)
        guard fileManager.fileExists(atPath: transcriptURL.path),
              let content = try? String(contentsOf: transcriptURL, encoding: .utf8) else {
            return nil
        }
        let stripped = stripYAMLFrontMatter(content)
        let cleaned = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    func saveTranscript(text: String, languageCode: String, for videoFilename: String) {
        let transcriptURL = storage.getVideoTranscriptURL(for: videoFilename)
        let newContent = "---\nlanguage: \(languageCode)\n---\n\n\(text.trimmingCharacters(in: .whitespacesAndNewlines))"
        try? newContent.write(to: transcriptURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Word confidences

    func loadWordConfidences(for videoFilename: String) -> [WordConfidence]? {
        let url = storage.getVideoPronunciationURL(for: videoFilename)
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let confidences = try? JSONDecoder().decode([WordConfidence].self, from: data),
              !confidences.isEmpty else {
            return nil
        }
        return confidences
    }

    // MARK: - Pronunciation assessment

    func loadAssessmentResult(for videoFilename: String) -> PronunciationAssessmentResult? {
        let url = storage.getVideoAssessmentURL(for: videoFilename)
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let result = try? JSONDecoder().decode(PronunciationAssessmentResult.self, from: data) else {
            return nil
        }
        return result
    }

    func saveAssessmentResult(_ result: PronunciationAssessmentResult, for videoFilename: String) {
        let url = storage.getVideoAssessmentURL(for: videoFilename)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(result) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

//
//  PronunciationService.swift
//

import Foundation
import AVFoundation

// MARK: - Azure Pronunciation Assessment Models

struct AzurePronunciationResult: Codable {
    let recognitionStatus: String?
    let nBest: [AzureNBestResult]?

    enum CodingKeys: String, CodingKey {
        case recognitionStatus = "RecognitionStatus"
        case nBest = "NBest"
    }
}

struct AzureNBestResult: Codable {
    let confidence: Double?
    let lexical: String?
    let accuracyScore: Double?
    let fluencyScore: Double?
    let completenessScore: Double?
    let prosodyScore: Double?
    let words: [AzureWord]?

    enum CodingKeys: String, CodingKey {
        case confidence = "Confidence"
        case lexical = "Lexical"
        case accuracyScore = "AccuracyScore"
        case fluencyScore = "FluencyScore"
        case completenessScore = "CompletenessScore"
        case prosodyScore = "ProsodyScore"
        case words = "Words"
    }
}

struct AzureWord: Codable {
    let word: String
    let accuracyScore: Double?
    let errorType: String?
    let phonemes: [AzurePhoneme]?

    enum CodingKeys: String, CodingKey {
        case word = "Word"
        case accuracyScore = "AccuracyScore"
        case errorType = "ErrorType"
        case phonemes = "Phonemes"
    }
}

struct AzurePhoneme: Codable {
    let phoneme: String
    let accuracyScore: Double?

    enum CodingKeys: String, CodingKey {
        case phoneme = "Phoneme"
        case accuracyScore = "AccuracyScore"
    }
}

// MARK: - Stored result model (saved to pronunciation-assessment.json)

struct PronunciationAssessmentResult: Codable {
    let overallAccuracy: Double
    let overallFluency: Double
    let overallCompleteness: Double
    let overallProsody: Double?
    let words: [AssessedWord]

    struct AssessedWord: Codable, Identifiable {
        var id: String { "\(word)-\(accuracyScore)" }
        let word: String
        let accuracyScore: Double
        let errorType: String?
        let phonemes: [AssessedPhoneme]
    }

    struct AssessedPhoneme: Codable, Identifiable {
        var id: String { "\(phoneme)-\(accuracyScore)" }
        let phoneme: String
        let accuracyScore: Double
    }
}

// MARK: - Service

class PronunciationService {
    static let shared = PronunciationService()
    static let azureKeyKeychainKey = "freespeech.azure.speech.key"
    static let azureRegionKeychainKey = "freespeech.azure.speech.region"

    private let session = URLSession.shared

    var hasAPIKey: Bool {
        KeychainHelper.load(key: Self.azureKeyKeychainKey) != nil
    }

    func assess(
        audioURL: URL,
        referenceText: String,
        languageCode: String,
        completion: @escaping (Result<PronunciationAssessmentResult, Error>) -> Void
    ) {
        guard let apiKey = KeychainHelper.load(key: Self.azureKeyKeychainKey) else {
            completion(.failure(PronunciationError.noAPIKey))
            return
        }
        let region = KeychainHelper.load(key: Self.azureRegionKeychainKey) ?? "eastus"

        // Extract audio as WAV first
        extractAudioAsWAV(from: audioURL) { result in
            switch result {
            case .success(let wavURL):
                self.submitToAzure(
                    wavURL: wavURL,
                    referenceText: referenceText,
                    languageCode: languageCode,
                    apiKey: apiKey,
                    region: region,
                    completion: completion
                )
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func extractAudioAsWAV(from movieURL: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        let asset = AVAsset(url: movieURL)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            completion(.failure(PronunciationError.audioExtractionFailed))
            return
        }

        // Use AVAssetReader + AVAssetWriter for WAV output since AVAssetExportSession doesn't support WAV
        Task {
            do {
                let wavURL = try await self.convertToWAV(asset: asset, outputURL: outputURL)
                DispatchQueue.main.async { completion(.success(wavURL)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    private func convertToWAV(asset: AVAsset, outputURL: URL) async throws -> URL {
        let reader = try AVAssetReader(asset: asset)

        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw PronunciationError.audioExtractionFailed
        }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        reader.add(readerOutput)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .wav)
        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: outputSettings)
        writer.add(writerInput)

        reader.startReading()
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        return try await withCheckedThrowingContinuation { continuation in
            writerInput.requestMediaDataWhenReady(on: DispatchQueue(label: "freespeech.audio.export")) {
                while writerInput.isReadyForMoreMediaData {
                    if let sampleBuffer = readerOutput.copyNextSampleBuffer() {
                        writerInput.append(sampleBuffer)
                    } else {
                        writerInput.markAsFinished()
                        writer.finishWriting {
                            if writer.status == .completed {
                                continuation.resume(returning: outputURL)
                            } else {
                                continuation.resume(throwing: writer.error ?? PronunciationError.audioExtractionFailed)
                            }
                        }
                        break
                    }
                }
            }
        }
    }

    private func submitToAzure(
        wavURL: URL,
        referenceText: String,
        languageCode: String,
        apiKey: String,
        region: String,
        completion: @escaping (Result<PronunciationAssessmentResult, Error>) -> Void
    ) {
        guard let wavData = try? Data(contentsOf: wavURL) else {
            completion(.failure(PronunciationError.audioExtractionFailed))
            return
        }

        Task {
            defer { try? FileManager.default.removeItem(at: wavURL) }
            do {
                let headerSize = 44
                let bytesPerSecond = 32000 // 16kHz * 16-bit * mono
                let audioBytes = max(0, wavData.count - headerSize)
                let totalDuration = Double(audioBytes) / Double(bytesPerSecond)

                let result: PronunciationAssessmentResult
                if totalDuration <= 55 {
                    result = try await self.assessChunk(
                        wavData: wavData, referenceText: referenceText,
                        languageCode: languageCode, apiKey: apiKey, region: region
                    )
                } else {
                    result = try await self.assessWithChunking(
                        wavData: wavData, referenceText: referenceText,
                        languageCode: languageCode, apiKey: apiKey, region: region,
                        totalDuration: totalDuration
                    )
                }
                DispatchQueue.main.async { completion(.success(result)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    private func assessWithChunking(
        wavData: Data,
        referenceText: String,
        languageCode: String,
        apiKey: String,
        region: String,
        totalDuration: Double
    ) async throws -> PronunciationAssessmentResult {
        let headerSize = 44
        let bytesPerSecond = 32000
        let audioBytes = max(0, wavData.count - headerSize)
        let chunkSeconds = 50
        let chunkBytes = chunkSeconds * bytesPerSecond

        let words = referenceText.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).map(String.init)
        let wordsPerSecond = Double(words.count) / totalDuration

        var chunkResults: [PronunciationAssessmentResult] = []
        var audioOffset = 0
        var wordOffset = 0

        while audioOffset < audioBytes {
            let audioEnd = min(audioOffset + chunkBytes, audioBytes)
            let pcmSlice = wavData[headerSize + audioOffset ..< headerSize + audioEnd]
            let chunkWAV = Self.buildWAVData(pcm: pcmSlice)

            let chunkDuration = Double(audioEnd - audioOffset) / Double(bytesPerSecond)
            let chunkWordCount: Int
            if audioEnd >= audioBytes {
                chunkWordCount = words.count - wordOffset
            } else {
                chunkWordCount = max(1, Int(round(chunkDuration * wordsPerSecond)))
            }
            let wordEnd = min(wordOffset + chunkWordCount, words.count)
            let chunkRef = words[wordOffset..<wordEnd].joined(separator: " ")

            if !chunkRef.isEmpty {
                let result = try await assessChunk(
                    wavData: chunkWAV, referenceText: chunkRef,
                    languageCode: languageCode, apiKey: apiKey, region: region
                )
                chunkResults.append(result)
            }

            wordOffset = wordEnd
            audioOffset = audioEnd
        }

        guard !chunkResults.isEmpty else { throw PronunciationError.noAssessment }

        return Self.mergeResults(chunkResults)
    }

    private static func mergeResults(_ results: [PronunciationAssessmentResult]) -> PronunciationAssessmentResult {
        if results.count == 1 { return results[0] }

        var allWords: [PronunciationAssessmentResult.AssessedWord] = []
        var totalAccuracy = 0.0, totalFluency = 0.0, totalCompleteness = 0.0, totalProsody = 0.0
        var totalWeight = 0.0, prosodyWeight = 0.0

        for r in results {
            let w = Double(max(1, r.words.count))
            allWords.append(contentsOf: r.words)
            totalAccuracy += r.overallAccuracy * w
            totalFluency += r.overallFluency * w
            totalCompleteness += r.overallCompleteness * w
            totalWeight += w
            if let p = r.overallProsody {
                totalProsody += p * w
                prosodyWeight += w
            }
        }

        return PronunciationAssessmentResult(
            overallAccuracy: totalWeight > 0 ? totalAccuracy / totalWeight : 0,
            overallFluency: totalWeight > 0 ? totalFluency / totalWeight : 0,
            overallCompleteness: totalWeight > 0 ? totalCompleteness / totalWeight : 0,
            overallProsody: prosodyWeight > 0 ? totalProsody / prosodyWeight : nil,
            words: allWords
        )
    }

    private func assessChunk(
        wavData: Data,
        referenceText: String,
        languageCode: String,
        apiKey: String,
        region: String
    ) async throws -> PronunciationAssessmentResult {
        let endpoint = "https://\(region).stt.speech.microsoft.com/speech/recognition/conversation/cognitiveservices/v1?language=\(languageCode)&format=detailed"

        guard let url = URL(string: endpoint) else {
            throw PronunciationError.invalidEndpoint
        }

        let assessmentConfig: [String: Any] = [
            "ReferenceText": referenceText,
            "GradingSystem": "HundredMark",
            "Granularity": "Phoneme",
            "Dimension": "Comprehensive",
            "EnableProsodyAssessment": true
        ]

        guard let configData = try? JSONSerialization.data(withJSONObject: assessmentConfig) else {
            throw PronunciationError.configurationError
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        request.setValue(configData.base64EncodedString(), forHTTPHeaderField: "Pronunciation-Assessment")
        request.httpBody = wavData

        let (data, response) = try await session.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            print("[Pronunciation] Azure HTTP \(http.statusCode): \(body)")
        }

        let azureResult = try JSONDecoder().decode(AzurePronunciationResult.self, from: data)
        guard let nBest = azureResult.nBest?.first,
              let accuracy = nBest.accuracyScore,
              let fluency = nBest.fluencyScore,
              let completeness = nBest.completenessScore else {
            throw PronunciationError.noAssessment
        }

        return PronunciationAssessmentResult(
            overallAccuracy: accuracy,
            overallFluency: fluency,
            overallCompleteness: completeness,
            overallProsody: nBest.prosodyScore,
            words: (nBest.words ?? []).map { word in
                PronunciationAssessmentResult.AssessedWord(
                    word: word.word,
                    accuracyScore: word.accuracyScore ?? 0,
                    errorType: word.errorType,
                    phonemes: (word.phonemes ?? []).map { phoneme in
                        PronunciationAssessmentResult.AssessedPhoneme(
                            phoneme: phoneme.phoneme,
                            accuracyScore: phoneme.accuracyScore ?? 0
                        )
                    }
                )
            }
        )
    }

    private static func buildWAVData(pcm: Data) -> Data {
        let dataSize = UInt32(pcm.count)
        let fileSize = dataSize + 36
        var header = Data(capacity: 44)

        func appendUInt32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { header.append(contentsOf: $0) } }
        func appendUInt16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { header.append(contentsOf: $0) } }

        header.append("RIFF".data(using: .ascii)!)
        appendUInt32(fileSize)
        header.append("WAVE".data(using: .ascii)!)
        header.append("fmt ".data(using: .ascii)!)
        appendUInt32(16)
        appendUInt16(1)
        appendUInt16(1)
        appendUInt32(16000)
        appendUInt32(32000)
        appendUInt16(2)
        appendUInt16(16)
        header.append("data".data(using: .ascii)!)
        appendUInt32(dataSize)

        return header + pcm
    }
}

enum PronunciationError: LocalizedError {
    case noAPIKey
    case audioExtractionFailed
    case invalidEndpoint
    case configurationError
    case noResponse
    case noAssessment

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "Azure Speech API key not configured. Add it in Settings."
        case .audioExtractionFailed: return "Failed to extract audio from video."
        case .invalidEndpoint: return "Invalid Azure endpoint."
        case .configurationError: return "Failed to create assessment configuration."
        case .noResponse: return "No response from Azure."
        case .noAssessment: return "No pronunciation assessment in response."
        }
    }
}

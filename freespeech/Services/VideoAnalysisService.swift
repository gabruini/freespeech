//
//  VideoAnalysisService.swift
//  freespeech
//

import Foundation
import AVFoundation

// MARK: - Result models

struct PatternExample: Codable, Identifiable {
    var id: String { "\(youSaid)-\(natural)" }
    let youSaid: String
    let natural: String
    let note: String?

    enum CodingKeys: String, CodingKey {
        case youSaid = "you_said"
        case natural
        case note
    }
}

struct LanguagePattern: Codable, Identifiable {
    var id: String { title }
    let title: String
    let rule: String
    let l1Contrast: String?
    let examples: [PatternExample]

    enum CodingKeys: String, CodingKey {
        case title
        case rule
        case l1Contrast = "l1_contrast"
        case examples
    }
}

struct NaturalUpgrade: Codable, Identifiable {
    var id: String { "\(youSaid)-\(natural)" }
    let youSaid: String
    let natural: String
    let kind: String
    let whyItSticks: String

    enum CodingKeys: String, CodingKey {
        case youSaid = "you_said"
        case natural
        case kind
        case whyItSticks = "why_it_sticks"
    }
}

struct GoldenSentence: Codable, Identifiable {
    var id: String { sentence }
    let sentence: String
    let pattern: String
    let cloze: String?
    let answer: String?
    let variations: [String]
    let focus: String?

    enum CodingKeys: String, CodingKey {
        case sentence
        case pattern
        case cloze
        case answer
        case variations
        case focus
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sentence = try c.decode(String.self, forKey: .sentence)
        pattern = try c.decodeIfPresent(String.self, forKey: .pattern) ?? ""
        cloze = try c.decodeIfPresent(String.self, forKey: .cloze)
        answer = try c.decodeIfPresent(String.self, forKey: .answer)
        variations = try c.decodeIfPresent([String].self, forKey: .variations) ?? []
        focus = try c.decodeIfPresent(String.self, forKey: .focus)
    }

    init(sentence: String, pattern: String, cloze: String? = nil, answer: String? = nil, variations: [String] = [], focus: String? = nil) {
        self.sentence = sentence
        self.pattern = pattern
        self.cloze = cloze
        self.answer = answer
        self.variations = variations
        self.focus = focus
    }
}

struct VideoAnalysisResult: Codable {
    let rawTranscript: String
    let patterns: [LanguagePattern]
    let upgrades: [NaturalUpgrade]
    let goldenSentences: [GoldenSentence]
    let correctedText: String

    enum CodingKeys: String, CodingKey {
        case rawTranscript
        case patterns
        case upgrades
        case goldenSentences = "golden_sentences"
        case correctedText = "corrected_text"
    }
}

enum VideoAnalysisPhase: Equatable {
    case idle
    case extractingAudio
    case transcribing
    case analyzing
    case synthesizing
    case done
    case error(String)

    var isActive: Bool {
        switch self {
        case .idle: return false
        default: return true
        }
    }
}

enum VideoAnalysisServiceError: LocalizedError {
    case missingElevenLabsKey
    case missingAzureKey
    case missingAnthropicKey
    case audioExtractionFailed
    case transcriptionFailed(String)
    case analysisFailed(String)
    case synthesisFailed(String)
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingElevenLabsKey: return "ElevenLabs API key not configured. Add it in Settings."
        case .missingAzureKey: return "Azure Speech API key not configured. Add it in Settings."
        case .missingAnthropicKey: return "Anthropic API key not configured. Add it in Settings."
        case .audioExtractionFailed: return "Failed to extract audio from video."
        case .transcriptionFailed(let m): return "Transcription failed: \(m)"
        case .analysisFailed(let m): return "Analysis failed: \(m)"
        case .synthesisFailed(let m): return "TTS synthesis failed: \(m)"
        case .decodingFailed(let m): return "Could not decode analysis response: \(m)"
        }
    }
}

// MARK: - Service

@MainActor
final class VideoAnalysisService: ObservableObject {
    static let shared = VideoAnalysisService()

    static let elevenLabsKeyKeychainKey = "freespeech.elevenlabs.api.key"
    static let anthropicKeyKeychainKey = "freespeech.anthropic.api.key"

    @Published var phase: VideoAnalysisPhase = .idle
    @Published var result: VideoAnalysisResult? = nil
    @Published var isRunning: Bool = false
    @Published var correctedAudioURL: URL? = nil

    // Corrected-audio playback state (observed by ContentView to render live subtitles).
    @Published var correctedAudioIsPlaying: Bool = false
    @Published var correctedAudioCurrentTime: TimeInterval = 0
    @Published var correctedAudioDuration: TimeInterval = 0
    @Published private(set) var correctedAudioCues: [SubtitleCue] = []
    @Published var playbackRate: Float = 1.0

    private var currentTask: Task<Void, Never>? = nil
    private var audioPlayer: AVAudioPlayer? = nil
    private var audioPlayerDelegate: AudioPlayerDelegate? = nil
    private var playbackTimer: Timer? = nil

    struct SubtitleCue: Equatable {
        let text: String
        let start: TimeInterval
        let end: TimeInterval
    }

    struct AudioWordTiming: Codable {
        let word: String
        let startSeconds: Double
        let endSeconds: Double
    }

    /// The word (or short phrase) currently being spoken, based on playback time.
    var currentSubtitle: String? {
        guard correctedAudioIsPlaying || correctedAudioCurrentTime > 0 else { return nil }
        let t = correctedAudioCurrentTime
        return correctedAudioCues.first(where: { t >= $0.start && t < $0.end })?.text
    }

    var hasAllKeys: Bool {
        KeychainHelper.load(key: Self.elevenLabsKeyKeychainKey) != nil &&
        KeychainHelper.load(key: Self.anthropicKeyKeychainKey) != nil &&
        KeychainHelper.load(key: PronunciationService.azureKeyKeychainKey) != nil
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        isRunning = false
        phase = .idle
    }

    // MARK: - Corrected-audio playback

    func toggleCorrectedPlayback() {
        guard let url = correctedAudioURL else { return }
        if correctedAudioIsPlaying {
            audioPlayer?.pause()
            correctedAudioIsPlaying = false
            stopPlaybackTimer()
            return
        }
        if let player = audioPlayer, player.url == url {
            if player.currentTime >= player.duration {
                player.currentTime = 0
                correctedAudioCurrentTime = 0
            }
            player.enableRate = true
            player.rate = playbackRate
            player.play()
            correctedAudioIsPlaying = true
            startPlaybackTimer()
            return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            let delegate = AudioPlayerDelegate { [weak self] in
                Task { @MainActor in self?.handlePlaybackFinished() }
            }
            player.delegate = delegate
            player.enableRate = true
            player.rate = playbackRate
            player.prepareToPlay()
            audioPlayer = player
            audioPlayerDelegate = delegate
            correctedAudioDuration = player.duration
            if correctedAudioCues.isEmpty {
                correctedAudioCues = Self.makeSubtitleCues(
                    text: result?.correctedText ?? "",
                    totalDuration: player.duration
                )
            }
            player.play()
            correctedAudioIsPlaying = true
            correctedAudioCurrentTime = 0
            startPlaybackTimer()
        } catch {
            // swallow — UI will reflect no playback
        }
    }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        if correctedAudioIsPlaying {
            audioPlayer?.rate = rate
        }
    }

    func stopCorrectedPlayback() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        correctedAudioIsPlaying = false
        correctedAudioCurrentTime = 0
        stopPlaybackTimer()
    }

    private func handlePlaybackFinished() {
        correctedAudioIsPlaying = false
        correctedAudioCurrentTime = 0
        stopPlaybackTimer()
    }

    private func startPlaybackTimer() {
        stopPlaybackTimer()
        let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.audioPlayer else { return }
                self.correctedAudioCurrentTime = player.currentTime
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        playbackTimer = timer
    }

    private func stopPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    /// Groups the corrected text into 6-word phrase cues, timing each by its
    /// share of total character weight. Phrase-level grouping feels much closer
    /// to real subtitle sync than word-by-word estimation.
    private static func makeSubtitleCues(text: String, totalDuration: TimeInterval) -> [SubtitleCue] {
        let tokens = text
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map(String.init)
        guard !tokens.isEmpty, totalDuration > 0 else { return [] }

        let chunkSize = 6
        var chunks: [(phrase: String, weight: Double)] = []
        var i = 0
        while i < tokens.count {
            let slice = tokens[i..<min(i + chunkSize, tokens.count)]
            let weight = slice.reduce(0.0) { $0 + Double(max(1, $1.count)) }
            chunks.append((slice.joined(separator: " "), weight))
            i += chunkSize
        }

        let totalWeight = chunks.reduce(0.0) { $0 + $1.weight }
        guard totalWeight > 0 else { return [] }

        var cues: [SubtitleCue] = []
        var cursor: TimeInterval = 0
        for chunk in chunks {
            let slice = (chunk.weight / totalWeight) * totalDuration
            let end = min(totalDuration, cursor + slice)
            cues.append(SubtitleCue(text: chunk.phrase, start: cursor, end: end))
            cursor = end
        }
        return cues
    }

    static func makeSubtitleCuesFromWordTimings(_ timings: [AudioWordTiming]) -> [SubtitleCue] {
        guard !timings.isEmpty else { return [] }
        let chunkSize = 6
        var cues: [SubtitleCue] = []
        var i = 0
        while i < timings.count {
            let slice = timings[i..<min(i + chunkSize, timings.count)]
            let phrase = slice.map(\.word).joined(separator: " ")
            cues.append(SubtitleCue(
                text: phrase,
                start: slice.first!.startSeconds,
                end: slice.last!.endSeconds
            ))
            i += chunkSize
        }
        return cues
    }

    /// Loads cached artifacts from a video entry directory, if present.
    func loadCached(videoDirectory: URL) -> (VideoAnalysisResult, URL?, [AudioWordTiming]?)? {
        let analysisURL = videoDirectory.appendingPathComponent("analysis.json")
        let audioURL = videoDirectory.appendingPathComponent("corrected.mp3")
        let timingsURL = videoDirectory.appendingPathComponent("word-timings.json")
        guard FileManager.default.fileExists(atPath: analysisURL.path),
              let data = try? Data(contentsOf: analysisURL),
              let decoded = try? JSONDecoder().decode(VideoAnalysisResult.self, from: data) else {
            return nil
        }
        let audio = FileManager.default.fileExists(atPath: audioURL.path) ? audioURL : nil
        let timings: [AudioWordTiming]? = {
            guard let tData = try? Data(contentsOf: timingsURL) else { return nil }
            return try? JSONDecoder().decode([AudioWordTiming].self, from: tData)
        }()
        return (decoded, audio, timings)
    }

    func adoptCached(_ cached: (VideoAnalysisResult, URL?, [AudioWordTiming]?)) {
        stopCorrectedPlayback()
        audioPlayer = nil
        audioPlayerDelegate = nil
        correctedAudioDuration = 0
        self.result = cached.0
        self.correctedAudioURL = cached.1
        self.phase = .done
        if let timings = cached.2 {
            correctedAudioCues = Self.makeSubtitleCuesFromWordTimings(timings)
        } else {
            correctedAudioCues = []
        }
    }

    func reset() {
        stopCorrectedPlayback()
        audioPlayer = nil
        audioPlayerDelegate = nil
        correctedAudioCues = []
        correctedAudioDuration = 0
        result = nil
        correctedAudioURL = nil
        phase = .idle
        isRunning = false
    }

    func run(videoURL: URL, languageCode: String, nativeLanguage: String = "Italian", videoDirectory: URL) {
        guard let elevenKey = KeychainHelper.load(key: Self.elevenLabsKeyKeychainKey) else {
            phase = .error(VideoAnalysisServiceError.missingElevenLabsKey.localizedDescription)
            return
        }
        guard let azureKey = KeychainHelper.load(key: PronunciationService.azureKeyKeychainKey) else {
            phase = .error(VideoAnalysisServiceError.missingAzureKey.localizedDescription)
            return
        }
        let azureRegion = KeychainHelper.load(key: PronunciationService.azureRegionKeychainKey) ?? "eastus"
        guard let anthropicKey = KeychainHelper.load(key: Self.anthropicKeyKeychainKey) else {
            phase = .error(VideoAnalysisServiceError.missingAnthropicKey.localizedDescription)
            return
        }

        currentTask?.cancel()
        isRunning = true
        phase = .extractingAudio
        result = nil
        correctedAudioURL = nil

        currentTask = Task { [weak self] in
            guard let self else { return }
            do {
                // 1. Extract audio
                let wavURL = try await Self.extractWAV(from: videoURL)
                defer { try? FileManager.default.removeItem(at: wavURL) }

                try Task.checkCancellation()
                await MainActor.run { self.phase = .transcribing }

                // 2. ElevenLabs STT
                let customVocab = UserDefaults.standard.stringArray(forKey: "customVocabulary") ?? []
                let (rawTranscriptJSON, transcriptText) = try await Self.transcribeWithElevenLabs(
                    wavURL: wavURL, apiKey: elevenKey, languageCode: languageCode, customVocabulary: customVocab
                )
                try? rawTranscriptJSON.write(
                    to: videoDirectory.appendingPathComponent("eleven-transcript.json"),
                    options: .atomic
                )

                let transcriptWithFrontMatter = "---\nlanguage: \(languageCode)\n---\n\n\(transcriptText)"
                try? transcriptWithFrontMatter.write(
                    to: videoDirectory.appendingPathComponent("transcript.md"),
                    atomically: true,
                    encoding: .utf8
                )

                try Task.checkCancellation()
                await MainActor.run { self.phase = .analyzing }

                // 3. Claude analysis + Azure pronunciation (parallel, Azure best-effort)
                async let analysisTask = Self.analyze(
                    transcript: transcriptText,
                    apiKey: anthropicKey,
                    nativeLanguage: nativeLanguage,
                    targetLanguageCode: languageCode
                )
                async let pronunciationTask: PronunciationAssessmentResult? = Self.runPronunciationIfAvailable(
                    videoURL: videoURL,
                    referenceText: transcriptText,
                    languageCode: languageCode,
                    videoDirectory: videoDirectory
                )

                let partial = try await analysisTask
                _ = await pronunciationTask
                let finalResult = VideoAnalysisResult(
                    rawTranscript: transcriptText,
                    patterns: partial.patterns,
                    upgrades: partial.upgrades,
                    goldenSentences: partial.goldenSentences,
                    correctedText: partial.correctedText
                )

                // Persist analysis + corrected text
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted]
                if let analysisData = try? encoder.encode(finalResult) {
                    try? analysisData.write(
                        to: videoDirectory.appendingPathComponent("analysis.json"),
                        options: .atomic
                    )
                }
                try? finalResult.correctedText.write(
                    to: videoDirectory.appendingPathComponent("corrected.txt"),
                    atomically: true, encoding: .utf8
                )

                try Task.checkCancellation()
                await MainActor.run { self.phase = .synthesizing }

                // 4. Azure TTS
                let mp3URL = videoDirectory.appendingPathComponent("corrected.mp3")
                try await Self.synthesize(
                    text: finalResult.correctedText,
                    azureKey: azureKey,
                    azureRegion: azureRegion,
                    languageCode: languageCode,
                    outputURL: mp3URL
                )

                // 5. Get word-level timing by running Azure STT on the TTS audio.
                var wordTimings: [AudioWordTiming] = []
                wordTimings = (try? await Self.extractWordTimings(
                    audioURL: mp3URL,
                    apiKey: azureKey,
                    region: azureRegion,
                    languageCode: languageCode
                )) ?? []

                if !wordTimings.isEmpty {
                    let timingsEncoder = JSONEncoder()
                    timingsEncoder.outputFormatting = [.prettyPrinted]
                    if let tData = try? timingsEncoder.encode(wordTimings) {
                        try? tData.write(
                            to: videoDirectory.appendingPathComponent("word-timings.json"),
                            options: .atomic
                        )
                    }
                }

                let cues: [SubtitleCue]
                if !wordTimings.isEmpty {
                    cues = Self.makeSubtitleCuesFromWordTimings(wordTimings)
                } else {
                    let duration = (try? await AVURLAsset(url: mp3URL).load(.duration).seconds) ?? 0
                    cues = Self.makeSubtitleCues(text: finalResult.correctedText, totalDuration: duration)
                }

                await MainActor.run {
                    self.result = finalResult
                    self.correctedAudioURL = mp3URL
                    self.correctedAudioCues = cues
                    self.phase = .done
                    self.isRunning = false
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.phase = .idle
                    self.isRunning = false
                }
            } catch {
                await MainActor.run {
                    self.phase = .error(error.localizedDescription)
                    self.isRunning = false
                }
            }
        }
    }

    // MARK: - Audio extraction

    private static func extractWAV(from movieURL: URL) async throws -> URL {
        let asset = AVAsset(url: movieURL)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw VideoAnalysisServiceError.audioExtractionFailed
        }

        let readerSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let writerSettings = readerSettings

        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: readerSettings)
        reader.add(readerOutput)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .wav)
        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: writerSettings)
        writer.add(writerInput)

        reader.startReading()
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        return try await withCheckedThrowingContinuation { continuation in
            writerInput.requestMediaDataWhenReady(on: DispatchQueue(label: "freespeech.analysis.export")) {
                while writerInput.isReadyForMoreMediaData {
                    if let sample = readerOutput.copyNextSampleBuffer() {
                        writerInput.append(sample)
                    } else {
                        writerInput.markAsFinished()
                        writer.finishWriting {
                            if writer.status == .completed {
                                continuation.resume(returning: outputURL)
                            } else {
                                continuation.resume(throwing: writer.error ?? VideoAnalysisServiceError.audioExtractionFailed)
                            }
                        }
                        break
                    }
                }
            }
        }
    }

    // MARK: - Azure Pronunciation (best-effort, parallel with OpenAI analyze)

    private static func runPronunciationIfAvailable(
        videoURL: URL,
        referenceText: String,
        languageCode: String,
        videoDirectory: URL
    ) async -> PronunciationAssessmentResult? {
        guard PronunciationService.shared.hasAPIKey else { return nil }
        return await withCheckedContinuation { continuation in
            PronunciationService.shared.assess(
                audioURL: videoURL,
                referenceText: referenceText,
                languageCode: languageCode
            ) { result in
                switch result {
                case .success(let assessment):
                    let url = videoDirectory.appendingPathComponent("pronunciation-assessment.json")
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted]
                    if let data = try? encoder.encode(assessment) {
                        try? data.write(to: url, options: .atomic)
                    }
                    continuation.resume(returning: assessment)
                case .failure(let error):
                    print("Pronunciation assessment failed during Analyze: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: - ElevenLabs STT

    private static func transcribeWithElevenLabs(wavURL: URL, apiKey: String, languageCode: String, customVocabulary: [String] = []) async throws -> (Data, String) {
        let url = URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let shortLang = String(languageCode.prefix(2)).lowercased()

        var body = Data()
        func appendField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        appendField("model_id", "scribe_v2")
        appendField("language_code", shortLang)
        appendField("tag_audio_events", "true")
        appendField("diarize", "false")
        if !customVocabulary.isEmpty {
            let vocabJSON = customVocabulary.map { "{\"word\":\"\($0)\"}" }.joined(separator: ",")
            appendField("custom_vocabulary", "[\(vocabJSON)]")
        }

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(try Data(contentsOf: wavURL))
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP error"
            throw VideoAnalysisServiceError.transcriptionFailed(msg)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String else {
            throw VideoAnalysisServiceError.transcriptionFailed("Unexpected response shape")
        }

        return (data, text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - Azure STT (used for word timing extraction from TTS audio)

    private static func transcribeWithAzure(
        wavURL: URL,
        apiKey: String,
        region: String,
        languageCode: String
    ) async throws -> String {
        let wavData = try Data(contentsOf: wavURL)
        let headerSize = 44
        let bytesPerSecond = 32000 // 16kHz * 16-bit * 1ch
        let audioBytes = max(0, wavData.count - headerSize)
        let totalDuration = Double(audioBytes) / Double(bytesPerSecond)

        if totalDuration <= 55 {
            let (text, _) = try await azureSTTRequest(
                wavData: wavData, apiKey: apiKey, region: region, languageCode: languageCode
            )
            return text
        }

        // Chunk long audio into ~50-second segments
        let chunkSeconds = 50
        let chunkBytes = chunkSeconds * bytesPerSecond
        var fullText = ""
        var offset = 0

        while offset < audioBytes {
            let end = min(offset + chunkBytes, audioBytes)
            let pcmSlice = wavData[headerSize + offset ..< headerSize + end]
            let chunkWAV = Self.buildWAVData(pcm: pcmSlice)
            let (text, _) = try await azureSTTRequest(
                wavData: chunkWAV, apiKey: apiKey, region: region, languageCode: languageCode
            )
            if !text.isEmpty {
                if !fullText.isEmpty { fullText += " " }
                fullText += text
            }
            offset = end
        }
        return fullText
    }

    private static func azureSTTRequest(
        wavData: Data,
        apiKey: String,
        region: String,
        languageCode: String
    ) async throws -> (String, [AudioWordTiming]) {
        let endpoint = "https://\(region).stt.speech.microsoft.com/speech/recognition/conversation/cognitiveservices/v1?language=\(languageCode)&format=detailed"
        guard let url = URL(string: endpoint) else {
            throw VideoAnalysisServiceError.transcriptionFailed("Invalid Azure endpoint")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        request.httpBody = wavData

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP error"
            throw VideoAnalysisServiceError.transcriptionFailed(msg)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw VideoAnalysisServiceError.transcriptionFailed("Unexpected response shape")
        }

        let displayText = (json["DisplayText"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        var wordTimings: [AudioWordTiming] = []
        if let nBest = json["NBest"] as? [[String: Any]],
           let first = nBest.first,
           let words = first["Words"] as? [[String: Any]] {
            let ticksPerSecond = 10_000_000.0
            for w in words {
                guard let word = w["Word"] as? String else { continue }
                let offset = Double(w["Offset"] as? Int64 ?? 0) / ticksPerSecond
                let duration = Double(w["Duration"] as? Int64 ?? 0) / ticksPerSecond
                wordTimings.append(AudioWordTiming(
                    word: word, startSeconds: offset, endSeconds: offset + duration
                ))
            }
        }

        return (displayText, wordTimings)
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
        appendUInt32(16)       // fmt chunk size
        appendUInt16(1)        // PCM
        appendUInt16(1)        // mono
        appendUInt32(16000)    // sample rate
        appendUInt32(32000)    // byte rate
        appendUInt16(2)        // block align
        appendUInt16(16)       // bits per sample
        header.append("data".data(using: .ascii)!)
        appendUInt32(dataSize)

        return header + pcm
    }

    // MARK: - Claude Analysis

    private struct AnalysisPayload: Decodable {
        let patterns: [LanguagePattern]
        let upgrades: [NaturalUpgrade]
        let goldenSentences: [GoldenSentence]
        let correctedText: String

        enum CodingKeys: String, CodingKey {
            case patterns
            case upgrades
            case goldenSentences = "golden_sentences"
            case correctedText = "corrected_text"
        }
    }

    private static func analyze(
        transcript: String,
        apiKey: String,
        nativeLanguage: String,
        targetLanguageCode: String
    ) async throws -> AnalysisPayload {
        let targetLanguage = Locale(identifier: "en_US").localizedString(forLanguageCode: targetLanguageCode) ?? targetLanguageCode

        let systemPrompt = """
        You are a demanding but concrete language tutor. The user's native language is \(nativeLanguage) and they are practicing \(targetLanguage) by recording spoken journal entries. Your job is to produce material that will STICK in memory — not generic praise, not textbook theory.

        Hard rules:
        - NEVER produce generic emotional feedback ("great job", "keep going", "nice work", "you did well with X"). It is explicitly banned.
        - NEVER invent examples. Every "you_said" string MUST be copied literally from the transcript (minor punctuation/capitalization is OK).
        - Group similar mistakes into ONE pattern. If the speaker made 3 preposition-of-time mistakes, that is one pattern with 3 examples — not 3 patterns.
        - Ignore filler words (uh, um, like, ehm, eh) unless they materially affect meaning.
        - NEVER include an example where `you_said` and `natural` are identical or differ only in capitalization/punctuation/commas. Punctuation is irrelevant in spoken language. If a phrasing is already correct, omit it entirely.
        - All user-facing text (rules, notes, why_it_sticks, focus, sentence, cloze, variations) is written in \(targetLanguage). For `l1_contrast` only, you MAY use short \(nativeLanguage) fragments when contrasting L1 habits directly.
        - In `golden_sentences`, NEVER include the wrong form anywhere. The speaker must read only correct \(targetLanguage). Do NOT instruct them to "swap X with Y", "say it wrong then right", or any meta-instruction. Drill material is correct sentences only.

        Produce a strict JSON object with this schema:
        {
          "patterns": [
            {
              "title": string,            // concise label, e.g. "Past simple vs present perfect"
              "rule": string,             // ONE actionable line. No theory. Example: "Use past simple for finished actions with a specific time; use present perfect when the time is unspecified or relevant to now."
              "l1_contrast": string,      // how a \(nativeLanguage) speaker typically mis-maps this into \(targetLanguage). Omit or leave empty string if no meaningful contrast.
              "examples": [               // 1–4 concrete examples FROM THE TRANSCRIPT
                { "you_said": string, "natural": string, "note": string }
              ]
            }
          ],
          "upgrades": [                    // phrasings a native would prefer — phrasal verbs, collocations, idiomatic usage. Only upgrades that teach something, not trivial synonym swaps.
            {
              "you_said": string,
              "natural": string,
              "kind": "phrasal_verb" | "collocation" | "idiomatic",
              "why_it_sticks": string     // one vivid line explaining why this is THE way a native says it (register, frequency, nuance). No fluff.
            }
          ],
          "golden_sentences": [            // 1–3 CORRECT sentences built from the speaker's own content, each embodying the single most important pattern they need to internalise. Each sentence must be ≤ ~14 words and pronounceable in ≤ 6 seconds.
            {
              "sentence": string,          // the canonical correct sentence
              "pattern": string,           // which pattern this sentence drills (match a patterns[].title when possible)
              "cloze": string|null,        // SAME sentence with the key element replaced by exactly "___" (three underscores). Target the element the speaker got wrong or that embodies the pattern. Use null if no single element captures the pattern cleanly.
              "answer": string|null,       // exact text that fills the blank in `cloze` (no surrounding words). Required when `cloze` is non-null; otherwise null.
              "variations": [string],      // 2–4 ALTERNATE sentences, ALL CORRECT, that drill the SAME pattern by changing one element (subject, object, time marker, etc.). Each variation ≤ ~14 words. Never include the wrong form. Empty array allowed if no good variations exist.
              "focus": string|null         // ONE short line in \(targetLanguage) naming what to notice (e.g. "'helps' agrees with 'Clothz' as a singular brand."). Optional.
            }
          ],
          "corrected_text": string         // the full transcript with only real mistakes fixed. Untouched sentences appear VERBATIM. Filler words removed so it reads naturally when spoken aloud.
        }

        Quality bar:
        - If the speaker made no real mistakes in a category, return an empty array for it. Do not pad.
        - Prefer 2 strong patterns with 3 examples each over 6 weak patterns with 1 example each.
        - `golden_sentences` is the highest-leverage part of the output. Pick sentences the speaker will actually want to say again — first person, topical to what they talked about. One pattern per sentence.

        Respond with JSON only. No markdown. No commentary.
        """

        let body: [String: Any] = [
            "model": "claude-sonnet-4-6",
            "max_tokens": 4096,
            "temperature": 0.2,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": "Here is the transcript to analyze:\n\n\(transcript)"]
            ]
        ]

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP error"
            throw VideoAnalysisServiceError.analysisFailed(msg)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let rawText = content.first?["text"] as? String else {
            throw VideoAnalysisServiceError.analysisFailed("Unexpected response shape")
        }

        // Strip markdown code fences if present (```json ... ``` or ``` ... ```)
        let text = rawText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^```(?:json)?\n?"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\n?```$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let contentData = text.data(using: .utf8) else {
            throw VideoAnalysisServiceError.analysisFailed("Could not encode response text")
        }

        do {
            return try JSONDecoder().decode(AnalysisPayload.self, from: contentData)
        } catch {
            throw VideoAnalysisServiceError.decodingFailed("\(error.localizedDescription)\n\nRaw response:\n\(text.prefix(500))")
        }
    }

    // MARK: - Azure TTS

    private static func azureTTSVoice(for languageCode: String) -> String {
        let voices: [String: String] = [
            "en-US": "en-US-JennyNeural",
            "en-GB": "en-GB-SoniaNeural",
            "en-AU": "en-AU-NatashaNeural",
            "it-IT": "it-IT-ElsaNeural",
            "fr-FR": "fr-FR-DeniseNeural",
            "de-DE": "de-DE-KatjaNeural",
            "es-ES": "es-ES-ElviraNeural",
            "es-MX": "es-MX-DaliaNeural",
            "pt-BR": "pt-BR-FranciscaNeural",
            "pt-PT": "pt-PT-RaquelNeural",
            "ja-JP": "ja-JP-NanamiNeural",
            "ko-KR": "ko-KR-SunHiNeural",
            "zh-CN": "zh-CN-XiaoxiaoNeural",
            "zh-TW": "zh-TW-HsiaoChenNeural",
            "ru-RU": "ru-RU-SvetlanaNeural",
            "nl-NL": "nl-NL-ColetteNeural",
            "pl-PL": "pl-PL-ZofiaNeural",
            "sv-SE": "sv-SE-SofieNeural",
            "tr-TR": "tr-TR-EmelNeural",
            "ar-SA": "ar-SA-ZariyahNeural",
        ]
        if let voice = voices[languageCode] { return voice }
        let prefix = String(languageCode.prefix(2)).lowercased()
        return voices.first(where: { $0.key.lowercased().hasPrefix(prefix) })?.value ?? "en-US-JennyNeural"
    }

    private static func synthesize(text: String, azureKey: String, azureRegion: String, languageCode: String, outputURL: URL) async throws {
        let voice = azureTTSVoice(for: languageCode)
        let escaped = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
        let ssml = "<speak version='1.0' xml:lang='\(languageCode)'><voice name='\(voice)'>\(escaped)</voice></speak>"

        let endpoint = "https://\(azureRegion).tts.speech.microsoft.com/cognitiveservices/v1"
        guard let url = URL(string: endpoint) else {
            throw VideoAnalysisServiceError.synthesisFailed("Invalid Azure TTS endpoint")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(azureKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.setValue("application/ssml+xml", forHTTPHeaderField: "Content-Type")
        request.setValue("audio-24khz-160kbitrate-mono-mp3", forHTTPHeaderField: "X-Microsoft-OutputFormat")
        request.httpBody = ssml.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP error"
            throw VideoAnalysisServiceError.synthesisFailed(msg)
        }

        try data.write(to: outputURL, options: .atomic)
    }

    // MARK: - Word timing extraction (Azure STT on TTS audio)

    private static func extractWordTimings(
        audioURL: URL,
        apiKey: String,
        region: String,
        languageCode: String
    ) async throws -> [AudioWordTiming] {
        let wavURL = try await extractWAV(from: audioURL)
        defer { try? FileManager.default.removeItem(at: wavURL) }

        let wavData = try Data(contentsOf: wavURL)
        let headerSize = 44
        let bytesPerSecond = 32000
        let audioBytes = max(0, wavData.count - headerSize)
        let totalDuration = Double(audioBytes) / Double(bytesPerSecond)

        if totalDuration <= 55 {
            let (_, timings) = try await azureSTTRequest(
                wavData: wavData, apiKey: apiKey, region: region, languageCode: languageCode
            )
            return timings
        }

        // Chunk for longer TTS audio (rare)
        let chunkSeconds = 50
        let chunkBytes = chunkSeconds * bytesPerSecond
        var allTimings: [AudioWordTiming] = []
        var offset = 0

        while offset < audioBytes {
            let end = min(offset + chunkBytes, audioBytes)
            let pcmSlice = wavData[headerSize + offset ..< headerSize + end]
            let chunkWAV = buildWAVData(pcm: pcmSlice)
            let chunkOffsetSeconds = Double(offset) / Double(bytesPerSecond)
            let (_, timings) = try await azureSTTRequest(
                wavData: chunkWAV, apiKey: apiKey, region: region, languageCode: languageCode
            )
            for t in timings {
                allTimings.append(AudioWordTiming(
                    word: t.word,
                    startSeconds: t.startSeconds + chunkOffsetSeconds,
                    endSeconds: t.endSeconds + chunkOffsetSeconds
                ))
            }
            offset = end
        }
        return allTimings
    }
}

private final class AudioPlayerDelegate: NSObject, AVAudioPlayerDelegate {
    private let onFinish: () -> Void
    init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish()
    }
}

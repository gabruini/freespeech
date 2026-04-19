//
//  PronunciationReviewView.swift
//

import SwiftUI
import AVFoundation

// MARK: - Confidence-based review (Phase 2, Apple-native)

struct PronunciationReviewView: View {
    let wordConfidences: [WordConfidence]
    let colorScheme: ColorScheme
    let assessmentResult: PronunciationAssessmentResult?
    let languageCode: String
    var isEmbedded: Bool = false
    var isRunningAssessment: Bool = false
    var onRunAzureAssessment: (() -> Void)? = nil
    var missingAzureKey: Bool = false

    init(
        wordConfidences: [WordConfidence],
        colorScheme: ColorScheme,
        assessmentResult: PronunciationAssessmentResult? = nil,
        languageCode: String = "en-US",
        isEmbedded: Bool = false,
        isRunningAssessment: Bool = false,
        onRunAzureAssessment: (() -> Void)? = nil,
        missingAzureKey: Bool = false
    ) {
        self.wordConfidences = wordConfidences
        self.colorScheme = colorScheme
        self.assessmentResult = assessmentResult
        self.languageCode = languageCode
        self.isEmbedded = isEmbedded
        self.isRunningAssessment = isRunningAssessment
        self.onRunAzureAssessment = onRunAzureAssessment
        self.missingAzureKey = missingAzureKey
    }

    var averageConfidence: Float {
        guard !wordConfidences.isEmpty else { return 0 }
        let total = wordConfidences.reduce(Float(0)) { $0 + $1.confidence }
        return total / Float(wordConfidences.count)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let assessment = assessmentResult {
                    AzureAssessmentView(result: assessment, colorScheme: colorScheme, languageCode: languageCode)
                } else if missingAzureKey {
                    missingAzureKeyState
                } else if wordConfidences.isEmpty {
                    emptyState
                } else {
                    confidenceView
                    if onRunAzureAssessment != nil {
                        runAssessmentButton
                    }
                }
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private var missingAzureKeyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Missing Azure API key", systemImage: "key.slash")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
            Text("Add an Azure Speech key in Settings to enable pronunciation assessment.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("No pronunciation data yet", systemImage: "mic.slash")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
            Text("Pronunciation feedback becomes available after Analyze runs, or by running the Azure assessment directly below.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            if onRunAzureAssessment != nil {
                runAssessmentButton
            }
        }
    }

    @ViewBuilder
    private var runAssessmentButton: some View {
        Button(action: { onRunAzureAssessment?() }) {
            HStack(spacing: 6) {
                if isRunningAssessment {
                    ProgressView().controlSize(.small)
                    Text("Running Azure assessment…")
                } else {
                    Image(systemName: "waveform.badge.magnifyingglass")
                    Text("Run Azure Pronunciation Assessment")
                }
            }
            .font(.system(size: 12))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(isRunningAssessment)
    }

    private var confidenceView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Recognition Confidence")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(Int(averageConfidence * 100))%")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(colorForConfidence(averageConfidence))
            }

            Text("Based on speech recognition confidence, not pronunciation accuracy.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .italic()

            Divider()

            WrappingHStack(wordConfidences: wordConfidences, colorScheme: colorScheme)

            HStack(spacing: 16) {
                legendItem(color: .green, label: "High (>80%)")
                legendItem(color: .orange, label: "Medium (50-80%)")
                legendItem(color: .red, label: "Low (<50%)")
            }
            .font(.system(size: 11))
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color.opacity(0.7))
                .frame(width: 8, height: 8)
            Text(label)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Azure Pronunciation Assessment View (Phase 4)

// Retained at module scope so utterances are not cut off when the view redraws.
private let sharedSpeechSynthesizer = AVSpeechSynthesizer()

private struct AzureAssessmentView: View {
    let result: PronunciationAssessmentResult
    let colorScheme: ColorScheme
    let languageCode: String
    @State private var selectedWord: PronunciationAssessmentResult.AssessedWord? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Pronunciation Assessment")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)

            // Overall scores
            HStack(spacing: 20) {
                ScoreGauge(label: "Accuracy", score: result.overallAccuracy)
                ScoreGauge(label: "Fluency", score: result.overallFluency)
                ScoreGauge(label: "Completeness", score: result.overallCompleteness)
                if let prosody = result.overallProsody {
                    ScoreGauge(label: "Prosody", score: prosody)
                }
            }

            Divider()

            // Word-level assessment
            Text("Word Accuracy")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)

            FlowLayout(spacing: 4) {
                ForEach(Array(result.words.enumerated()), id: \.offset) { index, word in
                    AssessedWordTag(word: word, colorScheme: colorScheme, isSelected: selectedWord?.id == word.id)
                        .onTapGesture {
                            if selectedWord?.id == word.id {
                                selectedWord = nil
                            } else {
                                selectedWord = word
                            }
                        }
                }
            }

            // Phoneme detail for selected word
            if let selected = selectedWord, !selected.phonemes.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Phonemes for \"\(selected.word)\"")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)

                        Spacer()

                        // Listen button
                        Button(action: {
                            speakWord(selected.word)
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(.system(size: 10))
                                Text("Listen")
                                    .font(.system(size: 11))
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.blue.opacity(0.8))
                    }

                    HStack(spacing: 6) {
                        ForEach(Array(selected.phonemes.enumerated()), id: \.offset) { _, phoneme in
                            VStack(spacing: 2) {
                                Text(phoneme.phoneme)
                                    .font(.system(size: 14, weight: .medium))
                                Text("\(Int(phoneme.accuracyScore))%")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(colorForScore(phoneme.accuracyScore).opacity(0.15))
                            )
                        }
                    }
                }
            }

            HStack(spacing: 16) {
                legendItem(color: .green, label: "Good (>80)")
                legendItem(color: .orange, label: "Fair (50-80)")
                legendItem(color: .red, label: "Needs work (<50)")
            }
            .font(.system(size: 11))
        }
    }

    private func speakWord(_ word: String) {
        if sharedSpeechSynthesizer.isSpeaking {
            sharedSpeechSynthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: word)
        utterance.rate = 0.4
        if let voice = AVSpeechSynthesisVoice(language: languageCode)
            ?? AVSpeechSynthesisVoice(language: String(languageCode.prefix(2))) {
            utterance.voice = voice
        }
        sharedSpeechSynthesizer.speak(utterance)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color.opacity(0.7))
                .frame(width: 8, height: 8)
            Text(label)
                .foregroundColor(.secondary)
        }
    }
}

private struct ScoreGauge: View {
    let label: String
    let score: Double

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 4)
                    .frame(width: 44, height: 44)

                Circle()
                    .trim(from: 0, to: score / 100)
                    .stroke(colorForScore(score), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 44, height: 44)
                    .rotationEffect(.degrees(-90))

                Text("\(Int(score))")
                    .font(.system(size: 13, weight: .semibold))
            }
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }
}

private struct AssessedWordTag: View {
    let word: PronunciationAssessmentResult.AssessedWord
    let colorScheme: ColorScheme
    let isSelected: Bool

    var body: some View {
        Text(word.word)
            .font(.system(size: 14))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(colorForScore(word.accuracyScore).opacity(isSelected ? 0.35 : 0.15))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(isSelected ? colorForScore(word.accuracyScore) : Color.clear, lineWidth: 1)
            )
            .foregroundColor(colorScheme == .light
                ? Color(red: 0.20, green: 0.20, blue: 0.20)
                : Color(red: 0.9, green: 0.9, blue: 0.9))
            .help("\(word.word): \(Int(word.accuracyScore))% accuracy\(word.errorType.map { " (\($0))" } ?? "")")
    }
}

// MARK: - Shared helpers

private func colorForConfidence(_ confidence: Float) -> Color {
    if confidence > 0.8 {
        return .green
    } else if confidence > 0.5 {
        return .orange
    } else {
        return .red
    }
}

private func colorForScore(_ score: Double) -> Color {
    if score > 80 { return .green }
    if score > 50 { return .orange }
    return .red
}

private struct WrappingHStack: View {
    let wordConfidences: [WordConfidence]
    let colorScheme: ColorScheme

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(Array(wordConfidences.enumerated()), id: \.offset) { _, wc in
                WordConfidenceTag(wordConfidence: wc, colorScheme: colorScheme)
            }
        }
    }
}

private struct WordConfidenceTag: View {
    let wordConfidence: WordConfidence
    let colorScheme: ColorScheme
    @State private var isHovering = false

    var body: some View {
        Text(wordConfidence.word)
            .font(.system(size: 14))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(colorForConfidence(wordConfidence.confidence).opacity(isHovering ? 0.3 : 0.15))
            )
            .foregroundColor(colorScheme == .light
                ? Color(red: 0.20, green: 0.20, blue: 0.20)
                : Color(red: 0.9, green: 0.9, blue: 0.9))
            .onHover { hovering in
                isHovering = hovering
            }
            .help("\(wordConfidence.word): \(Int(wordConfidence.confidence * 100))% confidence")
    }
}

// Simple flow layout for wrapping words
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            maxX = max(maxX, currentX)
        }

        return (positions, CGSize(width: maxX, height: currentY + lineHeight))
    }
}

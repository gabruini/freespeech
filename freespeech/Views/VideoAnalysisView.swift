//
//  VideoAnalysisView.swift
//

import SwiftUI
import AVFoundation

// MARK: - Siri-style animated blob

private struct SiriBlobView: View {
    let label: String

    var body: some View {
        VStack(spacing: 28) {
            TimelineView(.animation) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                BlobLayers(time: t)
            }
            .frame(width: 130, height: 130)

            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
    }
}

private struct OrganicBlobShape: Shape {
    var time: Double
    let frequencies: [Double]
    let amplitudes: [Double]

    var animatableData: Double {
        get { time }
        set { time = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let cx = rect.midX
        let cy = rect.midY
        let baseR = min(rect.width, rect.height) / 2
        let steps = 120
        var path = Path()

        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let angle = t * 2 * .pi
            var r = baseR
            for (freq, amp) in zip(frequencies, amplitudes) {
                r += amp * sin(freq * angle + time)
            }
            let x = cx + r * cos(angle)
            let y = cy + r * sin(angle)
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else       { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        path.closeSubpath()
        return path
    }
}

private struct BlobLayers: View {
    let time: Double

    private struct Blob {
        let speedMult: Double
        let phaseOffset: Double
        let orbitRadius: CGFloat
        let size: CGFloat
        let blurRadius: CGFloat
        let color: Color
        let freqs: [Double]
        let amps: [Double]
    }

    private let blobs: [Blob] = [
        Blob(speedMult: 1.0,  phaseOffset: 0,     orbitRadius: 24, size: 90, blurRadius: 22,
             color: Color(red: 0.38, green: 0.18, blue: 0.98),
             freqs: [3, 5, 7], amps: [4.5, 2.5, 1.5]),
        Blob(speedMult: 0.75, phaseOffset: 2.094, orbitRadius: 20, size: 82, blurRadius: 20,
             color: Color(red: 0.85, green: 0.20, blue: 0.65),
             freqs: [4, 6, 9], amps: [3.5, 2.0, 1.0]),
        Blob(speedMult: 1.25, phaseOffset: 4.189, orbitRadius: 18, size: 78, blurRadius: 18,
             color: Color(red: 0.10, green: 0.55, blue: 0.98),
             freqs: [3, 7, 11], amps: [4.0, 1.8, 1.2]),
    ]

    var body: some View {
        ZStack {
            ForEach(blobs.indices, id: \.self) { i in
                let b = blobs[i]
                let angle = time * b.speedMult + b.phaseOffset
                let pulse: CGFloat = 1.0 + 0.07 * sin(time * 1.8 + b.phaseOffset)
                let blobTime = time * b.speedMult + b.phaseOffset
                OrganicBlobShape(time: blobTime, frequencies: b.freqs, amplitudes: b.amps)
                    .fill(b.color.opacity(0.9))
                    .frame(width: b.size * pulse, height: b.size * pulse)
                    .offset(x: cos(angle) * b.orbitRadius, y: sin(angle) * b.orbitRadius * 0.55)
                    .blur(radius: b.blurRadius)
            }
            OrganicBlobShape(time: time * 0.6, frequencies: [4, 6], amplitudes: [3.0, 1.5])
                .fill(Color(red: 0.55, green: 0.35, blue: 1.0).opacity(0.7))
                .frame(width: 48, height: 48)
                .blur(radius: 10)
                .scaleEffect(1.0 + 0.06 * sin(time * 2.4))
        }
    }
}

enum VideoAnalysisVariant {
    case patterns
    case natural
    case drill
}

struct VideoAnalysisView: View {
    @ObservedObject var service: VideoAnalysisService
    let colorScheme: ColorScheme
    let onDismiss: () -> Void
    var isEmbedded: Bool = false
    var variant: VideoAnalysisVariant = .patterns

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch service.phase {
                    case .idle:
                        Text("Ready.")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    case .extractingAudio:
                        SiriBlobView(label: "Extracting audio…")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    case .transcribing:
                        SiriBlobView(label: "Transcribing…")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    case .analyzing:
                        SiriBlobView(label: "Analyzing…")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    case .synthesizing:
                        SiriBlobView(label: "Generating corrected audio…")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    case .error(let message):
                        errorView(message)
                    case .done:
                        if let result = service.result {
                            resultView(result)
                        }
                    }
                }
                .padding(16)
            }
        }
        .onDisappear {
            service.stopCorrectedPlayback()
        }
    }

    @ViewBuilder
    private func errorView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Something went wrong", systemImage: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 13, weight: .medium))
            Text(message)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func resultView(_ result: VideoAnalysisResult) -> some View {
        switch variant {
        case .patterns:
            patternsSection(result)
        case .natural:
            upgradesSection(result)
        case .drill:
            drillSection(result)
        }
    }

    // MARK: - Patterns

    @ViewBuilder
    private func patternsSection(_ result: VideoAnalysisResult) -> some View {
        if result.patterns.isEmpty {
            emptyState("No recurring patterns this time.", systemImage: "checkmark.seal")
        } else {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(result.patterns) { pattern in
                    patternCard(pattern)
                }
            }
        }
    }

    @ViewBuilder
    private func patternCard(_ pattern: LanguagePattern) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(pattern.title)
                .font(.system(size: 14, weight: .semibold))
                .textSelection(.enabled)

            if !pattern.rule.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.yellow)
                        .padding(.top, 2)
                    Text(pattern.rule)
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                }
            }

            if let l1 = pattern.l1Contrast, !l1.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "arrow.triangle.swap")
                        .font(.system(size: 11))
                        .foregroundColor(.purple)
                        .padding(.top, 2)
                    Text(l1)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
            }

            let errorExamples = pattern.examples.filter { isMeaningfulDifference($0.youSaid, $0.natural) }
            if !errorExamples.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(errorExamples) { ex in
                        contrastRow(youSaid: ex.youSaid, natural: ex.natural, note: ex.note)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
    }

    // MARK: - Natural upgrades

    @ViewBuilder
    private func upgradesSection(_ result: VideoAnalysisResult) -> some View {
        let meaningful = result.upgrades.filter { isMeaningfulDifference($0.youSaid, $0.natural) }
        if meaningful.isEmpty {
            emptyState("No natural-sounding upgrades to suggest.", systemImage: "sparkles")
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(meaningful) { upgrade in
                    upgradeCard(upgrade)
                }
            }
        }
    }

    @ViewBuilder
    private func upgradeCard(_ upgrade: NaturalUpgrade) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(upgrade.kind.replacingOccurrences(of: "_", with: " ").uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12))
                    .cornerRadius(3)
                Spacer()
            }

            contrastRow(youSaid: upgrade.youSaid, natural: upgrade.natural, note: nil)

            if !upgrade.whyItSticks.isEmpty {
                Text(upgrade.whyItSticks)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
    }

    // MARK: - Drill (golden sentences)

    @ViewBuilder
    private func drillSection(_ result: VideoAnalysisResult) -> some View {
        if result.goldenSentences.isEmpty {
            emptyState("No drill sentences for this entry.", systemImage: "mic")
        } else {
            VStack(alignment: .leading, spacing: 14) {
                Text("Fill in the blank aloud, then read each variation. Only correct forms.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                ForEach(result.goldenSentences) { sentence in
                    GoldenSentenceCard(sentence: sentence)
                }
            }
        }
    }

    // MARK: - Shared

    private func isMeaningfulDifference(_ a: String, _ b: String) -> Bool {
        let stripped = CharacterSet.punctuationCharacters.union(.symbols).union(.whitespacesAndNewlines)
        let normalize: (String) -> String = { $0.unicodeScalars.filter { !stripped.contains($0) }.map(String.init).joined().lowercased() }
        return normalize(a) != normalize(b)
    }

    @ViewBuilder
    private func contrastRow(youSaid: String, natural: String, note: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                Text("You")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.red)
                    .frame(width: 38, alignment: .leading)
                Text(youSaid)
                    .font(.system(size: 13))
                    .strikethrough()
                    .foregroundColor(.red.opacity(0.85))
                    .textSelection(.enabled)
            }
            HStack(alignment: .top, spacing: 6) {
                Text("Native")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.green)
                    .frame(width: 38, alignment: .leading)
                Text(natural)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.green)
                    .textSelection(.enabled)
            }
            if let note, !note.isEmpty {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.leading, 44)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private func emptyState(_ message: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundColor(.secondary)
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Golden sentence card

private struct GoldenSentenceCard: View {
    let sentence: GoldenSentence
    @State private var revealed = false

    private var hasCloze: Bool {
        guard let cloze = sentence.cloze, let answer = sentence.answer else { return false }
        return cloze.contains("___") && !answer.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !sentence.pattern.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "target")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                    Text(sentence.pattern)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.orange)
                }
            }

            if hasCloze {
                clozeView
            } else {
                Text("“\(sentence.sentence)”")
                    .font(.system(size: 16, weight: .medium, design: .serif))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let focus = sentence.focus, !focus.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.yellow)
                        .padding(.top, 2)
                    Text(focus)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
            }

            if !sentence.variations.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Now read these aloud")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    ForEach(Array(sentence.variations.enumerated()), id: \.offset) { _, variation in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "arrow.turn.down.right")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .padding(.top, 4)
                            Text(variation)
                                .font(.system(size: 13, design: .serif))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.orange.opacity(0.12), Color.orange.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.25), lineWidth: 1)
        )
        .cornerRadius(10)
    }

    @ViewBuilder
    private var clozeView: some View {
        let cloze = sentence.cloze ?? ""
        let answer = sentence.answer ?? ""
        let display = revealed ? cloze.replacingOccurrences(of: "___", with: answer) : cloze

        VStack(alignment: .leading, spacing: 8) {
            Text("“\(display)”")
                .font(.system(size: 16, weight: .medium, design: .serif))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeInOut(duration: 0.15), value: revealed)

            if revealed {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.green)
                    Text(answer)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.green)
                        .textSelection(.enabled)
                }
            } else {
                Button {
                    revealed = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "eye")
                            .font(.system(size: 10))
                        Text("Say it aloud, then reveal")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

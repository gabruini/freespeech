// Swift 5.0
//
//  ContentView.swift
//
//

import SwiftUI
import AppKit
import AVFoundation

struct ContentView: View {
    @StateObject private var vm = ContentViewModel()

    // Shim properties forwarding to the view model so existing body code stays unchanged.
    private var entries: [HumanEntry] {
        get { vm.entries }
        nonmutating set { vm.entries = newValue }
    }
    private var selectedEntryId: UUID? {
        get { vm.selectedEntryId }
        nonmutating set { vm.selectedEntryId = newValue }
    }
    private var currentVideoURL: URL? {
        get { vm.currentVideoURL }
        nonmutating set { vm.currentVideoURL = newValue }
    }
    private var selectedVideoHasTranscript: Bool {
        get { vm.selectedVideoHasTranscript }
        nonmutating set { vm.selectedVideoHasTranscript = newValue }
    }

    @State private var isFullscreen = false
    @State private var isHoveringFullscreen = false
    @State private var showingHistoryPage = false
    @State private var visibleMonth: Date = Date()
    @State private var dashboardEntryIndex: Int = 0
    @State private var isHoveringDashboardThumbnail = false
    @State private var historyPickerDay: Int? = nil
    @State private var isHoveringClock = false
    @State private var colorScheme: ColorScheme = .light
    @State private var didCopyTranscript: Bool = false
    @AppStorage("targetLanguageCode") private var targetLanguageCode: String = "en-US"
    @AppStorage("nativeLanguage") private var nativeLanguage: String = "English"
    @AppStorage("videoQuality") private var videoQuality: String = "high"
    @State private var showingLanguagePicker = false
    @State private var isHoveringLanguageButton = false
    @State private var selectedMainTab: MainTab = .patterns
    @State private var showingSettingsPopover = false
    @State private var isHoveringSettingsButton = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @State private var showingOnboarding: Bool = false
    @State private var showingVideoRecording = false // Add state for video recording view
    @State private var isHoveringVideoButton = false // Add state for video button hover
    @State private var showingVideoPermissionPopover = false
    @StateObject private var videoAnalysisService = VideoAnalysisService.shared
    @State private var isHoveringAnalyzeButton = false
    @State private var isHoveringHomeButton = false
    @State private var entryPendingDeletion: HumanEntry? = nil
    @State private var pendingDeletionIsLastInDay: Bool = false

    // MARK: - VM-backed shims (forwarded to `vm`)
    private var currentWordConfidences: [WordConfidence]? {
        get { vm.currentWordConfidences }
        nonmutating set { vm.currentWordConfidences = newValue }
    }
    private var currentAssessmentResult: PronunciationAssessmentResult? {
        get { vm.currentAssessmentResult }
        nonmutating set { vm.currentAssessmentResult = newValue }
    }
    private var isAssessingPronunciation: Bool {
        get { vm.isAssessingPronunciation }
        nonmutating set { vm.isAssessingPronunciation = newValue }
    }
    private var transcriptEditorText: String {
        get { vm.transcriptEditorText }
        nonmutating set { vm.transcriptEditorText = newValue }
    }
    private var transcriptEditorOriginal: String {
        get { vm.transcriptEditorOriginal }
        nonmutating set { vm.transcriptEditorOriginal = newValue }
    }
    private var customVocabularyWords: [String] {
        get { vm.customVocabularyWords }
        nonmutating set { vm.customVocabularyWords = newValue }
    }
    private var elevenLabsKeyInput: String {
        get { vm.elevenLabsKeyInput }
        nonmutating set { vm.elevenLabsKeyInput = newValue }
    }
    private var azureKeyInput: String {
        get { vm.azureKeyInput }
        nonmutating set { vm.azureKeyInput = newValue }
    }
    private var azureRegionInput: String {
        get { vm.azureRegionInput }
        nonmutating set { vm.azureRegionInput = newValue }
    }
    private var anthropicKeyInput: String {
        get { vm.anthropicKeyInput }
        nonmutating set { vm.anthropicKeyInput = newValue }
    }
    private var preparedCameraManager: CameraManager? {
        get { vm.preparedCameraManager }
        nonmutating set { vm.preparedCameraManager = newValue }
    }
    private var videoRecordingPreparationID: UUID? {
        get { vm.videoRecordingPreparationID }
        nonmutating set { vm.videoRecordingPreparationID = newValue }
    }
    private var isPreparingVideoRecording: Bool {
        get { vm.isPreparingVideoRecording }
        nonmutating set { vm.isPreparingVideoRecording = newValue }
    }
    private var videoPermissionPopoverItems: [VideoPermissionPopoverItem] {
        get { vm.videoPermissionPopoverItems }
        nonmutating set { vm.videoPermissionPopoverItems = newValue }
    }
    private var videoPermissionPopoverFallbackMessage: String? {
        get { vm.videoPermissionPopoverFallbackMessage }
        nonmutating set { vm.videoPermissionPopoverFallbackMessage = newValue }
    }

    private let fileManager = FileManager.default
    private let storage = FileStorageService.shared
    private let thumbnailService = ThumbnailService.shared
    private let transcriptService = TranscriptService.shared
    private let entryRepository = EntryRepository.shared

    // Initialize with saved theme preference if available
    init() {
        // Load saved color scheme preference
        let savedScheme = UserDefaults.standard.string(forKey: "colorScheme") ?? "light"
        _colorScheme = State(initialValue: savedScheme == "dark" ? .dark : .light)
    }

    private func getDocumentsDirectory() -> URL { storage.documentsDirectory }
    private func getVideosDirectory() -> URL { storage.videosDirectory }
    private func getVideoEntryDirectory(for videoFilename: String) -> URL { storage.getVideoEntryDirectory(for: videoFilename) }
    private func getVideoThumbnailURL(for filename: String) -> URL { storage.getVideoThumbnailURL(for: filename) }
    private func getVideoTranscriptURL(for filename: String) -> URL { storage.getVideoTranscriptURL(for: filename) }
    private func getVideoAssessmentURL(for filename: String) -> URL { storage.getVideoAssessmentURL(for: filename) }

    private var analyzePhaseLabel: String {
        switch videoAnalysisService.phase {
        case .extractingAudio: return "Extracting…"
        case .transcribing: return "Transcribing…"
        case .analyzing:
            return PronunciationService.shared.hasAPIKey
                ? "Analyzing & scoring pronunciation…"
                : "Analyzing…"
        case .synthesizing: return "Synthesizing…"
        default: return "Analyzing…"
        }
    }

    private func startVideoAnalysis(reanalyze: Bool = false) {
        guard let selectedEntryId,
              let entry = entries.first(where: { $0.id == selectedEntryId }) else { return }
        let videoFilename = entry.videoFilename

        let videoURL = getVideoURL(for: videoFilename)
        let directory: URL
        do {
            directory = try ensureVideoEntryDirectoryExists(for: videoFilename)
        } catch {
            return
        }
        let languageCode = entry.languageCode ?? parseTranscriptLanguageCode(for: videoFilename) ?? targetLanguageCode

        if !reanalyze, let cached = videoAnalysisService.loadCached(videoDirectory: directory) {
            videoAnalysisService.adoptCached(cached)
            selectedMainTab = .patterns
            return
        }

        transcriptEditorText = ""
        transcriptEditorOriginal = ""

        videoAnalysisService.run(
            videoURL: videoURL,
            languageCode: languageCode,
            nativeLanguage: nativeLanguage,
            videoDirectory: directory
        )
        selectedMainTab = .patterns
    }

    private func loadCachedAnalysisIfAvailable(for videoFilename: String) {
        let directory = getVideoEntryDirectory(for: videoFilename)
        if let cached = videoAnalysisService.loadCached(videoDirectory: directory) {
            videoAnalysisService.adoptCached(cached)
        } else {
            videoAnalysisService.reset()
        }
    }

    private func loadAssessmentResult(for videoFilename: String) -> PronunciationAssessmentResult? {
        transcriptService.loadAssessmentResult(for: videoFilename)
    }

    private func saveAssessmentResult(_ result: PronunciationAssessmentResult, for videoFilename: String) {
        transcriptService.saveAssessmentResult(result, for: videoFilename)
    }

    private func runPronunciationAssessmentForCurrentEntry() {
        guard let selectedEntryId,
              let entry = entries.first(where: { $0.id == selectedEntryId }) else { return }
        let videoFilename = entry.videoFilename
        guard let transcript = loadTranscriptText(for: videoFilename) else {
            return
        }
        let languageCode = entry.languageCode ?? parseTranscriptLanguageCode(for: videoFilename) ?? targetLanguageCode
        let videoURL = getVideoURL(for: videoFilename)

        isAssessingPronunciation = true
        PronunciationService.shared.assess(audioURL: videoURL, referenceText: transcript, languageCode: languageCode) { result in
            self.isAssessingPronunciation = false
            switch result {
            case .success(let assessmentResult):
                self.currentAssessmentResult = assessmentResult
                self.saveAssessmentResult(assessmentResult, for: videoFilename)
            case .failure(let error):
                print("Pronunciation assessment failed: \(error.localizedDescription)")
            }
        }
    }

    private func loadWordConfidences(for videoFilename: String) -> [WordConfidence]? {
        transcriptService.loadWordConfidences(for: videoFilename)
    }

    @discardableResult
    private func ensureVideoEntryDirectoryExists(for videoFilename: String) throws -> URL {
        try storage.ensureVideoEntryDirectoryExists(for: videoFilename)
    }

    private func getVideoURL(for filename: String) -> URL { storage.getVideoURL(for: filename) }

    private func hasVideoAsset(for filename: String) -> Bool { storage.hasVideoAsset(for: filename) }

    private let historyDebugEnabled = true

    private func historyDebug(_ message: String) {
        guard historyDebugEnabled else { return }
        print("[HistoryDebug] \(message)")
    }

    private func debugEntrySummary(_ entry: HumanEntry) -> String {
        let shortID = String(entry.id.uuidString.prefix(8))
        return "id=\(shortID) file=\(entry.filename) video=\(entry.videoFilename)"
    }

    private func logEntriesOrder(_ reason: String, limit: Int = 20) {
        guard historyDebugEnabled else { return }
        historyDebug("ORDER SNAPSHOT (\(reason)) total=\(entries.count) selected=\(selectedEntryId?.uuidString ?? "nil")")
        for (index, entry) in entries.prefix(limit).enumerated() {
            historyDebug("#\(index + 1) \(debugEntrySummary(entry))")
        }
    }

    private func persistThumbnail(_ image: NSImage, for videoFilename: String) {
        thumbnailService.persistThumbnail(image, for: videoFilename)
    }

    private func loadThumbnailImage(for videoFilename: String) -> NSImage? {
        thumbnailService.loadThumbnailImage(for: videoFilename)
    }

    private func deleteVideoAssets(for videoFilename: String) {
        thumbnailService.invalidate(videoFilename: videoFilename)
        storage.deleteVideoAssets(for: videoFilename)
    }

    private func parseTranscriptLanguageCode(for videoFilename: String) -> String? {
        transcriptService.parseTranscriptLanguageCode(for: videoFilename)
    }

    private func loadTranscriptText(for videoFilename: String) -> String? {
        transcriptService.loadTranscriptText(for: videoFilename)
    }

    private func copyTranscriptForSelectedVideoEntry() {
        guard let selectedEntryId,
              let selectedEntry = entries.first(where: { $0.id == selectedEntryId }) else { return }
        let videoFilename = selectedEntry.videoFilename
        guard let transcript = loadTranscriptText(for: videoFilename) else {
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(transcript, forType: .string)
        didCopyTranscript = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            didCopyTranscript = false
        }
    }
    
    private func parseCanonicalEntryFilename(_ filename: String) -> (uuid: UUID, timestamp: Date)? {
        entryRepository.parseCanonicalEntryFilename(filename)
    }

    private func isEntryNewer(_ lhs: HumanEntry, than rhs: HumanEntry) -> Bool {
        entryRepository.isEntryNewer(lhs, than: rhs)
    }
    
    private func saveTranscriptEdits() {
        guard let selectedEntryId,
              let entry = entries.first(where: { $0.id == selectedEntryId }) else { return }

        let videoFilename = entry.videoFilename
        let languageCode = entry.languageCode ?? parseTranscriptLanguageCode(for: videoFilename) ?? targetLanguageCode
        transcriptService.saveTranscript(text: transcriptEditorText, languageCode: languageCode, for: videoFilename)

        let tokenize: (String) -> Set<String> = { text in
            Set(text.components(separatedBy: .init(charactersIn: " \t\n.,!?;:\"'()[]{}")).filter { $0.count >= 2 })
        }
        let oldTokens = tokenize(transcriptEditorOriginal)
        let newTokens = tokenize(transcriptEditorText)
        var vocabSet = Set(UserDefaults.standard.stringArray(forKey: "customVocabulary") ?? [])
        for word in newTokens.subtracting(oldTokens) { vocabSet.insert(word) }
        UserDefaults.standard.set(Array(vocabSet), forKey: "customVocabulary")

        transcriptEditorOriginal = transcriptEditorText
    }

    // Load existing video entries (filter out text-only .md files without a paired .mov)
    private func loadExistingEntries() {
        vm.loadExistingEntries()
        logEntriesOrder("loadExistingEntries")
    }

    private var todayEntries: [HumanEntry] {
        let calendar = Calendar.current
        return entries.filter { entry in
            guard let parsed = parseCanonicalEntryFilename(entry.filename) else { return false }
            return calendar.isDateInToday(parsed.timestamp)
        }
    }

    private var todayEntry: HumanEntry? {
        let calendar = Calendar.current
        return entries.first { entry in
            guard let parsed = parseCanonicalEntryFilename(entry.filename) else { return false }
            return calendar.isDateInToday(parsed.timestamp)
        }
    }

    @ViewBuilder
    private var dashboardView: some View {
        let textPrimary = colorScheme == .light
            ? Color(red: 0.20, green: 0.20, blue: 0.20)
            : Color(red: 0.9, green: 0.9, blue: 0.9)

        let todays = todayEntries
        if !todays.isEmpty {
            let idx = min(dashboardEntryIndex, todays.count - 1)
            let entry = todays[idx]
            VStack(spacing: 20) {
                Text(Date(), format: .dateTime.weekday(.wide).month(.wide).day().year())
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(textPrimary.opacity(0.35))
                    .textCase(.uppercase)
                    .tracking(1.2)

                HStack(spacing: 12) {
                    if todays.count > 1 {
                        Button(action: {
                            dashboardEntryIndex = (idx - 1 + todays.count) % todays.count
                        }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(textPrimary.opacity(0.4))
                                .frame(width: 26, height: 26)
                                .overlay(Circle().stroke(textPrimary.opacity(0.25), lineWidth: 1))
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
                    }

                    if let thumbnail = loadThumbnailImage(for: entry.videoFilename) {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 240, height: 135)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay {
                                ZStack {
                                    if isHoveringDashboardThumbnail {
                                        Color.black.opacity(0.15)
                                    }
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 22))
                                        .foregroundColor(.white.opacity(isHoveringDashboardThumbnail ? 0.95 : 0.45))
                                        .shadow(radius: 3)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .onTapGesture {
                                selectedEntryId = entry.id
                                loadEntry(entry: entry)
                            }
                            .onHover { h in
                                isHoveringDashboardThumbnail = h
                                if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                            }
                    }

                    if todays.count > 1 {
                        Button(action: {
                            dashboardEntryIndex = (idx + 1) % todays.count
                        }) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(textPrimary.opacity(0.4))
                                .frame(width: 26, height: 26)
                                .overlay(Circle().stroke(textPrimary.opacity(0.25), lineWidth: 1))
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
                    }
                }

                VStack(spacing: 6) {
                    Text(todays.count > 1 ? "Video \(idx + 1) of \(todays.count) recorded today." : "You've already recorded today's video.")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(textPrimary)
                    Text("To record another, tap the camera icon below.")
                        .font(.system(size: 13))
                        .foregroundColor(textPrimary.opacity(0.6))
                }
            }
        } else {
            VStack(spacing: 8) {
                Text("Record your video for today.")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(textPrimary)
                Text("Tap the camera icon below to get started.")
                    .font(.system(size: 13))
                    .foregroundColor(textPrimary.opacity(0.6))
            }
        }
    }

    @ViewBuilder
    private func mainContentArea(navHeight: CGFloat) -> some View {
        if let videoURL = currentVideoURL {
            if videoAnalysisService.result != nil || videoAnalysisService.isRunning || videoAnalysisService.phase.isActive {
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        VStack(spacing: 0) {
                            let videoW = max(280, geo.size.width / 3)
                            let videoH = videoW * 9 / 16
                            VideoPlayerView(
                                videoURL: videoURL,
                                isPlaybackSuspended: isPreparingVideoRecording || showingVideoRecording
                            )
                                .id(videoURL.path)
                                .frame(width: videoW, height: videoH)

                            if selectedVideoHasTranscript && !transcriptEditorText.isEmpty {
                                inlineTranscriptEditor
                                    .frame(width: videoW)
                                    .padding(.top, 8)
                            }

                            if videoAnalysisService.phase == .done,
                               videoAnalysisService.correctedAudioURL != nil {
                                correctedAudioBox
                                    .frame(width: videoW)
                                    .padding(.top, 8)
                            }

                            Spacer()
                        }
                        .frame(width: max(280, geo.size.width / 3))
                        .frame(maxHeight: .infinity)

                        Divider()

                        analysisTabsView
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, navHeight)
            } else {
                GeometryReader { geo in
                    let videoW = min(geo.size.width, geo.size.height * 16 / 9)
                    let videoH = videoW * 9 / 16
                    VideoPlayerView(
                        videoURL: videoURL,
                        isPlaybackSuspended: isPreparingVideoRecording || showingVideoRecording
                    )
                        .id(videoURL.path)
                        .frame(width: videoW, height: videoH)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, navHeight)
            }
        } else if showingHistoryPage {
            historyPageView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, navHeight)
        } else {
            dashboardView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, navHeight)
        }
    }

    private func entriesByDay(in month: Date) -> [Int: [HumanEntry]] {
        let cal = Calendar.current
        let monthComps = cal.dateComponents([.year, .month], from: month)
        var result: [Int: [HumanEntry]] = [:]
        for entry in entries {
            guard let (_, timestamp) = parseCanonicalEntryFilename(entry.filename) else { continue }
            let comps = cal.dateComponents([.year, .month, .day], from: timestamp)
            guard comps.year == monthComps.year, comps.month == monthComps.month,
                  let day = comps.day else { continue }
            result[day, default: []].append(entry)
        }
        return result
    }

    @ViewBuilder
    private var historyPageView: some View {
        let textPrimary = colorScheme == .light
            ? Color(red: 0.20, green: 0.20, blue: 0.20)
            : Color(red: 0.9, green: 0.9, blue: 0.9)
        let emptyCell = colorScheme == .light ? Color.gray.opacity(0.08) : Color.gray.opacity(0.15)
        let filledCell = Color.green.opacity(0.55)
        let cal = Calendar.current
        let isCurrMonth = cal.isDate(visibleMonth, equalTo: Date(), toGranularity: .month)
        let dayEntries = entriesByDay(in: visibleMonth)
        let monthComps = cal.dateComponents([.year, .month], from: visibleMonth)
        let firstDay = cal.date(from: monthComps) ?? visibleMonth
        let daysInMonth = cal.range(of: .day, in: .month, for: visibleMonth)?.count ?? 30
        let rawFirstWeekday = cal.component(.weekday, from: firstDay)
        let firstDayOffset = (rawFirstWeekday - cal.firstWeekday + 7) % 7
        let orderedSymbols: [String] = (0..<7).map {
            cal.veryShortWeekdaySymbols[((cal.firstWeekday - 1) + $0) % 7]
        }
        let cellSize: CGFloat = 40
        let cellSpacing: CGFloat = 8
        let columns = Array(repeating: GridItem(.fixed(cellSize), spacing: cellSpacing), count: 7)
        let totalCells = firstDayOffset + daysInMonth

        VStack(spacing: 28) {
            // Page title
            Text("HISTORY")
                .font(.system(size: 11, weight: .regular))
                .tracking(2)
                .foregroundColor(textPrimary.opacity(0.35))

            // Month / year header
            HStack(spacing: 8) {
                let currentYear = cal.component(.year, from: Date())
                let currentMonth = cal.component(.month, from: Date())
                let selectedYear = cal.component(.year, from: visibleMonth)
                let selectedMonth = cal.component(.month, from: visibleMonth)
                let years = Array((currentYear - 5)...currentYear)

                Picker("", selection: Binding(
                    get: { selectedMonth },
                    set: { newMonth in
                        var comps = cal.dateComponents([.year, .month], from: visibleMonth)
                        comps.month = newMonth
                        if let d = cal.date(from: comps) { visibleMonth = d }
                    }
                )) {
                    let maxMonth = selectedYear == currentYear ? currentMonth : 12
                    ForEach(1...maxMonth, id: \.self) { m in
                        Text(cal.monthSymbols[m - 1].uppercased())
                            .tag(m)
                    }
                }
                .labelsHidden()
                .frame(width: 120)

                Picker("", selection: Binding(
                    get: { selectedYear },
                    set: { newYear in
                        var comps = cal.dateComponents([.year, .month], from: visibleMonth)
                        comps.year = newYear
                        if let d = cal.date(from: comps) { visibleMonth = d }
                    }
                )) {
                    ForEach(years, id: \.self) { y in
                        Text(String(y)).tag(y)
                    }
                }
                .labelsHidden()
                .frame(width: 80)

                // Clamp to current month if selection went into the future
                let _ = {
                    if selectedYear == currentYear && selectedMonth > currentMonth {
                        var comps = cal.dateComponents([.year, .month], from: visibleMonth)
                        comps.month = currentMonth
                        if let d = cal.date(from: comps) {
                            DispatchQueue.main.async { visibleMonth = d }
                        }
                    }
                }()

                if !isCurrMonth {
                    Button(action: { visibleMonth = Date() }) {
                        Text("TODAY")
                            .font(.system(size: 10, weight: .regular))
                            .tracking(1.5)
                            .foregroundColor(textPrimary.opacity(0.4))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(textPrimary.opacity(0.2), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
                }
            }

            VStack(spacing: 8) {
                // Weekday initials row
                HStack(spacing: cellSpacing) {
                    ForEach(Array(orderedSymbols.enumerated()), id: \.offset) { _, sym in
                        Text(sym)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(textPrimary.opacity(0.25))
                            .frame(width: cellSize)
                    }
                }

                // Day grid
                LazyVGrid(columns: columns, spacing: cellSpacing) {
                    ForEach(0..<totalCells, id: \.self) { idx in
                        if idx < firstDayOffset {
                            Color.clear.frame(width: cellSize, height: cellSize)
                        } else {
                            let day = idx - firstDayOffset + 1
                            let hasEntry = dayEntries[day] != nil
                            let isTodayCell: Bool = {
                                var dc = cal.dateComponents([.year, .month], from: visibleMonth)
                                dc.day = day
                                return cal.date(from: dc).map { cal.isDateInToday($0) } ?? false
                            }()

                            ZStack {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(hasEntry ? filledCell : emptyCell)
                                    .frame(width: cellSize, height: cellSize)
                                    .overlay {
                                        if isTodayCell {
                                            RoundedRectangle(cornerRadius: 4)
                                                .stroke(textPrimary.opacity(0.35), lineWidth: 1)
                                        }
                                    }

                                Text("\(day)")
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundColor(
                                        hasEntry
                                        ? Color.white.opacity(0.75)
                                        : textPrimary.opacity(0.2)
                                    )
                            }
                            .contentShape(Rectangle())
                            .popover(isPresented: Binding(
                                get: { historyPickerDay == day },
                                set: { if !$0 { historyPickerDay = nil } }
                            ), arrowEdge: .bottom) {
                                let dayList = dayEntries[day] ?? []
                                VStack(alignment: .leading, spacing: 0) {
                                    ForEach(dayList) { entry in
                                        HStack(spacing: 8) {
                                            HStack(spacing: 10) {
                                                if let thumb = loadThumbnailImage(for: entry.videoFilename) {
                                                    Image(nsImage: thumb)
                                                        .resizable()
                                                        .aspectRatio(contentMode: .fill)
                                                        .frame(width: 48, height: 27)
                                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                                } else {
                                                    RoundedRectangle(cornerRadius: 4)
                                                        .fill(Color.gray.opacity(0.2))
                                                        .frame(width: 48, height: 27)
                                                }
                                                if let (_, ts) = parseCanonicalEntryFilename(entry.filename) {
                                                    Text(ts, format: .dateTime.hour().minute())
                                                        .font(.system(size: 12))
                                                        .foregroundColor(.primary)
                                                }
                                                Spacer()
                                            }
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                historyPickerDay = nil
                                                selectedEntryId = entry.id
                                                loadEntry(entry: entry)
                                                showingHistoryPage = false
                                            }

                                            Button {
                                                entryPendingDeletion = entry
                                                pendingDeletionIsLastInDay = dayList.count <= 1
                                            } label: {
                                                Image(systemName: "trash")
                                                    .font(.system(size: 11))
                                                    .foregroundColor(.secondary)
                                            }
                                            .buttonStyle(.plain)
                                            .help("Delete entry")
                                            .padding(.trailing, 4)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        if entry.id != dayList.last?.id { Divider() }
                                    }
                                }
                                .frame(minWidth: 200)
                            }
                            .onTapGesture {
                                guard hasEntry else { return }
                                historyPickerDay = (historyPickerDay == day) ? nil : day
                            }
                            .onHover { h in
                                if hasEntry { if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
                            }
                        }
                    }
                }
            }
        }
    }

    private func startVideoRecordingPreflight() {
        guard !isPreparingVideoRecording, !showingVideoRecording else {
            return
        }

        showingVideoPermissionPopover = false
        videoPermissionPopoverItems = []
        videoPermissionPopoverFallbackMessage = nil

        let preparationID = UUID()
        let manager = CameraManager()
        manager.speechLocale = Locale(identifier: targetLanguageCode)
        manager.capturePreset = videoQualityPreset(videoQuality)

        videoRecordingPreparationID = preparationID
        preparedCameraManager = manager

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isPreparingVideoRecording = true
        }

        manager.onReadyToRecord = { [weak manager] in
            guard let manager else { return }
            DispatchQueue.main.async {
                finishVideoRecordingPreflight(
                    preparationID: preparationID,
                    manager: manager,
                    presentationDelay: 0.5
                )
            }
        }

        manager.onCannotRecord = { [weak manager] in
            guard let manager else { return }
            DispatchQueue.main.async {
                guard self.videoRecordingPreparationID == preparationID else {
                    return
                }
                let payload = self.videoPermissionPopoverPayload(
                    cameraGranted: manager.permissionGranted,
                    microphoneGranted: manager.microphonePermissionGranted,
                    speechGranted: manager.speechPermissionGranted
                )
                self.videoPermissionPopoverItems = payload.items
                self.videoPermissionPopoverFallbackMessage = payload.fallbackMessage
                self.showingVideoPermissionPopover = true
                self.clearVideoRecordingPreparationState()
            }
        }

        manager.checkPermissions()
    }

    private func finishVideoRecordingPreflight(
        preparationID: UUID,
        manager: CameraManager,
        presentationDelay: TimeInterval = 0
    ) {
        let presentRecorder = {
            guard videoRecordingPreparationID == preparationID else {
                return
            }

            videoRecordingPreparationID = nil
            manager.onReadyToRecord = nil
            manager.onCannotRecord = nil
            preparedCameraManager = manager

            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                isPreparingVideoRecording = false
                showingVideoRecording = true
            }
        }

        if presentationDelay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + presentationDelay) {
                presentRecorder()
            }
        } else {
            presentRecorder()
        }
    }

    private func clearVideoRecordingPreparationState() {
        preparedCameraManager?.onReadyToRecord = nil
        preparedCameraManager?.onCannotRecord = nil
        videoRecordingPreparationID = nil
        isPreparingVideoRecording = false
        preparedCameraManager = nil
    }

    private func videoPermissionPopoverPayload(
        cameraGranted: Bool,
        microphoneGranted: Bool,
        speechGranted: Bool
    ) -> (items: [VideoPermissionPopoverItem], fallbackMessage: String?) {
        var items: [VideoPermissionPopoverItem] = []
        if !cameraGranted {
            items.append(
                VideoPermissionPopoverItem(
                    message: "Hey, we need camera permission.",
                    buttonLabel: "Open Camera Settings",
                    settingsPane: "Privacy_Camera"
                )
            )
        }
        if !microphoneGranted {
            items.append(
                VideoPermissionPopoverItem(
                    message: "Hey, we need microphone permission.",
                    buttonLabel: "Open Microphone Settings",
                    settingsPane: "Privacy_Microphone"
                )
            )
        }
        if !speechGranted {
            items.append(
                VideoPermissionPopoverItem(
                    message: "Hey, we need speech recognition permission.",
                    buttonLabel: "Open Speech Settings",
                    settingsPane: "Privacy_SpeechRecognition"
                )
            )
        }

        if items.isEmpty {
            return (
                items: [],
                fallbackMessage: "Could not prepare camera right now. Please try again."
            )
        }

        return (
            items: items,
            fallbackMessage: nil
        )
    }

    private func openVideoPermissionSettings(_ settingsPane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(settingsPane)") {
            NSWorkspace.shared.open(url)
        }
    }

    var selectedTargetLanguage: TargetLanguage {
        TargetLanguage.supported.first(where: { $0.id == targetLanguageCode })
            ?? TargetLanguage.supported[0]
    }

    var languageButtonTitle: String {
        let lang = selectedTargetLanguage
        return "\(lang.flag) \(lang.name)"
    }

    var popoverBackgroundColor: Color {
        return colorScheme == .light ? Color(NSColor.controlBackgroundColor) : Color(NSColor.darkGray)
    }
    
    var popoverTextColor: Color {
        return colorScheme == .light ? Color.primary : Color.white
    }

    private var currentEntryLanguageCode: String {
        if let selectedEntryId,
           let entry = entries.first(where: { $0.id == selectedEntryId }) {
            return entry.languageCode ?? parseTranscriptLanguageCode(for: entry.videoFilename) ?? targetLanguageCode
        }
        return targetLanguageCode
    }

    @ViewBuilder
    private var inlineTranscriptEditor: some View {
        let isDirty = transcriptEditorText != transcriptEditorOriginal
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Video transcript")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Spacer()
                if isDirty {
                    Button("Save") { saveTranscriptEdits() }
                        .font(.system(size: 11, weight: .semibold))
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)
                }
            }
            TextEditor(text: $vm.transcriptEditorText)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 80, maxHeight: 200)
                .padding(6)
                .background(Color.secondary.opacity(0.07))
                .cornerRadius(6)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.07))
        .cornerRadius(8)
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var correctedAudioBox: some View {
        let isPlaying = videoAnalysisService.correctedAudioIsPlaying
        let subtitle = videoAnalysisService.currentSubtitle
        let speeds: [Float] = [0.75, 1.0, 1.25, 1.5]

        VStack(alignment: .leading, spacing: 10) {
            Text("Corrected Audio")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            Text(subtitle ?? (isPlaying ? "…" : " "))
                .font(.system(size: 13))
                .foregroundColor(subtitle != nil ? .primary : .secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .topLeading)
                .animation(.easeInOut(duration: 0.15), value: subtitle)

            Divider()

            HStack(spacing: 0) {
                Button(action: { videoAnalysisService.toggleCorrectedPlayback() }) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)

                Button(action: { videoAnalysisService.stopCorrectedPlayback() }) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 15))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Spacer()

                HStack(spacing: 2) {
                    ForEach(speeds, id: \.self) { rate in
                        let isActive = videoAnalysisService.playbackRate == rate
                        Button(action: { videoAnalysisService.setPlaybackRate(rate) }) {
                            Text(rate == 0.75 ? "0.75×" : rate == 1.0 ? "1×" : rate == 1.25 ? "1.25×" : "1.5×")
                                .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                                .foregroundColor(isActive ? .primary : .secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(isActive ? Color.secondary.opacity(0.15) : Color.clear)
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.07))
        .cornerRadius(8)
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var analysisTabsView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 20) {
                tabHeaderButton(title: "Patterns", tab: .patterns)
                tabHeaderButton(title: "Natural", tab: .natural)
                tabHeaderButton(title: "Drill", tab: .drill)
                tabHeaderButton(title: "Pronunciation", tab: .pronunciation)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Divider()

            Group {
                switch selectedMainTab {
                case .patterns:
                    VideoAnalysisView(
                        service: videoAnalysisService,
                        colorScheme: colorScheme,
                        onDismiss: {},
                        isEmbedded: true,
                        variant: .patterns
                    )
                case .natural:
                    VideoAnalysisView(
                        service: videoAnalysisService,
                        colorScheme: colorScheme,
                        onDismiss: {},
                        isEmbedded: true,
                        variant: .natural
                    )
                case .drill:
                    VideoAnalysisView(
                        service: videoAnalysisService,
                        colorScheme: colorScheme,
                        onDismiss: {},
                        isEmbedded: true,
                        variant: .drill
                    )
                case .pronunciation:
                    PronunciationReviewView(
                        wordConfidences: currentWordConfidences ?? [],
                        colorScheme: colorScheme,
                        assessmentResult: currentAssessmentResult,
                        languageCode: currentEntryLanguageCode,
                        isEmbedded: true,
                        isRunningAssessment: isAssessingPronunciation,
                        onRunAzureAssessment: PronunciationService.shared.hasAPIKey ? { runPronunciationAssessmentForCurrentEntry() } : nil,
                        missingAzureKey: !PronunciationService.shared.hasAPIKey
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func tabHeaderButton(title: String, tab: MainTab) -> some View {
        let isActive = selectedMainTab == tab
        Button(action: { selectedMainTab = tab }) {
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                    .foregroundColor(isActive ? .primary : .secondary)
                Rectangle()
                    .fill(isActive ? Color.accentColor : Color.clear)
                    .frame(height: 2)
            }
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }


    var body: some View {
        let navHeight: CGFloat = 68
        let textColor = colorScheme == .light ? Color.gray : Color.gray.opacity(0.8)
        let textHoverColor = colorScheme == .light ? Color.black : Color.white
        let isViewingVideoEntry = currentVideoURL != nil
        
        HStack(spacing: 0) {
            // Main content
            ZStack {
                Color(colorScheme == .light ? .white : .black)
                    .ignoresSafeArea()

                mainContentArea(navHeight: navHeight)
                    
                
                VStack {
                    Spacer()
                    ZStack {
                        // Left + right as background layer — home on left, utilities on right
                        HStack {
                            HStack(spacing: 8) {
                                Button(action: {
                                    selectedEntryId = nil
                                    currentVideoURL = nil
                                    selectedVideoHasTranscript = false
                                    showingHistoryPage = false
                                }) {
                                    Image(systemName: "house")
                                        .font(.system(size: 13))
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(isHoveringHomeButton ? textHoverColor : textColor)
                                .onHover { hovering in
                                    isHoveringHomeButton = hovering
                                    if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                                }

                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        if showingHistoryPage {
                                            showingHistoryPage = false
                                        } else {
                                            selectedEntryId = nil
                                            currentVideoURL = nil
                                            selectedVideoHasTranscript = false
                                            visibleMonth = Date()
                                            showingHistoryPage = true
                                        }
                                    }
                                }) {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .font(.system(size: 13))
                                        .foregroundColor(isHoveringClock ? textHoverColor : textColor)
                                }
                                .buttonStyle(.plain)
                                .onHover { hovering in
                                    isHoveringClock = hovering
                                    if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                                }
                            }

                            Spacer()

                            HStack(spacing: 8) {
                                Button(action: {
                                    elevenLabsKeyInput = KeychainHelper.load(key: VideoAnalysisService.elevenLabsKeyKeychainKey) ?? ""
                                    azureKeyInput = KeychainHelper.load(key: PronunciationService.azureKeyKeychainKey) ?? ""
                                    let savedRegion = KeychainHelper.load(key: PronunciationService.azureRegionKeychainKey) ?? ""
                                    azureRegionInput = savedRegion.isEmpty ? "eastus" : savedRegion
                                    anthropicKeyInput = KeychainHelper.load(key: VideoAnalysisService.anthropicKeyKeychainKey) ?? ""
                                    customVocabularyWords = UserDefaults.standard.stringArray(forKey: "customVocabulary") ?? []
                                    showingSettingsPopover = true
                                }) {
                                    Image(systemName: "gearshape")
                                        .foregroundColor(isHoveringSettingsButton ? textHoverColor : textColor)
                                }
                                .buttonStyle(.plain)
                                .onHover { hovering in
                                    isHoveringSettingsButton = hovering
                                    if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                                }
                                .sheet(isPresented: $showingSettingsPopover) {
                                    VStack(spacing: 0) {
                                        HStack {
                                            Text("Settings")
                                                .font(.system(size: 18, weight: .semibold))
                                            Spacer()
                                            Button(action: { showingSettingsPopover = false }) {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.system(size: 18))
                                                    .foregroundColor(.secondary)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        .padding(.horizontal, 24)
                                        .padding(.vertical, 18)

                                        Divider()

                                        ScrollView {
                                            VStack(alignment: .leading, spacing: 24) {
                                                HStack {
                                                    VStack(alignment: .leading, spacing: 4) {
                                                        Text("Appearance")
                                                            .font(.system(size: 14, weight: .semibold))
                                                        Text("Light or dark interface.")
                                                            .font(.system(size: 12))
                                                            .foregroundColor(.secondary)
                                                    }
                                                    Spacer()
                                                    HStack(spacing: 8) {
                                                        Image(systemName: "sun.max.fill")
                                                            .font(.system(size: 13))
                                                            .foregroundColor(.secondary)
                                                        Toggle("Dark mode", isOn: Binding(
                                                            get: { colorScheme == .dark },
                                                            set: { isDark in
                                                                colorScheme = isDark ? .dark : .light
                                                                UserDefaults.standard.set(isDark ? "dark" : "light", forKey: "colorScheme")
                                                            }
                                                        ))
                                                        .toggleStyle(.switch)
                                                        .labelsHidden()
                                                        Image(systemName: "moon.fill")
                                                            .font(.system(size: 13))
                                                            .foregroundColor(.secondary)
                                                    }
                                                }

                                                Divider()

                                                VStack(alignment: .leading, spacing: 8) {
                                                    VStack(alignment: .leading, spacing: 4) {
                                                        Text("Video Quality")
                                                            .font(.system(size: 14, weight: .semibold))
                                                        Text("Lower quality reduces file size. Audio quality is unaffected.")
                                                            .font(.system(size: 12))
                                                            .foregroundColor(.secondary)
                                                    }
                                                    Picker("Video Quality", selection: $videoQuality) {
                                                        Text("High").tag("high")
                                                        Text("Medium").tag("medium")
                                                        Text("Low").tag("low")
                                                    }
                                                    .pickerStyle(.segmented)
                                                    .labelsHidden()
                                                }

                                                Divider()

                                                VStack(alignment: .leading, spacing: 8) {
                                                    VStack(alignment: .leading, spacing: 4) {
                                                        Text("Native Language")
                                                            .font(.system(size: 14, weight: .semibold))
                                                        Text("Your mother tongue. Used to explain errors in terms of L1 habits during Analyze.")
                                                            .font(.system(size: 12))
                                                            .foregroundColor(.secondary)
                                                    }
                                                    Picker("Native Language", selection: $nativeLanguage) {
                                                        ForEach(["Afrikaans","Albanian","Arabic","Armenian","Azerbaijani","Basque","Belarusian","Bengali","Bosnian","Bulgarian","Catalan","Chinese (Simplified)","Chinese (Traditional)","Croatian","Czech","Danish","Dutch","English","Estonian","Finnish","French","Galician","Georgian","German","Greek","Gujarati","Hebrew","Hindi","Hungarian","Icelandic","Indonesian","Irish","Italian","Japanese","Kannada","Kazakh","Korean","Latvian","Lithuanian","Macedonian","Malay","Maltese","Marathi","Mongolian","Norwegian","Persian","Polish","Portuguese","Punjabi","Romanian","Russian","Serbian","Slovak","Slovenian","Spanish","Swahili","Swedish","Tamil","Telugu","Thai","Turkish","Ukrainian","Urdu","Uzbek","Vietnamese","Welsh"], id: \.self) { lang in
                                                            Text(lang).tag(lang)
                                                        }
                                                    }
                                                    .pickerStyle(.menu)
                                                    .labelsHidden()
                                                }

                                                Divider()

                                                Text("API Keys are stored securely in your macOS Keychain.")
                                                    .font(.system(size: 13))
                                                    .foregroundColor(.secondary)

                                                VStack(alignment: .leading, spacing: 8) {
                                                    Text("ElevenLabs")
                                                        .font(.system(size: 14, weight: .semibold))
                                                    Text("High-quality speech-to-text used during Analyze.")
                                                        .font(.system(size: 12))
                                                        .foregroundColor(.secondary)
                                                    SecureField("API Key", text: $vm.elevenLabsKeyInput)
                                                        .textFieldStyle(.roundedBorder)
                                                }

                                                Divider()

                                                VStack(alignment: .leading, spacing: 8) {
                                                    Text("Azure Speech")
                                                        .font(.system(size: 14, weight: .semibold))
                                                    Text("Used for pronunciation assessment and text-to-speech during Analyze.")
                                                        .font(.system(size: 12))
                                                        .foregroundColor(.secondary)
                                                    SecureField("API Key", text: $vm.azureKeyInput)
                                                        .textFieldStyle(.roundedBorder)
                                                    Picker("Region", selection: $vm.azureRegionInput) {
                                                        Group {
                                                            Text("East US (eastus)").tag("eastus")
                                                            Text("East US 2 (eastus2)").tag("eastus2")
                                                            Text("West US (westus)").tag("westus")
                                                            Text("West US 2 (westus2)").tag("westus2")
                                                            Text("Central US (centralus)").tag("centralus")
                                                            Text("North Central US (northcentralus)").tag("northcentralus")
                                                            Text("South Central US (southcentralus)").tag("southcentralus")
                                                            Text("West Central US (westcentralus)").tag("westcentralus")
                                                        }
                                                        Group {
                                                            Text("North Europe (northeurope)").tag("northeurope")
                                                            Text("West Europe (westeurope)").tag("westeurope")
                                                            Text("UK South (uksouth)").tag("uksouth")
                                                            Text("France Central (francecentral)").tag("francecentral")
                                                            Text("Germany West Central (germanywestcentral)").tag("germanywestcentral")
                                                            Text("Switzerland North (switzerlandnorth)").tag("switzerlandnorth")
                                                            Text("Norway East (norwayeast)").tag("norwayeast")
                                                            Text("Sweden Central (swedencentral)").tag("swedencentral")
                                                        }
                                                        Group {
                                                            Text("East Asia (eastasia)").tag("eastasia")
                                                            Text("Southeast Asia (southeastasia)").tag("southeastasia")
                                                            Text("Japan East (japaneast)").tag("japaneast")
                                                            Text("Japan West (japanwest)").tag("japanwest")
                                                            Text("Korea Central (koreacentral)").tag("koreacentral")
                                                            Text("Australia East (australiaeast)").tag("australiaeast")
                                                            Text("Central India (centralindia)").tag("centralindia")
                                                            Text("Brazil South (brazilsouth)").tag("brazilsouth")
                                                        }
                                                    }
                                                }

                                                Divider()

                                                VStack(alignment: .leading, spacing: 8) {
                                                    Text("Anthropic")
                                                        .font(.system(size: 14, weight: .semibold))
                                                    Text("Used for Analyze (language patterns, corrections).")
                                                        .font(.system(size: 12))
                                                        .foregroundColor(.secondary)
                                                    SecureField("API Key", text: $vm.anthropicKeyInput)
                                                        .textFieldStyle(.roundedBorder)
                                                }

                                                Divider()

                                                VStack(alignment: .leading, spacing: 8) {
                                                    Text("Custom Vocabulary")
                                                        .font(.system(size: 14, weight: .semibold))
                                                    Text("Words and names saved when you correct transcripts. Sent as hints to ElevenLabs during Analyze.")
                                                        .font(.system(size: 12))
                                                        .foregroundColor(.secondary)

                                                    if customVocabularyWords.isEmpty {
                                                        Text("No words yet. Correct a transcript to add words automatically.")
                                                            .font(.system(size: 12))
                                                            .foregroundColor(.secondary)
                                                            .italic()
                                                    } else {
                                                        FlowLayout(spacing: 6) {
                                                            ForEach(customVocabularyWords, id: \.self) { word in
                                                                HStack(spacing: 4) {
                                                                    Text(word)
                                                                        .font(.system(size: 12))
                                                                    Button(action: {
                                                                        customVocabularyWords.removeAll { $0 == word }
                                                                    }) {
                                                                        Image(systemName: "xmark")
                                                                            .font(.system(size: 9, weight: .bold))
                                                                            .foregroundColor(.secondary)
                                                                    }
                                                                    .buttonStyle(.plain)
                                                                }
                                                                .padding(.horizontal, 8)
                                                                .padding(.vertical, 4)
                                                                .background(Color.secondary.opacity(0.12))
                                                                .cornerRadius(6)
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                            .padding(24)
                                        }

                                        Divider()

                                        HStack {
                                            Spacer()
                                            Button("Cancel") { showingSettingsPopover = false }
                                                .keyboardShortcut(.cancelAction)
                                            Button("Save") {
                                                if !elevenLabsKeyInput.isEmpty {
                                                    _ = KeychainHelper.save(key: VideoAnalysisService.elevenLabsKeyKeychainKey, value: elevenLabsKeyInput)
                                                } else {
                                                    _ = KeychainHelper.delete(key: VideoAnalysisService.elevenLabsKeyKeychainKey)
                                                }
                                                if !azureKeyInput.isEmpty {
                                                    _ = KeychainHelper.save(key: PronunciationService.azureKeyKeychainKey, value: azureKeyInput)
                                                    _ = KeychainHelper.save(key: PronunciationService.azureRegionKeychainKey, value: azureRegionInput)
                                                } else {
                                                    _ = KeychainHelper.delete(key: PronunciationService.azureKeyKeychainKey)
                                                    _ = KeychainHelper.delete(key: PronunciationService.azureRegionKeychainKey)
                                                }
                                                if !anthropicKeyInput.isEmpty {
                                                    _ = KeychainHelper.save(key: VideoAnalysisService.anthropicKeyKeychainKey, value: anthropicKeyInput)
                                                } else {
                                                    _ = KeychainHelper.delete(key: VideoAnalysisService.anthropicKeyKeychainKey)
                                                }
                                                UserDefaults.standard.set(customVocabularyWords, forKey: "customVocabulary")
                                                showingSettingsPopover = false
                                            }
                                            .keyboardShortcut(.defaultAction)
                                            .buttonStyle(.borderedProminent)
                                        }
                                        .padding(.horizontal, 24)
                                        .padding(.vertical, 16)
                                    }
                                    .frame(width: 680, height: 680)
                                }

                            }
                        }
                        .padding(8)

                        // Center cluster — flag + camera + analyze, perfectly centered via ZStack
                        HStack(spacing: 8) {
                            Button(selectedTargetLanguage.flag) {
                                showingLanguagePicker = true
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 16))
                            .onHover { hovering in
                                isHoveringLanguageButton = hovering
                                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                            }
                            .popover(isPresented: $showingLanguagePicker, attachmentAnchor: .point(UnitPoint(x: 0.5, y: 0)), arrowEdge: .top) {
                                VStack(spacing: 0) {
                                    Text("Recording Language")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 12)
                                        .padding(.top, 8)
                                        .padding(.bottom, 4)
                                    Divider()
                                    ScrollView {
                                        VStack(spacing: 0) {
                                            ForEach(TargetLanguage.supported) { language in
                                                Button(action: {
                                                    targetLanguageCode = language.id
                                                    showingLanguagePicker = false
                                                }) {
                                                    HStack {
                                                        Text("\(language.flag) \(language.name)")
                                                            .font(.system(size: 13))
                                                        Spacer()
                                                        if language.id == targetLanguageCode {
                                                            Image(systemName: "checkmark")
                                                                .font(.system(size: 11, weight: .semibold))
                                                        }
                                                    }
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                                    .padding(.horizontal, 12)
                                                    .padding(.vertical, 6)
                                                    .contentShape(Rectangle())
                                                }
                                                .buttonStyle(.plain)
                                                .foregroundColor(popoverTextColor)
                                                .onHover { hovering in
                                                    if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                                                }
                                            }
                                        }
                                    }
                                    .frame(maxHeight: 300)
                                }
                                .frame(width: 200)
                                .background(popoverBackgroundColor)
                            }

                            Text("•").foregroundColor(.gray)

                            Button(action: {
                                guard !isPreparingVideoRecording else { return }
                                startVideoRecordingPreflight()
                            }) {
                                Group {
                                    if isPreparingVideoRecording {
                                        ProgressView()
                                            .controlSize(.small)
                                            .tint(isHoveringVideoButton ? textHoverColor : textColor)
                                    } else {
                                        Image(systemName: "video.fill")
                                            .foregroundColor(isHoveringVideoButton ? textHoverColor : textColor)
                                    }
                                }
                                .frame(width: 14, height: 14)
                            }
                            .buttonStyle(.plain)
                            .onHover { hovering in
                                isHoveringVideoButton = hovering
                                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                            }
                            .popover(
                                isPresented: $showingVideoPermissionPopover,
                                attachmentAnchor: .point(UnitPoint(x: 0.5, y: 0.0)),
                                arrowEdge: .top
                            ) {
                                VStack(spacing: 0) {
                                    if let fallbackMessage = videoPermissionPopoverFallbackMessage {
                                        Text(fallbackMessage)
                                            .font(.system(size: 14))
                                            .foregroundColor(popoverTextColor)
                                            .lineLimit(nil)
                                            .multilineTextAlignment(.leading)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                    }
                                    ForEach(videoPermissionPopoverItems) { item in
                                        if item.id != videoPermissionPopoverItems.first?.id || videoPermissionPopoverFallbackMessage != nil {
                                            Divider()
                                        }
                                        Button(action: {
                                            showingVideoPermissionPopover = false
                                            openVideoPermissionSettings(item.settingsPane)
                                        }) {
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(item.message)
                                                    .font(.system(size: 14))
                                                    .lineLimit(nil)
                                                    .multilineTextAlignment(.leading)
                                                    .fixedSize(horizontal: false, vertical: true)
                                                Text(item.buttonLabel)
                                                    .font(.system(size: 12))
                                                    .opacity(0.85)
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundColor(popoverTextColor)
                                        .onHover { hovering in
                                            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                                        }
                                    }
                                }
                                .frame(minWidth: 300, idealWidth: 320, maxWidth: 360)
                                .background(colorScheme == .light ? Color.white : Color.black)
                            }

                            if isViewingVideoEntry && videoAnalysisService.hasAllKeys
                                && videoAnalysisService.result == nil
                                && !videoAnalysisService.isRunning {
                                Text("•").foregroundColor(.gray)
                                Button(action: { startVideoAnalysis() }) {
                                    Text("Analyze").font(.system(size: 13))
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(isHoveringAnalyzeButton ? textHoverColor : textColor)
                                .onHover { hovering in
                                    isHoveringAnalyzeButton = hovering
                                    if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                                }
                            }


                        }
                        .padding(8)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                    .background(Color(colorScheme == .light ? .white : .black))
                }
            }
        }
        .overlay {
            if showingOnboarding {
                OnboardingView(isPresented: $showingOnboarding) {
                    hasCompletedOnboarding = true
                }
                .zIndex(20)
            }
        }
        .overlay {
            if showingVideoRecording {
                VideoRecordingView(
                    isPresented: $showingVideoRecording,
                    cameraManager: preparedCameraManager
                ) { videoURL, transcript, wordConfidences in
                    // Save the video and create entry
                    saveVideoEntry(from: videoURL, transcript: transcript, wordConfidences: wordConfidences)
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        showingVideoRecording = false
                    }
                }
                .zIndex(10)
            }
        }
        .frame(minWidth: 1100, minHeight: 600)
        .animation(.easeInOut(duration: 0.2), value: showingHistoryPage)
        .preferredColorScheme(colorScheme)
        .onAppear {
            loadExistingEntries()
            if !hasCompletedOnboarding {
                showingOnboarding = true
            }
        }
        .onChange(of: showingVideoRecording) { _, isShowing in
            if !isShowing {
                clearVideoRecordingPreparationState()
            }
        }
        .onChange(of: videoAnalysisService.phase) { _, newPhase in
            guard case .done = newPhase,
                  let selectedEntryId,
                  let entry = entries.first(where: { $0.id == selectedEntryId }) else { return }
            let videoFilename = entry.videoFilename

            selectedVideoHasTranscript = fileManager.fileExists(atPath: getVideoTranscriptURL(for: videoFilename).path)
            currentAssessmentResult = loadAssessmentResult(for: videoFilename)
            selectedMainTab = .patterns

            let reloadedTranscript = loadTranscriptText(for: videoFilename) ?? ""
            transcriptEditorText = reloadedTranscript
            transcriptEditorOriginal = reloadedTranscript
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willEnterFullScreenNotification)) { _ in
            isFullscreen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willExitFullScreenNotification)) { _ in
            isFullscreen = false
        }
        .alert("Delete this entry?", isPresented: Binding(
            get: { entryPendingDeletion != nil },
            set: { if !$0 { entryPendingDeletion = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let entry = entryPendingDeletion {
                    deleteEntry(entry: entry)
                    if pendingDeletionIsLastInDay { historyPickerDay = nil }
                    entryPendingDeletion = nil
                }
            }
            Button("Cancel", role: .cancel) {
                entryPendingDeletion = nil
            }
        } message: {
            Text("This will permanently delete the recording and all associated files.")
        }
    }
    
    private func loadEntry(entry: HumanEntry) {
        let videoFilename = entry.videoFilename
        let videoURL = getVideoURL(for: videoFilename)
        let thumbnailURL = getVideoThumbnailURL(for: videoFilename)
        let transcriptURL = getVideoTranscriptURL(for: videoFilename)
        historyDebug("LOAD VIDEO \(debugEntrySummary(entry)) resolvedVideoPath=\(videoURL.path) videoExists=\(fileManager.fileExists(atPath: videoURL.path)) thumbnailPath=\(thumbnailURL.path) thumbnailExists=\(fileManager.fileExists(atPath: thumbnailURL.path))")
        didCopyTranscript = false
        currentAssessmentResult = loadAssessmentResult(for: videoFilename)
        isAssessingPronunciation = false
        selectedVideoHasTranscript = fileManager.fileExists(atPath: transcriptURL.path)
        let loadedTranscript = loadTranscriptText(for: videoFilename) ?? ""
        transcriptEditorText = loadedTranscript
        transcriptEditorOriginal = loadedTranscript
        currentWordConfidences = loadWordConfidences(for: videoFilename)
        selectedMainTab = .patterns
        loadCachedAnalysisIfAvailable(for: videoFilename)
        if fileManager.fileExists(atPath: videoURL.path) {
            currentVideoURL = videoURL
            print("Successfully loaded video entry: \(videoFilename)")
        } else {
            currentVideoURL = nil
            print("Video file missing for entry: \(videoFilename)")
        }
    }

    private func saveVideoEntry(from tempURL: URL, transcript: String?, wordConfidences: [WordConfidence] = []) {
        let recordingLanguageCode = targetLanguageCode
        let videoEntry = HumanEntry.createVideoEntry(languageCode: recordingLanguageCode)
        let videoFilename = videoEntry.videoFilename

        do {
            let videoEntryDirectory = try ensureVideoEntryDirectoryExists(for: videoFilename)
            let videoDestURL = videoEntryDirectory.appendingPathComponent(videoFilename)
            let transcriptURL = videoEntryDirectory.appendingPathComponent("transcript.md")
            let cleanedTranscript = transcript?.trimmingCharacters(in: .whitespacesAndNewlines)

            if fileManager.fileExists(atPath: videoDestURL.path) {
                try fileManager.removeItem(at: videoDestURL)
            }
            try fileManager.copyItem(at: tempURL, to: videoDestURL)
            print("Successfully saved video: \(videoFilename)")

            if let thumbnailImage = generateVideoThumbnail(from: videoDestURL) {
                persistThumbnail(thumbnailImage, for: videoFilename)
                print("Successfully saved thumbnail for video: \(videoFilename)")
            } else {
                print("Could not generate thumbnail for video: \(videoFilename)")
            }

            // Write the .md metadata sibling so loadExistingEntries can enumerate this entry.
            let metadataURL = getDocumentsDirectory().appendingPathComponent(videoEntry.filename)
            try "Video Entry".write(to: metadataURL, atomically: true, encoding: .utf8)

            if let cleanedTranscript, !cleanedTranscript.isEmpty {
                let transcriptWithFrontMatter = "---\nlanguage: \(recordingLanguageCode)\n---\n\n\(cleanedTranscript)"
                try transcriptWithFrontMatter.write(to: transcriptURL, atomically: true, encoding: .utf8)
                print("Successfully saved transcript for video: \(videoFilename)")
            } else if fileManager.fileExists(atPath: transcriptURL.path) {
                try fileManager.removeItem(at: transcriptURL)
            }

            let selectNewVideoEntry = {
                self.entries.insert(videoEntry, at: 0)
                self.entries.sort { self.isEntryNewer($0, than: $1) }
                self.dashboardEntryIndex = 0
                guard let insertedEntry = self.entries.first(where: { $0.id == videoEntry.id }) else {
                    print("Could not find saved video entry in entries array")
                    return
                }
                self.selectedEntryId = insertedEntry.id
                self.currentVideoURL = videoDestURL
                self.didCopyTranscript = false
                self.selectedVideoHasTranscript = (cleanedTranscript?.isEmpty == false)
                self.currentWordConfidences = self.loadWordConfidences(for: videoFilename)
                self.currentAssessmentResult = nil
                self.selectedMainTab = .patterns
                self.loadCachedAnalysisIfAvailable(for: videoFilename)
                print("Successfully loaded new video entry: \(videoFilename)")
                self.historyDebug("VIDEO SAVE selected \(self.debugEntrySummary(insertedEntry)) videoPath=\(videoDestURL.path)")
                self.logEntriesOrder("saveVideoEntry")

            }

            if Thread.isMainThread {
                selectNewVideoEntry()
            } else {
                DispatchQueue.main.async {
                    selectNewVideoEntry()
                }
            }
            print("Successfully created video entry")
        } catch {
            print("Error saving video entry: \(error)")
        }
    }

    private func videoQualityPreset(_ quality: String) -> AVCaptureSession.Preset {
        switch quality {
        case "medium": return .hd1280x720
        case "low":    return .medium
        default:       return .high
        }
    }

    private func deleteEntry(entry: HumanEntry) {
        let documentsDirectory = getDocumentsDirectory()
        let fileURL = documentsDirectory.appendingPathComponent(entry.filename)

        do {
            try fileManager.removeItem(at: fileURL)
            print("Successfully deleted file: \(entry.filename)")

            deleteVideoAssets(for: entry.videoFilename)
            print("Successfully deleted video assets: \(entry.videoFilename)")

            if let index = entries.firstIndex(where: { $0.id == entry.id }) {
                entries.remove(at: index)
                historyDebug("DELETE ENTRY removed \(debugEntrySummary(entry))")
                logEntriesOrder("deleteEntry")

                if selectedEntryId == entry.id {
                    if let firstEntry = entries.first {
                        selectedEntryId = firstEntry.id
                        loadEntry(entry: firstEntry)
                    } else {
                        selectedEntryId = nil
                        currentVideoURL = nil
                        selectedVideoHasTranscript = false
                        currentWordConfidences = nil
                        currentAssessmentResult = nil
                    }
                }
            }
        } catch {
            print("Error deleting file: \(error)")
        }
    }
}

#Preview {
    ContentView()
}

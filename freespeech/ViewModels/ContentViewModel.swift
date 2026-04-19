// Swift 5.0
//
//  ContentViewModel.swift
//

import Foundation
import Combine

@MainActor
final class ContentViewModel: ObservableObject {
    // MARK: - Entry data state

    @Published var entries: [HumanEntry] = []
    @Published var selectedEntryId: UUID? = nil
    @Published var currentVideoURL: URL? = nil
    @Published var selectedVideoHasTranscript: Bool = false

    // MARK: - Analysis / transcript state

    @Published var currentWordConfidences: [WordConfidence]? = nil
    @Published var currentAssessmentResult: PronunciationAssessmentResult? = nil
    @Published var isAssessingPronunciation: Bool = false
    @Published var transcriptEditorText: String = ""
    @Published var transcriptEditorOriginal: String = ""
    @Published var customVocabularyWords: [String] = []

    // MARK: - API key inputs (bound to settings popover)

    @Published var elevenLabsKeyInput: String = ""
    @Published var azureKeyInput: String = ""
    @Published var azureRegionInput: String = "eastus"
    @Published var anthropicKeyInput: String = ""

    // MARK: - Video recording preflight

    @Published var preparedCameraManager: CameraManager? = nil
    @Published var videoRecordingPreparationID: UUID? = nil
    @Published var isPreparingVideoRecording: Bool = false
    @Published var videoPermissionPopoverItems: [VideoPermissionPopoverItem] = []
    @Published var videoPermissionPopoverFallbackMessage: String? = nil

    // MARK: - Dependencies

    private let repository = EntryRepository.shared

    init() {}

    // MARK: - Entry lifecycle

    /// Loads all canonical video entries from disk into `entries` and resets selection.
    func loadExistingEntries() {
        entries = repository.loadExistingEntries()
        selectedEntryId = nil
        currentVideoURL = nil
        selectedVideoHasTranscript = false
    }
}

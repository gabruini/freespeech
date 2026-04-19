// Swift 5.0
//
//  OnboardingView.swift
//

import SwiftUI

struct OnboardingView: View {
    @Binding var isPresented: Bool
    let onComplete: () -> Void

    @AppStorage("nativeLanguage") private var nativeLanguage: String = "English"
    @State private var step: Int = 0
    @State private var selectedLanguage: TargetLanguage? = nil

    @State private var anthropicKey: String = ""
    @State private var azureKey: String = ""
    @State private var azureRegion: String = ""
    @State private var elevenLabsKey: String = ""

    private var backgroundColor: Color { Color(NSColor.windowBackgroundColor) }
    private var primaryText: Color { Color(NSColor.labelColor) }
    private var secondaryText: Color { Color(NSColor.secondaryLabelColor) }

    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                if step == 0 {
                    languageStep
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                } else {
                    apiKeysStep
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                }

                Spacer()

                progressDots
                    .padding(.bottom, 32)
            }
        }
    }

    // MARK: - Step 1: Language

    private var languageStep: some View {
        VStack(spacing: 0) {
            Text("What's your native language?")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(primaryText)
                .multilineTextAlignment(.center)
                .padding(.bottom, 8)

            Text("This helps the app tailor its feedback to you.")
                .font(.system(size: 13))
                .foregroundColor(secondaryText)
                .multilineTextAlignment(.center)
                .padding(.bottom, 28)

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(TargetLanguage.supported) { lang in
                        languageRow(lang)
                    }
                }
            }
            .frame(maxHeight: 320)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Button(action: advanceToApiKeys) {
                Text("Continue")
                    .font(.system(size: 14, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedLanguage == nil)
            .padding(.top, 20)
        }
        .frame(width: 400)
    }

    private func languageRow(_ lang: TargetLanguage) -> some View {
        let isSelected = selectedLanguage?.id == lang.id
        return Button(action: { selectedLanguage = lang }) {
            HStack(spacing: 12) {
                Text(lang.flag)
                    .font(.system(size: 18))
                Text(lang.name)
                    .font(.system(size: 14))
                    .foregroundColor(primaryText)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 2: API Keys

    private var apiKeysStep: some View {
        VStack(spacing: 0) {
            Text("Set up AI features")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(primaryText)
                .multilineTextAlignment(.center)
                .padding(.bottom, 8)

            Text("Required to transcribe and analyze your videos.")
                .font(.system(size: 13))
                .foregroundColor(secondaryText)
                .multilineTextAlignment(.center)
                .padding(.bottom, 16)

            // Warning banner
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.orange)
                Text("Without these keys, video analysis won't be available. You can add them later in Settings.")
                    .font(.system(size: 12))
                    .foregroundColor(primaryText.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.orange.opacity(0.1))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.25), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.bottom, 20)

            ScrollView {
                VStack(spacing: 12) {
                    apiProviderCard(
                        logo: "anthropic",
                        name: "Anthropic",
                        description: "AI language coaching and video analysis",
                        fields: [
                            ("API Key", "Your Anthropic key", $anthropicKey, true)
                        ]
                    )

                    apiProviderCard(
                        logo: "azure",
                        name: "Microsoft Azure",
                        description: "Speech transcription and pronunciation scoring",
                        fields: [
                            ("API Key", "Your Azure Speech key", $azureKey, true)
                        ]
                    ) {
                        azureRegionPicker
                    }

                    apiProviderCard(
                        logo: "elevenlabs",
                        name: "ElevenLabs",
                        description: "High-accuracy audio transcription",
                        fields: [
                            ("API Key", "Your ElevenLabs key", $elevenLabsKey, true)
                        ]
                    )
                }
                .padding(.bottom, 4)
            }
            .frame(maxHeight: 320)
            .padding(.bottom, 20)

            Button(action: saveAndFinish) {
                Text("Save & Get Started")
                    .font(.system(size: 14, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!allKeysProvided)

            Button(action: finish) {
                Text("Skip for now")
                    .font(.system(size: 13))
                    .foregroundColor(secondaryText)
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
            .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
        }
        .frame(width: 420)
    }

    private func apiProviderCard<Extra: View>(
        logo: String,
        name: String,
        description: String,
        fields: [(String, String, Binding<String>, Bool)],
        @ViewBuilder extraContent: () -> Extra = { EmptyView() }
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                providerIcon(logo)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(primaryText)
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundColor(secondaryText)
                }
            }

            VStack(spacing: 8) {
                ForEach(Array(fields.enumerated()), id: \.offset) { _, field in
                    keyField(label: field.0, placeholder: field.1, text: field.2, isSecure: field.3)
                }
                extraContent()
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 1))
    }

    @ViewBuilder
    private func providerIcon(_ name: String) -> some View {
        let assetName = "\(name)-logo"
        Image(assetName)
            .resizable()
            .scaledToFit()
            .frame(width: 30, height: 30)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private let azureRegions: [(name: String, value: String)] = [
        ("East US", "eastus"),
        ("East US 2", "eastus2"),
        ("West US", "westus"),
        ("West US 2", "westus2"),
        ("West US 3", "westus3"),
        ("Central US", "centralus"),
        ("North Central US", "northcentralus"),
        ("South Central US", "southcentralus"),
        ("West Europe", "westeurope"),
        ("North Europe", "northeurope"),
        ("UK South", "uksouth"),
        ("France Central", "francecentral"),
        ("Germany West Central", "germanywestcentral"),
        ("Switzerland North", "switzerlandnorth"),
        ("Norway East", "norwayeast"),
        ("Australia East", "australiaeast"),
        ("Southeast Asia", "southeastasia"),
        ("East Asia", "eastasia"),
        ("Japan East", "japaneast"),
        ("Japan West", "japanwest"),
        ("Korea Central", "koreacentral"),
        ("Central India", "centralindia"),
        ("Canada Central", "canadacentral"),
        ("Brazil South", "brazilsouth"),
    ]

    private var azureRegionPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Region")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(secondaryText)
            Picker("", selection: $azureRegion) {
                Text("Select a region…").tag("")
                ForEach(azureRegions, id: \.value) { region in
                    Text("\(region.name) (\(region.value))").tag(region.value)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func keyField(label: String, placeholder: String, text: Binding<String>, isSecure: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(secondaryText)
            if isSecure {
                SecureField(placeholder, text: text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
            } else {
                TextField(placeholder, text: text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
            }
        }
    }

    // MARK: - Progress

    private var progressDots: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(step == 0 ? primaryText : secondaryText.opacity(0.4))
                .frame(width: 6, height: 6)
            Circle()
                .fill(step == 1 ? primaryText : secondaryText.opacity(0.4))
                .frame(width: 6, height: 6)
        }
    }

    private var allKeysProvided: Bool {
        !anthropicKey.trimmingCharacters(in: .whitespaces).isEmpty &&
        !azureKey.trimmingCharacters(in: .whitespaces).isEmpty &&
        !azureRegion.trimmingCharacters(in: .whitespaces).isEmpty &&
        !elevenLabsKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Actions

    private func advanceToApiKeys() {
        guard let lang = selectedLanguage else { return }
        nativeLanguage = lang.name
        withAnimation(.easeInOut(duration: 0.25)) {
            step = 1
        }
    }

    private func saveAndFinish() {
        if !anthropicKey.trimmingCharacters(in: .whitespaces).isEmpty {
            KeychainHelper.save(key: VideoAnalysisService.anthropicKeyKeychainKey, value: anthropicKey.trimmingCharacters(in: .whitespaces))
        }
        if !azureKey.trimmingCharacters(in: .whitespaces).isEmpty {
            KeychainHelper.save(key: PronunciationService.azureKeyKeychainKey, value: azureKey.trimmingCharacters(in: .whitespaces))
        }
        if !azureRegion.trimmingCharacters(in: .whitespaces).isEmpty {
            KeychainHelper.save(key: PronunciationService.azureRegionKeychainKey, value: azureRegion.trimmingCharacters(in: .whitespaces))
        }
        if !elevenLabsKey.trimmingCharacters(in: .whitespaces).isEmpty {
            KeychainHelper.save(key: VideoAnalysisService.elevenLabsKeyKeychainKey, value: elevenLabsKey.trimmingCharacters(in: .whitespaces))
        }
        finish()
    }

    private func finish() {
        onComplete()
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isPresented = false
        }
    }
}

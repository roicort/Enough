//
//  ContentView.swift
//  Enough!
//

import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif

struct ContentView: View {
    @StateObject private var pipeline = AnalysisPipeline()
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isFileImporterPresented = false
#if os(macOS)
    @State private var isShowingSettings = false
#endif
    @State private var isDropTargeted = false
    @State private var aiConfidenceThreshold = SharedSettings.aiConfidenceThreshold
    @AppStorage(
        SharedSettings.appLanguageCodeKey,
        store: SharedSettings.defaults
    ) private var appLanguageCode = "system"
    @State private var showVerifiedAIC2PA = SharedSettings.showVerifiedAIC2PA
    @AppStorage(
        VisualModel.preferenceKey,
        store: .standard
    ) private var visualModel = VisualModel.capcheck.rawValue

    var body: some View {
        content
#if os(macOS)
            .environment(\.locale, SharedSettings.locale(for: appLanguageCode))
#endif
            .task(id: selectedPhoto) {
                guard let selectedPhoto else { return }
                await pipeline.loadAndAnalyze(selectedPhoto)
            }
            .fileImporter(
                isPresented: $isFileImporterPresented,
                allowedContentTypes: [.image]
            ) { result in
                switch result {
                case let .success(url):
                    Task {
                        await pipeline.loadAndAnalyze(url)
                    }
                case let .failure(error):
                    pipeline.show(error: error)
                }
            }
            .onChange(of: appLanguageCode) { _, languageCode in
#if os(macOS)
                SharedSettings.setAppLanguageCode(languageCode)
#endif
            }
            .onChange(of: visualModel) {
                Task {
                    await pipeline.reanalyzeSelectedImage()
                }
            }
            .onAppear {
#if os(iOS)
                SharedSettings.setAppLanguageCode("system")
#endif
            }
    }

    @ViewBuilder
    private var content: some View {
#if os(macOS)
        analysisView
            .sheet(isPresented: $isShowingSettings) {
                SettingsView(
                    aiConfidenceThreshold: aiConfidenceThresholdBinding,
                    appLanguageCode: $appLanguageCode,
                    showVerifiedAIC2PA: showVerifiedAIC2PABinding,
                    visualModel: $visualModel
                )
            }
#else
        TabView {
            analysisView
                .tabItem {
                    Label("Analyze", systemImage: "photo")
                }

            SettingsView(
                aiConfidenceThreshold: aiConfidenceThresholdBinding,
                appLanguageCode: $appLanguageCode,
                showVerifiedAIC2PA: showVerifiedAIC2PABinding,
                visualModel: $visualModel
            )
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
#endif
    }

    private var aiConfidenceThresholdBinding: Binding<Double> {
        Binding(
            get: { aiConfidenceThreshold },
            set: { threshold in
                let clampedThreshold = min(max(threshold, 0.50), 0.95)
                aiConfidenceThreshold = clampedThreshold
                SharedSettings.setAIConfidenceThreshold(clampedThreshold)
            }
        )
    }

    private var showVerifiedAIC2PABinding: Binding<Bool> {
        Binding(
            get: { showVerifiedAIC2PA },
            set: { showVerified in
                showVerifiedAIC2PA = showVerified
                SharedSettings.setShowVerifiedAIC2PA(showVerified)
            }
        )
    }

    private var analysisView: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    dropZone

                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("Select image", systemImage: "photo.on.rectangle")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(pipeline.isAnalyzing)

                    if pipeline.isAnalyzing {
                        ProgressView("Analyzing image...")
                    }

                    if let result = pipeline.result {
                        ResultCard(
                            result: result,
                            aiConfidenceThreshold: aiConfidenceThreshold
                        )
                        NavigationLink {
                            MetadataView(sections: pipeline.metadataSections)
                        } label: {
                            Label("View metadata", systemImage: "list.bullet.rectangle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    } else if let error = pipeline.errorMessage {
                        ContentUnavailableView(
                            "Couldn’t analyze the image",
                            systemImage: "exclamationmark.triangle",
                            description: Text(error)
                        )
                    }
                }
                .padding()
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Enough!")
#if os(macOS)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .accessibilityIdentifier("openSettings")
                }
            }
#endif
        }
    }

    private var dropZone: some View {
        Group {
            if let image = pipeline.previewImage {
                image
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 320)
                    .accessibilityLabel("Selected image")
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "photo.badge.arrow.down")
                        .font(.system(size: 40))
#if os(macOS)
                    Text("Drag and drop an image here")
                        .font(.headline)
                    Text("Supported image files will be analyzed locally.")
                        .font(.footnote)
#else
                    Text("Tap to select an image")
                        .font(.headline)
                    Text("The image is processed locally on this device.")
                        .font(.footnote)
#endif
                }
                .padding()
            }
        }
        .foregroundStyle(isDropTargeted ? Color.accentColor : .secondary)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 160)
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(isDropTargeted ? Color.accentColor.opacity(0.1) : .clear)
        }
        .clipShape(.rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    isDropTargeted
                        ? Color.accentColor
                        : pipeline.previewImage == nil
                            ? Color.secondary
                            : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 2, dash: [8])
                )
        }
        .onDrop(
            of: [UTType.image, UTType.fileURL],
            isTargeted: $isDropTargeted,
            perform: loadDroppedItem
        )
        .onTapGesture {
            guard !pipeline.isAnalyzing else { return }
            isFileImporterPresented = true
        }
        .opacity(pipeline.isAnalyzing ? 0.1 : 1)
    }

    private func loadDroppedItem(from providers: [NSItemProvider]) -> Bool {
        guard !pipeline.isAnalyzing else {
            return false
        }
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.image.identifier)
                || $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }) else {
            return false
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) {
                data, error in
                Task { @MainActor in
                    if let data {
                        await pipeline.loadAndAnalyze(data)
                    } else {
                        pipeline.show(error: error ?? AnalysisError.unreadableImage)
                    }
                }
            }
        } else {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) {
                item, error in
                Task { @MainActor in
                    if let url = item as? URL {
                        await pipeline.loadAndAnalyze(url)
                    } else {
                        pipeline.show(error: error ?? AnalysisError.unreadableImage)
                    }
                }
            }
        }
        return true
    }

}

private struct C2PAStatus: View {
    let provenance: C2PAProvenance?

    var body: some View {
        switch provenance {
        case .verifiedAI:
            Label("C2PA present: AI declared", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
        case .verifiedReal:
            Label("C2PA present: digital capture declared", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
        case .unknown:
            Label("C2PA present: source type not declared", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
        case nil:
            Label("C2PA not present or unverifiable", systemImage: "xmark.seal")
                .foregroundStyle(.secondary)
        }
    }
}

private struct SettingsView: View {
    @Binding var aiConfidenceThreshold: Double
    @Binding var appLanguageCode: String
    @Binding var showVerifiedAIC2PA: Bool
    @Binding var visualModel: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Visual detection") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("AI threshold")
                            Text(
                                aiConfidenceThreshold,
                                format: .percent.precision(.fractionLength(0))
                            )
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: $aiConfidenceThreshold,
                            in: 0.50...0.95,
                            step: 0.01
                        )
                        Text(
                            "The visual verdict labels an image as AI-generated when confidence reaches this value."
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                    .listRowSeparator(.hidden)

                    Button("Reset to 65%") {
                        aiConfidenceThreshold = 0.65
                    }

                    Picker("Model", selection: $visualModel) {
                        Text("Capcheck (224 × 224) — Large, slower")
                            .tag(VisualModel.capcheck.rawValue)
                        Text("Sieve (384 × 384) — Small, fast")
                            .tag(VisualModel.sieve.rawValue)
                    }
                    Text(
                        "This selection applies only to image analysis in the app."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                Section("Language") {
#if os(macOS)
                    Picker("App language", selection: $appLanguageCode) {
                        Text("System default")
                            .tag("system")
                        Text("Spanish")
                            .tag("es")
                        Text("English")
                            .tag("en")
                    }
                    .accessibilityIdentifier("appLanguage")
                    Text("System default uses the device's preferred language.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
#else
                    Link(
                        "Open iOS Language Settings",
                        destination: URL(string: UIApplication.openSettingsURLString)!
                    )
                    Text(
                        "Choose this app's preferred language in iOS Settings."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
#endif
                }

                Section("Extension") {
                    Toggle("Show verified AI C2PA", isOn: $showVerifiedAIC2PA)
                }

                Section("Legal") {
                    Link(
                        "Enough on GitHub",
                        destination: URL(string: "https://github.com/roicort/Enough")!
                    )
                    NavigationLink {
                        OpenSourceLicensesView()
                    } label: {
                        Label(
                            "Open-source licenses",
                            systemImage: "doc.text"
                        )
                    }
                }
            }
            .formStyle(.grouped)
#if os(macOS)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
#endif
            .navigationTitle("Settings")
#if os(macOS)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
#endif
        }
#if os(macOS)
        .environment(\.locale, SharedSettings.locale(for: appLanguageCode))
#endif
#if os(macOS)
        .frame(minWidth: 440, minHeight: 480)
#endif
    }
}

private struct OpenSourceLicensesView: View {
    private let dependencies = [
        OpenSourceDependency(
            name: "C2PA Swift",
            version: "0.0.14",
            repository: "https://github.com/contentauth/c2pa-swift"
        ),
        OpenSourceDependency(
            name: "Swift ASN.1",
            version: "1.7.3",
            repository: "https://github.com/apple/swift-asn1"
        ),
        OpenSourceDependency(
            name: "Swift Certificates",
            version: "1.21.0",
            repository: "https://github.com/apple/swift-certificates"
        ),
        OpenSourceDependency(
            name: "Swift Crypto",
            version: "4.5.2",
            repository: "https://github.com/apple/swift-crypto"
        )
    ]

    var body: some View {
        List(dependencies) { dependency in
            Link(destination: dependency.repository) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(dependency.name)
                        .font(.headline)
                    Text("Version \(dependency.version) · Apache License 2.0")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Open-source licenses")
    }
}

private struct OpenSourceDependency: Identifiable {
    let name: String
    let version: String
    let repository: URL

    init(name: String, version: String, repository: String) {
        self.name = name
        self.version = version
        self.repository = URL(string: repository)!
    }

    var id: String { name }
}

private struct MetadataView: View {
    let sections: [ImageMetadataSection]

    var body: some View {
        List {
            ForEach(sections) { section in
                Section(LocalizedStringKey(section.title)) {
                    ForEach(section.rows) { row in
                        LabeledContent {
                            Text(
                                row.value == "C2PA signature and content verified"
                                    ? LocalizedStringKey("C2PA signature and content verified")
                                    : LocalizedStringKey(row.value)
                            )
                                .multilineTextAlignment(.trailing)
                                .textSelection(.enabled)
                        } label: {
                            if row.trust == .verified {
                                Label {
                                    metadataKeyLabel(row.key)
                                } icon: {
                                    Image(systemName: "checkmark.seal.fill")
                                }
                                .foregroundStyle(.green)
                            } else {
                                metadataKeyLabel(row.key)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Metadata")
    }

    private func metadataKeyLabel(_ key: String) -> Text {
        if key.hasPrefix("Hash algorithm") {
            let suffix = String(key.dropFirst("Hash algorithm".count))
            return Text("Hash algorithm \(Text(verbatim: suffix))")
        }
        if key.hasPrefix("Hash") {
            let suffix = String(key.dropFirst("Hash".count))
            return Text("Hash\(Text(verbatim: suffix))")
        }
        return Text(LocalizedStringKey(key))
    }
}

private struct ResultCard: View {
    let result: DetectionResult
    let aiConfidenceThreshold: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch result.source {
            case .c2paAI:
                Label("AI-generated", systemImage: "checkmark.seal")
                    .font(.title3.bold())
                    .foregroundStyle(.orange)
                C2PAStatus(provenance: result.c2paProvenance)
            case .c2paReal:
                Label("Authentic content", systemImage: "checkmark.seal")
                    .font(.title3.bold())
                    .foregroundStyle(.green)
                C2PAStatus(provenance: result.c2paProvenance)
            case .visual:
                let confidence = result.confidence ?? 0
                let isLikelyAI = confidence >= aiConfidenceThreshold
                Label {
                    if isLikelyAI {
                        Text("AI-generated")
                    } else {
                        Text("Real")
                    }
                } icon: {
                    Image(systemName: isLikelyAI ? "sparkles" : "checkmark.seal")
                }
                .font(.title3.bold())
                .foregroundStyle(isLikelyAI ? .orange : .green)

                HStack {
                    Text("Visual AI confidence")
                    Spacer()
                    Text(
                        confidence,
                        format: .percent.precision(.fractionLength(1))
                    )
                    .fontWeight(.semibold)
                }
                .font(.headline)
                ConfidenceBar(
                    confidence: confidence,
                    aiConfidenceThreshold: aiConfidenceThreshold
                )
                if let logit = result.logit {
                    HStack {
                        Text("Logit")
                        Spacer()
                        Text(
                            logit,
                            format: .number.precision(.fractionLength(4))
                        )
                        .monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                C2PAStatus(provenance: result.c2paProvenance)
                if result.usedSecondView {
                    Text("A second view was used to reduce uncertainty.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: .rect(cornerRadius: 16))
    }
}

private struct ConfidenceBar: View {
    let confidence: Double
    let aiConfidenceThreshold: Double

    private var clampedConfidence: Double {
        min(max(confidence, 0), 1)
    }

    private var clampedThreshold: Double {
        min(max(aiConfidenceThreshold, 0), 1)
    }

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.green, .yellow, .orange],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )

                    Path { path in
                        let thresholdX = geometry.size.width * clampedThreshold
                        path.move(to: CGPoint(x: thresholdX, y: 0))
                        path.addLine(to: CGPoint(x: thresholdX, y: geometry.size.height))
                    }
                    .stroke(
                        .primary.opacity(0.7),
                        style: StrokeStyle(lineWidth: 1, dash: [2, 2])
                    )

                    Rectangle()
                        .fill(.white)
                        .frame(width: 3)
                        .shadow(radius: 2)
                        .offset(x: geometry.size.width * clampedConfidence - 1.5)
                }
            }
            .frame(height: 10)

            HStack {
                Text("Real")
                Spacer()
                Text("Uncertain")
                Spacer()
                Text("AI")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            HStack {
                Text("AI threshold")
                Spacer()
                Text(
                    aiConfidenceThreshold,
                    format: .percent.precision(.fractionLength(0))
                )
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Visual AI confidence")
        .accessibilityValue(
            confidence.formatted(.percent.precision(.fractionLength(1)))
        )
        .accessibilityHint(
            Text(
                "AI threshold \(aiConfidenceThreshold, format: .percent.precision(.fractionLength(0)))"
            )
        )
    }
}

#Preview {
    ContentView()
}

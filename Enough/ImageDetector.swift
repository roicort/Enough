//
//  ImageDetector.swift
//  Enough
//

import CoreGraphics
import CoreImage
import Combine
import ImageIO
import PhotosUI
import SwiftUI
#if os(macOS)
import AppKit
#endif

struct DetectionResult {
    enum Source {
        case c2paAI
        case c2paReal
        case visual
    }

    let source: Source
    let logit: Double?
    let confidence: Double?
    let usedSecondView: Bool
    var c2paProvenance: C2PAProvenance?
}

@MainActor
final class ImageDetector: ObservableObject {
    @Published private(set) var previewImage: Image?
    @Published private(set) var result: DetectionResult?
    @Published private(set) var errorMessage: String?
    @Published private(set) var metadataSections: [ImageMetadataSection] = []
    @Published private(set) var isAnalyzing = false

    func loadAndAnalyze(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw AnalysisError.unreadableImage
            }
            try await analyze(data: data)
        } catch {
            show(error: error)
        }
    }

    func loadAndAnalyze(_ data: Data) async {
        do {
            try await analyze(data: data)
        } catch {
            show(error: error)
        }
    }

    func loadAndAnalyze(_ url: URL) async {
        let hasSecurityScopedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScopedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let data = try Data(contentsOf: url)
            try await analyze(data: data, sourceURL: url)
        } catch {
            show(error: error)
        }
    }

    func show(error: Error) {
        result = nil
        metadataSections = []
        errorMessage = error.localizedDescription
    }

    private func analyze(data: Data, sourceURL: URL? = nil) async throws {
        let sourceImage = try Preprocessor.decode(data: data)
        previewImage = Image(platformImage: sourceImage)
        result = nil
        metadataSections = []
        errorMessage = nil
        isAnalyzing = true
        defer { isAnalyzing = false }
        await Task.yield()

        let c2pa = sourceURL.map(Provenance.verify(fileAt:)) ?? Provenance.verify(data: data)
        metadataSections = (c2pa.metadataSection.map { [$0] } ?? [])
            + Provenance.technicalMetadata(data: data)
        switch c2pa.provenance {
        case .verifiedAI:
            result = DetectionResult(
                source: .c2paAI,
                logit: nil,
                confidence: nil,
                usedSecondView: false,
                c2paProvenance: .verifiedAI
            )
        case .verifiedReal:
            result = DetectionResult(
                source: .c2paReal,
                logit: nil,
                confidence: nil,
                usedSecondView: false,
                c2paProvenance: .verifiedReal
            )
        case .unknown:
            let visualAnalysis = try AnalysisPipeline().analyze(image: sourceImage)
            result = DetectionResult(
                source: .visual,
                logit: visualAnalysis.logit,
                confidence: visualAnalysis.confidence,
                usedSecondView: visualAnalysis.usedSecondView,
                c2paProvenance: c2pa.metadataSection == nil ? nil : .unknown
            )
        }
    }
}

private extension Image {
    init(platformImage: CGImage) {
#if os(macOS)
        self.init(nsImage: NSImage(cgImage: platformImage, size: .zero))
#else
        self.init(uiImage: UIImage(cgImage: platformImage))
#endif
    }
}

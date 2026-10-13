//
//  AnalysisPipeline.swift
//  Enough
//

import CoreGraphics
import CoreML
import Foundation

struct VisualAnalysis {
    let logit: Double
    let confidence: Double
    let usedSecondView = false
}

struct AnalysisPipeline {
    private static let inputName = "input"
    private static let outputName = "logit"
    private static let inputSize = 224

    private let model: MLModel

    init(bundle: Bundle = .main) throws {
        guard let url = bundle.url(
            forResource: "capcheck_ai_image_detection",
            withExtension: "mlmodelc"
        ) else {
            throw AnalysisError.missingModel
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuOnly
        model = try MLModel(contentsOf: url, configuration: configuration)
    }

    func analyze(data: Data) throws -> VisualAnalysis {
        try analyze(image: Preprocessor.decode(data: data))
    }

    func analyze(image: CGImage) throws -> VisualAnalysis {
        let image = try Preprocessor.resize(
            image,
            to: CGSize(width: Self.inputSize, height: Self.inputSize)
        )
        let logit = try prediction(for: image)
        return VisualAnalysis(
            logit: logit,
            confidence: 1 / (1 + exp(-logit))
        )
    }

    private func prediction(for image: CGImage) throws -> Double {
        guard
            let inputConstraint = model.modelDescription
                .inputDescriptionsByName[Self.inputName]?.imageConstraint
        else {
            throw AnalysisError.missingOutput
        }
        let provider = try MLDictionaryFeatureProvider(
            dictionary: [
                Self.inputName: try MLFeatureValue(
                    cgImage: image,
                    constraint: inputConstraint,
                    options: nil
                )
            ]
        )
        guard
            let multiArray = try model.prediction(from: provider)
                .featureValue(for: Self.outputName)?.multiArrayValue
        else {
            throw AnalysisError.missingOutput
        }
        return multiArray[0].doubleValue
    }
}

enum AnalysisError: LocalizedError {
    case missingModel
    case unreadableImage
    case missingOutput

    var errorDescription: String? {
        switch self {
        case .missingModel:
            String(
                localized: "The Core ML model could not be found in the app.",
                locale: SharedSettings.locale
            )
        case .unreadableImage:
            String(
                localized: "Could not open the selected image.",
                locale: SharedSettings.locale
            )
        case .missingOutput:
            String(
                localized: "The model did not return a valid result.",
                locale: SharedSettings.locale
            )
        }
    }
}

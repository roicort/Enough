//
//  AnalysisPipeline.swift
//  EnoughSafariExtension
//

import CoreGraphics
import CoreML
import Foundation

struct VisualAnalysis {
    let logit: Double
    let confidence: Double
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
        let image = try Preprocessor.decode(data: data)
        let resizedImage = try Preprocessor.resize(
            image,
            to: CGSize(width: Self.inputSize, height: Self.inputSize)
        )
        guard
            let constraint = model.modelDescription
                .inputDescriptionsByName[Self.inputName]?.imageConstraint
        else {
            throw AnalysisError.missingOutput
        }
        let provider = try MLDictionaryFeatureProvider(
            dictionary: [
                Self.inputName: try MLFeatureValue(
                    cgImage: resizedImage,
                    constraint: constraint,
                    options: nil
                )
            ]
        )
        guard
            let logit = try model.prediction(from: provider)
                .featureValue(for: Self.outputName)?
                .multiArrayValue?[0].doubleValue
        else {
            throw AnalysisError.missingOutput
        }
        return VisualAnalysis(
            logit: logit,
            confidence: 1 / (1 + exp(-logit))
        )
    }
}

enum AnalysisError: LocalizedError {
    case missingModel
    case unreadableImage
    case missingOutput

    var errorDescription: String? {
        switch self {
        case .missingModel:
            "The Core ML model could not be found in the extension."
        case .unreadableImage:
            "Could not open the image."
        case .missingOutput:
            "The model did not return a valid result."
        }
    }
}

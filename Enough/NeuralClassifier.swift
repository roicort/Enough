//
//  NeuralClassifier.swift
//  Enough
//

import CoreGraphics
import CoreML
import Foundation

enum VisualModel: String, CaseIterable {
    case capcheck
    case sieve

    static let preferenceKey = "visualModel"

    static var selected: VisualModel {
        VisualModel(
            rawValue: UserDefaults.standard.string(forKey: preferenceKey) ?? ""
        ) ?? .capcheck
    }

    var resourceName: String {
        switch self {
        case .capcheck:
            "capcheck_ai_image_detection"
        case .sieve:
            "w5810_best_fp16"
        }
    }
}

struct VisualAnalysis {
    let logit: Double
    let confidence: Double
    let usedSecondView: Bool
}

struct NeuralClassifier {
    private static let inputName = "input"
    private static let outputName = "logit"
    private static let capcheckInputSize = 224
    private static let sieveInputSize = 384
    private static let sieveResizeSize = 440

    private let selectedModel: VisualModel
    private let model: MLModel

    init(
        model selectedModel: VisualModel,
        bundle: Bundle = .main
    ) throws {
        guard let url = bundle.url(
            forResource: selectedModel.resourceName,
            withExtension: "mlmodelc"
        ) else {
            throw AnalysisError.missingModel
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        self.selectedModel = selectedModel
        model = try MLModel(contentsOf: url, configuration: configuration)
    }

    func analyze(image: CGImage) throws -> VisualAnalysis {
        switch selectedModel {
        case .capcheck:
            return try analyzeCapcheck(image)
        case .sieve:
            return try analyzeSieve(image)
        }
    }

    private func analyzeCapcheck(_ image: CGImage) throws -> VisualAnalysis {
        let resizedImage = try Preprocessing.resize(
            image,
            to: CGSize(
                width: Self.capcheckInputSize,
                height: Self.capcheckInputSize
            )
        )
        let logit = try capcheckPrediction(for: resizedImage)
        return VisualAnalysis(
            logit: logit,
            confidence: sigmoid(logit),
            usedSecondView: false
        )
    }

    private func analyzeSieve(_ image: CGImage) throws -> VisualAnalysis {
        let inputImage = try Preprocessing.sieveInputImage(
            image,
            resizeSize: Self.sieveResizeSize,
            cropSize: Self.sieveInputSize
        )
        let firstLogit = try sievePrediction(for: inputImage)
        let firstConfidence = sigmoid(firstLogit + 0.2)
        guard (0.25...0.85).contains(firstConfidence) else {
            return VisualAnalysis(
                logit: firstLogit,
                confidence: firstConfidence,
                usedSecondView: false
            )
        }

        // test-time augmentation (TTA).
        let flippedImage = try Preprocessing.horizontallyFlipped(inputImage)
        let secondLogit = try sievePrediction(for: flippedImage)
        let logit = (firstLogit + secondLogit) / 2
        return VisualAnalysis(
            logit: logit,
            confidence: sigmoid(logit + 0.2),
            usedSecondView: true
        )
    }

    private func capcheckPrediction(for image: CGImage) throws -> Double {
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
        return try logit(from: provider)
    }

    private func sievePrediction(for image: CGImage) throws -> Double {
        let input = try Preprocessing.sieveTensor(
            from: image,
            size: Self.sieveInputSize
        )
        let provider = try MLDictionaryFeatureProvider(
            dictionary: [
                Self.inputName: MLFeatureValue(multiArray: input)
            ]
        )
        return try logit(from: provider)
    }

    private func logit(from provider: MLFeatureProvider) throws -> Double {
        guard
            let multiArray = try model.prediction(from: provider)
                .featureValue(for: Self.outputName)?.multiArrayValue
        else {
            throw AnalysisError.missingOutput
        }
        return multiArray[0].doubleValue
    }

    // Sigmoid activation function used to convert logits to probabilities.
    private func sigmoid(_ value: Double) -> Double {
        1 / (1 + exp(-value))
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
                localized: "The Core ML model could not be found.",
                locale: SharedSettings.locale
            )
        case .unreadableImage:
            String(
                localized: "Could not open the image.",
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

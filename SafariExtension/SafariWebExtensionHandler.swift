//
//  SafariWebExtensionHandler.swift
//  EnoughSafariExtension
//

import Foundation
import SafariServices

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    private let maximumImageBytes = 8 * 1024 * 1024

    func beginRequest(with context: NSExtensionContext) {
        guard
            let item = context.inputItems.first as? NSExtensionItem,
            let message = item.userInfo?[SFExtensionMessageKey] as? [String: Any],
            let action = message["action"] as? String
        else {
            complete(context, with: failure("Invalid extension message."))
            return
        }

        switch action {
        case "analyzeImage":
            complete(context, with: analyze(message))
        case "settings":
            complete(
                context,
                with: success([
                    "aiConfidenceThreshold": SharedSettings.aiConfidenceThreshold,
                    "appLanguageCode": SharedSettings.appLanguageCode,
                    "showVerifiedAIC2PA": SharedSettings.showVerifiedAIC2PA
                ])
            )
        default:
            complete(context, with: failure("Unsupported extension action."))
        }
    }

    private func analyze(_ message: [String: Any]) -> [String: Any] {
        guard
            let encodedImage = message["imageBase64"] as? String,
            let imageData = Data(base64Encoded: encodedImage)
        else {
            return failure("The extension could not read the image data.")
        }
        guard imageData.count <= maximumImageBytes else {
            return failure("The image exceeds the 8 MB limit for local analysis.")
        }
        return analyze(imageData)
    }

    private func analyze(_ imageData: Data) -> [String: Any] {
        let c2pa = Provenance.verify(data: imageData)
        let c2paStatus = c2paStatus(for: c2pa)
        if c2pa.provenance == .verifiedReal {
            return success([
                "shouldBlur": false,
                "source": "c2pa-real",
                "c2paStatus": c2paStatus
            ])
        }

        do {
            let image = try Preprocessing.decode(data: imageData)
            let visualAnalysis = try NeuralClassifier(model: .sieve).analyze(image: image)
            let threshold = SharedSettings.aiConfidenceThreshold
            return success([
                "shouldBlur": visualAnalysis.confidence >= threshold,
                "confidence": visualAnalysis.confidence,
                "threshold": threshold,
                "source": c2pa.provenance == .verifiedAI ? "visual-c2pa-ai" : "visual",
                "c2paStatus": c2paStatus
            ])
        } catch {
            return failure(error.localizedDescription)
        }
    }

    private func complete(_ context: NSExtensionContext, with response: [String: Any]) {
        let item = NSExtensionItem()
        item.userInfo = [SFExtensionMessageKey: response]
        context.completeRequest(returningItems: [item])
    }

    private func success(_ data: [String: Any]) -> [String: Any] {
        ["success": true, "data": data]
    }

    private func failure(_ error: String) -> [String: Any] {
        ["success": false, "error": error]
    }

    private func c2paStatus(for verification: C2PAVerification) -> String {
        switch verification.provenance {
        case .verifiedAI:
            "aiDeclared"
        case .verifiedReal:
            "digitalCapture"
        case .unknown:
            verification.hasManifest
                ? "unknownType"
                : "unverified"
        }
    }
}

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
            complete(context, with: failure("Mensaje de extensión no válido."))
            return
        }

        switch action {
        case "analyzeImage":
            complete(context, with: analyze(message))
        case "analyzeImageURL":
            Task {
                complete(context, with: await analyzeRemoteImage(message))
            }
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
            complete(context, with: failure("Acción de extensión no compatible."))
        }
    }

    private func analyze(_ message: [String: Any]) -> [String: Any] {
        guard
            let encodedImage = message["imageBase64"] as? String,
            let imageData = Data(base64Encoded: encodedImage)
        else {
            return failure("La extensión no pudo leer los datos de la imagen.")
        }
        guard imageData.count <= maximumImageBytes else {
            return failure("La imagen supera el límite de 8 MB para análisis local.")
        }
        return analyze(imageData)
    }

    private func analyzeRemoteImage(_ message: [String: Any]) async -> [String: Any] {
        guard
            let urlString = message["url"] as? String,
            let url = URL(string: urlString),
            ["http", "https"].contains(url.scheme?.lowercased())
        else {
            return failure("La extensión no pudo leer la URL de la imagen.")
        }

        do {
            let (imageData, response) = try await URLSession.shared.data(from: url)
            guard let response = response as? HTTPURLResponse,
                  (200...299).contains(response.statusCode) else {
                return failure("La extensión no pudo descargar la imagen.")
            }
            guard imageData.count <= maximumImageBytes else {
                return failure("La imagen supera el límite de 8 MB para análisis local.")
            }
            return analyze(imageData)
        } catch {
            return failure("La extensión no pudo descargar la imagen: \(error.localizedDescription)")
        }
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
            let visualAnalysis = try AnalysisPipeline().analyze(data: imageData)
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

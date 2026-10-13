//
//  Provenance.swift
//  EnoughSafariExtension
//

import C2PA
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum C2PAProvenance {
    case verifiedAI
    case verifiedReal
    case unknown
}

struct C2PAVerification {
    let provenance: C2PAProvenance
    let hasManifest: Bool
}

enum Provenance {
    static func verify(data: Data) -> C2PAVerification {
        let fileExtension: String
        if
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let type = CGImageSourceGetType(source),
            let utType = UTType(type as String)
        {
            fileExtension = utType.preferredFilenameExtension ?? "jpg"
        } else {
            fileExtension = "jpg"
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            try data.write(to: url, options: .atomic)
            let manifestJSON = try C2PA.readFile(at: url)
            return C2PAVerification(
                provenance: classify(manifestJSON: manifestJSON),
                hasManifest: true
            )
        } catch {
            return C2PAVerification(provenance: .unknown, hasManifest: false)
        }
    }

    private static func classify(manifestJSON: String) -> C2PAProvenance {
        guard
            let data = manifestJSON.data(using: .utf8),
            let manifest = try? JSONSerialization.jsonObject(with: data)
        else {
            return .unknown
        }
        let sourceTypes = strings(in: manifest, forKey: "digitalSourceType")
            .map { $0.lowercased() }
        if sourceTypes.contains(where: {
            $0.contains("trainedalgorithmicmedia") || $0.contains("syntheticmedia")
        }) {
            return .verifiedAI
        }
        if sourceTypes.contains(where: { $0.contains("digitalcapture") }) {
            return .verifiedReal
        }
        return .unknown
    }

    private static func strings(in value: Any, forKey targetKey: String) -> [String] {
        if let dictionary = value as? [String: Any] {
            return dictionary.flatMap { key, nestedValue in
                let current = key == targetKey ? stringValues(in: nestedValue) : []
                return current + strings(in: nestedValue, forKey: targetKey)
            }
        }
        if let values = value as? [Any] {
            return values.flatMap { strings(in: $0, forKey: targetKey) }
        }
        return []
    }

    private static func stringValues(in value: Any) -> [String] {
        if let string = value as? String {
            return [string]
        }
        if let values = value as? [Any] {
            return values.compactMap { $0 as? String }
        }
        return []
    }
}

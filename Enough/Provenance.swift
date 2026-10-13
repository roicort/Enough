//
//  Provenance.swift
//  Enough
//

import C2PA
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum C2PAProvenance: Equatable {
    case verifiedAI
    case verifiedReal
    case unknown
}

struct ImageMetadataRow: Identifiable {
    enum Trust {
        case verified
        case informational
    }

    let key: String
    let value: String
    let trust: Trust

    nonisolated init(
        key: String,
        value: String,
        trust: Trust = .informational
    ) {
        self.key = key
        self.value = value
        self.trust = trust
    }

    var id: String {
        "\(key):\(value)"
    }
}

struct ImageMetadataSection: Identifiable {
    enum Trust {
        case verified
        case informational
    }

    let title: String
    let rows: [ImageMetadataRow]
    let trust: Trust

    var id: String {
        title
    }

    nonisolated init(
        title: String,
        rows: [ImageMetadataRow],
        trust: Trust = .informational
    ) {
        self.title = title
        self.rows = rows
        self.trust = trust
    }
}

struct C2PAVerification {
    let provenance: C2PAProvenance
    let metadataSection: ImageMetadataSection?

    nonisolated init(
        provenance: C2PAProvenance,
        metadataSection: ImageMetadataSection?
    ) {
        self.provenance = provenance
        self.metadataSection = metadataSection
    }
}

struct Provenance {
    nonisolated static func verify(data: Data) -> C2PAVerification {
        let fileExtension = imageFileExtension(for: data)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            try data.write(to: url, options: .atomic)
            return verify(fileAt: url)
        } catch {
            return C2PAVerification(provenance: .unknown, metadataSection: nil)
        }
    }

    nonisolated static func verify(fileAt url: URL) -> C2PAVerification {
        do {
            let manifestJSON = try C2PA.readFile(at: url)
            return C2PAVerification(
                provenance: classify(manifestJSON: manifestJSON),
                metadataSection: metadataSection(manifestJSON: manifestJSON)
            )
        } catch {
            return C2PAVerification(provenance: .unknown, metadataSection: nil)
        }
    }

    nonisolated static func classify(manifestJSON: String) -> C2PAProvenance {
        guard
            let data = manifestJSON.data(using: .utf8),
            let manifest = try? JSONSerialization.jsonObject(with: data)
        else {
            return .unknown
        }

        let sourceTypes = strings(
            in: manifest,
            forKey: "digitalSourceType"
        ).map { $0.lowercased() }

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

    private nonisolated static func imageFileExtension(for data: Data) -> String {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let type = CGImageSourceGetType(source),
            let utType = UTType(type as String)
        else {
            return "jpg"
        }

        return utType.preferredFilenameExtension ?? "jpg"
    }

    nonisolated static func technicalMetadata(data: Data) -> [ImageMetadataSection] {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any]
        else {
            return []
        }

        var sections = [
            ImageMetadataSection(
                title: "File",
                rows: compactRows([
                    ("Format", CGImageSourceGetType(source)
                        .flatMap { UTType($0 as String)?.localizedDescription }),
                    ("Width", value(properties[kCGImagePropertyPixelWidth])),
                    ("Height", value(properties[kCGImagePropertyPixelHeight])),
                    ("Orientation", value(properties[kCGImagePropertyOrientation]))
                ])
            )
        ]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let iptc = properties[kCGImagePropertyIPTCDictionary] as? [CFString: Any] ?? [:]

        let cameraRows = compactRows([
            ("Manufacturer", value(tiff[kCGImagePropertyTIFFMake])),
            ("Model", value(tiff[kCGImagePropertyTIFFModel])),
            ("Software", value(tiff[kCGImagePropertyTIFFSoftware])),
            ("Date", value(exif[kCGImagePropertyExifDateTimeOriginal] ?? tiff[kCGImagePropertyTIFFDateTime])),
            ("Lens", value(exif[kCGImagePropertyExifLensModel])),
            ("ISO", value(exif[kCGImagePropertyExifISOSpeedRatings])),
            ("Aperture", value(exif[kCGImagePropertyExifFNumber])),
            ("Exposure", value(exif[kCGImagePropertyExifExposureTime])),
            ("Focal length", value(exif[kCGImagePropertyExifFocalLength]))
        ])
        if !cameraRows.isEmpty {
            sections.append(ImageMetadataSection(title: "EXIF", rows: cameraRows))
        }

        let iptcRows = compactRows([
            ("Title", value(iptc[kCGImagePropertyIPTCObjectName])),
            ("Author", value(iptc[kCGImagePropertyIPTCByline])),
            ("Credit", value(iptc[kCGImagePropertyIPTCCredit])),
            ("Copyright", value(iptc[kCGImagePropertyIPTCCopyrightNotice])),
            ("Keywords", value(iptc[kCGImagePropertyIPTCKeywords]))
        ])
        if !iptcRows.isEmpty {
            sections.append(ImageMetadataSection(title: "IPTC", rows: iptcRows))
        }
        return sections
    }

    private nonisolated static func metadataSection(manifestJSON: String) -> ImageMetadataSection? {
        guard
            let data = manifestJSON.data(using: .utf8),
            let manifest = try? JSONSerialization.jsonObject(with: data)
        else {
            return nil
        }
        var rows = compactRows([
            ("Status", "C2PA signature and content verified"),
            ("Manifest ID", firstString(in: manifest, forKey: "active_manifest")
                ?? firstString(in: manifest, forKey: "instance_id")),
            ("Title", firstString(in: manifest, forKey: "title")),
            ("Issuer", firstString(in: manifest, forKey: "claim_generator")),
            ("Declared format", firstString(in: manifest, forKey: "format")),
            ("Source type", strings(in: manifest, forKey: "digitalSourceType")
                .joined(separator: ", "))
        ], trust: .verified)
        let signature = firstDictionary(in: manifest, forKey: "signature_info")
        rows += compactRows([
            ("Signature algorithm", value(signature?["alg"])),
            ("Certificate serial number", value(signature?["cert_serial_number"])),
            ("Signing time", value(signature?["time"]))
        ], trust: .verified)
        rows += hashRows(in: manifest)
        return ImageMetadataSection(
            title: "C2PA",
            rows: rows,
            trust: .verified
        )
    }

    private nonisolated static func strings(in value: Any, forKey targetKey: String) -> [String] {
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

    private nonisolated static func stringValues(in value: Any) -> [String] {
        if let string = value as? String {
            return [string]
        }
        if let values = value as? [Any] {
            return values.flatMap(stringValues)
        }
        return []
    }

    private nonisolated static func firstString(in value: Any, forKey key: String) -> String? {
        strings(in: value, forKey: key).first
    }

    private nonisolated static func firstDictionary(
        in value: Any,
        forKey targetKey: String
    ) -> [String: Any]? {
        if let dictionary = value as? [String: Any] {
            if targetKey == "signature_info", let signature = dictionary[targetKey] as? [String: Any] {
                return signature
            }
            for nestedValue in dictionary.values {
                if let result = firstDictionary(in: nestedValue, forKey: targetKey) {
                    return result
                }
            }
        }
        if let values = value as? [Any] {
            for nestedValue in values {
                if let result = firstDictionary(in: nestedValue, forKey: targetKey) {
                    return result
                }
            }
        }
        return nil
    }

    private nonisolated static func hashRows(in value: Any) -> [ImageMetadataRow] {
        var hashes: [(algorithm: String?, value: String)] = []
        collectHashes(in: value, into: &hashes)
        return hashes.enumerated().flatMap { index, hash in
            let suffix = hashes.count > 1 ? " \(index + 1)" : ""
            let encoding = hash.value.contains("=") || hash.value.contains("/") || hash.value.contains("+")
                ? "Base64"
                : "hexadecimal"
            return compactRows([
                ("Hash algorithm\(suffix)", hash.algorithm),
                ("Hash\(suffix) (\(encoding))", hash.value)
            ], trust: .verified)
        }
    }

    private nonisolated static func collectHashes(
        in value: Any,
        into hashes: inout [(algorithm: String?, value: String)]
    ) {
        if let dictionary = value as? [String: Any] {
            let label = dictionary["label"] as? String ?? ""
            if label.lowercased().hasPrefix("c2pa.hash"),
               let data = dictionary["data"] as? [String: Any],
               let hash = data["hash"] as? String {
                hashes.append((data["alg"] as? String, hash))
            }
            for nestedValue in dictionary.values {
                collectHashes(in: nestedValue, into: &hashes)
            }
        } else if let values = value as? [Any] {
            for nestedValue in values {
                collectHashes(in: nestedValue, into: &hashes)
            }
        }
    }

    private nonisolated static func compactRows(
        _ entries: [(String, String?)],
        trust: ImageMetadataRow.Trust = .informational
    ) -> [ImageMetadataRow] {
        entries.compactMap { key, value in
            guard let value, !value.isEmpty else { return nil }
            return ImageMetadataRow(key: key, value: value, trust: trust)
        }
    }

    private nonisolated static func value(_ rawValue: Any?) -> String? {
        guard let rawValue else { return nil }
        if let values = rawValue as? [Any] {
            return values.map { String(describing: $0) }.joined(separator: ", ")
        }
        return String(describing: rawValue)
    }
}

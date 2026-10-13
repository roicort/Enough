//
//  Preprocessor.swift
//  Enough
//

import CoreGraphics
import CoreImage
import Foundation
import ImageIO

enum Preprocessor {
    static func decode(data: Data) throws -> CGImage {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw AnalysisError.unreadableImage
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientation = (properties?[kCGImagePropertyOrientation] as? UInt32)
            .flatMap { CGImagePropertyOrientation(rawValue: $0) } ?? .up
        let oriented = CIImage(cgImage: image).oriented(orientation)
        return CIContext().createCGImage(oriented, from: oriented.extent) ?? image
    }

    static func resize(_ image: CGImage, to size: CGSize) throws -> CGImage {
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        guard
            width > 0,
            height > 0,
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            throw AnalysisError.unreadableImage
        }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(origin: .zero, size: size))
        guard let resizedImage = context.makeImage() else {
            throw AnalysisError.unreadableImage
        }
        return resizedImage
    }
}

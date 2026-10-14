//
//  Preprocessing.swift
//  Enough
//

import CoreGraphics
import CoreImage
import CoreML
import Foundation
import ImageIO

enum Preprocessing {
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

    static func sieveInputImage(
        _ image: CGImage,
        resizeSize: Int,
        cropSize: Int
    ) throws -> CGImage {
        let scale = Double(resizeSize) / Double(min(image.width, image.height))
        let resizedSize = CGSize(
            width: Double(image.width) * scale,
            height: Double(image.height) * scale
        )
        let cropOrigin = CGPoint(
            x: (Double(cropSize) - resizedSize.width) / 2,
            y: (Double(cropSize) - resizedSize.height) / 2
        )
        guard let context = CGContext(
            data: nil,
            width: cropSize,
            height: cropSize,
            bitsPerComponent: 8,
            bytesPerRow: cropSize * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            throw AnalysisError.unreadableImage
        }
        context.interpolationQuality = .medium
        context.draw(
            image,
            in: CGRect(origin: cropOrigin, size: resizedSize)
        )
        guard let croppedImage = context.makeImage() else {
            throw AnalysisError.unreadableImage
        }
        return croppedImage
    }

    static func horizontallyFlipped(_ image: CGImage) throws -> CGImage {
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            throw AnalysisError.unreadableImage
        }
        context.translateBy(x: CGFloat(image.width), y: 0)
        context.scaleBy(x: -1, y: 1)
        context.draw(
            image,
            in: CGRect(x: 0, y: 0, width: image.width, height: image.height)
        )
        guard let flippedImage = context.makeImage() else {
            throw AnalysisError.unreadableImage
        }
        return flippedImage
    }

    static func sieveTensor(from image: CGImage, size: Int) throws -> MLMultiArray {
        guard image.width == size, image.height == size else {
            throw AnalysisError.unreadableImage
        }
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let didDraw = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: size,
                height: size,
                bitsPerComponent: 8,
                bytesPerRow: size * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
            ) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
            return true
        }
        guard didDraw else {
            throw AnalysisError.unreadableImage
        }

        let tensor = try MLMultiArray(
            shape: [1, 3, NSNumber(value: size), NSNumber(value: size)],
            dataType: .float32
        )
        let means: [Float] = [0.485, 0.456, 0.406]
        let standardDeviations: [Float] = [0.229, 0.224, 0.225]
        for channel in 0..<3 {
            for pixelIndex in 0..<(size * size) {
                let pixel = Float(pixels[pixelIndex * 4 + channel]) / 255
                let normalized = (pixel - means[channel]) / standardDeviations[channel]
                tensor[channel * size * size + pixelIndex] = NSNumber(value: normalized)
            }
        }
        return tensor
    }
}

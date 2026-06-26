import AppKit
import CoreImage

enum ColorExtractor {
    static func dominantColor(from image: NSImage, completion: @escaping (NSColor) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let color = extract(from: cgImage) else {
                DispatchQueue.main.async { completion(NSColor(red: 0.4, green: 0.3, blue: 0.8, alpha: 1)) }
                return
            }
            DispatchQueue.main.async { completion(color) }
        }
    }

    private static func extract(from cgImage: CGImage) -> NSColor? {
        let ciImage = CIImage(cgImage: cgImage)
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: 0.1, y: 0.1))

        guard let kmeans = CIFilter(name: "CIKMeans", parameters: [
            kCIInputImageKey: scaled,
            "inputCount": 5,
            kCIInputExtentKey: CIVector(cgRect: scaled.extent)
        ]), let output = kmeans.outputImage else { return nil }

        let context = CIContext()
        var bitmap = [UInt8](repeating: 0, count: 5 * 4)
        context.render(
            output,
            toBitmap: &bitmap,
            rowBytes: 5 * 4,
            bounds: CGRect(x: 0, y: 0, width: 5, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        var bestColor: NSColor = NSColor(red: 0.4, green: 0.3, blue: 0.8, alpha: 1)
        var bestSaturation: CGFloat = 0

        for i in 0..<5 {
            let r = CGFloat(bitmap[i * 4]) / 255
            let g = CGFloat(bitmap[i * 4 + 1]) / 255
            let b = CGFloat(bitmap[i * 4 + 2]) / 255
            let color = NSColor(red: r, green: g, blue: b, alpha: 1)
            var h: CGFloat = 0, s: CGFloat = 0, br: CGFloat = 0, a: CGFloat = 0
            color.getHue(&h, saturation: &s, brightness: &br, alpha: &a)
            if s > bestSaturation { bestSaturation = s; bestColor = color }
        }

        return bestColor
    }
}

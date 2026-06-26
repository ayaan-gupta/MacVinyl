import AppKit

enum AlbumArtPixelator {
    static func pixelate(_ image: NSImage, pixelCount: Double) -> NSImage {
        guard let cgSrc = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return image
        }
        let ciInput = CIImage(cgImage: cgSrc)
        guard let filter = CIFilter(name: "CIPixellate") else { return image }
        filter.setValue(ciInput, forKey: kCIInputImageKey)
        let targetPixelCount = max(4, pixelCount)
        let scale = max(2.0, Double(cgSrc.width) / targetPixelCount)
        filter.setValue(scale, forKey: kCIInputScaleKey)
        guard let output = filter.outputImage else { return image }
        let ctx = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgOut = ctx.createCGImage(output, from: ciInput.extent) else { return image }
        return NSImage(cgImage: cgOut, size: NSSize(width: cgSrc.width, height: cgSrc.height))
    }
}

import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

struct QRCodeView: View {
    let text: String

    private let context = CIContext()
    private let filter = CIFilter.qrCodeGenerator()

    var body: some View {
        if let image = makeCGImage(from: text) {
            Image(decorative: image, scale: 1.0)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
        } else {
            Text(text)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    private func makeCGImage(from string: String) -> CGImage? {
        filter.message = Data(string.utf8)

        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        return context.createCGImage(scaled, from: scaled.extent)
    }
}


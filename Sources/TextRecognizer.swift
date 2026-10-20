import AppKit
import Vision

enum TextRecognizer {
    /// OCR image → text (async). Used to make screenshots/images searchable.
    static func recognize(imageURL: URL, completion: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            guard let image = NSImage(contentsOf: imageURL),
                  let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let cg = rep.cgImage else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            do {
                try handler.perform([request])
                let text = request.results?
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                DispatchQueue.main.async {
                    completion((text?.isEmpty == false) ? text : nil)
                }
            } catch {
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }
}

import Foundation
import Vision

protocol ImageRecognizing: Sendable {
    func recognize(_ data: Data) async throws -> String?
}

/// Vision work is serialized off the main actor; capture and history insertion do
/// not wait for recognition. Cancellation is checked before expensive queued work.
actor ImageRecognitionService: ImageRecognizing {
    func recognize(_ data: Data) async throws -> String? {
        try Task.checkCancellation()
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .fast
        textRequest.usesLanguageCorrection = true
        let barcodeRequest = VNDetectBarcodesRequest()
        try VNImageRequestHandler(data: data).perform([textRequest, barcodeRequest])
        try Task.checkCancellation()
        var values = (textRequest.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        values.append(contentsOf: (barcodeRequest.results ?? []).compactMap(\.payloadStringValue))
        var seen = Set<String>()
        let unique = values.filter { seen.insert($0).inserted }
        return unique.isEmpty ? nil : unique.joined(separator: "\n")
    }
}

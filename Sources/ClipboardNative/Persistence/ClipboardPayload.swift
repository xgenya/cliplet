import Foundation

extension ClipboardItem {
    func payloadData(for key: String) throws -> Data? {
        let inline = ["image": imageData, "rtf": rtfData, "html": htmlData][key] ?? nil
        if let inline { return inline }
        guard let name = payloadReferences?[key] else { return nil }
        guard HistoryRepository.isPayloadName(name), let payloadDirectory else {
            throw HistoryStorageError.invalidPayload
        }
        return try Data(contentsOf: payloadDirectory.appendingPathComponent(name))
    }

    var resolvedImageData: Data? { try? payloadData(for: "image") }

}

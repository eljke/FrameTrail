import Foundation

extension URLRequest {
    func testBodyData() throws -> Data {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { throw URLError(.requestBodyStreamExhausted) }
        stream.open()
        defer { stream.close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeContentData) }
            if count == 0 { break }
            result.append(contentsOf: buffer.prefix(count))
        }
        return result
    }
}

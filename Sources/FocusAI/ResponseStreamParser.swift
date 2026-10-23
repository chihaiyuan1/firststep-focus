import Foundation

/// Buffers bytes until a complete SSE line arrives; UTF-8 may span network chunks.
struct ResponseStreamParser {
    private var buffer = Data()
    private var eventData: [String] = []
    private var eventName = ""
    private var text = ""
    private(set) var completed = false
    private var failed = false
    private var byteCount = 0
    mutating func append(_ data: Data) throws {
        byteCount += data.count
        guard byteCount <= 8 * 1024 * 1024 else { failed = true; throw ChatGPTError.invalidResponse }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 10) {
            var line = buffer.prefix(upTo: newline)
            if line.last == 13 { line = line.dropLast() }
            guard let string = String(data: line, encoding: .utf8) else { failed = true; throw ChatGPTError.invalidResponse }
            buffer.removeSubrange(...newline)
            try consumeLine(string)
        }
    }
    private mutating func consumeLine(_ line: String) throws {
        if line.isEmpty { try dispatch(); eventData.removeAll(keepingCapacity: true); eventName = ""; return }
        if line.hasPrefix(":") { return }
        let fields = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let value = fields.count > 1 ? String(fields[1].first == " " ? fields[1].dropFirst() : fields[1]) : ""
        if fields[0] == "data" { eventData.append(value) }
        if fields[0] == "event" { eventName = value }
    }
    private mutating func dispatch() throws {
        guard !eventData.isEmpty else { return }
        let string = eventData.joined(separator: "\n")
        if string == "[DONE]" { return }
        guard let data = string.data(using: .utf8), let event = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let type = event["type"] as? String else { failed = true; throw ChatGPTError.invalidResponse }
        guard eventName.isEmpty || eventName == type else { failed = true; throw ChatGPTError.invalidResponse }
        switch type {
        case "response.output_text.delta":
            guard !completed, let delta = event["delta"] as? String else { failed = true; throw ChatGPTError.invalidResponse }
            text += delta
        case "response.failed", "response.incomplete", "error":
            failed = true
            if type == "response.incomplete" { throw ChatGPTError.incompleteResponse }
            let response = event["response"] as? [String: Any]
            let error = response?["error"] as? [String: Any] ?? event["error"] as? [String: Any]
            throw ChatGPTError.fromCode(error?["code"] as? String ?? event["code"] as? String)
        case "response.completed":
            if let response = event["response"] as? [String: Any], let status = response["status"] as? String, status != "completed" { failed = true; throw ChatGPTError.incompleteResponse }
            completed = true
        default: break
        }
    }
    func finish() throws -> String {
        guard completed, !failed else { throw ChatGPTError.incompleteResponse }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ChatGPTError.emptyResponse }
        return text
    }
}

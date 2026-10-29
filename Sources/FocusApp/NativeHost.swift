import Foundation
import FocusCore

private struct HostRequest: Decodable { let id: String; let command: Command? }
private struct HostReply: Encodable { let id: String; let ok: Bool; let state: FocusState?; let error: String? }
func runNativeHost() {
    let input = FileHandle.standardInput, output = FileHandle.standardOutput, store = StateStore()
    func readExactly(_ count: Int) -> Data? {
        var data = Data()
        while data.count < count {
            guard let chunk = try? input.read(upToCount: count - data.count), !chunk.isEmpty else { return nil }
            data.append(chunk)
        }
        return data
    }
    while let header = readExactly(4) {
        let length = header.enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << ($1.offset * 8) }
        guard length > 0, length <= 1_048_576, let data = readExactly(Int(length)) else { return }
        var requestID = ""
        let reply: HostReply
        do {
            let request = try JSONDecoder().decode(HostRequest.self, from: data); requestID = request.id
            let command = request.command ?? Command("getState")
            guard ["getState", "heartbeat", "requestAccess", "confirmAccess", "cancelRequest"].contains(command.action) else {
                throw FocusError("此操作请在 Mac 工具中完成")
            }
            var state = try store.transact(command: command)
            state.inboxItems = nil
            state.completionRecords = nil
            for i in state.tasks.indices { state.tasks[i].subtasks = nil; state.tasks[i].scheduledDay = nil; state.tasks[i].reminderAt = nil }
            // Only the browser snapshot is bounded; old daily forests stay on disk.
            state.history = Array(state.history.prefix(500))
            reply = HostReply(id: request.id, ok: true, state: state, error: nil)
        } catch { reply = HostReply(id: requestID, ok: false, state: nil, error: error.localizedDescription) }
        guard let encoded = try? JSONEncoder().encode(reply) else { return }
        var size = UInt32(encoded.count).littleEndian
        let prefix = withUnsafeBytes(of: &size) { Data($0) }
        do { try output.write(contentsOf: prefix + encoded) } catch { return }
    }
}

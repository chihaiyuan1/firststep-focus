import Foundation
import Network

/// One loopback-only OAuth attempt. Queue confinement guarantees a single terminal result.
final class CallbackServer: @unchecked Sendable {
    private let queue=DispatchQueue(label:"com.dayuan.firststep.oauth")
    private var listener:NWListener?
    private var waiter:CheckedContinuation<URL,Error>?
    private var result:Result<URL,Error>?
    private var connections:[NWConnection]=[]
    private var base:URL?
    private let state:String
    init(state:String) { self.state=state }
    func start() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let parameters=NWParameters.tcp
                    parameters.requiredLocalEndpoint = .hostPort(host:"127.0.0.1",port:.any)
                    let listener=try NWListener(using:parameters)
                    self.listener=listener
                    var pending=true
                    listener.stateUpdateHandler = { state in
                        switch state {
                        case .ready:
                            if pending,let port=listener.port {pending=false;let url=URL(string:"http://127.0.0.1:\(port.rawValue)/auth/callback")!;self.base=url;continuation.resume(returning:url)}
                        case .failed:
                            if pending {pending=false;continuation.resume(throwing:ChatGPTError.network)}
                            self.finish(.failure(ChatGPTError.network))
                        case .cancelled:
                            if pending {pending=false;continuation.resume(throwing:ChatGPTError.cancelled)}
                        default:break
                        }
                    }
                    listener.newConnectionHandler = {connection in
                        self.connections.append(connection);connection.start(queue:self.queue);self.receive(connection,buffer:Data())
                    }
                    listener.start(queue:self.queue)
                    self.queue.asyncAfter(deadline:.now()+600) {self.finish(.failure(ChatGPTError.signInExpired))}
                } catch {continuation.resume(throwing:ChatGPTError.network)}
            }
        }
    }
    func wait() async throws -> URL {
        try await withTaskCancellationHandler(operation:{
            try await withCheckedThrowingContinuation { continuation in
                queue.async {if let result=self.result {continuation.resume(with:result)} else if self.waiter==nil {self.waiter=continuation} else {continuation.resume(throwing:ChatGPTError.signInBusy)}}
            }
        },onCancel:{self.cancel()})
    }
    func cancel() {queue.async {self.finish(.failure(ChatGPTError.cancelled))}}
    private func finish(_ value:Result<URL,Error>) {
        guard result==nil else {return};result=value
        listener?.cancel();listener=nil
        waiter?.resume(with:value);waiter=nil
        queue.asyncAfter(deadline:.now()+1) {self.connections.forEach {$0.cancel()};self.connections=[]}
    }
    private func receive(_ connection:NWConnection,buffer:Data) {
        connection.receive(minimumIncompleteLength:1,maximumLength:8192) {data,_,done,error in
            var current=buffer;current.append(data ?? Data())
            guard current.count<=16384,error==nil else {connection.cancel();return}
            guard let end=current.range(of:Data("\r\n\r\n".utf8)) else {if !done {self.receive(connection,buffer:current)} else {connection.cancel()};return}
            guard let request=String(data:current[..<end.lowerBound],encoding:.utf8),let line=request.components(separatedBy:"\r\n").first,
                  let base=self.base else {connection.cancel();return}
            let pieces=line.components(separatedBy:" ")
            let headers=request.components(separatedBy:"\r\n").dropFirst()
            let host=headers.first(where:{$0.lowercased().hasPrefix("host:")})?.dropFirst(5).trimmingCharacters(in:.whitespaces)
            let path=pieces.count==3 ? pieces[1] : ""
            let url=URL(string:"http://127.0.0.1:\(base.port!)"+path)
            let items=url.flatMap {URLComponents(url:$0,resolvingAgainstBaseURL:false)?.queryItems} ?? []
            let valid=pieces.first=="GET" && host=="127.0.0.1:\(base.port!)" && path.hasPrefix("/auth/callback?") && items.filter({$0.name=="state"}).count==1 && items.first(where:{$0.name=="state"})?.value==self.state
            let text=valid ? "授权信息已返回先做一刻。请回到软件查看连接结果。" : "无效的授权请求，请返回先做一刻。"
            let body="<!doctype html><html lang=zh-CN><meta charset=utf-8><title>先做一刻</title><body><h2>先做一刻</h2><p>\(text)</p></body></html>"
            let response="HTTP/1.1 \(valid ? "200 OK" : "400 Bad Request")\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nCache-Control: no-store\r\nReferrer-Policy: no-referrer\r\nContent-Security-Policy: default-src 'none'; frame-ancestors 'none'\r\nConnection: close\r\n\r\n\(body)"
            connection.send(content:Data(response.utf8),completion:.contentProcessed {_ in connection.cancel()})
            if valid,let url {self.finish(.success(url))}
        }
    }
}

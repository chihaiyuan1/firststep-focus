import Foundation
import Security
import CryptoKit

private func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !value() { throw CheckFailure(message: message) }
}
private struct CheckFailure: Error { let message: String }
private func rejects(_ message: String, _ body: () throws -> Void) throws {
    do { try body() } catch { return }; throw CheckFailure(message: message)
}
private func fixture(_ extra: [String: Any] = [:]) throws -> Data {
    var value: [String: Any] = ["email":"test@example.invalid", "issuer":"https://auth.openai.com", "subject":"fixture-sub", "client_id":"oaiapp_fixture", "ext_agent_host_id":"urn:uuid:00000000-0000-4000-8000-000000000000", "id_token":"fixture-id", "access_token":"fixture-access", "refresh_token":"fixture-refresh", "token_type":"Bearer", "expires_in":3600, "scope":"openid resource.invoke chatgpt.tokens.use.direct", "scopes":["openid","resource.invoke","chatgpt.tokens.use.direct"], "saved_at":ISO8601DateFormatter.fractional.string(from: Date())]
    for (key, item) in extra { value[key] = item }
    return try JSONSerialization.data(withJSONObject: value)
}
private func event(_ type: String, _ fields: [String: Any] = [:]) throws -> Data {
    var item = fields; item["type"] = type
    let json = String(data: try JSONSerialization.data(withJSONObject: item), encoding: .utf8)!
    return Data("event: \(type)\r\ndata: \(json)\r\n\r\n".utf8)
}
private final class RefreshProtocol:URLProtocol {
    static let lock=NSLock()
    static var refreshCount=0
    private var work:DispatchWorkItem?
    override class func canInit(with request:URLRequest)->Bool {true}
    override class func canonicalRequest(for request:URLRequest)->URLRequest {request}
    static func count()->Int {lock.lock();defer {lock.unlock()};return refreshCount}
    override func startLoading() {
        let token=request.url!.path.hasSuffix("/token")
        if token {Self.lock.lock();Self.refreshCount+=1;Self.lock.unlock()}
        let item=DispatchWorkItem { [self] in
            let completion="data: {\"type\":\"response.output_text.delta\",\"delta\":\"mock-complete\"}\n\ndata: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\"}}\n\n"
            let body=request.url!.path.hasSuffix("/responses") ? completion : token ? #"{"access_token":"rotated-access","refresh_token":"rotated-refresh","token_type":"Bearer","expires_in":3600}"# : #"{"models":[{"slug":"test-model","display_name":"Test","visibility":"list"}]}"#
            client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!,cacheStoragePolicy:.notAllowed)
            client?.urlProtocol(self,didLoad:Data(body.utf8));client?.urlProtocolDidFinishLoading(self)
        }
        work=item;DispatchQueue.global().asyncAfter(deadline:.now()+(token ? 0.15 : 0),execute:item)
    }
    override func stopLoading() {work?.cancel()}
}
@main struct ChatGPTChecks {
    static func main() async throws {
        // Catches treating deltas, [DONE], failed, incomplete or empty completions as an adoptable answer.
        var parser = ResponseStreamParser()
        let content = try event("response.output_text.delta", ["delta":"你好 👋"])
        for byte in content { try parser.append(Data([byte])) }
        try rejects("partial stream accepted") { _ = try parser.finish() }
        try parser.append(event("response.completed", ["response":["status":"completed"]]))
        try check(try parser.finish() == "你好 👋", "fragmented UTF-8/SSE text lost")
        for type in ["response.failed","response.incomplete","error"] {
            var failed = ResponseStreamParser()
            try rejects("error stream accepted") {
                try failed.append(event("response.output_text.delta", ["delta":"partial"]))
                try failed.append(event(type, ["response":["error":["code":"subscription_sharing_usage_limit_exceeded"]]]))
                _ = try failed.finish()
            }
        }
        try rejects("empty completion accepted") { var p = ResponseStreamParser(); try p.append(event("response.completed")); _ = try p.finish() }
        try rejects("done marker accepted without completion") { var p = ResponseStreamParser(); try p.append(Data("data: [DONE]\n\n".utf8)); _ = try p.finish() }
        try rejects("malformed SSE JSON accepted") { var p = ResponseStreamParser(); try p.append(Data("data: {broken}\n\n".utf8)) }
        // Catches using hidden models or changing the model slug/order sent to Responses.
        let modelData = Data(#"{"models":[{"slug":"one","display_name":"One","visibility":"list"},{"slug":"secret","display_name":"Hidden","visibility":"hidden"},{"slug":"two","display_name":"Two","visibility":"list"}]}"#.utf8)
        try check(try ChatGPTModel.decodeCatalog(modelData).map(\.id) == ["one","two"], "model visibility/order")
        // RFC 7636 S256 vector catches accidental plain PKCE or wrong base64url encoding.
        try check(OAuthSupport.challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", "PKCE mismatch")
        let callback = URL(string:"http://127.0.0.1:1234/auth/callback?code=test&state=expected&client_id=oaiapp_new")!
        let accepted = try OAuthSupport.callback(callback, state:"expected", clientID:nil)
        try check(accepted.clientID == "oaiapp_new", "issued client discarded")
        try rejects("wrong state accepted") { _ = try OAuthSupport.callback(callback, state:"wrong", clientID:nil) }
        try rejects("returning registration replaced") { _ = try OAuthSupport.callback(callback, state:"expected", clientID:"oaiapp_old") }
        try rejects("duplicate state accepted") { _ = try OAuthSupport.callback(URL(string:callback.absoluteString + "&state=expected")!, state:"expected", clientID:nil) }
        try rejects("dynamic registration ID saved") { _ = try OAuthSupport.callback(URL(string:"http://127.0.0.1:1234/auth/callback?code=x&state=expected&client_id=dynamic_agent_client")!, state:"expected", clientID:nil) }
        try rejects("access denial accepted") { _ = try OAuthSupport.callback(URL(string:"http://127.0.0.1:1234/auth/callback?error=access_denied&state=expected")!, state:"expected", clientID:nil) }
        // Catches replacing the selected identity on reauth and claim validation omissions.
        let claims: [String:Any] = ["iss":"https://auth.openai.com","sub":"alice","aud":"oaiapp_fixture","exp":Date().timeIntervalSince1970 + 600,"nonce":"nonce"]
        _ = try OAuthSupport.validateClaims(claims, clientID:"oaiapp_fixture", nonce:"nonce", expectedSubject:"alice")
        for (field, bad) in [("iss","https://attacker.invalid"),("aud","other"),("nonce","wrong"),("sub","bob")] {
            var changed = claims; changed[field] = bad
            try rejects("invalid \(field) accepted") { _ = try OAuthSupport.validateClaims(changed, clientID:"oaiapp_fixture", nonce:"nonce", expectedSubject:"alice") }
        }
        var expired = claims; expired["exp"] = 1
        try rejects("expired identity accepted") { _ = try OAuthSupport.validateClaims(expired, clientID:"oaiapp_fixture", nonce:"nonce", expectedSubject:nil) }
        // A real RSA signature proves the JWK-to-SecKey bridge, not only claim checks.
        let key=SecKeyCreateRandomKey([kSecAttrKeyType:kSecAttrKeyTypeRSA,kSecAttrKeySizeInBits:2048] as CFDictionary,nil)!
        let publicDER=SecKeyCopyExternalRepresentation(SecKeyCopyPublicKey(key)!,nil)! as Data
        var offset=0
        func tlv() throws -> Data {
            guard offset+2<=publicDER.count else {throw CheckFailure(message:"DER fixture")}
            offset+=1;var length=Int(publicDER[offset]);offset+=1
            if length>127 {let count=length&127;length=0;for _ in 0..<count {length=(length<<8)|Int(publicDER[offset]);offset+=1}}
            guard offset+length<=publicDER.count else {throw CheckFailure(message:"DER length")}
            let value=publicDER.subdata(in:offset..<offset+length);offset+=length;return value
        }
        _=try tlv(); offset=publicDER.count>256 ? 4 : 3
        var modulus=try tlv();if modulus.first==0 {modulus.removeFirst()};let exponent=try tlv()
        let jwks=try JSONSerialization.data(withJSONObject:["keys":[["kid":"fixture","kty":"RSA","alg":"RS256","use":"sig","n":OAuthSupport.base64(modulus),"e":OAuthSupport.base64(exponent)]]])
        let header=OAuthSupport.base64(Data(#"{"alg":"RS256","kid":"fixture"}"#.utf8)), payload=OAuthSupport.base64(try JSONSerialization.data(withJSONObject:claims))
        let message=Data((header+"."+payload).utf8)
        let signature=SecKeyCreateSignature(key,.rsaSignatureMessagePKCS1v15SHA256,message as CFData,nil)! as Data
        let jwt=header+"."+payload+"."+OAuthSupport.base64(signature)
        _=try OAuthSupport.validateID(jwt,jwks:jwks,clientID:"oaiapp_fixture",nonce:"nonce",expectedSubject:"alice")
        try rejects("tampered signature accepted") {_=try OAuthSupport.validateID(header+"."+payload+"."+OAuthSupport.base64(Data(repeating:0,count:signature.count)),jwks:jwks,clientID:"oaiapp_fixture",nonce:"nonce",expectedSubject:nil)}
        // Catches incompatible import, path traversal, permission regression and signout deleting registration.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("FirstStepAI-check-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try CredentialStore(directory:directory)
        let id = "account-0123456789abcdef01234567"
        let record = try JSONDecoder().decode(CredentialRecord.self, from:fixture())
        try store.save(record, id:id)
        let loaded = try store.read(id)
        try check(loaded.clientID == "oaiapp_fixture", "import client mismatch")
        try check(loaded.authorized, "import unexpectedly unauthorized")
        let service = ChatGPTService(directory:directory)
        let accounts = try await service.accounts()
        try check(accounts.count == 1 && accounts[0].id == id && accounts[0].label.contains("234567"), "stable registration label")
        let attrs = try FileManager.default.attributesOfItem(atPath:directory.appendingPathComponent(id + ".json").path)
        try check((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600, "credential mode")
        let dirAttrs = try FileManager.default.attributesOfItem(atPath:directory.path)
        try check((dirAttrs[.posixPermissions] as? NSNumber)?.intValue == 0o700, "directory mode")
        try rejects("path traversal allowed") { _ = try store.read("../host") }
        var signedOut = loaded; signedOut.clearTokens(); try store.save(signedOut, id:id)
        let retained = try store.read(id)
        try check(!retained.authorized && retained.clientID == loaded.clientID && retained.hostID == loaded.hostID, "signout registration retention")
        let badScopes = try JSONDecoder().decode(CredentialRecord.self, from:fixture(["scope":"openid","scopes":["openid"]]))
        try check(!badScopes.authorized, "identity scope enabled inference")
        // Cancel while a rotating refresh is in flight. The next operation must use
        // the saved replacement, and simultaneous requests must not refresh twice.
        let expiredRecord=try JSONDecoder().decode(CredentialRecord.self,from:fixture(["saved_at":"2000-01-01T00:00:00.000Z"]))
        try store.save(expiredRecord,id:id)
        let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[RefreshProtocol.self]
        let mockSession=URLSession(configuration:config)
        let mockService=ChatGPTService(directory:directory,session:mockSession)
        let cancelled=Task {try await mockService.models(accountID:id)}
        while RefreshProtocol.count()==0 {try await Task.sleep(nanoseconds:1_000_000)}
        cancelled.cancel()
        do {_=try await cancelled.value;throw CheckFailure(message:"cancelled request succeeded")} catch let error as CheckFailure {throw error} catch {}
        let rotated=try store.read(id)
        try check(rotated.refreshToken=="rotated-refresh","cancellation lost rotating refresh token")
        let recoveredModels=try await mockService.models(accountID:id)
        try check(recoveredModels.first?.id=="test-model","saved refresh did not recover")
        try store.save(expiredRecord,id:id)
        async let first=mockService.models(accountID:id)
        async let second=mockService.models(accountID:id)
        _=try await (first,second)
        try check(RefreshProtocol.count()==2,"concurrent requests refreshed the same token twice")
        let wrapped=String(repeating:"问",count:16000)+"元数据日期"
        let wireAnswer=try await mockService.respond(accountID:id,model:"test-model",instructions:"fixture",messages:[AIMessage(role:"user",content:wrapped)])
        try check(wireAnswer=="mock-complete","semantic history plus metadata rejected by wire limit")
        do {
            _=try await mockService.respond(accountID:id,model:"test-model",instructions:"fixture",messages:[AIMessage(role:"user",content:String(repeating:"x",count:20001))])
            throw CheckFailure(message:"unbounded wire content accepted")
        } catch let error as CheckFailure {throw error} catch {}
        mockSession.invalidateAndCancel()
        let callbackServer=CallbackServer(state:"server-state")
        let callbackURL=try await callbackServer.start()
        let callbackTask=Task {try await callbackServer.wait()}
        var components=URLComponents(url:callbackURL,resolvingAgainstBaseURL:false)!
        components.queryItems=[URLQueryItem(name:"state",value:"server-state"),URLQueryItem(name:"code",value:"fixture-code"),URLQueryItem(name:"client_id",value:"fixture-client")]
        let (_,http)=try await URLSession.shared.data(from:components.url!)
        try check((http as? HTTPURLResponse)?.statusCode==200,"loopback listener not reachable")
        let returned=try await callbackTask.value
        try check(returned.port==callbackURL.port,"loopback callback changed port")
        print("ChatGPT checks passed: SSE, catalog, PKCE/callback, identity, credentials")
    }
}

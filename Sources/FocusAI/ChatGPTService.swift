import Foundation

public actor ChatGPTService {
    private let directory:URL
    private let session:URLSession
    private struct Pending {
        let server:CallbackServer, state:String, nonce:String, verifier:String, redirect:URL, hostID:String
        let accountID:String?, record:CredentialRecord?
        let generation:UUID
    }
    private var pending:Pending?
    private var starting=false
    private var completing=false
    public init(directory:URL) {
        self.directory=directory
        let config=URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest=90;config.timeoutIntervalForResource=180
        config.urlCache=nil;config.httpCookieStorage=nil
        session=URLSession(configuration:config)
    }
    init(directory:URL,session:URLSession) {self.directory=directory;self.session=session}
    public func accounts() throws -> [ChatGPTAccount] {try CredentialStore(directory:directory).accounts()}
    public func models(accountID:String) async throws -> [ChatGPTModel] {
        do {
            let token=try await accessToken(accountID)
            var request=URLRequest(url:URL(string:"https://api.openai.com/v1/models")!)
            request.setValue("Bearer \(token)",forHTTPHeaderField:"Authorization")
            return try ChatGPTModel.decodeCatalog(await data(request))
        } catch {throw ChatGPTError.sanitized(error)}
    }
    public func respond(accountID:String,model:String,instructions:String,messages:[AIMessage]) async throws -> String {
        do {
            guard !model.isEmpty,!instructions.isEmpty,!messages.isEmpty,messages.count<=12,messages.allSatisfy({["user","assistant"].contains($0.role) && $0.content.count<=16000}) else {throw ChatGPTError.invalidResponse}
            let token=try await accessToken(accountID)
            var request=URLRequest(url:URL(string:"https://api.openai.com/v1/responses")!)
            request.httpMethod="POST";request.setValue("Bearer \(token)",forHTTPHeaderField:"Authorization");request.setValue("application/json",forHTTPHeaderField:"Content-Type")
            request.httpBody=try JSONSerialization.data(withJSONObject:["model":model,"store":false,"stream":true,"instructions":instructions,"input":messages.map {["role":$0.role,"content":$0.content]}])
            let (bytes,response)=try await session.bytes(for:request)
            guard let http=response as? HTTPURLResponse else {throw ChatGPTError.invalidResponse}
            if http.statusCode != 200 {
                var body=Data();for try await byte in bytes {body.append(byte);if body.count>=65536 {break}}
                throw ChatGPTError.response(status:http.statusCode,data:body)
            }
            var parser=ResponseStreamParser(),chunk=Data()
            for try await byte in bytes {
                try Task.checkCancellation();chunk.append(byte)
                if byte==10 || chunk.count>=4096 {try parser.append(chunk);chunk.removeAll(keepingCapacity:true)}
            }
            if !chunk.isEmpty {try parser.append(chunk)}
            try Task.checkCancellation()
            return try parser.finish()
        } catch {throw ChatGPTError.sanitized(error)}
    }
    public func beginSignIn(accountID:String? = nil) async throws -> URL {
        guard pending==nil,!starting else {throw ChatGPTError.signInBusy}
        starting=true;defer {starting=false}
        let store=try CredentialStore(directory:directory)
        let lock=try await store.lock()
        let record=try accountID.map {try store.read($0)}
        let host=try store.hostID()
        withExtendedLifetime(lock) {}
        let state=try OAuthSupport.random(),nonce=try OAuthSupport.random(),verifier=try OAuthSupport.random()
        let server=CallbackServer(state:state)
        do {
            let redirect=try await server.start()
            try Task.checkCancellation()
            let attempt=Pending(server:server,state:state,nonce:nonce,verifier:verifier,redirect:redirect,hostID:host,accountID:accountID,record:record,generation:UUID())
            var values=["client_id":record?.clientID ?? "dynamic_agent_client","ext_agent_host_id":host,"response_type":"code","redirect_uri":redirect.absoluteString,"scope":"openid profile email offline_access resource.invoke chatgpt.tokens.use.direct","resource":"https://api.openai.com/v1","state":state,"nonce":nonce,"code_challenge_method":"S256","code_challenge":OAuthSupport.challenge(verifier)]
            if let record {if let hint=record.idToken {values["id_token_hint"]=hint};if let email=record.email {values["login_hint"]=email}}
            else {values["agent_name_hint"]="先做一刻"}
            var components=URLComponents(string:OAuthSupport.issuer+"/api/accounts/authorize")!
            components.queryItems=values.sorted {$0.key<$1.key}.map {URLQueryItem(name:$0.key,value:$0.value)}
            pending=attempt
            return components.url!
        } catch {server.cancel();throw ChatGPTError.sanitized(error)}
    }
    public func completeSignIn() async throws -> ChatGPTAccount {
        guard let attempt=pending,!completing else {throw ChatGPTError.signInRequired}
        completing=true
        defer {completing=false;if pending?.generation==attempt.generation {pending=nil};attempt.server.cancel()}
        do {
            let url=try await attempt.server.wait()
            let callback=try OAuthSupport.callback(url,state:attempt.state,clientID:attempt.record?.clientID)
            let raw=try await tokenRequest(["grant_type":"authorization_code","client_id":callback.clientID,"code":callback.code,"code_verifier":attempt.verifier,"redirect_uri":attempt.redirect.absoluteString,"resource":"https://api.openai.com/v1"])
            guard let object=try JSONSerialization.jsonObject(with:raw) as? [String:Any],let idToken=object["id_token"] as? String else {throw ChatGPTError.invalidIdentity}
            let jwks=try await data(URLRequest(url:URL(string:OAuthSupport.issuer+"/.well-known/jwks.json")!))
            let claims=try OAuthSupport.validateID(idToken,jwks:jwks,clientID:callback.clientID,nonce:attempt.nonce,expectedSubject:attempt.record?.subject)
            var record=CredentialRecord(email:claims["email"] as? String,issuer:OAuthSupport.issuer,subject:claims["sub"] as! String,clientID:callback.clientID,hostID:attempt.hostID)
            try applyTokens(raw,to:&record)
            guard record.authorized else {throw ChatGPTError.permissionMissing}
            try Task.checkCancellation()
            guard pending?.generation==attempt.generation else {throw ChatGPTError.cancelled}
            let store=try CredentialStore(directory:directory),lock=try await store.lock()
            let id=attempt.accountID ?? record.stableID
            try Task.checkCancellation()
            guard pending?.generation==attempt.generation else {throw ChatGPTError.cancelled}
            try store.save(record,id:id)
            withExtendedLifetime(lock) {}
            return record.account(id:id)
        } catch {throw ChatGPTError.sanitized(error)}
    }
    public func cancelSignIn() {pending?.server.cancel();pending=nil}
    public func signOut(accountID:String) async throws {
        let store=try CredentialStore(directory:directory),lock=try await store.lock()
        defer {withExtendedLifetime(lock) {}}
        var record=try store.read(accountID)
        var confirmed=true
        if let refresh=record.refreshToken {
            do {
                let config=try await data(URLRequest(url:URL(string:OAuthSupport.issuer+"/.well-known/openid-configuration")!))
                guard let endpoint=(try JSONSerialization.jsonObject(with:config) as? [String:Any])?["revocation_endpoint"] as? String,let url=URL(string:endpoint),url.scheme=="https",url.host=="auth.openai.com" else {throw ChatGPTError.invalidResponse}
                var request=URLRequest(url:url);request.httpMethod="POST";request.setValue("application/x-www-form-urlencoded",forHTTPHeaderField:"Content-Type")
                request.httpBody=OAuthSupport.form(["token":refresh,"token_type_hint":"refresh_token","client_id":record.clientID])
                _=try await data(request)
            } catch {confirmed=false}
        }
        record.clearTokens();try store.save(record,id:accountID)
        if !confirmed {throw ChatGPTError.remoteRevocationUnconfirmed}
    }
    private func accessToken(_ accountID:String) async throws -> String {
        let store=try CredentialStore(directory:directory),lock=try await store.lock()
        defer {withExtendedLifetime(lock) {}}
        var record=try store.read(accountID)
        guard record.authorized else {throw ChatGPTError.signInRequired}
        if let expiry=record.expiresAt,expiry.timeIntervalSinceNow>60 {return record.accessToken!}
        guard let refresh=record.refreshToken,!refresh.isEmpty else {throw ChatGPTError.unauthorized}
        if let earliest=record.earliestRefreshAt,earliest.date>Date() {
            if let expiry=record.expiresAt,expiry>Date() {return record.accessToken!}
            throw ChatGPTError.refreshNotReady
        }
        // Refresh tokens rotate. Finish and persist an in-flight refresh even if the UI
        // cancels the answer request, or its next attempt could reuse a spent token.
        let fields=["grant_type":"refresh_token","client_id":record.clientID,"refresh_token":refresh,"resource":"https://api.openai.com/v1"]
        let refreshTask=Task {try await self.tokenRequest(fields)}
        let raw=try await refreshTask.value
        try applyTokens(raw,to:&record)
        guard record.authorized else {throw ChatGPTError.permissionMissing}
        // Persist rotating token even if cancellation arrives after the server processed refresh.
        try store.save(record,id:accountID)
        try Task.checkCancellation()
        return record.accessToken!
    }
    private func applyTokens(_ data:Data,to record:inout CredentialRecord) throws {
        guard let object=try JSONSerialization.jsonObject(with:data) as? [String:Any],let token=object["access_token"] as? String,!token.isEmpty,
              let type=object["token_type"] as? String,type.lowercased()=="bearer",let seconds=object["expires_in"] as? Double,seconds>0,seconds.isFinite else {throw ChatGPTError.invalidResponse}
        record.accessToken=token;record.tokenType=type;record.expiresIn=seconds
        if let refresh=object["refresh_token"] as? String,!refresh.isEmpty {record.refreshToken=refresh}
        if let idToken=object["id_token"] as? String {record.idToken=idToken}
        if let scope=object["scope"] as? String {record.scope=scope;record.scopes=scope.split(separator:" ").map(String.init)}
        record.savedAt=ISO8601DateFormatter.fractional.string(from:Date())
        record.earliestRefreshAt=nil
        if let seconds=object["earliest_refresh_at"] as? Double {record.earliestRefreshAt=RefreshDate(date:Date(timeIntervalSince1970:seconds))}
        else if let raw=object["earliest_refresh_at"] as? String,let date=ISO8601DateFormatter.parse(raw) {record.earliestRefreshAt=RefreshDate(date:date)}
    }
    private func tokenRequest(_ fields:[String:String]) async throws -> Data {
        var request=URLRequest(url:URL(string:OAuthSupport.issuer+"/api/accounts/oauth/token")!)
        request.httpMethod="POST";request.setValue("application/x-www-form-urlencoded",forHTTPHeaderField:"Content-Type");request.httpBody=OAuthSupport.form(fields)
        return try await data(request)
    }
    private func data(_ request:URLRequest) async throws -> Data {
        let (body,response)=try await session.data(for:request)
        guard body.count<=4*1024*1024,let response=response as? HTTPURLResponse else {throw ChatGPTError.invalidResponse}
        guard (200...299).contains(response.statusCode) else {throw ChatGPTError.response(status:response.statusCode,data:body)}
        return body
    }
}

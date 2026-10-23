import Foundation
import CryptoKit
import Security

enum OAuthSupport {
    static let issuer = "https://auth.openai.com"
    static func random() throws -> String {
        var bytes=[UInt8](repeating:0,count:32)
        guard SecRandomCopyBytes(kSecRandomDefault,bytes.count,&bytes)==errSecSuccess else {throw ChatGPTError.server}
        return base64(Data(bytes))
    }
    static func base64(_ data:Data)->String { data.base64EncodedString().replacingOccurrences(of:"+",with:"-").replacingOccurrences(of:"/",with:"_").replacingOccurrences(of:"=",with:"") }
    static func decode(_ value:String) throws -> Data {
        var s=value.replacingOccurrences(of:"-",with:"+").replacingOccurrences(of:"_",with:"/")
        s += String(repeating:"=",count:(4-s.count%4)%4)
        guard let result=Data(base64Encoded:s) else {throw ChatGPTError.invalidIdentity};return result
    }
    static func challenge(_ verifier:String)->String { base64(Data(SHA256.hash(data:Data(verifier.utf8)))) }
    static func callback(_ url:URL,state:String,clientID:String?) throws -> (code:String,clientID:String) {
        guard url.scheme=="http", url.host=="127.0.0.1",url.path=="/auth/callback",let components=URLComponents(url:url,resolvingAgainstBaseURL:false) else {throw ChatGPTError.invalidCallback}
        let items=components.queryItems ?? []
        guard Set(items.map(\.name)).count==items.count,items.first(where:{$0.name=="state"})?.value==state else {throw ChatGPTError.invalidCallback}
        if items.contains(where:{$0.name=="error"}) {throw ChatGPTError.permissionMissing}
        let issued=items.first(where:{$0.name=="client_id"})?.value ?? clientID
        guard let issued,!issued.isEmpty,issued != "dynamic_agent_client", clientID == nil || issued==clientID,
              let code=items.first(where:{$0.name=="code"})?.value,!code.isEmpty else {throw ChatGPTError.invalidCallback}
        return (code,issued)
    }
    static func validateClaims(_ claims:[String:Any],clientID:String,nonce:String,expectedSubject:String?) throws -> [String:Any] {
        let audience=(claims["aud"] as? [String]) ?? (claims["aud"] as? String).map {[$0]} ?? []
        guard claims["iss"] as? String==issuer, let subject=claims["sub"] as? String,!subject.isEmpty,
              expectedSubject==nil || subject==expectedSubject, audience.contains(clientID),
              audience.count<2 || claims["azp"] as? String==clientID,
              let exp=claims["exp"] as? Double, exp.isFinite,exp>Date().timeIntervalSince1970,
              (claims["nbf"] as? Double ?? 0)<=Date().timeIntervalSince1970+60,
              claims["nonce"] as? String==nonce else {throw ChatGPTError.invalidIdentity}
        return claims
    }
    static func validateID(_ token:String,jwks:Data,clientID:String,nonce:String,expectedSubject:String?) throws -> [String:Any] {
        let parts=token.components(separatedBy:".");guard parts.count==3 else {throw ChatGPTError.invalidIdentity}
        guard let header=try JSONSerialization.jsonObject(with:decode(parts[0])) as? [String:Any],header["alg"] as? String=="RS256",
              let kid=header["kid"] as? String, let keys=(try JSONSerialization.jsonObject(with:jwks) as? [String:Any])?["keys"] as? [[String:Any]],
              let key=keys.first(where:{$0["kid"] as? String==kid && $0["kty"] as? String=="RSA" && ($0["use"] == nil || $0["use"] as? String=="sig") && ($0["alg"] == nil || $0["alg"] as? String=="RS256")}),
              let n=key["n"] as? String,let e=key["e"] as? String else {throw ChatGPTError.invalidIdentity}
        let modulus=try decode(n),exponent=try decode(e)
        guard modulus.count>=256,modulus.count<=1024,exponent.count<=8 else {throw ChatGPTError.invalidIdentity}
        func length(_ n:Int)->Data { if n<128{return Data([UInt8(n)])};var v=n;var bytes=[UInt8]();while v>0 {bytes.insert(UInt8(v&255),at:0);v >>= 8};return Data([0x80|UInt8(bytes.count)]+bytes) }
        func integer(_ value:Data)->Data {var bytes=value;while bytes.count>1 && bytes.first==0 {bytes.removeFirst()};if (bytes.first ?? 0)&0x80 != 0 {bytes.insert(0,at:0)};return Data([2])+length(bytes.count)+bytes}
        let content=integer(modulus)+integer(exponent),der=Data([0x30])+length(content.count)+content
        let attributes:[CFString:Any]=[kSecAttrKeyType:kSecAttrKeyTypeRSA,kSecAttrKeyClass:kSecAttrKeyClassPublic,kSecAttrKeySizeInBits:modulus.count*8]
        guard let publicKey=SecKeyCreateWithData(der as CFData,attributes as CFDictionary,nil),
              SecKeyVerifySignature(publicKey,.rsaSignatureMessagePKCS1v15SHA256,Data((parts[0]+"."+parts[1]).utf8) as CFData,try decode(parts[2]) as CFData,nil),
              let claims=try JSONSerialization.jsonObject(with:decode(parts[1])) as? [String:Any] else {throw ChatGPTError.invalidIdentity}
        return try validateClaims(claims,clientID:clientID,nonce:nonce,expectedSubject:expectedSubject)
    }
    static func form(_ values:[String:String])->Data {
        var parts=URLComponents();parts.queryItems=values.sorted {$0.key<$1.key}.map {URLQueryItem(name:$0.key,value:$0.value)}
        return Data((parts.percentEncodedQuery ?? "").replacingOccurrences(of:"+",with:"%2B").utf8)
    }
}

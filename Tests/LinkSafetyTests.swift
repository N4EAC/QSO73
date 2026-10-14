import Foundation

@main struct LinkSafetyTests {
    static func main() throws {
        func check(_ b: Bool, _ message: String) { if !b { fatalError(message) } }
        let blocked = ["http://example.com", "javascript:alert(1)", "file:///etc/passwd", "https://user:secret@example.com/", "https://@example.com/", "https://127.0.0.1/", "https://10.0.0.1/", "https://[::1]/", "https://localhost/", "https://radio.local/", "https://radio.localdomain/", "https://example.com:8443/", "https://example.com/%0Dtest", "https://example.com/%09test", "https://xn--fake-123.com/", "https://exa\\mple.com/", "https://example.com\n/evil"]
        for url in blocked { check((try? CheckedLink(url)) == nil, "Unsafe structural URL accepted: \(url)") }
        check(try CheckedLink("https://example.com/path?q=radio#section").host == "example.com", "Public HTTPS hostname")
        check(try CheckedLink("HTTPS://EXAMPLE.COM:443/").host == "example.com", "Scheme/hostname normalization")
        for address: [UInt8] in [[0,0,0,0],[10,1,2,3],[127,0,0,1],[172,16,1,1],[192,168,0,1],[169,254,1,1],[100,64,0,1],[198,18,1,1],[203,0,113,1],[224,0,0,1]] { check(!DNSLinkCheck.publicAddress(address), "Blocked/private IPv4 accepted") }
        check(DNSLinkCheck.publicAddress([93,184,216,34]), "Public IPv4")
        check(!DNSLinkCheck.publicAddress(Array(repeating: 0, count: 16)), "IPv6 unspecified")
        check(!DNSLinkCheck.publicAddress([0x20,1,0x0d,0xb8] + Array(repeating:0,count:12)), "IPv6 documentation")
        var q = DNSLinkCheck.query(host: "example.com", type: 1)
        if CommandLine.arguments.count > 1 { try q.write(to: URL(fileURLWithPath: CommandLine.arguments[1])) }
        var answer = Array(q); answer[2] = 0x81; answer[3] = 0x80; answer[7] = 1
        answer += [0xc0,0x0c,0,1,0,1,0,0,0,60,0,4,93,184,216,34]
        check(try DNSLinkCheck.response(Data(answer), host: "example.com", type: 1), "Compressed DNS public answer")
        var denied=answer; denied.replaceSubrange((denied.count-4)..<denied.count, with: [0,0,0,0])
        check((try? DNSLinkCheck.response(Data(denied), host: "example.com", type: 1)) == nil, "Malware block answer")
        var nx=Array(q); nx[2]=0x81; nx[3]=0x83
        check((try? DNSLinkCheck.response(Data(nx), host: "example.com", type: 1)) == nil, "NXDOMAIN cannot be treated as safe")
        q[2]=0x81; q[3]=0x80
        check(try !DNSLinkCheck.response(q, host: "example.com", type: 1), "Empty A result")
        for size in 0..<answer.count { check((try? DNSLinkCheck.response(Data(answer.prefix(size)), host: "example.com", type: 1)) == nil, "Truncated response accepted") }
        check((try? DNSLinkCheck.response(Data(answer), host: "different.com", type: 1)) == nil, "Wrong DNS question accepted")
        var loop=answer; loop[12]=0xc0; loop[13]=12
        check((try? DNSLinkCheck.response(Data(loop), host: "example.com", type: 1)) == nil, "Compression loop accepted")
        print("PASS: HTTPS policy, private/malware addresses, DNS correlation, compression, malformed replies and fail-closed behavior")
    }
}

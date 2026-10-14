import Foundation
import AppKit
import Combine

struct CheckedLink {
    let url: URL
    let host: String
    init(_ raw: String) throws {
        let lower = raw.lowercased()
        guard raw.utf8.count <= 2048, !raw.contains("\\"), !raw.unicodeScalars.contains(where: { $0.value < 33 || $0.value == 127 }),
              lower.range(of: "%(?:0[0-9a-f]|1[0-9a-f]|7f)", options: .regularExpression) == nil,
              let c = URLComponents(string: raw), c.scheme?.lowercased() == "https", c.user == nil, c.password == nil,
              c.port == nil || c.port == 443, let host = c.host?.lowercased(), let url = c.url else { throw RadioError.invalid("Only HTTPS web links without credentials, control characters or unusual ports can be opened.") }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard host.utf8.count <= 253, labels.count >= 2, !host.contains("xn--"),
              labels.allSatisfy({ !$0.isEmpty && $0.count <= 63 && $0.first != "-" && $0.last != "-" && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") } }),
              labels.last!.count >= 2, labels.last!.allSatisfy({ $0.isLetter }),
              !["local", "localhost", "localdomain", "lan", "internal", "home", "onion", "test", "invalid", "example"].contains(String(labels.last!)) else { throw RadioError.invalid("Local, IP-literal, internationalized and ambiguous hostnames are not opened from radio messages.") }
        self.url = url; self.host = host
    }
}
struct DNSLinkCheck {
    static func query(host: String, type: UInt16) -> Data {
        var bytes: [UInt8] = [0x73, 0x51, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0]
        for label in host.split(separator: ".") { bytes.append(UInt8(label.utf8.count)); bytes += label.utf8 }
        bytes += [0, UInt8(type >> 8), UInt8(type & 255), 0, 1]; return Data(bytes)
    }
    static func publicAddress(_ b: [UInt8]) -> Bool {
        if b.count == 4 {
            return !(b[0] == 0 || b[0] == 10 || b[0] == 127 || b[0] >= 224 ||
                (b[0] == 100 && (64...127).contains(b[1])) || (b[0] == 169 && b[1] == 254) ||
                (b[0] == 172 && (16...31).contains(b[1])) || (b[0] == 192 && (b[1] == 168 || (b[1] == 0 && (b[2] == 0 || b[2] == 2)))) ||
                (b[0] == 198 && (b[1] == 18 || b[1] == 19 || (b[1] == 51 && b[2] == 100))) ||
                (b[0] == 203 && b[1] == 0 && b[2] == 113))
        }
        if b.count == 16 { return b[0] & 0xe0 == 0x20 && !(b[0] == 0x20 && b[1] == 2) && !(b[0...3] == [0x20, 1, 0x0d, 0xb8] || b[0...3] == [0x20, 1, 0, 0]) }
        return false
    }
    static func response(_ data: Data, host: String, type: UInt16) throws -> Bool {
        let b = Array(data)
        func invalid() -> RadioError { .invalid("Domain blocked, unresolvable, or security reply invalid. Link not opened.") }
        func word(_ p: Int) throws -> Int { guard p >= 0, p + 2 <= b.count else { throw invalid() }; return Int(b[p]) << 8 | Int(b[p + 1]) }
        func name(_ start: inout Int) throws -> String {
            var p = start, end: Int? = nil, seen = Set<Int>(), labels: [String] = []
            for _ in 0..<64 {
                guard p < b.count, seen.insert(p).inserted else { throw invalid() }
                let n = Int(b[p]); p += 1
                if n == 0 { start = end ?? p; return labels.joined(separator: ".").lowercased() }
                if n & 0xc0 == 0xc0 {
                    guard p < b.count else { throw invalid() }
                    if end == nil { end = p + 1 }; p = (n & 0x3f) << 8 | Int(b[p]); continue
                }
                guard n <= 63, p + n <= b.count, b[p..<p+n].allSatisfy({ $0 >= 33 && $0 < 127 }) else { throw invalid() }
                labels.append(String(decoding: b[p..<p+n], as: UTF8.self)); p += n
            }
            throw invalid()
        }
        guard b.count >= 12, b.count <= 4096, try word(0) == 0x7351,
              try word(2) & 0x8000 != 0, try word(2) & 0x020f == 0,
              try word(4) == 1, try word(6) <= 64 else { throw invalid() }
        var p = 12
        guard try name(&p) == host, try word(p) == Int(type), try word(p + 2) == 1 else { throw invalid() }; p += 4
        var found = false
        for _ in 0..<(try word(6)) {
            _ = try name(&p)
            let t = try word(p), cls = try word(p + 2), length = try word(p + 8); p += 10
            guard p + length <= b.count else { throw invalid() }
            if cls == 1 && (t == 1 || t == 28) {
                guard length == (t == 1 ? 4 : 16), publicAddress(Array(b[p..<p+length])) else { throw invalid() }; found = true
            }
            p += length
        }
        return found
    }
    static func check(_ link: CheckedLink) async throws {
        let config = URLSessionConfiguration.ephemeral; config.timeoutIntervalForRequest = 5; config.timeoutIntervalForResource = 12
        config.httpShouldSetCookies = false; config.urlCache = nil
        let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
        for endpoint in ["https://security.cloudflare-dns.com/dns-query", "https://dns.quad9.net/dns-query"] {
            var resolved = false
            for type: UInt16 in [1, 28] {
                try Task.checkCancellation()
                let question = query(host: link.host, type: type).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
                var request = URLRequest(url: URL(string: endpoint + "?dns=" + question)!); request.setValue("application/dns-message", forHTTPHeaderField: "Accept")
                let data: Data, response: URLResponse
                do { (data, response) = try await session.data(for: request) }
                catch let error as URLError where [.networkConnectionLost, .cannotConnectToHost, .timedOut].contains(error.code) {
                    try Task.checkCancellation()
                    // Same provider, official IPv4 HTTPS endpoint; TLS validation stays on.
                    if endpoint.contains("dns.quad9.net") {
                        request.url = URL(string: "https://9.9.9.9/dns-query?dns=" + question)
                    }
                    (data, response) = try await session.data(for: request)
                }
                guard let http = response as? HTTPURLResponse, http.statusCode == 200, http.value(forHTTPHeaderField: "Content-Type")?.lowercased().hasPrefix("application/dns-message") == true else { throw RadioError.invalid("Online security check unavailable. Link not opened.") }
                let result = try self.response(data, host: link.host, type: type); resolved = resolved || result
            }
            guard resolved else { throw RadioError.invalid("Security service could not resolve the domain. Link not opened.") }
        }
    }
}
@MainActor final class ChatLinkSafety: ObservableObject {
    @Published var checking = false
    @Published var host = ""
    @Published var warning: String? = nil
    private var task: Task<Void, Never>?
    private var generation = UUID()
    func cancel() { generation = UUID(); task?.cancel(); task = nil; checking = false }
    func open(_ url: URL) {
        cancel(); warning = nil
        do {
            let link = try CheckedLink(url.absoluteString); host = link.host; checking = true; let token = generation
            task = Task { [weak self] in
                do {
                    try await DNSLinkCheck.check(link)
                    guard let self, token == self.generation, !Task.isCancelled else { return }
                    self.checking = false
                    if !NSWorkspace.shared.open(link.url) { self.warning = "Could not open your default browser." }
                } catch {
                    guard let self, token == self.generation, !Task.isCancelled else { return }
                    self.checking = false; self.warning = error.localizedDescription
                }
            }
        } catch { warning = error.localizedDescription }
    }
}

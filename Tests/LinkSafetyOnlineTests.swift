import Foundation
@main struct LinkSafetyOnlineTests {
    static func main() async throws {
        try await DNSLinkCheck.check(CheckedLink("https://example.com/"))
        print("PASS: live Cloudflare and Quad9 A/AAAA reputation checks; no browser opened or target page fetched")
        do {
            try await DNSLinkCheck.check(CheckedLink("https://malware.testcategory.com/"))
            fatalError("Official malware-test hostname was permitted")
        } catch let error as RadioError {
            guard error.localizedDescription.contains("Domain blocked") else { throw error }
            print("PASS: live official malware-test hostname denied by security resolver; no target page fetched")
        }
    }
}

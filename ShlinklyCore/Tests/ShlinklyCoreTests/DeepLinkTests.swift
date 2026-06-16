import Foundation
import Testing
@testable import ShlinklyCore

struct DeepLinkTests {
    @Test("Parses shlinkly://link/{shortCode} into .linkDetail")
    func parsesLinkDetail() throws {
        let url = try #require(URL(string: "shlinkly://link/abc123"))
        #expect(DeepLink.parse(url) == .linkDetail(shortCode: "abc123"))
    }

    @Test("Scheme and host match case-insensitively; short code keeps its case")
    func caseInsensitiveSchemeHost() throws {
        let url = try #require(URL(string: "SHLINKLY://LINK/AbC123"))
        #expect(DeepLink.parse(url) == .linkDetail(shortCode: "AbC123"))
    }

    @Test("A foreign scheme is rejected")
    func foreignScheme() throws {
        let url = try #require(URL(string: "https://example.com/abc123"))
        #expect(DeepLink.parse(url) == nil)
    }

    @Test("The wrong host is rejected")
    func wrongHost() throws {
        let url = try #require(URL(string: "shlinkly://settings/abc123"))
        #expect(DeepLink.parse(url) == nil)
    }

    @Test("A missing short code is rejected")
    func missingShortCode() throws {
        #expect(DeepLink.parse(try #require(URL(string: "shlinkly://link"))) == nil)
        #expect(DeepLink.parse(try #require(URL(string: "shlinkly://link/"))) == nil)
    }

    @Test("Junk input is rejected")
    func junk() throws {
        #expect(DeepLink.parse(try #require(URL(string: "garbage"))) == nil)
    }
}

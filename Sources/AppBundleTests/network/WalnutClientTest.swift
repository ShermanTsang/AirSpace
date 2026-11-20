@testable import AppBundle
import Foundation
import Testing

@Suite
struct WalnutClientTest {
    @Test func decodesReleaseCheckPayloadFromGateway() throws {
        let json = """
            {"available":true,"release_id":"r1","title":"AirSpace 1.2.0","version":"1.2.0","version_code":1002000,\
            "release_channel":"stable","release_note":"Notes","force_update":true,"published_at":1795194207,\
            "artifacts":[{"platform":"macos","arch":"universal","package_type":"app","filename":"AirSpace.zip",\
            "github_url":"https://example.com/AirSpace.zip"}]}
            """
        let response = try WalnutClient.makeDecoder()
            .decode(WalnutClient.ReleaseCheckResponse.self, from: Data(json.utf8))

        #expect(response.isAvailable)
        #expect(response.version == "1.2.0")
        #expect(response.versionCode == 1_002_000)
        #expect(response.releaseChannel == "stable")
        #expect(response.forceUpdate == true)
        #expect(response.artifacts?.first?.packageType == "app")
        #expect(response.downloadURL?.absoluteString == "https://example.com/AirSpace.zip")
    }

    @Test func decodesContactChannelFromGateway() throws {
        let json = """
            {"list":[{"id":"1","code":"github-issues","scene":"customer_service","scene_name":"Customer Support",\
            "channel_type":"url","channel_type_name":"Website","name":"GitHub Issues",\
            "link_url":"https://github.com/ShermanTsang/AirSpace/issues","image_url":"","expire_at":0,\
            "updated_at":1795194207,"actions":["open","copy_link"]}]}
            """
        let response = try WalnutClient.makeDecoder()
            .decode(WalnutClient.ContactsResponse.self, from: Data(json.utf8))
        let channel = try #require(response.items.first)

        #expect(channel.channelType == "url")
        #expect(channel.sceneName == "Customer Support")
        #expect(channel.linkUrl == "https://github.com/ShermanTsang/AirSpace/issues")
        #expect(channel.effectiveActions == ["open", "copy_link"])
        #expect(channel.openURL?.absoluteString == "https://github.com/ShermanTsang/AirSpace/issues")
    }

    @Test func decodesDocListFromGateway() throws {
        let json = """
            {"list":[{"id":"bf9ee11f-5df6-4a0d-b09b-eaff2716d677","slug":"getting-started",\
            "type_id":"196f23cc-86b6-4a30-ad8b-0d5b0b9862cc","name":"Getting Started","description":"Docs",\
            "cover_image":"","created_at":1795194214,"updated_at":1795194214,"parent_id":"","order":0}],"total":1}
            """
        let response = try WalnutClient.makeDecoder()
            .decode(WalnutClient.DocsResponse.self, from: Data(json.utf8))
        let doc = try #require(response.items.first)

        #expect(doc.slug == "getting-started")
        #expect(doc.typeId == "196f23cc-86b6-4a30-ad8b-0d5b0b9862cc")
        #expect(doc.parentId == "")
        #expect(doc.order == 0)
    }

    @Test func decodesCamelCaseErrorPayload() throws {
        let json = """
            {"message":"Not found","code":"app_not_found","errorType":"client","detail":"detail",\
            "sourceService":"portal","sourceComponent":"gateway"}
            """
        let payload = try WalnutClient.makeDecoder()
            .decode(WalnutErrorPayload.self, from: Data(json.utf8))

        #expect(payload.message == "Not found")
        #expect(payload.errorType == "client")
        #expect(payload.sourceService == "portal")
    }

    @Test func versionCodeMatchesManifestConvention() {
        #expect(WalnutVersion.code(from: "1.2.3") == 1_002_003)
        #expect(WalnutVersion.code(from: "1.2") == 1_002_000)
        #expect(WalnutVersion.code(from: "0.0.0-SNAPSHOT") == 0)
        #expect(WalnutVersion.code(from: "2.1000.1000") == 2_999_999)
    }
}

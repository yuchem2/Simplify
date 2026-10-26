import Testing
@testable import SimplifyKit

struct AppGroupTests {
    @Test func teamPrefixedIdentifierIsUsed() {
        #expect(AppGroup.identifier(from: "ABCDE12345.dev.yoom.simplify") == "ABCDE12345.dev.yoom.simplify")
    }

    @Test func unsignedBuildHasNoGroup() {
        #expect(AppGroup.identifier(from: "dev.yoom.simplify") == nil)
        #expect(AppGroup.identifier(from: "") == nil)
        #expect(AppGroup.identifier(from: nil) == nil)
    }
}

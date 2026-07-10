import Testing
import Foundation
@testable import RootOutCore

@Test func leftoverKindsExist() {
    #expect(!LeftoverKind.allCases.isEmpty)
}

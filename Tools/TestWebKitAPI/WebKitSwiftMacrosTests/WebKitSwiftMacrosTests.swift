//
//  WebKitSwiftMacrosTests.swift
//  WebKitSwiftMacrosTests
//
//  Created by Richard Robinson on 6/19/25.
//

import Testing
import SwiftParser
import SwiftSyntax
import SwiftSyntaxMacros
import SwiftSyntaxMacroExpansion
import WebKit
import WebKitSwiftMacros
import SwiftOperators

struct WebKitSwiftMacrosTests {

    @Test func validURLExpansion() async throws {
        let source: SourceFileSyntax = """
            let url = #url("https://www.apple.com")
            """

        let file = BasicMacroExpansionContext.KnownSourceFile(
            moduleName: "MyModule",
            fullFilePath: "test.swift"
        )

        let context = BasicMacroExpansionContext(sourceFiles: [source: file])

        let transformedSF = source.expand(
            macros: ["url": MyMacro.self],
            in: context
        )

        let expectedDescription = """
            let url = URL(string: "https://www.apple.com")!
            """

        #expect(transformedSF.description == expectedDescription)
    }
}

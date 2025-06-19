import SwiftSyntax
import SwiftSyntaxMacros
internal import Foundation

public struct MyMacro: ExpressionMacro, Sendable {
    enum Error: Swift.Error, CustomStringConvertible {
        case invalidParameterType
        case invalidURL(String)

        var description: String {
            switch self {
            case .invalidParameterType:
                "This macro requires a StaticString"

            case let .invalidURL(url):
                "The url \(url) is invalid"
            }
        }
    }

    public static func expansion(of node: some FreestandingMacroExpansionSyntax, in context: some MacroExpansionContext) throws -> ExprSyntax {
        guard let argument = node.arguments.first?.expression,
              let segments = argument.as(StringLiteralExprSyntax.self)?.segments
        else {
            throw Error.invalidParameterType
        }

        guard let _ = URL(string: segments.description) else {
            throw Error.invalidURL("\(argument)")
        }

        return "URL(string: \(argument))!"
    }
}

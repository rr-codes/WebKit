// Copyright (C) 2025 Apple Inc. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions
// are met:
// 1. Redistributions of source code must retain the above copyright
//    notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright
//    notice, this list of conditions and the following disclaimer in the
//    documentation and/or other materials provided with the distribution.
//
// THIS SOFTWARE IS PROVIDED BY APPLE INC. AND ITS CONTRIBUTORS ``AS IS''
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
// THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
// PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL APPLE INC. OR ITS CONTRIBUTORS
// BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
// THE POSSIBILITY OF SUCH DAMAGE.

#if compiler(>=6.2) && ENABLE_CXX_INTEROP

import Testing

private typealias Cxx = SwiftCxxInteropTestbed

extension WTF.String {
    /// Creates a WTF String from an optional Swift String.
    ///
    /// - Parameter string: The Swift String to convert. If this is `nil`, the resulting WTF String will be ``WTF/nullString``.
    public init(_ string: Swift.String?) {
        self = if let string {
            .init(string as NSString)
        } else {
            unsafe WTF.nullString().pointee
        }
    }
}

extension Swift.String {
    /// Creates an optional Swift String from a WTF String.
    ///
    /// - Parameter string: The WTF String to convert. If this is ``WTF/nullString``, the resulting optional Swift String will be `nil`.
    public init?(_ string: WTF.String) {
        guard !string.isNull() else {
            return nil
        }

        self = unsafe string.createNSString().get()
    }
}

extension WTF.String : LosslessStringConvertible {
    public init(_ description: Swift.String) {
        self = .init(description as NSString)
    }

    public var description: Swift.String {
        unsafe self.createNSString().get()
    }
}

extension WTF.String : ExpressibleByStringLiteral {
    public init(stringLiteral: Swift.String) {
        self.init(stringLiteral)
    }
}

@MainActor
struct SwiftCxxInteropTests {
    @Test
    func wtfFunctionCanBeInvokedFromSwift() async throws {
        let function = Cxx.IntBoolFunction { argument in
            argument ? 1 : 0
        }

        let result = Cxx.callIntBoolFunction(true, consuming: function)

        #expect(result == 1)
    }

    @Test
    func wtfCompletionHandlerCanBeInvokedFromSwift() async throws {
        // FIXME: Improve the ergonomics of using this from Swift.

        let result = await withCheckedContinuation { continuation in
            let completionHandler = Cxx.IntCompletionHandler(
                { result in continuation.resume(returning: result)
                },
                WTF.ThreadLikeAssertion(WTF.CurrentThreadLike())
            )

            Cxx.callIntCompletionHandler(3, consuming: completionHandler)
        }

        #expect(result == 3)
    }
}

#endif // compiler(>=6.2) && ENABLE_CXX_INTEROP

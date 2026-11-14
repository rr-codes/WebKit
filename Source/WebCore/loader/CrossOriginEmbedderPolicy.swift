// Copyright (C) 2021 Apple Inc. All rights reserved.
// Copyright (C) 2026 Apple Inc. All rights reserved.
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

// Swift operators import every visible C++ operator of the same name; these modules define reference types that some of
// them name (rdar://192229293).
internal import JavaScriptCore_Private.Cxx.DOMJITCallDOMGetterSnippet
internal import JavaScriptCore_Private.Cxx.Snippet
internal import JavaScriptCore_Private.Cxx.WasmCalleeGroup
internal import JavaScriptCore_Private.Cxx.WasmInstanceAnchor
internal import JavaScriptCore_Private.Cxx.WasmModule
internal import JavaScriptCore_Private.Cxx.WasmModuleDebugInfo
internal import WebCore_Private.Core.CrossOriginEmbedderPolicy
internal import WebCore_Private.Core.CrossOriginEmbedderPolicyValue
internal import WebCore_Private.Core.SecurityPoliciesSwiftTypes
internal import WebCore_Private.HTTPHeaderParsersTypes
internal import wtf.Core.StdLibExtras
internal import wtf.Core.Stopwatch
internal import wtf.Core.text.WTFString

/// The policy that the values of a response's Cross-Origin-Embedder-Policy and
/// Cross-Origin-Embedder-Policy-Report-Only headers give, for obtainCrossOriginEmbedderPolicy() once the context and
/// the settings allow it.
///
/// A null value is an absent header.
@_expose(Cxx)
func crossOriginEmbedderPolicyFromHeaders(
    _ coep: consuming WTF.String,
    _ coepReportOnly: consuming WTF.String
) -> WebCore.CrossOriginEmbedderPolicy {
    var policy = WebCore.CrossOriginEmbedderPolicy()
    // An empty value is not an item, and leaves the policy as it is.
    if !coep.isEmpty() {
        let bytes: Span<UInt8> = WebCore.securityPoliciesSpan8(coep)
        if !bytes.isEmpty {
            crossOriginEmbedderPolicyReadHeader(bytes, reportOnly: false, into: &policy)
        } else {
            let units: Span<UInt16> = coep.checkedSpan16()
            crossOriginEmbedderPolicyReadHeader(units, reportOnly: false, into: &policy)
        }
    }
    if !coepReportOnly.isEmpty() {
        let reportOnlyBytes: Span<UInt8> = WebCore.securityPoliciesSpan8(coepReportOnly)
        if !reportOnlyBytes.isEmpty {
            crossOriginEmbedderPolicyReadHeader(reportOnlyBytes, reportOnly: true, into: &policy)
        } else {
            let reportOnlyUnits: Span<UInt16> = coepReportOnly.checkedSpan16()
            crossOriginEmbedderPolicyReadHeader(reportOnlyUnits, reportOnly: true, into: &policy)
        }
    }
    return policy
}

/// isRecognizedCrossOriginEmbedderPolicyToken() for 8-bit characters.
///
/// `token` is the characters of the caller's `StringView`, whose `String` the caller keeps allocated and unchanged, at
/// their length, for the call. Nothing this function calls writes them, and every Latin-1 code unit is a valid value.
///
/// FIXME: Take the characters as a Span when Swift can receive a std::span safely (rdar://186723514).
@_expose(Cxx)
func isRecognizedCrossOriginEmbedderPolicyToken8(_ token: WebCore.HTTPHeaderLatin1Span) -> Bool {
    let characters = unsafe Span<UInt8>(_unsafeCxxSpan: WTF.bytesOfLatin1Characters(token))
    return crossOriginEmbedderPolicyTokenIsRecognized(characters)
}

/// isRecognizedCrossOriginEmbedderPolicyToken8() for 16-bit characters, which hold for the call in the same way, and
/// every UTF-16 code unit is a valid value.
///
/// FIXME: Take the characters as a Span when Swift can receive a std::span safely (rdar://186723514).
@_expose(Cxx)
func isRecognizedCrossOriginEmbedderPolicyToken16(_ token: WebCore.HTTPHeaderUTF16Span) -> Bool {
    let characters = unsafe Span<UInt16>(_unsafeCxxSpan: token)
    return crossOriginEmbedderPolicyTokenIsRecognized(characters)
}

/// isUnsupportedCrossOriginEmbedderPolicyToken() for 8-bit characters.
///
/// `token` is the characters of the caller's `StringView`, whose `String` the caller keeps allocated and unchanged, at
/// their length, for the call. Nothing this function calls writes them, and every Latin-1 code unit is a valid value.
///
/// FIXME: Take the characters as a Span when Swift can receive a std::span safely (rdar://186723514).
@_expose(Cxx)
func isUnsupportedCrossOriginEmbedderPolicyToken8(_ token: WebCore.HTTPHeaderLatin1Span) -> Bool {
    let characters = unsafe Span<UInt8>(_unsafeCxxSpan: WTF.bytesOfLatin1Characters(token))
    // FIXME: Support credentialless, then treat it as recognized.
    return rfc8941CharactersEqual(characters, "credentialless")
}

/// isUnsupportedCrossOriginEmbedderPolicyToken8() for 16-bit characters, which hold for the call in the same way, and
/// every UTF-16 code unit is a valid value.
///
/// FIXME: Take the characters as a Span when Swift can receive a std::span safely (rdar://186723514).
@_expose(Cxx)
func isUnsupportedCrossOriginEmbedderPolicyToken16(_ token: WebCore.HTTPHeaderUTF16Span) -> Bool {
    let characters = unsafe Span<UInt16>(_unsafeCxxSpan: token)
    return rfc8941CharactersEqual(characters, "credentialless")
}

/// The values CrossOriginEmbedderPolicy::addPolicyHeadersTo() sets for the Cross-Origin-Embedder-Policy and
/// Cross-Origin-Embedder-Policy-Report-Only headers, each null when the header is not set.
@_expose(Cxx)
func crossOriginEmbedderPolicyHeaderValues(
    _ value: WebCore.CrossOriginEmbedderPolicyValue,
    _ reportingEndpoint: consuming WTF.String,
    _ reportOnlyValue: WebCore.CrossOriginEmbedderPolicyValue,
    _ reportOnlyReportingEndpoint: consuming WTF.String
) -> WebCore.SecurityPoliciesPolicyHeaderValues {
    var values = WebCore.SecurityPoliciesPolicyHeaderValues()
    if value != .UnsafeNone {
        values.value = crossOriginEmbedderPolicyHeaderValue(reportingEndpoint)
    }
    if reportOnlyValue != .UnsafeNone {
        values.reportOnlyValue = crossOriginEmbedderPolicyHeaderValue(reportOnlyReportingEndpoint)
    }
    return values
}

// https://html.spec.whatwg.org/multipage/origin.html#obtain-an-embedder-policy: whether the header's item is the
// require-corp token.
func crossOriginEmbedderPolicyRequiresCORP(_ header: borrowing WTF.String) -> Bool {
    // An empty value is not an item.
    if header.isEmpty() {
        return false
    }
    let bytes: Span<UInt8> = WebCore.securityPoliciesSpan8(header)
    if !bytes.isEmpty {
        return crossOriginEmbedderPolicyRequireCORPItem(bytes) != nil
    }
    let units: Span<UInt16> = header.checkedSpan16()
    return crossOriginEmbedderPolicyRequireCORPItem(units) != nil
}

// Sets require-corp and the report-to string that one header gives, the report-only ones for `reportOnly`, and leaves
// the policy as it is unless the header's item is the require-corp token. report-to is only read as a string.
private func crossOriginEmbedderPolicyReadHeader<CodeUnit: HTTPHeaderStringCodeUnit>(
    _ characters: Span<CodeUnit>,
    reportOnly: Bool,
    into policy: inout WebCore.CrossOriginEmbedderPolicy
) {
    guard let item = crossOriginEmbedderPolicyRequireCORPItem(characters) else {
        return
    }
    if reportOnly {
        policy.reportOnlyValue = .RequireCORP
    } else {
        policy.value = .RequireCORP
    }
    guard let reportTo = item.reportTo else {
        return
    }
    if reportOnly {
        policy.reportOnlyReportingEndpoint = structuredFieldStringBody(characters, reportTo.start, reportTo.length, reportTo.integer)
    } else {
        policy.reportingEndpoint = structuredFieldStringBody(characters, reportTo.start, reportTo.length, reportTo.integer)
    }
}

// The header's item when it is the require-corp token.
private func crossOriginEmbedderPolicyRequireCORPItem<CodeUnit: HTTPHeaderStringCodeUnit>(
    _ characters: Span<CodeUnit>
) -> RFC8941PolicyItem? {
    guard let item = rfc8941PolicyItem(characters), item.bareItem.kind == .Token,
        rfc8941TextEquals(characters, item.bareItem, "require-corp")
    else {
        return nil
    }
    return item
}

private func crossOriginEmbedderPolicyTokenIsRecognized<CodeUnit: FixedWidthInteger & UnsignedInteger>(
    _ token: Span<CodeUnit>
) -> Bool {
    rfc8941CharactersEqual(token, "require-corp") || rfc8941CharactersEqual(token, "unsafe-none")
}

// The endpoint is written between the quotes as it is, without escaping.
private func crossOriginEmbedderPolicyHeaderValue(_ reportingEndpoint: borrowing WTF.String) -> WTF.String {
    if reportingEndpoint.isEmpty() {
        return rfc8941TokenString("require-corp")
    }
    return rfc8941TokenWithReportToHeaderValue("require-corp", reportingEndpoint)
}

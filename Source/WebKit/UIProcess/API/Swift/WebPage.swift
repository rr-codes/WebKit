// Copyright (C) 2024 Apple Inc. All rights reserved.
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

#if ENABLE_SWIFTUI && compiler(>=6.0)

import Foundation
import Observation

@_spi(Private)
@MainActor
@Observable
public class WebPage_v0 {
    public let navigations: Navigations

    public var url: URL? {
        backingProperty(\.url, backedBy: \.url)
    }

    public var title: String {
        backingProperty(\.title, backedBy: \.title) { backingValue in
            // The title property is annotated as optional in WKWebView, but is never actually `nil`.
            backingValue!
        }
    }

    public var estimatedProgress: Double {
        backingProperty(\.estimatedProgress, backedBy: \.estimatedProgress)
    }

    public var isLoading: Bool {
        backingProperty(\.isLoading, backedBy: \.isLoading)
    }

    public var serverTrust: SecTrust? {
        backingProperty(\.serverTrust, backedBy: \.serverTrust)
    }

    public var hasOnlySecureContent: Bool {
        backingProperty(\.hasOnlySecureContent, backedBy: \.hasOnlySecureContent)
    }

    @ObservationTracked
    public var mediaType: String? {
        get { backingWebView.mediaType }
        set { backingWebView.mediaType = newValue }
    }

    public var customUserAgent: String? {
        get { backingWebView.customUserAgent }
        set { backingWebView.customUserAgent = newValue }
    }

    public var isInspectable: Bool {
        get { backingWebView.isInspectable }
        set { backingWebView.isInspectable = newValue }
    }

    private let backingNavigationDelegate: WKNavigationDelegateAdapter

    @ObservationIgnored
    private var observations = KeyValueObservations()

    @ObservationIgnored
    @_spi(CrossImportOverlay)
    public var isBoundToWebView = false

    @ObservationIgnored
    @_spi(CrossImportOverlay)
    public lazy var backingWebView: WKWebView = {
        let webView = WKWebView(frame: .zero)
        webView.navigationDelegate = backingNavigationDelegate
        return webView
    }()

    public init() {
        // FIXME: Consider whether we want to have a single value here or if the getter for `navigations` should return a fresh sequence every time.
        let (stream, continuation) = AsyncStream.makeStream(of: NavigationEvent.self)
        navigations = Navigations(source: stream)

        backingNavigationDelegate = WKNavigationDelegateAdapter(navigationProgressContinuation: continuation)
    }

    @discardableResult
    public func load(_ request: URLRequest) -> NavigationID? {
        backingWebView.load(request).map(NavigationID.init(_:))
    }

    @discardableResult
    public func load(htmlString: String, baseURL: URL) -> NavigationID? {
        backingWebView.loadHTMLString(htmlString, baseURL: baseURL).map(NavigationID.init(_:))
    }

    private func createObservation<Value, BackingValue>(for keyPath: KeyPath<WebPage_v0, Value>, backedBy backingKeyPath: KeyPath<WKWebView, BackingValue>) -> NSKeyValueObservation {
        return backingWebView.observe(backingKeyPath, options: [.prior, .old, .new]) { [_$observationRegistrar, unowned self] _, change in
            if change.isPrior {
                _$observationRegistrar.willSet(self, keyPath: keyPath)
            } else {
                _$observationRegistrar.didSet(self, keyPath: keyPath)
            }
        }
    }

    @_spi(CrossImportOverlay)
    public func backingProperty<Value, BackingValue>(_ keyPath: KeyPath<WebPage_v0, Value>, backedBy backingKeyPath: KeyPath<WKWebView, BackingValue>, _ transform: (BackingValue) -> Value) -> Value {
        if observations.contents[keyPath] == nil {
            observations.contents[keyPath] = createObservation(for: keyPath, backedBy: backingKeyPath)
        }

        self.access(keyPath: keyPath)

        let backingValue = backingWebView[keyPath: backingKeyPath]
        return transform(backingValue)
    }

    @_spi(CrossImportOverlay)
    public func backingProperty<Value>(_ keyPath: KeyPath<WebPage_v0, Value>, backedBy backingKeyPath: KeyPath<WKWebView, Value>) -> Value {
        backingProperty(keyPath, backedBy: backingKeyPath) { $0 }
    }
}

extension WebPage_v0 {
    private struct KeyValueObservations: ~Copyable {
        var contents: [PartialKeyPath<WebPage_v0> : NSKeyValueObservation] = [:]

        deinit {
            for (_, observation) in contents {
                observation.invalidate()
            }
        }
    }
}

#endif

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

internal import WebKit_Internal
public import SwiftUI // FIXME: (283455) Do not import SwiftUI in WebKit proper.

#if canImport(UIKit)
fileprivate typealias PlatformView = UIView
#else
fileprivate typealias PlatformView = NSView
#endif

@_spi(Private)
public struct WebView_v0: View {
    public init(_ page: WebPage_v0) {
        self.page = page
    }

    fileprivate let page: WebPage_v0

    public var body: some View {
        WebViewRepresentable(owner: self)
    }
}

fileprivate class WebViewWrapper: PlatformView {
    override var frame: CGRect {
        get {
            super.frame
        }
        set {
            super.frame = newValue
            updateWebViewFrame()
        }
    }

    override var bounds: CGRect {
        get {
            super.bounds
        }
        set {
            super.bounds = newValue
            updateWebViewFrame()
        }
    }

    var webView: WKWebView? = nil {
        willSet {
            webView?.removeFromSuperview()
        }
        didSet {
            guard let webView else {
                return
            }

            addSubview(webView)
            updateWebViewFrame()
        }
    }

    private func updateWebViewFrame() {
        webView?.frame = bounds
    }
}

@MainActor
fileprivate struct WebViewRepresentable {
    let owner: WebView_v0

    @Environment(\.webViewCameraCaptureState) var cameraCaptureState
    @Environment(\.webViewMicrophoneCaptureState) var microphoneCaptureState

    func makePlatformView(context: Context) -> WebViewWrapper {
        // FIXME: Make this more robust by figuring out what happens when a WebPage moves between representables.
        // We can't have multiple owners regardless, but we'll want to decide if it's an error, if we can handle it gracefully, and how deterministic it might even be.
        // Perhaps we should keep an ownership assertion which we can tear down in something like dismantleUIView().

        precondition(!owner.page.isBoundToWebView, "This web page is already bound to another web view.")

        let parent = WebViewWrapper()
        parent.webView = owner.page.backingWebView
        owner.page.isBoundToWebView = true

        context.coordinator.owner = owner.page

        return parent
    }

    func updatePlatformView(_ platformView: WebViewWrapper, context: Context) {
        let webView = owner.page.backingWebView
        let environment = context.environment

        platformView.webView = webView

        webView.allowsBackForwardNavigationGestures = environment.webViewAllowsBackForwardNavigationGestures
        webView.allowsLinkPreview = environment.webViewAllowsLinkPreview

        webView.configuration.preferences.isTextInteractionEnabled = environment.webViewAllowsTextInteraction
        webView.configuration.preferences.tabFocusesLinks = environment.webViewAllowsTabFocusingLinks
        webView.configuration.preferences.isElementFullscreenEnabled = environment.webViewAllowsElementFullscreen

        if let cameraCaptureState = environment.webViewCameraCaptureState, cameraCaptureState.wrappedValue != webView.cameraCaptureState {
            webView.setCameraCaptureState(cameraCaptureState.wrappedValue)
        }

        if let microphoneCaptureState = environment.webViewMicrophoneCaptureState, microphoneCaptureState.wrappedValue != webView.microphoneCaptureState {
            webView.setMicrophoneCaptureState(microphoneCaptureState.wrappedValue)
        }
    }

    func makeCoordinator() -> WebViewCoordinator {
        WebViewCoordinator(cameraCaptureState: cameraCaptureState, microphoneCaptureState: microphoneCaptureState)
    }
}

#if canImport(UIKit)
extension WebViewRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> WebViewWrapper {
        makePlatformView(context: context)
    }

    func updateUIView(_ uiView: WebViewWrapper, context: Context) {
        updatePlatformView(uiView, context: context)
    }
}
#else
extension WebViewRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> WebViewWrapper {
        makePlatformView(context: context)
    }
    
    func updateNSView(_ nsView: WebViewWrapper, context: Context) {
        updatePlatformView(nsView, context: context)
    }
}
#endif

@MainActor
private final class WebViewCoordinator {
    init(cameraCaptureState: Binding<WKMediaCaptureState>?, microphoneCaptureState: Binding<WKMediaCaptureState>?) {
        self.cameraCaptureState = cameraCaptureState
        self.microphoneCaptureState = microphoneCaptureState
    }

    deinit {
        for observation in observations {
            observation.invalidate()
        }
    }

    private var cameraCaptureState: Binding<WKMediaCaptureState>?
    private var microphoneCaptureState: Binding<WKMediaCaptureState>?

    private var observations: Set<NSKeyValueObservation> = []

    weak var owner: WebPage_v0? = nil {
        didSet {
            updateObservations()
        }
    }

    private func createObservation<Value>(
        on webView: WKWebView,
        keyPath: KeyPath<WebViewCoordinator, Binding<Value>?>,
        backedBy backingKeyPath: KeyPath<WKWebView, Value>
    ) -> NSKeyValueObservation where Value: Equatable {
        let boxedKeyPath = UncheckedSendableKeyPathBox(keyPath: keyPath)
        let boxedBackingKeyPath = UncheckedSendableKeyPathBox(keyPath: backingKeyPath)

        return webView.observe(backingKeyPath, options: []) { [weak self] webView, change in
            guard let self else {
                return
            }

            MainActor.assumeIsolated {
                guard self[keyPath: boxedKeyPath.keyPath]?.wrappedValue != webView[keyPath: boxedBackingKeyPath.keyPath] else {
                    return
                }

                self[keyPath: boxedKeyPath.keyPath]?.wrappedValue = webView[keyPath: boxedBackingKeyPath.keyPath]
            }
        }
    }

    private func updateObservations() {
        if let owner {
            observations = [
                createObservation(on: owner.backingWebView, keyPath: \.cameraCaptureState, backedBy: \.cameraCaptureState),
                createObservation(on: owner.backingWebView, keyPath: \.microphoneCaptureState, backedBy: \.microphoneCaptureState),
            ]
        } else {
            for observation in observations {
                observation.invalidate()
            }
            observations = []
        }
    }
}

/// The key path used within `createObservation` must be Sendable.
/// This is safe as long as it is not used for object subscripting and isn't created with captured subscript key paths.
fileprivate struct UncheckedSendableKeyPathBox<Root, Value>: @unchecked Sendable {
    let keyPath: KeyPath<Root, Value>
}

#endif

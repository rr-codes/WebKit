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

#if HAVE_PDFKIT && ENABLE_SWIFTUI

import Foundation

@_spi(CrossImportOverlay) import WebKit
private import TestWebKitAPILibrary
import Testing
private import UniformTypeIdentifiers
private import CoreTransferable

@MainActor
struct PDFSnapshotTests {
    @Test
    func fullContent() async throws {
        let webPage = WebPage()

        let html = """
            <meta name='viewport' content='width=device-width'>
            <body bgcolor=#00ff00>Hello</body>
            """

        try await webPage.load(html: html).wait()

        let pdfSnapshotData = try await webPage.exported(as: .pdf)

        let document = TestPDFDocument(from: pdfSnapshotData)
        #expect(document.pageCount == 1)

        let page = try #require(document.page(at: 0))
        let defaultWebPageSize = CGSize(width: 1024, height: 768)
        #expect(page.bounds == .init(origin: .zero, size: defaultWebPageSize))

        #expect(page.text == "Hello")

        // The entire page should be green. Pick a point in the middle to check.
        #expect(page.color(at: .init(x: 400, y: 300)) == .green)
    }

    @Test
    func subregions() async throws {
        let webPage = WebPage()

        let html = """
            <meta name='viewport' content='width=device-width'>
            <body bgcolor=#00ff00>Hello</body>
            """

        try await webPage.load(html: html).wait()

        // Snapshot a subregion contained entirely within the view
        let pdfSnapshotData = try await webPage.exported(
            as: .pdf(region: .rect(.init(x: 200, y: 150, width: 400, height: 300)))
        )

        let document = TestPDFDocument(from: pdfSnapshotData)
        #expect(document.pageCount == 1)

        let page = try #require(document.page(at: 0))
        #expect(page.bounds == .init(x: 0, y: 0, width: 400, height: 300))

        #expect(page.characterCount == 0)

        // The entire page should be green. Pick a point in the middle to check.
        #expect(page.color(at: .init(x: 200, y: 150)) == .green)
    }

    @Test
    func subregionWithSizeGreaterThanView() async throws {
        let webPage = WebPage()

        let html = """
            <meta name='viewport' content='width=device-width'>
            <body bgcolor=#00ff00>Hello</body>
            """

        try await webPage.load(html: html).wait()

        // Snapshot a region larger than the view
        let pdfSnapshotData = try await webPage.exported(
            as: .pdf(region: .rect(.init(x: 0, y: 0, width: 1200, height: 1200)))
        )

        let document = TestPDFDocument(from: pdfSnapshotData)
        #expect(document.pageCount == 1)

        let page = try #require(document.page(at: 0))
        #expect(page.bounds == .init(x: 0, y: 0, width: 1200, height: 1200))

        // A pixel that was in the view should be green. Pick a point in the middle to check.
        #expect(page.color(at: .init(x: 200, y: 150)) == .green)

        // A pixel that was outside the view should also be green (we extend background color out). Pick a point in the middle to check.
        #expect(page.color(at: .init(x: 900, y: 700)) == .green)
    }

    @Test
    func over200Inches() async throws {
        let webPage = WebPage()
        webPage.backingWebView.frame = .init(x: 0, y: 0, width: 800, height: 29400)

        let html = """
            <meta name='viewport' content='width=device-width'>
            <body bgcolor=#00ff00>Hello</body>
            """

        try await webPage.load(html: html).wait()

        let pdfSnapshotData = try await webPage.exported(as: .pdf)

        let document = TestPDFDocument(from: pdfSnapshotData)
        #expect(document.pageCount == 3)

        let firstPage = try #require(document.page(at: 0))
        #expect(firstPage.bounds == .init(x: 0, y: 0, width: 800, height: 14400))
        #expect(firstPage.color(at: .init(x: 400, y: 300)) == .green)
        #expect(firstPage.text == "Hello")

        let secondPage = try #require(document.page(at: 1))
        #expect(secondPage.bounds == .init(x: 0, y: 0, width: 800, height: 14400))
        #expect(secondPage.color(at: .init(x: 400, y: 300)) == .green)
        #expect(secondPage.text.isEmpty)

        let thirdPage = try #require(document.page(at: 2))
        #expect(thirdPage.bounds == .init(x: 0, y: 0, width: 800, height: 600))
        #expect(thirdPage.color(at: .init(x: 400, y: 300)) == .green)
        #expect(thirdPage.text.isEmpty)
    }

    @Test
    func links() async throws {
        let webPage = WebPage()
        webPage.backingWebView.frame = .init(x: 0, y: 0, width: 800, height: 15000)

        let html = """
            <meta name='viewport' content='width=device-width'>
            <div style=\"-webkit-line-box-contain: glyphs\">
                <a href=\"https://webkit.org/\">Click me</a>
            </div>
            """

        try await webPage.load(html: html).wait()

        let pdfSnapshotData = try await webPage.exported(as: .pdf)

        let document = TestPDFDocument(from: pdfSnapshotData)
        #expect(document.pageCount == 2)

        let page = try #require(document.page(at: 0))

        #expect(page.bounds == .init(x: 0, y: 0, width: 800, height: 14400))

        #if canImport(UIKit)
        let sRGBWhite = CocoaColor.white
        #else
        let sRGBWhite = try #require(CocoaColor.white.usingColorSpace(.sRGB))
        #endif

        #expect(page.color(at: .init(x: 400, y: 300)) == sRGBWhite)

        #expect(page.text == "Click me")

        let annotations = page.annotations
        #expect(annotations.count == 1)

        #expect(annotations[0].isLink)
        #expect(annotations[0].linkURL == URL(string: "https://webkit.org/"))

        let cRect = page.rectForCharacter(at: 1)
        let cMidpoint = CGPoint(x: cRect.midX, y: cRect.midY)
        let annotationBounds = annotations[0].bounds

        #expect(annotationBounds.contains(cMidpoint))
    }

    @Test
    func inlineLinks() async throws {
        let webPage = WebPage()

        let html = """
            <meta name='viewport' content='width=device-width'>
            <a href=\"https://webkit.org/\">Click me</a>
            """

        try await webPage.load(html: html).wait()

        let pdfSnapshotData = try await webPage.exported(as: .pdf)

        let document = TestPDFDocument(from: pdfSnapshotData)
        #expect(document.pageCount == 1)

        let page = try #require(document.page(at: 0))

        let annotations = page.annotations
        #expect(annotations.count == 1)

        #expect(annotations[0].isLink)
        #expect(annotations[0].linkURL == URL(string: "https://webkit.org/"))

        let cRect = page.rectForCharacter(at: 1)
        let cMidpoint = CGPoint(x: cRect.midX, y: cRect.midY)
        let annotationBounds = annotations[0].bounds

        #expect(annotationBounds.contains(cMidpoint))
    }

    @Test
    func allowTransparentBackground() async throws {
        let webPage = WebPage()

        let html = """
            <?xml version="1.0" encoding="UTF-8" standalone="no"?><svg height="210" width="500"><polygon points="200,10 250,190 160,210" style="fill:lime" /></svg>
            """

        try await webPage.load(html: html).wait()

        let pdfSnapshotData = try await webPage.exported(
            as: .pdf(allowTransparentBackground: true)
        )

        let document = TestPDFDocument(from: pdfSnapshotData)

        let page = try #require(document.page(at: 0))

        #expect(page.color(at: .init(x: 1, y: 1)) == .white)
    }
}

#endif // HAVE_PDFKIT && ENABLE_SWIFTUI

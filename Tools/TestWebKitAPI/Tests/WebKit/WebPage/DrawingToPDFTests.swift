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

import WebKit
private import TestWebKitAPILibrary
import Testing
private import UniformTypeIdentifiers
private import CoreTransferable

@MainActor
struct DrawingToPDFTests {
    @Test
    func gradientIntoPDF() async throws {
        let webPage = WebPage()

        let html = """
            <style>
                body { margin: 0 } 
                div { width: 100px; height: 100px; border: 2px solid black; background: linear-gradient(blue, blue 90%, green); print-color-adjust: exact; }
            </style> 
            <div></div>
            """

        try await webPage.load(html: html).wait()

        let pdfSnapshotData = try await webPage.exported(
            as: .pdf(
                region: .rect(.init(x: 0, y: 0, width: 100, height: 100))
            )
        )

        let document = TestPDFDocument(from: pdfSnapshotData)
        #expect(document.pageCount == 1)

        let page = try #require(document.page(at: 0))

        #expect(page.color(at: .init(x: 50, y: 50)) == .blue)
    }

    @Test
    func backgroundClipText() async throws {
        let webPage = WebPage()

        let html = """
            <style>
            @font-face { font-family: Ahem; src: url(Ahem.ttf); }
            body { margin: 0 }
            div { font-family: Ahem; font-size: 20px; padding: 10px; color: transparent; background: blue; background-clip: text; print-color-adjust: exact; }
            </style>
            <div>A</div>
            """

        let resources = try #require(Bundle.testResources.resourceURL)
        try await webPage.load(html: html, baseURL: resources).wait()

        let pdfSnapshotData = try await webPage.exported(
            as: .pdf(region: .rect(.init(x: 0, y: 0, width: 40, height: 40)))
        )

        let document = TestPDFDocument(from: pdfSnapshotData)
        #expect(document.pageCount == 1)

        let page = try #require(document.page(at: 0))

        #if canImport(UIKit)
        let sRGBWhite = CocoaColor.white
        #else
        let sRGBWhite = try #require(CocoaColor.white.usingColorSpace(.sRGB))
        #endif

        #expect(page.color(at: .init(x: 2, y: 2)) == sRGBWhite)
        // We can't test for blue because the colors are affected by colorspace conversions.
        #expect(page.color(at: .init(x: 25, y: 25)) != sRGBWhite)
    }

    @Test
    func siteIsolationFormControl() async throws {
        let webPage = WebPage()
        webPage.setWebFeature("SiteIsolationEnabled", enabled: true)

        let html = """
            <meta name='viewport' content='width=device-width'>
            <body bgcolor=#00ff00><input type='checkbox'>
                <label> Checkbox</label>
            </body>
            """

        try await webPage.load(html: html).wait()

        let pdfSnapshotData = try await webPage.exported(as: .pdf)

        let document = TestPDFDocument(from: pdfSnapshotData)
        #expect(document.pageCount == 1)

        let page = try #require(document.page(at: 0))

        let defaultWebPageSize = CGSize(width: 1024, height: 768)
        #expect(page.bounds == .init(origin: .zero, size: defaultWebPageSize))

        #expect(page.characterCount == 8)
        #expect(page.text == "Checkbox")

        // The entire page should be green. Pick a point in the middle to check.
        #expect(page.color(at: .init(x: 400, y: 300)) == .green)
    }
}

#endif // HAVE_PDFKIT && ENABLE_SWIFTUI

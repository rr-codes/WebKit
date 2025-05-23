/*
 * Copyright (C) 2011 Apple Inc. All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY APPLE INC. AND ITS CONTRIBUTORS ``AS IS''
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
 * THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL APPLE INC. OR ITS CONTRIBUTORS
 * BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
 * THE POSSIBILITY OF SUCH DAMAGE.
 */

#if PLATFORM(MAC)

#import "Connection.h"
#import <WebCore/IntRectHash.h>
#import <condition_variable>
#import <wtf/Condition.h>
#import <wtf/HashMap.h>
#import <wtf/Lock.h>
#import <wtf/RetainPtr.h>
#import <wtf/Vector.h>
#import <wtf/WeakObjCPtr.h>

@class WKPrintingViewData;
@class PDFDestination;
@class PDFDocument;

namespace WebCore {
class ShareableBitmap;
}

namespace WebKit {
class WebFrameProxy;
}

@interface WKPrintingView : NSView {
@public
    WeakObjCPtr<NSPrintOperation> _printOperation;
    RetainPtr<NSView> _wkView;

    const RefPtr<WebKit::WebFrameProxy> _webFrame;
    Vector<WebCore::IntRect> _printingPageRects;
    double _totalScaleFactorForPrinting;
    HashMap<WebCore::IntRect, RefPtr<WebCore::ShareableBitmap>> _pagePreviews;

    Vector<uint8_t> _printedPagesData;
    RetainPtr<PDFDocument> _printedPagesPDFDocument;
    Vector<Vector<RetainPtr<PDFDestination>>> _linkDestinationsPerPage;

    Markable<IPC::Connection::AsyncReplyID> _expectedComputedPagesCallback;
    HashMap<IPC::Connection::AsyncReplyID, WebCore::IntRect> _expectedPreviewCallbacks;
    Markable<IPC::Connection::AsyncReplyID> _latestExpectedPreviewCallback;
    Markable<IPC::Connection::AsyncReplyID> _expectedPrintCallback;

    BOOL _isPrintingFromSecondaryThread;
    Lock _printingCallbackMutex;
    Condition _printingCallbackCondition;

    NSTimer *_autodisplayResumeTimer;
}

- (id)initWithFrameProxy:(WebKit::WebFrameProxy&)frame view:(NSView *)wkView;

@end

#endif // PLATFORM(MAC)

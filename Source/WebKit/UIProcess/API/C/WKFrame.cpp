/*
 * Copyright (C) 2010 Apple Inc. All rights reserved.
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

#include "config.h"
#include "WKFrame.h"

#include "APIData.h"
#include "APIFrameHandle.h"
#include "APIFrameInfo.h"
#include "WKAPICast.h"
#include "WebFrameProxy.h"
#include "WebPageProxy.h"

using namespace WebKit;

WKTypeID WKFrameGetTypeID()
{
    return toAPI(WebFrameProxy::APIType);
}

bool WKFrameIsMainFrame(WKFrameRef frameRef)
{
    return toProtectedImpl(frameRef)->isMainFrame();
}

WKFrameLoadState WKFrameGetFrameLoadState(WKFrameRef frameRef)
{
    RefPtr frame = toImpl(frameRef);
    switch (frame->frameLoadState().state()) {
    case FrameLoadState::State::Provisional:
        return kWKFrameLoadStateProvisional;
    case FrameLoadState::State::Committed:
        return kWKFrameLoadStateCommitted;
    case FrameLoadState::State::Finished:
        return kWKFrameLoadStateFinished;
    }
    
    ASSERT_NOT_REACHED();
    return kWKFrameLoadStateFinished;
}

WKURLRef WKFrameCopyProvisionalURL(WKFrameRef frameRef)
{
    return toCopiedURLAPI(toImpl(frameRef)->provisionalURL());
}

WKURLRef WKFrameCopyURL(WKFrameRef frameRef)
{
    return toCopiedURLAPI(toImpl(frameRef)->url());
}

WKURLRef WKFrameCopyUnreachableURL(WKFrameRef frameRef)
{
    return toCopiedURLAPI(toImpl(frameRef)->unreachableURL());
}

void WKFrameStopLoading(WKFrameRef)
{
}

WKStringRef WKFrameCopyMIMEType(WKFrameRef frameRef)
{
    return toCopiedAPI(toImpl(frameRef)->mimeType());
}

WKStringRef WKFrameCopyTitle(WKFrameRef frameRef)
{
    return toCopiedAPI(toImpl(frameRef)->title());
}

WKPageRef WKFrameGetPage(WKFrameRef frameRef)
{
    return toAPI(toProtectedImpl(frameRef)->protectedPage().get());
}

WKCertificateInfoRef WKFrameGetCertificateInfo(WKFrameRef frameRef)
{
    return nullptr;
}

bool WKFrameCanProvideSource(WKFrameRef frameRef)
{
    return toProtectedImpl(frameRef)->canProvideSource();
}

bool WKFrameCanShowMIMEType(WKFrameRef, WKStringRef)
{
    return false;
}

bool WKFrameIsDisplayingStandaloneImageDocument(WKFrameRef frameRef)
{
    return toProtectedImpl(frameRef)->isDisplayingStandaloneImageDocument();
}

bool WKFrameIsDisplayingMarkupDocument(WKFrameRef frameRef)
{
    return toProtectedImpl(frameRef)->isDisplayingMarkupDocument();
}

bool WKFrameIsFrameSet(WKFrameRef frameRef)
{
    return false;
}

WKFrameHandleRef WKFrameCreateFrameHandle(WKFrameRef frameRef)
{
    return toAPILeakingRef(API::FrameHandle::create(toProtectedImpl(frameRef)->frameID()));
}

WKFrameInfoRef WKFrameCreateFrameInfo(WKFrameRef frameRef)
{
    return nullptr;
}

void WKFrameGetMainResourceData(WKFrameRef frameRef, WKFrameGetResourceDataFunction callback, void* context)
{
    toProtectedImpl(frameRef)->getMainResourceData([context, callback] (API::Data* data) {
        callback(toAPI(data), nullptr, context);
    });
}

void WKFrameGetResourceData(WKFrameRef frameRef, WKURLRef resourceURL, WKFrameGetResourceDataFunction callback, void* context)
{
    toProtectedImpl(frameRef)->getResourceData(toProtectedImpl(resourceURL).get(), [context, callback] (API::Data* data) {
        callback(toAPI(data), nullptr, context);
    });
}

void WKFrameGetWebArchive(WKFrameRef frameRef, WKFrameGetWebArchiveFunction callback, void* context)
{
    toProtectedImpl(frameRef)->getWebArchive([context, callback] (API::Data* data) {
        callback(toAPI(data), nullptr, context);
    });
}

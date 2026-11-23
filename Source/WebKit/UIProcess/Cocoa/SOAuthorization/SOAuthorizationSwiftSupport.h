/*
 * Copyright (C) 2019-2026 Apple Inc. All rights reserved.
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

#pragma once

#if HAVE(APP_SSO)

#include "APINavigationAction.h"
#include "PageLoadState.h"
#include "WebPageProxy.h"
#include "WebPreferences.h"
#include <wtf/URL.h>
#include <wtf/WeakPtr.h>

@protocol SOAuthorizationClassProtocol;

NS_HEADER_AUDIT_BEGIN(nullability, sendability)

// Swift cannot import pal/cocoa/AppSSOSoftLink.h, whose AppSSO SPI header is empty in a module build: these are the two
// declarations from it that the Swift uses.
namespace PAL {
extern ::Class _Nullable (* _Nonnull getSOAuthorizationClassSingleton)();
NSErrorDomain get_AppSSO_SOErrorDomainSingleton();
}

namespace WebKit {
namespace SOAuthorizationSupport {

// nil only on macOS, where AppSSO may be missing.
inline id<SOAuthorizationClassProtocol> _Nullable authorizationClass() { return (id<SOAuthorizationClassProtocol>)PAL::getSOAuthorizationClassSingleton(); }

// Swift 6.4 does not import WeakPtr's constrained constructors, nor the LIFETIME_BOUND references: URL and PageLoadState.
inline WeakPtrWebPageProxy makeWeakPtr(WebPageProxy& page) { return WeakPtrWebPageProxy { &page }; }
inline URL activeURL(WebPageProxy& page) { return page.pageLoadState().activeURL(); }
inline NSURL * _Nullable requestNSURL(const API::NavigationAction& navigationAction) { return navigationAction.request().url().createNSURL().autorelease(); }

} // namespace SOAuthorizationSupport
} // namespace WebKit

NS_HEADER_AUDIT_END(nullability, sendability)

#endif // HAVE(APP_SSO)

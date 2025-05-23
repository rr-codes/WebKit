/*
 * Copyright (C) 2013-2025 Apple Inc. All rights reserved.
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
#include "PageLoadState.h"

#include "WebPageProxy.h"

namespace WebKit {

// Progress always starts at this value. This helps provide feedback as soon as a load starts.
static const double initialProgressValue = 0.1;

PageLoadState::PageLoadState(WebPageProxy& webPageProxy)
    : m_webPageProxy(webPageProxy)
    , m_mayHaveUncommittedChanges(false)
    , m_outstandingTransactionCount(0)
{
}

PageLoadState::~PageLoadState()
{
    ASSERT(m_observers.isEmptyIgnoringNullReferences());
}

PageLoadState::Transaction::Transaction(PageLoadState& pageLoadState)
    : m_pageLoadState(&pageLoadState)
{
    pageLoadState.beginTransaction();
}

PageLoadState::Transaction::Transaction(Transaction&& other)
    : m_pageLoadState(std::exchange(other.m_pageLoadState, nullptr))
{
}

PageLoadState::Transaction::~Transaction()
{
    if (RefPtr pageLoadState = m_pageLoadState)
        pageLoadState->endTransaction();
}

void PageLoadState::addObserver(Observer& observer)
{
    ASSERT(!m_observers.contains(observer));

    m_observers.add(observer);
}

void PageLoadState::removeObserver(Observer& observer)
{
    bool removed = m_observers.remove(observer);
    ASSERT_UNUSED(removed, removed);
}

void PageLoadState::endTransaction()
{
    ASSERT(m_outstandingTransactionCount > 0);

    if (!--m_outstandingTransactionCount)
        commitChanges();
}

Ref<WebPageProxy> PageLoadState::protectedPage() const
{
    return m_webPageProxy.get();
}

void PageLoadState::ref() const
{
    m_webPageProxy->ref();
}

void PageLoadState::deref() const
{
    m_webPageProxy->deref();
}

void PageLoadState::commitChanges()
{
    if (!m_mayHaveUncommittedChanges)
        return;

    m_mayHaveUncommittedChanges = false;

    bool canGoBackChanged = m_committedState.canGoBack != m_uncommittedState.canGoBack;
    bool canGoForwardChanged = m_committedState.canGoForward != m_uncommittedState.canGoForward;
    bool titleChanged = m_committedState.title != m_uncommittedState.title
        || m_committedState.titleFromBrowsingWarning != m_uncommittedState.titleFromBrowsingWarning;
    bool isLoadingChanged = isLoading(m_committedState) != isLoading(m_uncommittedState);
    bool activeURLChanged = activeURL(m_committedState) != activeURL(m_uncommittedState);
    bool hasOnlySecureContentChanged = hasOnlySecureContent(m_committedState) != hasOnlySecureContent(m_uncommittedState);
    bool negotiatedLegacyTLSChanged = m_committedState.negotiatedLegacyTLS != m_uncommittedState.negotiatedLegacyTLS;
    bool wasPrivateRelayedChanged = m_committedState.wasPrivateRelayed != m_uncommittedState.wasPrivateRelayed;
    bool estimatedProgressChanged = estimatedProgress(m_committedState) != estimatedProgress(m_uncommittedState);
    bool networkRequestsInProgressChanged = m_committedState.networkRequestsInProgress != m_uncommittedState.networkRequestsInProgress;
    bool certificateInfoChanged = m_committedState.certificateInfo != m_uncommittedState.certificateInfo;

    if (canGoBackChanged)
        callObserverCallback(&Observer::willChangeCanGoBack);
    if (canGoForwardChanged)
        callObserverCallback(&Observer::willChangeCanGoForward);
    if (titleChanged)
        callObserverCallback(&Observer::willChangeTitle);
    if (isLoadingChanged)
        callObserverCallback(&Observer::willChangeIsLoading);
    if (activeURLChanged)
        callObserverCallback(&Observer::willChangeActiveURL);
    if (hasOnlySecureContentChanged)
        callObserverCallback(&Observer::willChangeHasOnlySecureContent);
    if (negotiatedLegacyTLSChanged)
        callObserverCallback(&Observer::willChangeNegotiatedLegacyTLS);
    if (wasPrivateRelayedChanged)
        callObserverCallback(&Observer::willChangeWasPrivateRelayed);
    if (estimatedProgressChanged)
        callObserverCallback(&Observer::willChangeEstimatedProgress);
    if (networkRequestsInProgressChanged)
        callObserverCallback(&Observer::willChangeNetworkRequestsInProgress);
    if (certificateInfoChanged)
        callObserverCallback(&Observer::willChangeCertificateInfo);

    m_committedState = m_uncommittedState;

    protectedPage()->isLoadingChanged();

    // The "did" ordering is the reverse of the "will". This is a requirement of Cocoa Key-Value Observing.
    if (certificateInfoChanged)
        callObserverCallback(&Observer::didChangeCertificateInfo);
    if (networkRequestsInProgressChanged)
        callObserverCallback(&Observer::didChangeNetworkRequestsInProgress);
    if (estimatedProgressChanged)
        callObserverCallback(&Observer::didChangeEstimatedProgress);
    if (hasOnlySecureContentChanged)
        callObserverCallback(&Observer::didChangeHasOnlySecureContent);
    if (negotiatedLegacyTLSChanged)
        callObserverCallback(&Observer::didChangeNegotiatedLegacyTLS);
    if (wasPrivateRelayedChanged)
        callObserverCallback(&Observer::didChangeWasPrivateRelayed);
    if (activeURLChanged)
        callObserverCallback(&Observer::didChangeActiveURL);
    if (isLoadingChanged)
        callObserverCallback(&Observer::didChangeIsLoading);
    if (titleChanged)
        callObserverCallback(&Observer::didChangeTitle);
    if (canGoForwardChanged)
        callObserverCallback(&Observer::didChangeCanGoForward);
    if (canGoBackChanged)
        callObserverCallback(&Observer::didChangeCanGoBack);
}

void PageLoadState::reset(const Transaction::Token& token)
{
    ASSERT_UNUSED(token, &token.m_pageLoadState == this);

    m_uncommittedState.state = State::Finished;
    m_uncommittedState.hasInsecureContent = false;

    m_uncommittedState.pendingAPIRequest = { };
    m_uncommittedState.provisionalURL = String();
    m_uncommittedState.url = String();
    m_uncommittedState.origin = { };

    m_uncommittedState.unreachableURL = String();
    m_lastUnreachableURL = String();

    m_uncommittedState.title = String();
    m_uncommittedState.titleFromBrowsingWarning = { };

    m_uncommittedState.estimatedProgress = 0;
    m_uncommittedState.networkRequestsInProgress = false;
}

String PageLoadState::activeURL(const Data& data)
{
    // If there is a currently pending URL, it is the active URL,
    // even when there's no main frame yet, as it might be the
    // first API request.
    if (!data.pendingAPIRequest.url.isNull())
        return data.pendingAPIRequest.url;

    if (!data.unreachableURL.isEmpty())
        return data.unreachableURL;

    switch (data.state) {
    case State::Provisional:
        return data.provisionalURL;
    case State::Committed:
    case State::Finished:
        return data.url;
    }

    ASSERT_NOT_REACHED();
    return String();
}

bool PageLoadState::hasOnlySecureContent(const Data& data)
{
    if (data.hasInsecureContent)
        return false;

    if (data.state == State::Provisional)
        return WTF::protocolIs(data.provisionalURL, "https"_s);

    return WTF::protocolIs(data.url, "https"_s);
}

bool PageLoadState::hasOnlySecureContent() const
{
    return hasOnlySecureContent(m_committedState);
}

bool PageLoadState::hasNegotiatedLegacyTLS() const
{
    return m_committedState.negotiatedLegacyTLS;
}

void PageLoadState::negotiatedLegacyTLS(const Transaction::Token& token)
{
    ASSERT_UNUSED(token, &token.m_pageLoadState == this);
    m_uncommittedState.negotiatedLegacyTLS = true;
}

double PageLoadState::estimatedProgress(const Data& data)
{
    if (!data.pendingAPIRequest.url.isNull())
        return initialProgressValue;

    return data.estimatedProgress;
}

double PageLoadState::estimatedProgress() const
{
    return estimatedProgress(m_committedState);
}

void PageLoadState::setPendingAPIRequest(const Transaction::Token& token, PendingAPIRequest&& pendingAPIRequest, const URL& resourceDirectoryURL)
{
    ASSERT_UNUSED(token, &token.m_pageLoadState == this);
    m_uncommittedState.pendingAPIRequest = WTFMove(pendingAPIRequest);
    m_uncommittedState.resourceDirectoryURL = resourceDirectoryURL;
}

void PageLoadState::clearPendingAPIRequest(const Transaction::Token& token)
{
    ASSERT_UNUSED(token, &token.m_pageLoadState == this);
    m_uncommittedState.pendingAPIRequest = { };
}

void PageLoadState::didExplicitOpen(const Transaction::Token& token, const String& url)
{
    ASSERT_UNUSED(token, &token.m_pageLoadState == this);

    m_uncommittedState.url = url;
    m_uncommittedState.provisionalURL = String();
}

void PageLoadState::didStartProvisionalLoad(const Transaction::Token& token, const String& url, const String& unreachableURL)
{
    ASSERT_UNUSED(token, &token.m_pageLoadState == this);
    ASSERT(m_uncommittedState.provisionalURL.isEmpty());

    m_uncommittedState.state = State::Provisional;

    m_uncommittedState.provisionalURL = url;

    setUnreachableURL(token, unreachableURL);
}

void PageLoadState::didReceiveServerRedirectForProvisionalLoad(const Transaction::Token& token, const String& url)
{
    ASSERT_UNUSED(token, &token.m_pageLoadState == this);
    ASSERT(m_uncommittedState.state == State::Provisional);

    m_uncommittedState.provisionalURL = url;
}

void PageLoadState::didFailProvisionalLoad(const Transaction::Token& token)
{
    ASSERT_UNUSED(token, &token.m_pageLoadState == this);
    ASSERT(m_uncommittedState.state == State::Provisional);

    m_uncommittedState.state = State::Finished;

    m_uncommittedState.provisionalURL = String();
    m_uncommittedState.unreachableURL = m_lastUnreachableURL;
}

void PageLoadState::didCommitLoad(const Transaction::Token& token, const WebCore::CertificateInfo& certificateInfo, bool hasInsecureContent, bool usedLegacyTLS, bool wasPrivateRelayed, const String& proxyName, const WebCore::ResourceResponseSource source, const WebCore::SecurityOriginData& origin)
{
    ASSERT_UNUSED(token, &token.m_pageLoadState == this);
    ASSERT(m_uncommittedState.state == State::Provisional);

    m_uncommittedState.state = State::Committed;
    m_uncommittedState.hasInsecureContent = hasInsecureContent;
    m_uncommittedState.certificateInfo = certificateInfo;

    ASSERT(!m_uncommittedState.provisionalURL.isNull());
    m_uncommittedState.url = m_uncommittedState.provisionalURL.isNull() ? aboutBlankURL().string() : std::exchange(m_uncommittedState.provisionalURL, { });
    m_uncommittedState.negotiatedLegacyTLS = usedLegacyTLS;
    m_uncommittedState.wasPrivateRelayed = wasPrivateRelayed;
    m_uncommittedState.origin = origin;

    m_uncommittedState.title = String();
    m_uncommittedState.titleFromBrowsingWarning = { };
    m_uncommittedState.proxyName = proxyName;
    m_uncommittedState.source = source;
}

void PageLoadState::didFinishLoad(const Transaction::Token& token)
{
    ASSERT_UNUSED(token, &token.m_pageLoadState == this);
    ASSERT(m_uncommittedState.state == State::Committed);
    ASSERT(m_uncommittedState.provisionalURL.isEmpty());

    m_uncommittedState.state = State::Finished;
}

void PageLoadState::didFailLoad(const Transaction::Token& token)
{
    ASSERT_UNUSED(token, &token.m_pageLoadState == this);
    ASSERT(m_uncommittedState.provisionalURL.isEmpty());

    m_uncommittedState.state = State::Finished;
}

void PageLoadState::didSameDocumentNavigation(const Transaction::Token& token, const String& url)
{
    ASSERT_UNUSED(token, &token.m_pageLoadState == this);
    ASSERT(!m_uncommittedState.url.isEmpty());

    m_uncommittedState.url = url;
}

void PageLoadState::didDisplayOrRunInsecureContent(const Transaction::Token& token)
{
    ASSERT_UNUSED(token, &token.m_pageLoadState == this);

    m_uncommittedState.hasInsecureContent = true;
}

void PageLoadState::setUnreachableURL(const Transaction::Token& token, const String& unreachableURL)
{
    ASSERT_UNUSED(token, &token.m_pageLoadState == this);

    m_lastUnreachableURL = m_uncommittedState.unreachableURL;
    m_uncommittedState.unreachableURL = unreachableURL;
}

const String& PageLoadState::title() const
{
    if (!m_committedState.titleFromBrowsingWarning.isNull())
        return m_committedState.titleFromBrowsingWarning;

    return m_committedState.title;
}

void PageLoadState::setTitle(const Transaction::Token& token, String&& title)
{
    ASSERT_UNUSED(token, &token.m_pageLoadState == this);
    m_uncommittedState.title = WTFMove(title);
}

void PageLoadState::setTitleFromBrowsingWarning(const Transaction::Token& token, const String& title)
{
    ASSERT_UNUSED(token, &token.m_pageLoadState == this);
    m_uncommittedState.titleFromBrowsingWarning = title;
}

bool PageLoadState::canGoBack() const
{
    return m_committedState.canGoBack;
}

void PageLoadState::setCanGoBack(const Transaction::Token& token, bool canGoBack)
{
    ASSERT_UNUSED(token, &token.m_pageLoadState == this);
    m_uncommittedState.canGoBack = canGoBack;
}

bool PageLoadState::canGoForward() const
{
    return m_committedState.canGoForward;
}

void PageLoadState::setCanGoForward(const Transaction::Token& token, bool canGoForward)
{
    ASSERT_UNUSED(token, &token.m_pageLoadState == this);
    m_uncommittedState.canGoForward = canGoForward;
}

void PageLoadState::didStartProgress(const Transaction::Token& token)
{
    ASSERT_UNUSED(token, &token.m_pageLoadState == this);
    m_uncommittedState.estimatedProgress = initialProgressValue;
}

void PageLoadState::didChangeProgress(const Transaction::Token& token, double value)
{
    ASSERT_UNUSED(token, &token.m_pageLoadState == this);
    m_uncommittedState.estimatedProgress = value;
}

void PageLoadState::didFinishProgress(const Transaction::Token& token)
{
    ASSERT_UNUSED(token, &token.m_pageLoadState == this);
    m_uncommittedState.estimatedProgress = 1;
}

void PageLoadState::setNetworkRequestsInProgress(const Transaction::Token& token, bool networkRequestsInProgress)
{
    ASSERT_UNUSED(token, &token.m_pageLoadState == this);
    m_uncommittedState.networkRequestsInProgress = networkRequestsInProgress;
}

void PageLoadState::setHTTPFallbackInProgress(const Transaction::Token& token, bool isHTTPFallbackInProgress)
{
    ASSERT_UNUSED(token, &token.m_pageLoadState == this);
    m_uncommittedState.isHTTPFallbackInProgress = isHTTPFallbackInProgress;
}

bool PageLoadState::httpFallbackInProgress()
{
    return m_uncommittedState.isHTTPFallbackInProgress;
}

bool PageLoadState::isLoading(const Data& data)
{
    if (!data.pendingAPIRequest.url.isNull())
        return true;

    switch (data.state) {
    case State::Provisional:
    case State::Committed:
        return true;

    case State::Finished:
        return false;
    }

    ASSERT_NOT_REACHED();
    return false;
}

void PageLoadState::didSwapWebProcesses()
{
    callObserverCallback(&Observer::didSwapWebProcesses);
}

void PageLoadState::willChangeProcessIsResponsive()
{
    callObserverCallback(&Observer::willChangeWebProcessIsResponsive);
}

void PageLoadState::didChangeProcessIsResponsive()
{
    callObserverCallback(&Observer::didChangeWebProcessIsResponsive);
}

void PageLoadState::callObserverCallback(void (Observer::*callback)())
{
    Ref protectedPage { m_webPageProxy.get() };

    for (auto& observer : copyToVector(m_observers)) {
        // This appears potentially inefficient on the surface (searching in a Vector)
        // but in practice - using only API - there will only ever be (1) observer.
        if (RefPtr protectedObserver = observer.get(); !protectedObserver || !m_observers.contains(*protectedObserver))
            continue;

        ((*observer).*callback)();
    }
}

} // namespace WebKit

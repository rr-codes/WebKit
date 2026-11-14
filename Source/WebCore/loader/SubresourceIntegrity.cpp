/*
 * Copyright (C) 2017 Apple Inc. All rights reserved.
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
#include "SubresourceIntegrity.h"

#include "CachedResource.h"
#include "LocalFrame.h"
#include "LocalFrameInlines.h"
#include "ResourceCryptographicDigest.h"
#include "SharedBuffer.h"
#include "SubresourceLoader.h"
#include "ViolationReportType.h"
#include "WebCore-Swift.h"
#include <wtf/text/Base64.h>
#include <wtf/text/MakeString.h>

namespace WebCore {

NODELETE static bool isResponseEligible(const CachedResource& resource)
{
    // FIXME: The spec says this should check XXX.
    return resource.isCORSSameOrigin();
}

static Ref<FormData> createReportFormData(const String& type, const URL& url, const String& userAgent, NOESCAPE const Function<void(JSON::Object&)>& populateBody)
{
    auto body = JSON::Object::create();
    populateBody(body);

    // https://www.w3.org/TR/reporting-1/#queue-report, step 2.3.1.
    auto reportObject = JSON::Object::create();
    reportObject->setObject("body"_s, WTF::move(body));
    reportObject->setString("type"_s, type);
    reportObject->setString("user_agent"_s, userAgent);
    // The spec allows user agents to delay report sending, in order to reduce impact on the user and potential overhead. See https://www.w3.org/TR/reporting-1/#delivery
    // Currently we're not taking advantage of that, so setting the `age` to 0 to indicate immediate delivery.
    reportObject->setInteger("age"_s, 0);
    reportObject->setInteger("attempts"_s, 0);
    if (url.isValid())
        reportObject->setString("url"_s, url.strippedForUseAsReferrer().string);

    auto reportList = JSON::Array::create();
    reportList->pushObject(reportObject);

    return FormData::create(reportList->toJSONString().utf8().span());
}

static String addHashPrefix(ResourceCryptographicDigest::Algorithm algorithm, StringView hash)
{
    switch (algorithm) {
    case ResourceCryptographicDigest::Algorithm::SHA256:
        return makeString("sha256-"_s, hash);
    case ResourceCryptographicDigest::Algorithm::SHA384:
        return makeString("sha384-"_s, hash);
    case ResourceCryptographicDigest::Algorithm::SHA512:
        return makeString("sha512-"_s, hash);
    }
    ASSERT_NOT_REACHED();
    return String();
}

NODELETE static std::optional<ResourceCryptographicDigest::Algorithm> findStrongestAlgorithm(HashAlgorithmSet algorithmSet)
{
    for (int i = ResourceCryptographicDigest::algorithmCount - 1; i >= 0; --i) {
        uint8_t algorithm = (1 << i);
        if (algorithmSet & algorithm)
            return static_cast<ResourceCryptographicDigest::Algorithm>(algorithm);
    }
    return std::nullopt;
}

void reportHashesIfNeeded(const CachedResource& resource)
{
    if (!resource.isHashReportingNeeded())
        return;

    RefPtr loader = resource.loader();
    if (!loader)
        return;
    RefPtr frame = loader->frame();
    if (!frame)
        return;
    RefPtr document = frame->document();
    if (!document)
        return;

    CheckedRef csp = *document->contentSecurityPolicy();
    URL documentURL = document->url();

    auto& hashesToReport = csp->hashesToReport();
    if (hashesToReport.isEmpty())
        return;

    bool canExposeHashes = isResponseEligible(resource);
    for (auto& [algorithmSet, fixedEndpoints] : hashesToReport) {
        auto hashAlgorithm = findStrongestAlgorithm(algorithmSet);
        if (!hashAlgorithm)
            return;

        String hash = ""_s;
        if (canExposeHashes)
            hash = addHashPrefix(hashAlgorithm.value(), base64EncodeToString(resource.cryptographicDigest(hashAlgorithm.value()).value));
        Ref report = createReportFormData("csp-hash"_s, documentURL, document->httpUserAgent(), [&](auto& body) {
            body.setString("documentURL"_s, documentURL.strippedForUseAsReferrer().string);
            body.setString("subresourceURL"_s, resource.url().strippedForUseAsReferrer().string);
            body.setString("hash"_s, hash);
            body.setString("type"_s, "subresource"_s);
            body.setString("destination"_s, "script"_s);
        });
        document->sendReportToEndpoints(documentURL, { }, fixedEndpoints, WTF::move(report), ViolationReportType::CSPHashReport);
    }
}

bool matchIntegrityMetadataSlow(const CachedResource& resource, const String& integrityMetadataList)
{
    // 1. Let parsedMetadata be the result of parsing metadataList.
    auto algorithm = subresourceIntegrityStrongestAlgorithm(integrityMetadataList);

    // 2. If parsedMetadata is no metadata, return true.
    if (algorithm == SubresourceIntegrityStrongestAlgorithm::None)
        return true;

    // 3. If response is not eligible for integrity validation, return false.
    if (!isResponseEligible(resource))
        return false;

    // 4. If parsedMetadata is the empty set, return true.
    if (algorithm == SubresourceIntegrityStrongestAlgorithm::EmptySet)
        return true;

    // 5. Let metadata be the result of getting the strongest metadata from parsedMetadata.
    // 6. For each item in metadata, return true if applying its algorithm to response matches its value.
    return subresourceIntegrityMatches(integrityMetadataList, resource.cryptographicDigest(static_cast<ResourceCryptographicDigest::Algorithm>(algorithm)));
}

String integrityMismatchDescription(const CachedResource& resource, const String& integrityMetadata)
{
    auto resourceURL = resource.url().stringCenterEllipsizedToLength();
    if (RefPtr resourceBuffer = resource.resourceBuffer()) {
        return makeString(resourceURL, ". Failed integrity metadata check. Content length: "_s, resourceBuffer->size(), ", Expected content length: "_s,
            resource.response().expectedContentLength(), ", Expected metadata: "_s, integrityMetadata);
    }
    return makeString(resourceURL, ". Failed integrity metadata check. Content length: (no content), Expected content length: "_s,
        resource.response().expectedContentLength(), ", Expected metadata: "_s, integrityMetadata);
}

}

// Copyright 2018 The Chromium Authors. All rights reserved.
// Copyright (C) 2019-2021 Apple Inc. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the names of its
// contributors may be used to endorse or promote products derived from
// this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#include "config.h"

#if ENABLE(WEB_AUTHN)

#include "FidoTestData.h"
#include <WebCore/AuthenticatorSelectionCriteria.h>
#include <WebCore/FidoConstants.h>
#include <WebCore/PublicKeyCredentialCreationOptions.h>
#include <WebCore/PublicKeyCredentialRequestOptions.h>
#include <WebCore/U2fCommandConstructor.h>
#include <WebCore/WebAuthenticationConstants.h>
#include <WebCore/WebAuthenticationUtils.h>

namespace TestWebKitAPI {
using namespace WebCore;
using namespace fido;

PublicKeyCredentialCreationOptions constructMakeCredentialRequest()
{
    PublicKeyCredentialRpEntity rp;
    rp.id = "acme.com"_s;
    rp.name = "acme.com"_s;

    PublicKeyCredentialUserEntity user;
    user.id = WebCore::toBufferSource(TestData::kUserId);
    user.name = "johnpsmith@example.com"_s;
    user.displayName = "John P. Smith"_s;
    user.icon = "https://pics.acme.com/00/p/aBjjjpqPb.png"_s;

    PublicKeyCredentialParameters params;
    params.type = PublicKeyCredentialType::PublicKey;
    params.alg = COSE::ES256;

    AuthenticationExtensionsClientInputs extensions;

    PublicKeyCredentialCreationOptions options;
    options.rp = WTFMove(rp);
    options.user = WTFMove(user);
    options.pubKeyCredParams.append(WTFMove(params));
    options.extensions = WTFMove(extensions);

    return options;
}

PublicKeyCredentialRequestOptions constructGetAssertionRequest()
{
    PublicKeyCredentialRequestOptions options;
    options.rpId = "acme.com"_s;
    return options;
}

TEST(U2fCommandConstructorTest, TestConvertCtapMakeCredentialToU2fRegister)
{
    const auto makeCredentialParam = constructMakeCredentialRequest();

    EXPECT_TRUE(isConvertibleToU2fRegisterCommand(makeCredentialParam));

    const auto u2fRegisterCommand = convertToU2fRegisterCommand(std::span { TestData::kClientDataHash }, makeCredentialParam);
    ASSERT_TRUE(u2fRegisterCommand);
    EXPECT_EQ(*u2fRegisterCommand, Vector<uint8_t>(TestData::kU2fRegisterCommandApdu));
}

TEST(U2fCommandConstructorTest, TestConvertCtapMakeCredentialToU2fCheckOnlySign)
{
    auto makeCredentialParam = constructMakeCredentialRequest();
    PublicKeyCredentialDescriptor credentialDescriptor;
    credentialDescriptor.type = PublicKeyCredentialType::PublicKey;
    credentialDescriptor.id = WebCore::toBufferSource(TestData::kU2fSignKeyHandle).variant();
    Vector<PublicKeyCredentialDescriptor> excludeList;
    excludeList.append(credentialDescriptor);
    makeCredentialParam.excludeCredentials = WTFMove(excludeList);
    EXPECT_TRUE(isConvertibleToU2fRegisterCommand(makeCredentialParam));

    const auto u2fCheckOnlySign = convertToU2fCheckOnlySignCommand(std::array { TestData::kClientDataHash }, makeCredentialParam, credentialDescriptor);
    ASSERT_TRUE(u2fCheckOnlySign);
    EXPECT_EQ(*u2fCheckOnlySign, Vector<uint8_t> { TestData::kU2fCheckOnlySignCommandApdu });
}

TEST(U2fCommandConstructorTest, TestConvertCtapMakeCredentialToU2fCheckOnlySignWithInvalidCredentialType)
{
    auto makeCredentialParam = constructMakeCredentialRequest();
    PublicKeyCredentialDescriptor credentialDescriptor;
    credentialDescriptor.type = static_cast<PublicKeyCredentialType>(-1);
    credentialDescriptor.id = WebCore::toBufferSource(TestData::kU2fSignKeyHandle).variant();
    Vector<PublicKeyCredentialDescriptor> excludeList;
    excludeList.append(credentialDescriptor);
    makeCredentialParam.excludeCredentials = WTFMove(excludeList);
    EXPECT_TRUE(isConvertibleToU2fRegisterCommand(makeCredentialParam));

    const auto u2fCheckOnlySign = convertToU2fCheckOnlySignCommand(std::span { TestData::kClientDataHash }, makeCredentialParam, credentialDescriptor);
    EXPECT_FALSE(u2fCheckOnlySign);
}

TEST(U2fCommandConstructorTest, TestU2fRegisterCredentialAlgorithmRequirement)
{
    PublicKeyCredentialRpEntity rp;
    rp.id = "acme.com"_s;
    rp.name = "acme.com"_s;

    PublicKeyCredentialUserEntity user;
    user.id = WebCore::toBufferSource(TestData::kUserId);
    user.name = "johnpsmith@example.com"_s;
    user.displayName = "John P. Smith"_s;
    user.icon = "https://pics.acme.com/00/p/aBjjjpqPb.png"_s;

    PublicKeyCredentialParameters params;
    params.type = PublicKeyCredentialType::PublicKey;
    params.alg = -257;

    PublicKeyCredentialCreationOptions makeCredentialParam;
    makeCredentialParam.rp = WTFMove(rp);
    makeCredentialParam.user = WTFMove(user);
    makeCredentialParam.pubKeyCredParams.append(WTFMove(params));

    EXPECT_FALSE(isConvertibleToU2fRegisterCommand(makeCredentialParam));
}

TEST(U2fCommandConstructorTest, TestU2fRegisterUserVerificationRequirement)
{
    auto makeCredentialParam = constructMakeCredentialRequest();
    AuthenticatorSelectionCriteria selection;
    selection.userVerification = UserVerificationRequirement::Required;
    makeCredentialParam.authenticatorSelection = WTFMove(selection);

    EXPECT_FALSE(isConvertibleToU2fRegisterCommand(makeCredentialParam));
}

TEST(U2fCommandConstructorTest, TestU2fRegisterResidentKeyRequirement)
{
    auto makeCredentialParam = constructMakeCredentialRequest();
    AuthenticatorSelectionCriteria selection;
    selection.requireResidentKey = true;
    makeCredentialParam.authenticatorSelection = WTFMove(selection);

    EXPECT_FALSE(isConvertibleToU2fRegisterCommand(makeCredentialParam));
}

TEST(U2fCommandConstructorTest, TestConvertCtapGetAssertionToU2fSignRequest)
{
    auto getAssertionReq = constructGetAssertionRequest();
    PublicKeyCredentialDescriptor credentialDescriptor;
    credentialDescriptor.type = PublicKeyCredentialType::PublicKey;
    credentialDescriptor.id = WebCore::toBufferSource(TestData::kU2fSignKeyHandle);
    Vector<PublicKeyCredentialDescriptor> allowedList;
    allowedList.append(WTFMove(credentialDescriptor));
    getAssertionReq.allowCredentials = WTFMove(allowedList);
    EXPECT_TRUE(isConvertibleToU2fSignCommand(getAssertionReq));

    const auto u2fSignCommand = convertToU2fSignCommand(std::span { TestData::kClientDataHash }, getAssertionReq, WebCore::toBufferSource(TestData::kU2fSignKeyHandle));
    ASSERT_TRUE(u2fSignCommand);
    EXPECT_EQ(*u2fSignCommand, Vector<uint8_t> { TestData::kU2fSignCommandApdu });
}

TEST(U2fCommandConstructorTest, TestConvertCtapGetAssertionWithAppIDToU2fSignRequest)
{
    auto getAssertionReq = constructGetAssertionRequest();
    PublicKeyCredentialDescriptor credentialDescriptor;
    credentialDescriptor.type = PublicKeyCredentialType::PublicKey;
    credentialDescriptor.id = WebCore::toBufferSource(TestData::kU2fSignKeyHandle);
    Vector<PublicKeyCredentialDescriptor> allowedList;
    allowedList.append(WTFMove(credentialDescriptor));
    getAssertionReq.allowCredentials = WTFMove(allowedList);
    EXPECT_TRUE(isConvertibleToU2fSignCommand(getAssertionReq));

    // AppID
    WebCore::AuthenticationExtensionsClientInputs extensions;
    extensions.appid = "https://www.example.com/appid"_s;
    getAssertionReq.extensions = WTFMove(extensions);

    const auto u2fSignCommand = convertToU2fSignCommand(std::span { TestData::kClientDataHash }, getAssertionReq, WebCore::toBufferSource(TestData::kU2fSignKeyHandle), true);
    ASSERT_TRUE(u2fSignCommand);
    EXPECT_EQ(*u2fSignCommand, Vector<uint8_t> { TestData::kU2fAppIDSignCommandApdu });
}

TEST(U2fCommandConstructorTest, TestU2fSignAllowListRequirement)
{
    auto getAssertionReq = constructGetAssertionRequest();
    EXPECT_FALSE(isConvertibleToU2fSignCommand(getAssertionReq));
}

TEST(U2fCommandConstructorTest, TestU2fSignUserVerificationRequirement)
{
    auto getAssertionReq = constructGetAssertionRequest();
    PublicKeyCredentialDescriptor credentialDescriptor;
    credentialDescriptor.type = PublicKeyCredentialType::PublicKey;
    credentialDescriptor.id = WebCore::toBufferSource(TestData::kU2fSignKeyHandle);
    Vector<PublicKeyCredentialDescriptor> allowedList;
    allowedList.append(WTFMove(credentialDescriptor));
    getAssertionReq.allowCredentials = WTFMove(allowedList);
    getAssertionReq.userVerification = UserVerificationRequirement::Required;

    EXPECT_FALSE(isConvertibleToU2fSignCommand(getAssertionReq));
}

TEST(U2fCommandConstructorTest, TestCreateSignWithIncorrectKeyHandle)
{
    auto getAssertionReq = constructGetAssertionRequest();
    PublicKeyCredentialDescriptor credentialDescriptor;
    credentialDescriptor.type = PublicKeyCredentialType::PublicKey;
    credentialDescriptor.id = WebCore::toBufferSource(TestData::kU2fSignKeyHandle);
    Vector<PublicKeyCredentialDescriptor> allowedList;
    allowedList.append(WTFMove(credentialDescriptor));
    getAssertionReq.allowCredentials = WTFMove(allowedList);
    ASSERT_TRUE(isConvertibleToU2fSignCommand(getAssertionReq));

    Vector<uint8_t> keyHandle(kMaxKeyHandleLength, 0xff);
    const auto validSignCommand = convertToU2fSignCommand(std::span { TestData::kClientDataHash }, getAssertionReq, WebCore::toBufferSource(keyHandle.span()));
    EXPECT_TRUE(validSignCommand);

    keyHandle.append(0xff);
    const auto invalidSignCommand = convertToU2fSignCommand(std::span { TestData::kClientDataHash }, getAssertionReq, WebCore::toBufferSource(keyHandle.span()));
    EXPECT_FALSE(invalidSignCommand);
}

TEST(U2fCommandConstructorTest, TestConstructBogusU2fRegistrationCommand)
{
    EXPECT_EQ(constructBogusU2fRegistrationCommand(), Vector<uint8_t> { TestData::kU2fFakeRegisterCommand });
}

} // namespace TestWebKitAPI

#endif // ENABLE(WEB_AUTHN)

/*
 * Copyright (C) 2004-2022 Apple Inc. All rights reserved.
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
 * THIS SOFTWARE IS PROVIDED BY APPLE INC. ``AS IS'' AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL APPLE INC. OR
 * CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 * EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 * PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
 * OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE. 
 */

#include "config.h"
#include "SimpleCaretAnimator.h"

#include "RenderTheme.h"
#include <wtf/TZoneMallocInlines.h>

namespace WebCore {

WTF_MAKE_TZONE_ALLOCATED_IMPL(SimpleCaretAnimator);

SimpleCaretAnimator::SimpleCaretAnimator(CaretAnimationClient& client)
    : CaretAnimator(client)
{
}

void SimpleCaretAnimator::updateAnimationProperties()
{
    auto currentTime = MonotonicTime::now();
    auto caretBlinkInterval = RenderTheme::singleton().caretBlinkInterval();

    setBlinkingSuspended(!caretBlinkInterval);

    if (isBlinkingSuspended()) {
        // Ensure the caret is always visible when blinking is suspended.
        if (m_presentationProperties.blinkState == PresentationProperties::BlinkState::On)
            m_blinkTimer.startOneShot(caretBlinkInterval.value_or(0_ms));
        return;
    }

    ASSERT(caretBlinkInterval.has_value());

    if (currentTime - m_lastTimeCaretPaintWasToggled >= caretBlinkInterval) {
        setBlinkState(!m_presentationProperties.blinkState);
        m_lastTimeCaretPaintWasToggled = currentTime;

        m_blinkTimer.startOneShot(*caretBlinkInterval);
    }
}

void SimpleCaretAnimator::start()
{
    m_lastTimeCaretPaintWasToggled = MonotonicTime::now();
    didStart(m_lastTimeCaretPaintWasToggled, RenderTheme::singleton().caretBlinkInterval());
}

String SimpleCaretAnimator::debugDescription() const
{
    TextStream textStream;
    textStream << "SimpleCaretAnimator " << this << " active " << isActive() << " blink state = " << (m_presentationProperties.blinkState == PresentationProperties::BlinkState::On ? "On" : "Off");
    return textStream.release();
}

} // namespace WebCore

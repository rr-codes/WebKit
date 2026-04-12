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

#pragma once

#include "LocalFrame.h"

namespace WebCore {

class NavigationDisabler {
    WTF_DEPRECATED_MAKE_FAST_ALLOCATED_WITH_HEAP_IDENTIFIER(NavigationDisabler, Loader);
public:
    NavigationDisabler(LocalFrame* frame)
        : m_frame(frame)
    {
        if (frame) {
            ++frame->m_navigationDisableCount;
            if (auto* mainFrame = dynamicDowncast<LocalFrame>(frame->mainFrame()))
                ++mainFrame->m_totalNavigationDisableCount;
        } else // Disable all navigations when destructing a frame-less document.
            ++s_globalNavigationDisableCount;
    }

    ~NavigationDisabler()
    {
        if (auto* frame = m_frame.get()) {
            ASSERT(frame->m_navigationDisableCount);
            --frame->m_navigationDisableCount;
            if (auto* mainFrame = dynamicDowncast<LocalFrame>(frame->mainFrame())) {
                ASSERT(mainFrame->m_totalNavigationDisableCount);
                --mainFrame->m_totalNavigationDisableCount;
            }
        } else {
            ASSERT(s_globalNavigationDisableCount);
            --s_globalNavigationDisableCount;
        }
    }

    static bool isNavigationAllowed(Frame& frame)
    {
        if (s_globalNavigationDisableCount)
            return false;
        auto* localMainFrame = dynamicDowncast<LocalFrame>(frame.mainFrame());
        if (!localMainFrame || !localMainFrame->m_totalNavigationDisableCount)
            return true;
        // Check if the target frame or any of its ancestors has navigation disabled.
        for (auto* ancestor = &frame; ancestor; ancestor = ancestor->tree().parent()) {
            if (auto* localAncestor = dynamicDowncast<LocalFrame>(*ancestor)) {
                if (localAncestor->m_navigationDisableCount)
                    return false;
            }
        }
        // Check if any descendant of the target frame has navigation disabled,
        // since navigating an ancestor would disrupt the descendant's beforeunload.
        for (auto* descendant = frame.tree().firstChild(); descendant; descendant = descendant->tree().traverseNext(&frame)) {
            if (auto* localDescendant = dynamicDowncast<LocalFrame>(*descendant)) {
                if (localDescendant->m_navigationDisableCount)
                    return false;
            }
        }
        return true;
    }

private:
    RefPtr<LocalFrame> m_frame;

    static unsigned s_globalNavigationDisableCount;
};

}

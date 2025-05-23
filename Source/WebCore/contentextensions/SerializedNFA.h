/*
 * Copyright (C) 2020 Apple Inc. All rights reserved.
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

#if ENABLE(CONTENT_EXTENSIONS)

#include "ImmutableNFA.h"
#include <wtf/MappedFileData.h>
#include <wtf/StdLibExtras.h>

namespace WebCore {
namespace ContentExtensions {

struct NFA;

class SerializedNFA {
public:
    static std::optional<SerializedNFA> serialize(NFA&&);
    SerializedNFA(SerializedNFA&&) = default;

    template<typename T>
    class Range {
    public:
        Range(std::span<const T> span)
            : m_span(span)
        { }
        const T* begin() const { return std::to_address(m_span.begin()); }
        const T* end() const { return std::to_address(m_span.end()); }
        size_t size() const { return m_span.size(); }
        const T* pointerAt(size_t i) const { return &m_span[i]; }
        T valueAt(size_t i) const
        {
            T value;
            memcpySpan(singleElementSpan(value), m_span.subspan(i, 1));
            return value;
        }
    private:
        std::span<const T> m_span;
    };

    const Range<ImmutableNFANode> nodes() const;
    const Range<ImmutableRange<char>> transitions() const;
    const Range<uint32_t> targets() const;
    const Range<uint32_t> epsilonTransitionsTargets() const;
    const Range<uint64_t> actions() const;

    uint32_t root() const
    {
        RELEASE_ASSERT(nodes().size());
        return 0;
    }

    struct ConstTargetIterator {
        const SerializedNFA& serializedNFA;
        uint32_t position;

        uint32_t operator*() const { return serializedNFA.targets().valueAt(position); }
        const uint32_t* operator->() const { return serializedNFA.targets().pointerAt(position); }

        bool operator==(const ConstTargetIterator& other) const
        {
            ASSERT(&serializedNFA == &other.serializedNFA);
            return position == other.position;
        }

        ConstTargetIterator& operator++()
        {
            ++position;
            return *this;
        }
    };

    struct IterableConstTargets {
        const SerializedNFA& serializedNFA;
        uint32_t targetStart;
        uint32_t targetEnd;

        ConstTargetIterator begin() const { return { serializedNFA, targetStart }; }
        ConstTargetIterator end() const { return { serializedNFA, targetEnd }; }
    };

    struct ConstRangeIterator {
        const SerializedNFA& serializedNFA;
        uint32_t position;

        bool operator==(const ConstRangeIterator& other) const
        {
            ASSERT(&serializedNFA == &other.serializedNFA);
            return position == other.position;
        }

        ConstRangeIterator& operator++()
        {
            ++position;
            return *this;
        }

        char first() const
        {
            return range()->first;
        }

        char last() const
        {
            return range()->last;
        }

        IterableConstTargets data() const
        {
            const ImmutableRange<char>* range = this->range();
            return { serializedNFA, range->targetStart, range->targetEnd };
        };

    private:
        const ImmutableRange<char>* range() const
        {
            return serializedNFA.transitions().pointerAt(position);
        }
    };

    struct IterableConstRange {
        const SerializedNFA& serializedNFA;
        uint32_t rangesStart;
        uint32_t rangesEnd;

        ConstRangeIterator begin() const { return { serializedNFA, rangesStart }; }
        ConstRangeIterator end() const { return { serializedNFA, rangesEnd }; }

#if CONTENT_EXTENSIONS_STATE_MACHINE_DEBUGGING
        void debugPrint() const
        {
            for (const auto& range : *this)
                WTFLogAlways("    %d-%d", range.first, range.last);
        }
#endif
    };

    IterableConstRange transitionsForNode(uint32_t nodeId) const
    {
        const auto* node = nodes().pointerAt(nodeId);
        return { *this, node->rangesStart, node->rangesEnd };
    }

private:
    struct Metadata {
        size_t nodesSize { 0 };
        size_t transitionsSize { 0 };
        size_t targetsSize { 0 };
        size_t epsilonTransitionsTargetsSize { 0 };
        size_t actionsSize { 0 };

        size_t nodesOffset { 0 };
        size_t transitionsOffset { 0 };
        size_t targetsOffset { 0 };
        size_t epsilonTransitionsTargetsOffset { 0 };
        size_t actionsOffset { 0 };
    };
    SerializedNFA(FileSystem::MappedFileData&&, Metadata&&);

    template<typename T>
    std::span<const T> spanAtOffsetInFile(size_t offset, size_t length) const;
    
    FileSystem::MappedFileData m_file;
    Metadata m_metadata;
};

} // namespace ContentExtensions
} // namespace WebCore

#endif // ENABLE(CONTENT_EXTENSIONS)

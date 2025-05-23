/*
 * Copyright (c) 2021-2023 Apple Inc. All rights reserved.
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

#pragma once

#import "ShaderStage.h"
#import <wtf/EnumeratedArray.h>
#import <wtf/FastMalloc.h>
#import <wtf/HashMap.h>
#import <wtf/HashTraits.h>
#import <wtf/Ref.h>
#import <wtf/RefCountedAndCanMakeWeakPtr.h>
#import <wtf/TZoneMalloc.h>
#import <wtf/Vector.h>
#import <wtf/WeakPtr.h>

struct WGPUBindGroupLayoutImpl {
};

namespace WebGPU {

class BindGroup;
class Device;
class PipelineLayout;

// https://gpuweb.github.io/gpuweb/#gpubindgrouplayout
class BindGroupLayout : public RefCountedAndCanMakeWeakPtr<BindGroupLayout>, public WGPUBindGroupLayoutImpl {
    WTF_MAKE_TZONE_ALLOCATED(BindGroupLayout);
public:
    template <typename T>
    using ShaderStageArray = EnumeratedArray<ShaderStage, T, ShaderStage::Compute>;
    using ArgumentBufferIndices = ShaderStageArray<std::optional<uint32_t>>;
    struct Entry {
        uint32_t binding;
        WGPUShaderStageFlags visibility;
        using BindingLayout = Variant<WGPUBufferBindingLayout, WGPUSamplerBindingLayout, WGPUTextureBindingLayout, WGPUStorageTextureBindingLayout, WGPUExternalTextureBindingLayout>;
        BindingLayout bindingLayout;
        ArgumentBufferIndices argumentBufferIndices;
        ArgumentBufferIndices bufferSizeArgumentBufferIndices;
        std::optional<uint32_t> vertexDynamicOffset;
        std::optional<uint32_t> fragmentDynamicOffset;
        std::optional<uint32_t> computeDynamicOffset;
        uint32_t dynamicOffsetsIndex;
    };
    using EntriesContainer = HashMap<uint32_t, Entry, DefaultHash<uint32_t>, WTF::UnsignedWithZeroKeyHashTraits<uint32_t>>;

#if USE(METAL_ARGUMENT_ACCESS_ENUMS)
    using BindingAccess = MTLArgumentAccess;
    static constexpr auto BindingAccessReadOnly = MTLArgumentAccessReadOnly;
    static constexpr auto BindingAccessReadWrite = MTLArgumentAccessReadWrite;
    static constexpr auto BindingAccessWriteOnly = MTLArgumentAccessWriteOnly;
#else
    using BindingAccess = MTLBindingAccess;
    static constexpr auto BindingAccessReadOnly = MTLBindingAccessReadOnly;
    static constexpr auto BindingAccessReadWrite = MTLBindingAccessReadWrite;
    static constexpr auto BindingAccessWriteOnly = MTLBindingAccessWriteOnly;
#endif
    using StageMapValue = BindingAccess;
    using StageMapTable = HashMap<uint64_t, StageMapValue, DefaultHash<uint64_t>, WTF::UnsignedWithZeroKeyHashTraits<uint64_t>>;
    using ArgumentIndices = HashSet<uint32_t, IntHash<uint32_t>, WTF::UnsignedWithZeroKeyHashTraits<uint32_t>>;

    static Ref<BindGroupLayout> create(StageMapTable&& stageMapTable, id<MTLArgumentEncoder> vertexArgumentEncoder, id<MTLArgumentEncoder> fragmentArgumentEncoder, id<MTLArgumentEncoder> computeArgumentEncoder, EntriesContainer&& entries, size_t sizeOfVertexDynamicOffsets, size_t sizeOfFragmentDynamicOffsets, size_t sizeOfComputeDynamicOffsets, bool isAutoGenerated, ShaderStageArray<uint32_t>&& uniformBuffersPerStage, ShaderStageArray<uint32_t>&& storageBuffersPerStage, ShaderStageArray<uint32_t>&& samplersPerStage, ShaderStageArray<uint32_t>&& texturesPerStage, ShaderStageArray<uint32_t>&& storageTexturesPerStage, uint32_t dynamicUniformBuffers, uint32_t dynamicStorageBuffers, ShaderStageArray<ArgumentIndices>&& argumentIndices, uint32_t identifier, const Device& device)
    {
        return adoptRef(*new BindGroupLayout(WTFMove(stageMapTable), vertexArgumentEncoder, fragmentArgumentEncoder, computeArgumentEncoder, WTFMove(entries), sizeOfVertexDynamicOffsets, sizeOfFragmentDynamicOffsets, sizeOfComputeDynamicOffsets, isAutoGenerated, WTFMove(uniformBuffersPerStage), WTFMove(storageBuffersPerStage), WTFMove(samplersPerStage), WTFMove(texturesPerStage), WTFMove(storageTexturesPerStage), dynamicUniformBuffers, dynamicStorageBuffers, WTFMove(argumentIndices), identifier, device));
    }
    static Ref<BindGroupLayout> createInvalid(const Device& device)
    {
        return adoptRef(*new BindGroupLayout(device));
    }

    ~BindGroupLayout();

    void setLabel(String&&);

    bool isValid() const { return m_valid; }

    NSUInteger encodedLength(ShaderStage) const;

    id<MTLArgumentEncoder> vertexArgumentEncoder() const { return m_vertexArgumentEncoder; }
    id<MTLArgumentEncoder> fragmentArgumentEncoder() const { return m_fragmentArgumentEncoder; }
    id<MTLArgumentEncoder> computeArgumentEncoder() const { return m_computeArgumentEncoder; }

    std::optional<StageMapValue> bindingAccessForBindingIndex(uint32_t bindingIndex, ShaderStage renderStage) const;
    NSUInteger argumentBufferIndexForEntryIndex(uint32_t bindingIndex, ShaderStage renderStage) const;
    std::optional<uint32_t> bufferSizeIndexForEntryIndex(uint32_t bindingIndex, ShaderStage renderStage) const;

    static bool isPresent(const WGPUBufferBindingLayout&);
    static bool isPresent(const WGPUSamplerBindingLayout&);
    static bool isPresent(const WGPUTextureBindingLayout&);
    static bool isPresent(const WGPUStorageTextureBindingLayout&);

    const EntriesContainer& entries() const { return m_bindGroupLayoutEntries; }
    const Vector<const Entry*> sortedEntries() const;
    uint32_t sizeOfVertexDynamicOffsets() const;
    uint32_t sizeOfFragmentDynamicOffsets() const;
    uint32_t sizeOfComputeDynamicOffsets() const;
    const Device& device() const;
    bool isAutoGenerated() const;
    const PipelineLayout* autogeneratedPipelineLayout() const;
    void setAutogeneratedPipelineLayout(const PipelineLayout*);

    uint32_t uniformBuffersPerStage(ShaderStage) const;
    uint32_t storageBuffersPerStage(ShaderStage) const;
    uint32_t samplersPerStage(ShaderStage) const;
    uint32_t texturesPerStage(ShaderStage) const;
    uint32_t storageTexturesPerStage(ShaderStage) const;
    uint32_t dynamicUniformBuffers() const;
    uint32_t dynamicStorageBuffers() const;
    uint32_t dynamicBufferCount() const;
    NSString* errorValidatingDynamicOffsets(std::span<const uint32_t>, const BindGroup&, uint32_t& maxOffset) const;
    NSString* errorValidatingBindGroupCompatibility(const BindGroupLayout&) const;
    static bool equalBindingEntries(const BindGroupLayout::Entry::BindingLayout&, const BindGroupLayout::Entry::BindingLayout&);
    const ArgumentIndices& argumentIndices(ShaderStage) const;
    uint32_t uniqueId() const { return m_uniqueIdentifier; }
private:
    BindGroupLayout(StageMapTable&&, id<MTLArgumentEncoder>, id<MTLArgumentEncoder>, id<MTLArgumentEncoder>, EntriesContainer&&, size_t sizeOfVertexDynamicOffsets, size_t sizeOfFragmentDynamicOffsets, size_t sizeOfComputeDynamicOffsets, bool isAutoGenerated, ShaderStageArray<uint32_t>&& uniformBuffersPerStage, ShaderStageArray<uint32_t>&& storageBuffersPerStage, ShaderStageArray<uint32_t>&& samplersPerStage, ShaderStageArray<uint32_t>&& texturesPerStage, ShaderStageArray<uint32_t>&& storageTexturesPerStage, uint32_t dynamicUniformBuffers, uint32_t dynamicStorageBuffers, ShaderStageArray<ArgumentIndices>&&, uint32_t identifier, const Device&);
    explicit BindGroupLayout(const Device&);

    const StageMapTable m_indicesForBinding;

    const id<MTLArgumentEncoder> m_vertexArgumentEncoder { nil };
    const id<MTLArgumentEncoder> m_fragmentArgumentEncoder { nil };
    const id<MTLArgumentEncoder> m_computeArgumentEncoder { nil };

    const EntriesContainer m_bindGroupLayoutEntries;
    Vector<const Entry*> m_sortedEntries;
    const bool m_valid { true };
    const size_t m_sizeOfVertexDynamicOffsets { 0 };
    const size_t m_sizeOfFragmentDynamicOffsets { 0 };
    const size_t m_sizeOfComputeDynamicOffsets { 0 };
    Ref<const Device> m_device;
    WeakPtr<const PipelineLayout> m_autogeneratedPipelineLayout;
    bool m_isAutoGenerated { false };
    ShaderStageArray<uint32_t> m_uniformBuffersPerStage;
    ShaderStageArray<uint32_t> m_storageBuffersPerStage;
    ShaderStageArray<uint32_t> m_samplersPerStage;
    ShaderStageArray<uint32_t> m_texturesPerStage;
    ShaderStageArray<uint32_t> m_storageTexturesPerStage;
    ShaderStageArray<ArgumentIndices> m_argumentIndices;
    uint32_t m_dynamicUniformBuffers { 0 };
    uint32_t m_dynamicStorageBuffers { 0 };
    uint32_t m_uniqueIdentifier { 0 };
};

} // namespace WebGPU

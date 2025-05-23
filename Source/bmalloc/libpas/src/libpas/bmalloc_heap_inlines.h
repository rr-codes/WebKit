/*
 * Copyright (c) 2021 Apple Inc. All rights reserved.
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

#ifndef BMALLOC_HEAP_INLINES_H
#define BMALLOC_HEAP_INLINES_H

#include "pas_platform.h"

PAS_IGNORE_WARNINGS_BEGIN("missing-field-initializers")

#include "bmalloc_heap.h"
#include "bmalloc_heap_config.h"
#include "bmalloc_heap_innards.h"
#include "pas_deallocate.h"
#include "pas_try_allocate.h"
#include "pas_try_allocate_array.h"
#include "pas_try_allocate_intrinsic.h"
#include "pas_try_allocate_primitive.h"
#include "pas_try_reallocate.h"

#if PAS_ENABLE_BMALLOC

PAS_BEGIN_EXTERN_C;

PAS_CREATE_TRY_ALLOCATE_PRIMITIVE(
    bmalloc_try_allocate_auxiliary_impl,
    BMALLOC_HEAP_CONFIG,
    &bmalloc_primitive_runtime_config.base,
    &bmalloc_allocator_counts,
    pas_allocation_result_identity);

PAS_CREATE_TRY_ALLOCATE_PRIMITIVE(
    bmalloc_allocate_auxiliary_impl,
    BMALLOC_HEAP_CONFIG,
    &bmalloc_primitive_runtime_config.base,
    &bmalloc_allocator_counts,
    pas_allocation_result_crash_on_error);

PAS_API void* bmalloc_try_allocate_auxiliary_with_alignment_casual(
    pas_primitive_heap_ref* heap_ref, size_t size, size_t alignment, pas_allocation_mode allocation_mode);
PAS_API void* bmalloc_allocate_auxiliary_with_alignment_casual(
    pas_primitive_heap_ref* heap_ref, size_t size, size_t alignment, pas_allocation_mode allocation_mode);

static PAS_ALWAYS_INLINE void* bmalloc_try_allocate_auxiliary_inline(pas_primitive_heap_ref* heap_ref,
                                                                     size_t size,
                                                                     pas_allocation_mode allocation_mode)
{
    pas_allocation_result result;
    result = bmalloc_try_allocate_auxiliary_impl_inline_only(heap_ref, size, 1, allocation_mode);
    if (PAS_LIKELY(result.did_succeed))
        return (void*)result.begin;
    return bmalloc_try_allocate_auxiliary_with_alignment_casual(heap_ref, size, 1, allocation_mode);
}

static PAS_ALWAYS_INLINE void* bmalloc_allocate_auxiliary_inline(pas_primitive_heap_ref* heap_ref,
                                                                 size_t size,
                                                                 pas_allocation_mode allocation_mode)
{
    pas_allocation_result result;
    result = bmalloc_allocate_auxiliary_impl_inline_only(heap_ref, size, 1, allocation_mode);
    if (PAS_LIKELY(result.did_succeed))
        return (void*)result.begin;
    return bmalloc_allocate_auxiliary_with_alignment_casual(heap_ref, size, 1, allocation_mode);
}

static PAS_ALWAYS_INLINE void* bmalloc_try_allocate_auxiliary_zeroed_inline(
    pas_primitive_heap_ref* heap_ref,
    size_t size,
    pas_allocation_mode allocation_mode)
{
    return (void*)pas_allocation_result_zero(
        bmalloc_try_allocate_auxiliary_impl(heap_ref, size, 1, allocation_mode),
        size).begin;
}

static PAS_ALWAYS_INLINE void* bmalloc_allocate_auxiliary_zeroed_inline(pas_primitive_heap_ref* heap_ref,
                                                                        size_t size,
                                                                        pas_allocation_mode allocation_mode)
{
    return (void*)pas_allocation_result_zero(
        bmalloc_allocate_auxiliary_impl(heap_ref, size, 1, allocation_mode),
        size).begin;
}

static PAS_ALWAYS_INLINE void*
bmalloc_try_allocate_auxiliary_with_alignment_inline(pas_primitive_heap_ref* heap_ref,
                                                     size_t size,
                                                     size_t alignment,
                                                     pas_allocation_mode allocation_mode)
{
    pas_allocation_result result;
    result = bmalloc_try_allocate_auxiliary_impl_inline_only(heap_ref, size, alignment, allocation_mode);
    if (PAS_LIKELY(result.did_succeed))
        return (void*)result.begin;
    return bmalloc_try_allocate_auxiliary_with_alignment_casual(heap_ref, size, alignment, allocation_mode);
}

static PAS_ALWAYS_INLINE void*
bmalloc_allocate_auxiliary_with_alignment_inline(pas_primitive_heap_ref* heap_ref,
                                                 size_t size,
                                                 size_t alignment,
                                                 pas_allocation_mode allocation_mode)
{
    pas_allocation_result result;
    result = bmalloc_allocate_auxiliary_impl_inline_only(heap_ref, size, alignment, allocation_mode);
    if (PAS_LIKELY(result.did_succeed))
        return (void*)result.begin;
    return bmalloc_allocate_auxiliary_with_alignment_casual(heap_ref, size, alignment, allocation_mode);
}

static PAS_ALWAYS_INLINE void* bmalloc_try_reallocate_auxiliary_inline(
    void* old_ptr,
    pas_primitive_heap_ref* heap_ref,
    size_t new_size,
    pas_allocation_mode allocation_mode,
    pas_reallocate_free_mode free_mode)
{
    return (void*)pas_try_reallocate_primitive(
        old_ptr,
        heap_ref,
        new_size,
        allocation_mode,
        BMALLOC_HEAP_CONFIG,
        bmalloc_try_allocate_auxiliary_impl_for_realloc,
        &bmalloc_primitive_runtime_config.base,
        pas_reallocate_allow_heap_teleport,
        free_mode).begin;
}

static PAS_ALWAYS_INLINE void* bmalloc_reallocate_auxiliary_inline(void* old_ptr,
                                                                   pas_primitive_heap_ref* heap_ref,
                                                                   size_t new_size,
                                                                   pas_allocation_mode allocation_mode,
                                                                   pas_reallocate_free_mode free_mode)
{
    return (void*)pas_try_reallocate_primitive(
        old_ptr,
        heap_ref,
        new_size,
        allocation_mode,
        BMALLOC_HEAP_CONFIG,
        bmalloc_allocate_auxiliary_impl_for_realloc,
        &bmalloc_primitive_runtime_config.base,
        pas_reallocate_allow_heap_teleport,
        free_mode).begin;
}

PAS_CREATE_TRY_ALLOCATE_INTRINSIC(
    bmalloc_try_allocate_impl,
    BMALLOC_HEAP_CONFIG,
    &bmalloc_intrinsic_runtime_config.base,
    &bmalloc_allocator_counts,
    pas_allocation_result_identity,
    &bmalloc_common_primitive_heap,
    &bmalloc_common_primitive_heap_support,
    pas_intrinsic_heap_is_designated);

/* Need to create a different set of allocation functions if we want to pass nontrivial alignment,
   since in that case we do not want to use the fancy lookup path. */
PAS_CREATE_TRY_ALLOCATE_INTRINSIC(
    bmalloc_try_allocate_with_alignment_impl,
    BMALLOC_HEAP_CONFIG,
    &bmalloc_intrinsic_runtime_config.base,
    &bmalloc_allocator_counts,
    pas_allocation_result_identity,
    &bmalloc_common_primitive_heap,
    &bmalloc_common_primitive_heap_support,
    pas_intrinsic_heap_is_not_designated);

PAS_CREATE_TRY_ALLOCATE_INTRINSIC(
    bmalloc_allocate_impl,
    BMALLOC_HEAP_CONFIG,
    &bmalloc_intrinsic_runtime_config.base,
    &bmalloc_allocator_counts,
    pas_allocation_result_crash_on_error,
    &bmalloc_common_primitive_heap,
    &bmalloc_common_primitive_heap_support,
    pas_intrinsic_heap_is_designated);

PAS_CREATE_TRY_ALLOCATE_INTRINSIC(
    bmalloc_allocate_with_alignment_impl,
    BMALLOC_HEAP_CONFIG,
    &bmalloc_intrinsic_runtime_config.base,
    &bmalloc_allocator_counts,
    pas_allocation_result_crash_on_error,
    &bmalloc_common_primitive_heap,
    &bmalloc_common_primitive_heap_support,
    pas_intrinsic_heap_is_not_designated);

PAS_API void* bmalloc_try_allocate_casual(size_t size, pas_allocation_mode allocation_mode);
PAS_API void* bmalloc_allocate_casual(size_t size, pas_allocation_mode allocation_mode);

static PAS_ALWAYS_INLINE void* bmalloc_try_allocate_inline(size_t size, pas_allocation_mode allocation_mode)
{
    if (allocation_mode == pas_always_compact_allocation_mode && PAS_USE_COMPACT_ONLY_HEAP)
        return (void*)bmalloc_try_allocate_auxiliary_inline(&bmalloc_compact_primitive_heap_ref, size, allocation_mode);
    pas_allocation_result result;
    result = bmalloc_try_allocate_impl_inline_only(size, 1, allocation_mode);
    if (PAS_LIKELY(result.did_succeed))
        return (void*)result.begin;
    return bmalloc_try_allocate_casual(size, allocation_mode);
}

static PAS_ALWAYS_INLINE void*
bmalloc_try_allocate_with_alignment_inline(size_t size, size_t alignment, pas_allocation_mode allocation_mode)
{
    if (allocation_mode == pas_always_compact_allocation_mode && PAS_USE_COMPACT_ONLY_HEAP)
        return (void*)bmalloc_try_allocate_auxiliary_with_alignment_inline(&bmalloc_compact_primitive_heap_ref, size, alignment, allocation_mode);
    return (void*)bmalloc_try_allocate_with_alignment_impl(size, alignment, allocation_mode).begin;
}

static PAS_ALWAYS_INLINE void* bmalloc_try_allocate_zeroed_inline(size_t size, pas_allocation_mode allocation_mode)
{
    if (allocation_mode == pas_always_compact_allocation_mode && PAS_USE_COMPACT_ONLY_HEAP)
        return (void*)bmalloc_try_allocate_auxiliary_zeroed_inline(&bmalloc_compact_primitive_heap_ref, size, allocation_mode);
    return (void*)pas_allocation_result_zero(
        bmalloc_try_allocate_impl(size, 1, allocation_mode),
        size).begin;
}

static PAS_ALWAYS_INLINE void* bmalloc_allocate_inline(size_t size, pas_allocation_mode allocation_mode)
{
    if (allocation_mode == pas_always_compact_allocation_mode && PAS_USE_COMPACT_ONLY_HEAP)
        return (void*)bmalloc_allocate_auxiliary_inline(&bmalloc_compact_primitive_heap_ref, size, allocation_mode);
    pas_allocation_result result;
    result = bmalloc_allocate_impl_inline_only(size, 1, allocation_mode);
    if (PAS_LIKELY(result.did_succeed))
        return (void*)result.begin;
    return bmalloc_allocate_casual(size, allocation_mode);
}

static PAS_ALWAYS_INLINE void*
bmalloc_allocate_with_alignment_inline(size_t size, size_t alignment, pas_allocation_mode allocation_mode)
{
    if (allocation_mode == pas_always_compact_allocation_mode && PAS_USE_COMPACT_ONLY_HEAP)
        return (void*)bmalloc_allocate_auxiliary_with_alignment_inline(&bmalloc_compact_primitive_heap_ref, size, alignment, allocation_mode);
    return (void*)bmalloc_allocate_with_alignment_impl(size, alignment, allocation_mode).begin;
}

static PAS_ALWAYS_INLINE void* bmalloc_allocate_zeroed_inline(size_t size, pas_allocation_mode allocation_mode)
{
    if (allocation_mode == pas_always_compact_allocation_mode && PAS_USE_COMPACT_ONLY_HEAP)
        return (void*)bmalloc_allocate_auxiliary_zeroed_inline(&bmalloc_compact_primitive_heap_ref, size, allocation_mode);
    return (void*)pas_allocation_result_zero(
        bmalloc_allocate_impl(size, 1, allocation_mode),
        size).begin;
}

static PAS_ALWAYS_INLINE void*
bmalloc_try_reallocate_inline(void* old_ptr, size_t new_size,
                              pas_allocation_mode allocation_mode,
                              pas_reallocate_free_mode free_mode)
{
    if (allocation_mode == pas_always_compact_allocation_mode && PAS_USE_COMPACT_ONLY_HEAP)
        return (void*)bmalloc_try_reallocate_auxiliary_inline(old_ptr, &bmalloc_compact_primitive_heap_ref, new_size, allocation_mode, free_mode);
    return (void*)pas_try_reallocate_intrinsic(
        old_ptr,
        &bmalloc_common_primitive_heap,
        new_size,
        allocation_mode,
        BMALLOC_HEAP_CONFIG,
        bmalloc_try_allocate_impl_for_realloc,
        pas_reallocate_allow_heap_teleport,
        free_mode).begin;
}

static PAS_ALWAYS_INLINE void*
bmalloc_reallocate_inline(void* old_ptr, size_t new_size,
                          pas_allocation_mode allocation_mode,
                          pas_reallocate_free_mode free_mode)
{
    if (allocation_mode == pas_always_compact_allocation_mode && PAS_USE_COMPACT_ONLY_HEAP)
        return (void*)bmalloc_reallocate_auxiliary_inline(old_ptr, &bmalloc_compact_primitive_heap_ref, new_size, allocation_mode, free_mode);
    return (void*)pas_try_reallocate_intrinsic(
        old_ptr,
        &bmalloc_common_primitive_heap,
        new_size,
        allocation_mode,
        BMALLOC_HEAP_CONFIG,
        bmalloc_allocate_impl_for_realloc,
        pas_reallocate_allow_heap_teleport,
        free_mode).begin;
}

PAS_CREATE_TRY_ALLOCATE(
    bmalloc_try_iso_allocate_impl,
    BMALLOC_HEAP_CONFIG,
    &bmalloc_typed_runtime_config.base,
    &bmalloc_allocator_counts,
    pas_allocation_result_identity);

PAS_CREATE_TRY_ALLOCATE(
    bmalloc_iso_allocate_impl,
    BMALLOC_HEAP_CONFIG,
    &bmalloc_typed_runtime_config.base,
    &bmalloc_allocator_counts,
    pas_allocation_result_crash_on_error);

PAS_API void* bmalloc_try_iso_allocate_casual(pas_heap_ref* heap_ref, pas_allocation_mode allocation_mode);
PAS_API void* bmalloc_iso_allocate_casual(pas_heap_ref* heap_ref, pas_allocation_mode allocation_mode);

static PAS_ALWAYS_INLINE void bmalloc_deallocate_inline(void* ptr)
{
    pas_deallocate(ptr, BMALLOC_HEAP_CONFIG);
}

PAS_END_EXTERN_C;

#endif /* PAS_ENABLE_BMALLOC */

PAS_IGNORE_WARNINGS_END

#endif /* BMALLOC_HEAP_INLINES_H */


# This file was generated with the command:
# "./gni-to-cmake.py" "src/libANGLE/renderer/metal/BUILD.gn" "Metal.cmake" "--prepend" "src/libANGLE/renderer/metal/"

# Copyright 2019 The ANGLE Project Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
#
# This file houses the build configuration for the ANGLE Metal back-end.
# Copyright 2022 The ANGLE Project Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

set(metal_backend_sources
    "src/libANGLE/renderer/metal/BufferMtl.h"
    "src/libANGLE/renderer/metal/BufferMtl.mm"
    "src/libANGLE/renderer/metal/CompilerMtl.h"
    "src/libANGLE/renderer/metal/CompilerMtl.mm"
    "src/libANGLE/renderer/metal/ContextMtl.h"
    "src/libANGLE/renderer/metal/ContextMtl.mm"
    "src/libANGLE/renderer/metal/DeviceMtl.h"
    "src/libANGLE/renderer/metal/DeviceMtl.mm"
    "src/libANGLE/renderer/metal/DisplayMtl.h"
    "src/libANGLE/renderer/metal/DisplayMtl.mm"
    "src/libANGLE/renderer/metal/DisplayMtl_api.h"
    "src/libANGLE/renderer/metal/FrameBufferMtl.h"
    "src/libANGLE/renderer/metal/FrameBufferMtl.mm"
    "src/libANGLE/renderer/metal/IOSurfaceSurfaceMtl.h"
    "src/libANGLE/renderer/metal/IOSurfaceSurfaceMtl.mm"
    "src/libANGLE/renderer/metal/ImageMtl.h"
    "src/libANGLE/renderer/metal/ImageMtl.mm"
    "src/libANGLE/renderer/metal/ProgramExecutableMtl.h"
    "src/libANGLE/renderer/metal/ProgramExecutableMtl.mm"
    "src/libANGLE/renderer/metal/ProgramMtl.h"
    "src/libANGLE/renderer/metal/ProgramMtl.mm"
    "src/libANGLE/renderer/metal/ProvokingVertexHelper.h"
    "src/libANGLE/renderer/metal/ProvokingVertexHelper.mm"
    "src/libANGLE/renderer/metal/QueryMtl.h"
    "src/libANGLE/renderer/metal/QueryMtl.mm"
    "src/libANGLE/renderer/metal/RenderBufferMtl.h"
    "src/libANGLE/renderer/metal/RenderBufferMtl.mm"
    "src/libANGLE/renderer/metal/RenderTargetMtl.h"
    "src/libANGLE/renderer/metal/RenderTargetMtl.mm"
    "src/libANGLE/renderer/metal/SamplerMtl.h"
    "src/libANGLE/renderer/metal/SamplerMtl.mm"
    "src/libANGLE/renderer/metal/ShaderMtl.h"
    "src/libANGLE/renderer/metal/ShaderMtl.mm"
    "src/libANGLE/renderer/metal/SurfaceMtl.h"
    "src/libANGLE/renderer/metal/SurfaceMtl.mm"
    "src/libANGLE/renderer/metal/SyncMtl.h"
    "src/libANGLE/renderer/metal/SyncMtl.mm"
    "src/libANGLE/renderer/metal/TextureMtl.h"
    "src/libANGLE/renderer/metal/TextureMtl.mm"
    "src/libANGLE/renderer/metal/TransformFeedbackMtl.h"
    "src/libANGLE/renderer/metal/TransformFeedbackMtl.mm"
    "src/libANGLE/renderer/metal/VertexArrayMtl.h"
    "src/libANGLE/renderer/metal/VertexArrayMtl.mm"
    "src/libANGLE/renderer/metal/blocklayoutMetal.cpp"
    "src/libANGLE/renderer/metal/blocklayoutMetal.h"
    "src/libANGLE/renderer/metal/mtl_buffer_manager.h"
    "src/libANGLE/renderer/metal/mtl_buffer_manager.mm"
    "src/libANGLE/renderer/metal/mtl_buffer_pool.h"
    "src/libANGLE/renderer/metal/mtl_buffer_pool.mm"
    "src/libANGLE/renderer/metal/mtl_command_buffer.h"
    "src/libANGLE/renderer/metal/mtl_command_buffer.mm"
    "src/libANGLE/renderer/metal/mtl_common.h"
    "src/libANGLE/renderer/metal/mtl_common.mm"
    "src/libANGLE/renderer/metal/mtl_context_device.h"
    "src/libANGLE/renderer/metal/mtl_context_device.mm"
    "src/libANGLE/renderer/metal/mtl_format_table_autogen.mm"
    "src/libANGLE/renderer/metal/mtl_format_utils.h"
    "src/libANGLE/renderer/metal/mtl_format_utils.mm"
    "src/libANGLE/renderer/metal/mtl_library_cache.h"
    "src/libANGLE/renderer/metal/mtl_library_cache.mm"
    "src/libANGLE/renderer/metal/mtl_msl_utils.h"
    "src/libANGLE/renderer/metal/mtl_msl_utils.mm"
    "src/libANGLE/renderer/metal/mtl_occlusion_query_pool.h"
    "src/libANGLE/renderer/metal/mtl_occlusion_query_pool.mm"
    "src/libANGLE/renderer/metal/mtl_pipeline_cache.h"
    "src/libANGLE/renderer/metal/mtl_pipeline_cache.mm"
    "src/libANGLE/renderer/metal/mtl_render_utils.h"
    "src/libANGLE/renderer/metal/mtl_render_utils.mm"
    "src/libANGLE/renderer/metal/mtl_resource_spi.h"
    "src/libANGLE/renderer/metal/mtl_resources.h"
    "src/libANGLE/renderer/metal/mtl_resources.mm"
    "src/libANGLE/renderer/metal/mtl_state_cache.h"
    "src/libANGLE/renderer/metal/mtl_state_cache.mm"
    "src/libANGLE/renderer/metal/mtl_utils.h"
    "src/libANGLE/renderer/metal/mtl_utils.mm"
    "src/libANGLE/renderer/metal/renderermtl_utils.cpp"
    "src/libANGLE/renderer/metal/renderermtl_utils.h"
    "src/libANGLE/renderer/metal/shaders/constants.h"
    "src/libANGLE/renderer/metal/shaders/mtl_internal_shaders_src_autogen.h"
    "src/libANGLE/renderer/metal/shaders/rewrite_indices_shared.h"
)
# We can build the ANGLE internal shaders at build-time if we have access to the Mac SDK in the "build" dir.
# Building internal shaders for iOS is not supported. The Chromium Mac SDK does not have all the required files.
# This is also an issue when cross-compiling for mac.

set(metal_internal_shader_compilation_supported
)

set(metal_internal_shaders_header
)

if(metal_internal_shader_compilation_supported)
    list(APPEND metal_backend_sources metal_internal_shaders_header)
endif()

if(metal_internal_shader_compilation_supported)
    set(_metal_internal_shaders_air_file
    )
    set(_metal_internal_shaders_metallib_file
    )
endif()

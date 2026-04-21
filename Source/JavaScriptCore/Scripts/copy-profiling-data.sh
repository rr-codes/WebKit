#!/bin/bash -e

# Decompresses and copies PGO profiles from WebKitAdditions to a derived folder.

PROFILES_FOLDER="${SCRIPT_INPUT_FILE_0}"
EMPTY_PROFDATA="${SCRIPT_INPUT_FILE_1}"

function decompress {
    eval $(stat -s "${1}")
    if [ ${st_size} -lt 1024 ]; then
        if [ "${CONFIGURATION}" = Production ]; then
            echo "error: ${1} is <1KB, is it a Git LFS stub?"\
                "Ensure this file was checked out on a machine with git-lfs installed."
            exit 1
        else
            echo "warning: ${1} is <1KB, is it a Git LFS stub?"\
                "To build with production optimizations, ensure this file was checked out on a machine with git-lfs installed."\
                "Falling back to stub profile data."
            cp -vf "${EMPTY_PROFDATA}" "${2}"
        fi
    else
        compression_tool -v -decode -i "${1}" -o "${2}"
    fi
}

if [ "${WK_ENABLE_PGO_USE}" = YES ]; then
    for arch in ${ARCHS_BASE:-${ARCHS}}; do
        name=${arch}-${LLVM_TARGET_TRIPLE_VENDOR}-${LLVM_TARGET_TRIPLE_OS_VERSION}${LLVM_TARGET_TRIPLE_SUFFIX}.profile.compressed
        decompress "${PROFILES_FOLDER}/${name}" "${SCRIPT_OUTPUT_FILE_0}"
    done
    echo "dependencies: ${SCRIPT_INPUT_FILE_0}/JavaScriptCore.profdata.compressed" > "${TARGET_TEMP_DIR}/copy-profiling-data.d"
else
    echo "dependencies: " > "${DERIVED_FILES_DIR}/copy-profiling-data.d"
fi

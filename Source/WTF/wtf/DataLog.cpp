/*
 * Copyright (C) 2012-2022 Apple Inc. All rights reserved.
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
#include <wtf/DataLog.h>

#include <stdarg.h>
#include <string.h>
#include <wtf/Assertions.h>
#include <wtf/FilePrintStream.h>
#include <wtf/LockedPrintStream.h>
#include <wtf/ProcessID.h>
#include <mutex>

WTF_ALLOW_UNSAFE_BUFFER_USAGE_BEGIN

// Setting DATA_LOG_TO_FILE to 1 will cause logs to be sent to the filename
// specified in the WTF_DATA_LOG_FILENAME envvar.
#define DATA_LOG_TO_FILE 0
// Alternatively, setting this to 1 will override the above settings and use
// the temp directory from confstr instead of the hardcoded directory.
#define DATA_LOG_TO_DARWIN_TEMP_DIR 0

// Setting DATA_LOG_TO_FILE_IGNORE_ENVVAR to 1 will cause both data-log options
// above to always use the fallback filename.
#define DATA_LOG_IGNORE_ENV_VAR 0

#if DATA_LOG_TO_FILE && DATA_LOG_TO_DARWIN_TEMP_DIR
#error "Set at most one data-log file target"
#endif

#if OS(WINDOWS) && DATA_LOG_TO_DARWIN_TEMP_DIR
#error "Cannot log to Darwin temp dir on Windows"
#endif

// Note that we will append ".<pid>.txt" where <pid> is the PID.
#define DATA_LOG_DEFAULT_BASENAME "WTFLog"
#if OS(WINDOWS)
#define DATA_LOG_DEFAULT_PATH "%localappdata%\\Temp\\"
#else
#define DATA_LOG_DEFAULT_PATH "/tmp/"
#endif

namespace WTF {

static constexpr size_t maxPathLength = 1024;

static PrintStream* s_file;
static uint64_t s_fileData[(sizeof(FilePrintStream) + 7) / 8];
static uint64_t s_lockedFileData[(sizeof(LockedPrintStream) + 7) / 8];

static void initializeLogFileOnce()
{
    const char* filename = nullptr;

    if (s_file)
        return;

#if DATA_LOG_TO_FILE || DATA_LOG_TO_DARWIN_TEMP_DIR
#if DATA_LOG_TO_DARWIN_TEMP_DIR
    std::array<char, maxPathLength + 1> filenameBuffer;
    const char* logBasename = DATA_LOG_DEFAULT_BASENAME;
#if !DATA_LOG_IGNORE_ENV_VAR
    logBasename = getenv("WTF_DATA_LOG_FILENAME");
    if (!logBasename)
        logBasename = DATA_LOG_DEFAULT_BASENAME;
#endif

    bool success = confstr(_CS_DARWIN_USER_TEMP_DIR, filenameBuffer.data(), filenameBuffer.size());
    if (success) {
        // FIXME: Assert that the path ends with a slash instead of adding a slash if it does not exist
        // once <rdar://problem/23579077> is fixed in all iOS Simulator versions that we use.
        size_t lastComponentLength = strlen(logBasename) + 20; // More than enough for ".<pid>.txt"
        size_t dirnameLength = strlenSpan(filenameBuffer);
        bool shouldAddPathSeparator = filenameBuffer[dirnameLength - 1] != '/' && logBasename[0] != '/';
        if (lastComponentLength + shouldAddPathSeparator <= filenameBuffer.size() - dirnameLength - 1) {
            if (shouldAddPathSeparator)
                strncat(filenameBuffer.data(), "/", 1);
            strncat(filenameBuffer.data(), logBasename, filenameBuffer.size() - strlenSpan(filenameBuffer) - 1);
            filename = filenameBuffer.data();
        }
    }
#elif DATA_LOG_TO_FILE // !DATA_LOG_TO_DARWIN_TEMP_DIR
    [[maybe_unused]] static constexpr const char* fallbackFilepath = DATA_LOG_DEFAULT_PATH DATA_LOG_DEFAULT_BASENAME;
    filename = fallbackFilepath;
#if !DATA_LOG_IGNORE_ENV_VAR
    filename = getenv("WTF_DATA_LOG_FILENAME");
    if (!filename)
        filename = fallbackFilepath;
#endif
#endif // DATA_LOG_TO_FILE
    char actualFilename[maxPathLength + 1];
    if (filename && !contains(unsafeSpan(filename), "%pid"_span)) {
        snprintf(actualFilename, sizeof(actualFilename), "%s.%%pid.txt", filename);
        filename = actualFilename;
    }
#endif // DATA_LOG_TO_FILE || DATA_LOG_TO_DARWIN_TEMP_DIR

    setDataFile(filename);
}

static void initializeLogFile()
{
    static std::once_flag once;
    std::call_once(
        once,
        [] {
            initializeLogFileOnce();
        });
}

void setDataFile(const char* path)
{
    FilePrintStream* file = nullptr;
    char formattedPath[maxPathLength + 1];
    const char* pathToOpen = path;

    if (path) {
        auto pathSpan = unsafeSpan(path);
        if (size_t pidIndex = find(pathSpan, "%pid"_span); pidIndex != notFound) {
            size_t pathCharactersAvailable = std::min(maxPathLength, pidIndex);
            strncpy(formattedPath, path, pathCharactersAvailable);
            char* nextDest = formattedPath + pathCharactersAvailable;
            pathCharactersAvailable = maxPathLength - pathCharactersAvailable;
            if (pathCharactersAvailable) {
                int pidTextLength = snprintf(nextDest, pathCharactersAvailable, "%d", getCurrentProcessID());

                if (pidTextLength >= 0 && static_cast<size_t>(pidTextLength) < pathCharactersAvailable) {
                    pathCharactersAvailable -= static_cast<size_t>(pidTextLength);
                    nextDest += pidTextLength;
                    strncpy(nextDest, pathSpan.subspan(pidIndex + 4).data(), pathCharactersAvailable);
                }
            }
            formattedPath[maxPathLength] = '\0';
            pathToOpen = formattedPath;
        }

        file = FilePrintStream::open(pathToOpen, "w").release();
        if (file)
            WTFLogAlways("*** DataLog output to \"%s\" ***\n", pathToOpen);
        else
            WTFLogAlways("Warning: Could not open DataLog file %s for writing.\n", pathToOpen);
    }

    if (!file) {
        // Use placement new; this makes it easier to use dataLog() to debug
        // fastMalloc.
        file = new (s_fileData) FilePrintStream(stderr, FilePrintStream::Borrow);
    }

    setvbuf(file->file(), nullptr, _IONBF, 0); // Prefer unbuffered output, so that we get a full log upon crash or deadlock.

    if (s_file)
        s_file->flush();

    s_file = new (s_lockedFileData) LockedPrintStream(std::unique_ptr<FilePrintStream>(file));
}

void setDataFile(std::unique_ptr<PrintStream>&& file)
{
    RELEASE_ASSERT(!s_file || reinterpret_cast<void*>(s_file) == &s_lockedFileData[0]);
    s_file = file.release();
}

PrintStream& dataFile()
{
    initializeLogFile();
    return *s_file;
}

void dataLogFV(const char* format, va_list argList)
{
    dataFile().vprintf(format, argList);
}

void dataLogF(const char* format, ...)
{
    va_list argList;
    va_start(argList, format);
    dataLogFV(format, argList);
    va_end(argList);
}

void dataLogFString(const char* str)
{
    dataFile().printf("%s", str);
}

} // namespace WTF

WTF_ALLOW_UNSAFE_BUFFER_USAGE_END

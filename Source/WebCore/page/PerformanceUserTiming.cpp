/*
 * Copyright (C) 2012 Intel Inc. All rights reserved.
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
#include "PerformanceUserTiming.h"

#include "Document.h"
#include "FrameDestructionObserverInlines.h"
#include "InspectorInstrumentation.h"
#include "MessagePort.h"
#include "PerformanceMarkOptions.h"
#include "PerformanceMeasureOptions.h"
#include "PerformanceTiming.h"
#include "SerializedScriptValue.h"
#include "WorkerOrWorkletGlobalScope.h"
#include <JavaScriptCore/JSCJSValueInlines.h>
#include <wtf/SortedArrayMap.h>
#include <wtf/TZoneMallocInlines.h>
#include <wtf/text/MakeString.h>

namespace WebCore {

WTF_MAKE_TZONE_ALLOCATED_IMPL(PerformanceUserTiming);

using NavigationTimingFunction = unsigned long long (PerformanceTiming::*)() const;

static constexpr std::pair<ComparableASCIILiteral, NavigationTimingFunction> restrictedMarkMappings[] = {
    { "connectEnd"_s, &PerformanceTiming::connectEnd },
    { "connectStart"_s, &PerformanceTiming::connectStart },
    { "domComplete"_s, &PerformanceTiming::domComplete },
    { "domContentLoadedEventEnd"_s, &PerformanceTiming::domContentLoadedEventEnd },
    { "domContentLoadedEventStart"_s, &PerformanceTiming::domContentLoadedEventStart },
    { "domInteractive"_s, &PerformanceTiming::domInteractive },
    { "domLoading"_s, &PerformanceTiming::domLoading },
    { "domainLookupEnd"_s, &PerformanceTiming::domainLookupEnd },
    { "domainLookupStart"_s, &PerformanceTiming::domainLookupStart },
    { "fetchStart"_s, &PerformanceTiming::fetchStart },
    { "loadEventEnd"_s, &PerformanceTiming::loadEventEnd },
    { "loadEventStart"_s, &PerformanceTiming::loadEventStart },
    { "navigationStart"_s, &PerformanceTiming::navigationStart },
    { "redirectEnd"_s, &PerformanceTiming::redirectEnd },
    { "redirectStart"_s, &PerformanceTiming::redirectStart },
    { "requestStart"_s, &PerformanceTiming::requestStart },
    { "responseEnd"_s, &PerformanceTiming::responseEnd },
    { "responseStart"_s, &PerformanceTiming::responseStart },
    { "secureConnectionStart"_s, &PerformanceTiming::secureConnectionStart },
    { "unloadEventEnd"_s, &PerformanceTiming::unloadEventEnd },
    { "unloadEventStart"_s, &PerformanceTiming::unloadEventStart },
};
static constexpr SortedArrayMap restrictedMarkFunctions { restrictedMarkMappings };

bool PerformanceUserTiming::isRestrictedMarkName(const String& markName)
{
    return restrictedMarkFunctions.contains(markName);
}

PerformanceUserTiming::PerformanceUserTiming(Performance& performance)
    : m_performance(performance)
{
}

static void clearPerformanceEntries(PerformanceEntryMap& map, const String& name)
{
    if (name.isNull())
        map.clear();
    else
        map.remove(name);
}

static void addPerformanceEntry(PerformanceEntryMap& map, const String& name, PerformanceEntry& entry)
{
    auto& performanceEntryList = map.ensure(name, [] { return Vector<Ref<PerformanceEntry>>(); }).iterator->value;
    performanceEntryList.append(entry);
}

ExceptionOr<Ref<PerformanceMark>> PerformanceUserTiming::mark(JSC::JSGlobalObject& globalObject, const String& markName, std::optional<PerformanceMarkOptions>&& markOptions)
{
    Ref context = *m_performance->scriptExecutionContext();

    std::optional<MonotonicTime> timestamp;
    if (markOptions && markOptions->startTime)
        timestamp = m_performance->monotonicTimeFromRelativeTime(*markOptions->startTime);

    InspectorInstrumentation::performanceMark(context.get(), markName, timestamp);

    auto mark = PerformanceMark::create(globalObject, context, markName, WTFMove(markOptions));
    if (mark.hasException())
        return mark.releaseException();

    addPerformanceEntry(m_marksMap, markName, mark.returnValue().get());
    return mark.releaseReturnValue();
}

void PerformanceUserTiming::clearMarks(const String& markName)
{
    clearPerformanceEntries(m_marksMap, markName);
}

ExceptionOr<double> PerformanceUserTiming::convertMarkToTimestamp(const Variant<String, double>& mark) const
{
    return WTF::switchOn(mark, [&](auto& value) {
        return convertMarkToTimestamp(value);
    });
}

ExceptionOr<double> PerformanceUserTiming::convertMarkToTimestamp(const String& mark) const
{
    if (!isMainThread()) {
        if (restrictedMarkFunctions.contains(mark))
            return Exception { ExceptionCode::TypeError };
    } else {
        if (auto function = restrictedMarkFunctions.tryGet(mark)) {
            if (*function == &PerformanceTiming::navigationStart)
                return 0.0;

            // PerformanceTiming should always be non-null for the Document ScriptExecutionContext.
            ASSERT(m_performance->timing());
            auto timing = m_performance->timing();
            auto startTime = timing->navigationStart();
            auto endTime = ((*timing).*(*function))();
            if (!endTime)
                return Exception { ExceptionCode::InvalidAccessError };
            return endTime - startTime;
        }
    }

    auto iterator = m_marksMap.find(mark);
    if (iterator != m_marksMap.end())
        return iterator->value.last()->startTime();

    return Exception { ExceptionCode::SyntaxError, makeString("No mark named '"_s, mark, "' exists"_s) };
}

ExceptionOr<double> PerformanceUserTiming::convertMarkToTimestamp(double mark) const
{
    if (mark < 0)
        return Exception { ExceptionCode::TypeError };
    return mark;
}

ExceptionOr<Ref<PerformanceMeasure>> PerformanceUserTiming::measure(const String& measureName, const String& startMark, const String& endMark)
{
    double endTime;
    if (!endMark.isNull()) {
        auto end = convertMarkToTimestamp(endMark);
        if (end.hasException())
            return end.releaseException();
        endTime = end.returnValue();
    } else
        endTime = m_performance->now();

    double startTime;
    if (!startMark.isNull()) {
        auto start = convertMarkToTimestamp(startMark);
        if (start.hasException())
            return start.releaseException();
        startTime = start.returnValue();
    } else
        startTime = 0.0;
        
    auto measure = PerformanceMeasure::create(measureName, startTime, endTime, SerializedScriptValue::nullValue());
    if (measure.hasException())
        return measure.releaseException();

    addPerformanceEntry(m_measuresMap, measureName, measure.returnValue().get());
    return measure.releaseReturnValue();
}

ExceptionOr<Ref<PerformanceMeasure>> PerformanceUserTiming::measure(JSC::JSGlobalObject& globalObject, const String& measureName, const PerformanceMeasureOptions& measureOptions)
{
    double endTime;
    if (measureOptions.end) {
        auto end = convertMarkToTimestamp(*measureOptions.end);
        if (end.hasException())
            return end.releaseException();
        endTime = end.returnValue();
    } else if (measureOptions.start && measureOptions.duration) {
        auto start = convertMarkToTimestamp(*measureOptions.start);
        if (start.hasException())
            return start.releaseException();
        auto duration = convertMarkToTimestamp(*measureOptions.duration);
        if (duration.hasException())
            return duration.releaseException();
        endTime = start.returnValue() + duration.returnValue();
    } else
        endTime = m_performance->now();

    double startTime;
    if (measureOptions.start) {
        auto start = convertMarkToTimestamp(*measureOptions.start);
        if (start.hasException())
            return start.releaseException();
        startTime = start.returnValue();
    } else if (measureOptions.duration && measureOptions.end) {
        auto duration = convertMarkToTimestamp(*measureOptions.duration);
        if (duration.hasException())
            return duration.releaseException();
        auto end = convertMarkToTimestamp(*measureOptions.end);
        if (end.hasException())
            return end.releaseException();
        startTime = end.returnValue() - duration.returnValue();
    } else
        startTime = 0;


    JSC::JSValue detail = measureOptions.detail;
    if (detail.isUndefined())
        detail = JSC::jsNull();

    Vector<Ref<MessagePort>> ignoredMessagePorts;
    auto serializedDetail = SerializedScriptValue::create(globalObject, detail, { }, ignoredMessagePorts);
    if (serializedDetail.hasException())
        return serializedDetail.releaseException();

    auto measure = PerformanceMeasure::create(measureName, startTime, endTime, serializedDetail.releaseReturnValue());
    if (measure.hasException())
        return measure.releaseException();

    addPerformanceEntry(m_measuresMap, measureName, measure.returnValue().get());
    return measure.releaseReturnValue();
}

static bool isNonEmptyDictionary(const PerformanceMeasureOptions& measureOptions)
{
    return !measureOptions.detail.isUndefined() || measureOptions.start || measureOptions.duration || measureOptions.end;
}

ExceptionOr<Ref<PerformanceMeasure>> PerformanceUserTiming::measure(JSC::JSGlobalObject& globalObject, const String& measureName, std::optional<StartOrMeasureOptions>&& startOrMeasureOptions, const String& endMark)
{
    if (startOrMeasureOptions) {
        return WTF::switchOn(*startOrMeasureOptions,
            [&] (const PerformanceMeasureOptions& measureOptions) -> ExceptionOr<Ref<PerformanceMeasure>> {
                if (isNonEmptyDictionary(measureOptions)) {
                    if (!endMark.isNull())
                        return Exception { ExceptionCode::TypeError };
                    if (!measureOptions.start && !measureOptions.end)
                        return Exception { ExceptionCode::TypeError };
                    if (measureOptions.start && measureOptions.duration && measureOptions.end)
                        return Exception { ExceptionCode::TypeError };
                }

                return measure(globalObject, measureName, measureOptions);
            },
            [&] (const String& startMark) {
                return measure(measureName, startMark, endMark);
            }
        );
    }

    return measure(measureName, { }, endMark);
}

void PerformanceUserTiming::clearMeasures(const String& measureName)
{
    clearPerformanceEntries(m_measuresMap, measureName);
}

static Vector<Ref<PerformanceEntry>> convertToEntrySequence(const PerformanceEntryMap& map)
{
    Vector<Ref<PerformanceEntry>> entries;
    for (auto& entry : map.values())
        entries.appendVector(entry);
    return entries;
}

Vector<Ref<PerformanceEntry>> PerformanceUserTiming::getMarks() const
{
    return convertToEntrySequence(m_marksMap);
}

Vector<Ref<PerformanceEntry>> PerformanceUserTiming::getMarks(const String& name) const
{
    return m_marksMap.get(name);
}

Vector<Ref<PerformanceEntry>> PerformanceUserTiming::getMeasures() const
{
    return convertToEntrySequence(m_measuresMap);
}

Vector<Ref<PerformanceEntry>> PerformanceUserTiming::getMeasures(const String& name) const
{
    return m_measuresMap.get(name);
}

} // namespace WebCore

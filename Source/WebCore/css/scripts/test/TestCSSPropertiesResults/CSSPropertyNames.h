// This file is automatically generated from CSSProperties.json by the process-css-properties.py script. Do not edit it.

#pragma once

#include <array>
#include <wtf/HashFunctions.h>
#include <wtf/HashTraits.h>

namespace WebCore {

class Settings;

enum CSSPropertyID : uint16_t {
    CSSPropertyInvalid = 0,
    CSSPropertyCustom = 1,
    CSSPropertyTestTopPriority = 2,
    CSSPropertyTestHighPriority = 3,
    CSSPropertyFirstTestDescriptorForFirstDescriptor = 4,
    CSSPropertyFirstTestDescriptorForSecondDescriptor = 5,
    CSSPropertyTestAnimationWrapper = 6,
    CSSPropertyTestAnimationWrapperAccelerationAlways = 7,
    CSSPropertyTestAnimationWrapperAccelerationThreadedOnly = 8,
    CSSPropertyTestBoundedRepetitionWithCommas = 9,
    CSSPropertyTestBoundedRepetitionWithCommasFixed = 10,
    CSSPropertyTestBoundedRepetitionWithCommasNoSingleItemOpt = 11,
    CSSPropertyTestBoundedRepetitionWithCommasSingleItemOpt = 12,
    CSSPropertyTestBoundedRepetitionWithSpaces = 13,
    CSSPropertyTestBoundedRepetitionWithSpacesFixed = 14,
    CSSPropertyTestBoundedRepetitionWithSpacesNoSingleItemOpt = 15,
    CSSPropertyTestBoundedRepetitionWithSpacesSingleItemOpt = 16,
    CSSPropertyTestBoundedRepetitionWithSpacesWithType = 17,
    CSSPropertyTestBoundedRepetitionWithSpacesWithTypeNoSingleItemOpt = 18,
    CSSPropertyTestBoundedRepetitionWithSpacesWithTypeWithDefaultPrevious = 19,
    CSSPropertyTestBoundedRepetitionWithSpacesWithTypeWithDefaultPreviousTwo = 20,
    CSSPropertyTestColor = 21,
    CSSPropertyTestColorAllowsTypesAbsolute = 22,
    CSSPropertyTestColorAllowsTypesAbsolutePlusQuirkyColors = 23,
    CSSPropertyTestColorQuirkyColors = 24,
    CSSPropertyTestFunctionBoundedParameters = 25,
    CSSPropertyTestFunctionFixedParameters = 26,
    CSSPropertyTestFunctionNoParameters = 27,
    CSSPropertyTestFunctionParametersMatchAllAnyOrder = 28,
    CSSPropertyTestFunctionParametersMatchAllAnyOrderWithOptional = 29,
    CSSPropertyTestFunctionParametersMatchAllOrdered = 30,
    CSSPropertyTestFunctionParametersMatchAllOrderedWithOptional = 31,
    CSSPropertyTestFunctionParametersMatchOneOrMoreAnyOrder = 32,
    CSSPropertyTestFunctionSingleParameter = 33,
    CSSPropertyTestFunctionSingleParameterMatchOne = 34,
    CSSPropertyTestFunctionSingleParameterOptional = 35,
    CSSPropertyTestFunctionUnboundedParametersNoMin = 36,
    CSSPropertyTestFunctionUnboundedParametersWithMinimum = 37,
    CSSPropertyTestImage = 38,
    CSSPropertyTestImageNoImageSet = 39,
    CSSPropertyTestKeyword = 40,
    CSSPropertyTestKeywordWithAliasedTo = 41,
    CSSPropertyTestMatchAllAnyOrder = 42,
    CSSPropertyTestMatchAllAnyOrderWithCustomType = 43,
    CSSPropertyTestMatchAllAnyOrderWithOptional = 44,
    CSSPropertyTestMatchAllAnyOrderWithOptionalAndCustomType = 45,
    CSSPropertyTestMatchAllAnyOrderWithOptionalAndMultipleRequiredAndCustomType = 46,
    CSSPropertyTestMatchAllAnyOrderWithOptionalAndMultipleRequiredAndCustomTypeNoSingleItemOpt = 47,
    CSSPropertyTestMatchAllAnyOrderWithOptionalAndMultipleRequiredAndPreserveOrderAndCustomType = 48,
    CSSPropertyTestMatchAllAnyOrderWithOptionalAndMultipleRequiredAndPreserveOrderAndCustomTypeNoSingleItemOpt = 49,
    CSSPropertyTestMatchAllAnyOrderWithOptionalAndPreserveOrderAndCustomType = 50,
    CSSPropertyTestMatchAllAnyOrderWithOptionalNoSingleItemOpt = 51,
    CSSPropertyTestMatchAllAnyOrderWithOptionalSingleItemOpt = 52,
    CSSPropertyTestMatchAllAnyOrderWithOptionalWithPreserveOrder = 53,
    CSSPropertyTestMatchAllAnyOrderWithOptionalWithPreserveOrderNoSingleItemOpt = 54,
    CSSPropertyTestMatchAllAnyOrderWithPreserveOrder = 55,
    CSSPropertyTestMatchAllAnyOrderWithPreserveOrderAndCustomType = 56,
    CSSPropertyTestMatchAllAnyOrderWithPreserveOrderNoSingleItemOpt = 57,
    CSSPropertyTestMatchAllOrdered = 58,
    CSSPropertyTestMatchAllOrderedWithCustomType = 59,
    CSSPropertyTestMatchAllOrderedWithOptional = 60,
    CSSPropertyTestMatchAllOrderedWithOptionalAndCustomType = 61,
    CSSPropertyTestMatchAllOrderedWithOptionalAndCustomTypeAndNoSingleItemOpt = 62,
    CSSPropertyTestMatchAllOrderedWithOptionalAndMultipleRequired = 63,
    CSSPropertyTestMatchAllOrderedWithOptionalAndMultipleRequiredAndCustomType = 64,
    CSSPropertyTestMatchAllOrderedWithOptionalNoSingleItemOpt = 65,
    CSSPropertyTestMatchAllOrderedWithOptionalSingleItemOpt = 66,
    CSSPropertyTestMatchOne = 67,
    CSSPropertyTestMatchOneOrMoreAnyOrder = 68,
    CSSPropertyTestMatchOneOrMoreAnyOrderNoSingleItemOpt = 69,
    CSSPropertyTestMatchOneOrMoreAnyOrderWithCustomType = 70,
    CSSPropertyTestMatchOneOrMoreAnyOrderWithCustomTypeNoSingleItemOpt = 71,
    CSSPropertyTestMatchOneOrMoreAnyOrderWithPreserveOrder = 72,
    CSSPropertyTestMatchOneOrMoreAnyOrderWithPreserveOrderAndCustomType = 73,
    CSSPropertyTestMatchOneOrMoreAnyOrderWithPreserveOrderAndCustomTypeNoSingleItemOpt = 74,
    CSSPropertyTestMatchOneOrMoreAnyOrderWithPreserveOrderNoSingleItemOpt = 75,
    CSSPropertyTestMatchOneWithGroupWithSettingsFlag = 76,
    CSSPropertyTestMatchOneWithKeywordWithSettingsFlag = 77,
    CSSPropertyTestMatchOneWithMultipleKeywords = 78,
    CSSPropertyTestMatchOneWithReferenceWithSettingsFlag = 79,
    CSSPropertyTestMatchOneWithSettingsFlag = 80,
    CSSPropertyTestNumericValueRange = 81,
    CSSPropertyTestProperty = 82,
    CSSPropertyTestSettingsOne = 83,
    CSSPropertyTestUnboundedRepetitionWithCommasWithMin = 84,
    CSSPropertyTestUnboundedRepetitionWithCommasWithMinNoSingleItemOpt = 85,
    CSSPropertyTestUnboundedRepetitionWithCommasWithMinSingleItemOpt = 86,
    CSSPropertyTestUnboundedRepetitionWithSpacesNoMin = 87,
    CSSPropertyTestUnboundedRepetitionWithSpacesNoMinNoSingleItemOpt = 88,
    CSSPropertyTestUnboundedRepetitionWithSpacesWithMin = 89,
    CSSPropertyTestUnboundedRepetitionWithSpacesWithMinNoSingleItemOpt = 90,
    CSSPropertyTestUnboundedRepetitionWithSpacesWithMinSingleItemOpt = 91,
    CSSPropertyTestUsingSharedRule = 92,
    CSSPropertyTestUsingSharedRuleExported = 93,
    CSSPropertyTestUsingSharedRuleWithOverrideFunction = 94,
    CSSPropertyTestSinkPriority = 95,
    CSSPropertyTestLogicalPropertyGroupLogicalBlock = 96,
    CSSPropertyTestLogicalPropertyGroupLogicalInline = 97,
    CSSPropertyTestLogicalPropertyGroupPhysicalHorizontal = 98,
    CSSPropertyTestLogicalPropertyGroupPhysicalVertical = 99,
    CSSPropertyFont = 100,
    CSSPropertyTestShorthandOne = 101,
    CSSPropertyTestShorthandTwo = 102,
};

// Enum value of the first "real" CSS property, which excludes
// CSSPropertyInvalid and CSSPropertyCustom.
constexpr uint16_t firstCSSProperty = 2;
// Total number of enum values in the CSSPropertyID enum. If making an array
// that can be indexed into using the enum value, use this as the size.
constexpr uint16_t cssPropertyIDEnumValueCount = 103;
// Number of "real" CSS properties. This differs from cssPropertyIDEnumValueCount,
// as this doesn't consider CSSPropertyInvalid and CSSPropertyCustom.
constexpr uint16_t numCSSProperties = 101;
constexpr unsigned maxCSSPropertyNameLength = 114;
constexpr auto firstTopPriorityProperty = CSSPropertyID::CSSPropertyTestTopPriority;
constexpr auto lastTopPriorityProperty = CSSPropertyID::CSSPropertyTestTopPriority;
constexpr auto firstHighPriorityProperty = CSSPropertyID::CSSPropertyTestHighPriority;
constexpr auto lastHighPriorityProperty = CSSPropertyID::CSSPropertyTestHighPriority;
constexpr auto firstLowPriorityProperty = CSSPropertyID::CSSPropertyFirstTestDescriptorForFirstDescriptor;
constexpr auto lastLowPriorityProperty = CSSPropertyID::CSSPropertyTestSinkPriority;
constexpr auto firstLogicalGroupProperty = CSSPropertyID::CSSPropertyTestLogicalPropertyGroupLogicalBlock;
constexpr auto lastLogicalGroupProperty = CSSPropertyID::CSSPropertyTestLogicalPropertyGroupPhysicalVertical;
constexpr auto firstShorthandProperty = CSSPropertyID::CSSPropertyFont;
constexpr auto lastShorthandProperty = CSSPropertyID::CSSPropertyTestShorthandTwo;
constexpr uint16_t numCSSPropertyLonghands = firstShorthandProperty - firstCSSProperty;
extern const std::array<CSSPropertyID, 96> computedPropertyIDs;

struct CSSPropertySettings {
    WTF_MAKE_STRUCT_FAST_ALLOCATED;

    bool cssDescriptorEnabled : 1 { false };
    bool cssSettingsOneEnabled : 1 { false };

    CSSPropertySettings() = default;
    explicit CSSPropertySettings(const Settings&);
};

bool operator==(const CSSPropertySettings&, const CSSPropertySettings&);
void add(Hasher&, const CSSPropertySettings&);

constexpr bool isLonghand(CSSPropertyID);
bool isInternal(CSSPropertyID);
bool isExposed(CSSPropertyID, const Settings*);
bool isExposed(CSSPropertyID, const Settings&);
bool isExposed(CSSPropertyID, const CSSPropertySettings*);
bool isExposed(CSSPropertyID, const CSSPropertySettings&);

CSSPropertyID findCSSProperty(const char* characters, unsigned length);
ASCIILiteral nameLiteral(CSSPropertyID);
const AtomString& nameString(CSSPropertyID);
String nameForIDL(CSSPropertyID);

CSSPropertyID cascadeAliasProperty(CSSPropertyID);

template<CSSPropertyID first, CSSPropertyID last> struct CSSPropertiesRange {
    struct Iterator {
        uint16_t index { static_cast<uint16_t>(first) };
        constexpr CSSPropertyID operator*() const { return static_cast<CSSPropertyID>(index); }
        constexpr Iterator& operator++() { ++index; return *this; }
        constexpr bool operator==(std::nullptr_t) const { return index > static_cast<uint16_t>(last); }
    };
    static constexpr Iterator begin() { return { }; }
    static constexpr std::nullptr_t end() { return nullptr; }
    static constexpr uint16_t size() { return last - first + 1; }
};
using AllCSSPropertiesRange = CSSPropertiesRange<static_cast<CSSPropertyID>(firstCSSProperty), lastShorthandProperty>;
using AllLonghandCSSPropertiesRange = CSSPropertiesRange<static_cast<CSSPropertyID>(firstCSSProperty), lastLogicalGroupProperty>;
constexpr AllCSSPropertiesRange allCSSProperties() { return { }; }
constexpr AllLonghandCSSPropertiesRange allLonghandCSSProperties() { return { }; }

constexpr bool isLonghand(CSSPropertyID property)
{
    return static_cast<uint16_t>(property) >= firstCSSProperty && static_cast<uint16_t>(property) < static_cast<uint16_t>(firstShorthandProperty);
}
constexpr bool isShorthand(CSSPropertyID property)
{
    return static_cast<uint16_t>(property) >= static_cast<uint16_t>(firstShorthandProperty) && static_cast<uint16_t>(property) <= static_cast<uint16_t>(lastShorthandProperty);
}

WTF::TextStream& operator<<(WTF::TextStream&, CSSPropertyID);

} // namespace WebCore

namespace WTF {

template<> struct DefaultHash<WebCore::CSSPropertyID> : IntHash<unsigned> { };

template<> struct HashTraits<WebCore::CSSPropertyID> : GenericHashTraits<WebCore::CSSPropertyID> {
    static const bool emptyValueIsZero = true;
    static void constructDeletedValue(WebCore::CSSPropertyID& slot) { slot = static_cast<WebCore::CSSPropertyID>(std::numeric_limits<uint16_t>::max()); }
    static bool isDeletedValue(WebCore::CSSPropertyID value) { return static_cast<uint16_t>(value) == std::numeric_limits<uint16_t>::max(); }
};

} // namespace WTF

namespace std {

template<> struct iterator_traits<WebCore::AllCSSPropertiesRange::Iterator> { using value_type = WebCore::CSSPropertyID; };
template<> struct iterator_traits<WebCore::AllLonghandCSSPropertiesRange::Iterator> { using value_type = WebCore::CSSPropertyID; };

} // namespace std


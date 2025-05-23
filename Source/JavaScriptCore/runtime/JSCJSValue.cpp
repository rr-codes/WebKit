/*
 *  Copyright (C) 1999-2001 Harri Porten (porten@kde.org)
 *  Copyright (C) 2001 Peter Kelly (pmk@post.com)
 *  Copyright (C) 2003-2020 Apple Inc. All rights reserved.
 *
 *  This library is free software; you can redistribute it and/or
 *  modify it under the terms of the GNU Library General Public
 *  License as published by the Free Software Foundation; either
 *  version 2 of the License, or (at your option) any later version.
 *
 *  This library is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 *  Library General Public License for more details.
 *
 *  You should have received a copy of the GNU Library General Public License
 *  along with this library; see the file COPYING.LIB.  If not, write to
 *  the Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
 *  Boston, MA 02110-1301, USA.
 *
 */

#include "config.h"
#include "JSCJSValue.h"

#include "BigIntObject.h"
#include "BooleanConstructor.h"
#include "CustomGetterSetter.h"
#include "GetterSetter.h"
#include "JSBigInt.h"
#include "JSCInlines.h"
#include "NumberObject.h"
#include "NumberPrototype.h"
#include "ParseInt.h"
#include "TypeError.h"
#include <wtf/text/MakeString.h>

namespace JSC {

double JSValue::toIntegerPreserveNaN(JSGlobalObject* globalObject) const
{
    if (isInt32())
        return asInt32();
    return trunc(toNumber(globalObject));
}

uint64_t JSValue::toLength(JSGlobalObject* globalObject) const
{
    // ECMA 7.1.15
    // http://www.ecma-international.org/ecma-262/6.0/#sec-tolength
    if (isInt32())
        return static_cast<uint64_t>(std::max<int32_t>(asInt32(), 0));
    double d = toIntegerOrInfinity(globalObject);
    if (d <= 0)
        return 0;
    return static_cast<uint64_t>(std::min(d, maxSafeInteger()));
}

double JSValue::toNumberSlowCase(JSGlobalObject* globalObject) const
{
    VM& vm = globalObject->vm();
    auto scope = DECLARE_THROW_SCOPE(vm);

    ASSERT(!isInt32() && !isDouble());
    if (isCell())
        RELEASE_AND_RETURN(scope, asCell()->toNumber(globalObject));
#if USE(BIGINT32)
    if (isBigInt32()) {
        throwTypeError(globalObject, scope, "Conversion from 'BigInt' to 'number' is not allowed."_s);
        return 0.0;
    }
#endif
    if (isTrue())
        return 1.0;
    return isUndefined() ? PNaN : 0; // null and false both convert to 0.
}

std::optional<double> JSValue::toNumberFromPrimitive() const
{
    if (isEmpty())
        return std::nullopt;
    if (isNumber())
        return asNumber();
    if (isBoolean())
        return asBoolean();
    if (isUndefined())
        return PNaN;
    if (isNull())
        return 0;
    return std::nullopt;
}

// https://tc39.es/ecma262/#sec-tobigint
JSValue JSValue::toBigInt(JSGlobalObject* globalObject) const
{
    VM& vm = globalObject->vm();
    auto scope = DECLARE_THROW_SCOPE(vm);

    JSValue primitive = toPrimitive(globalObject, PreferNumber);
    RETURN_IF_EXCEPTION(scope, { });

    if (primitive.isBigInt())
        return primitive;

    if (primitive.isBoolean()) {
#if USE(BIGINT32)
        return jsBigInt32(primitive.asBoolean());
#else
        RELEASE_AND_RETURN(scope, JSBigInt::createFrom(globalObject, primitive.asBoolean()));
#endif
    }

    if (primitive.isString()) {
        scope.release();
        return toStringView(globalObject, primitive, [&] (StringView view) {
            return JSBigInt::parseInt(globalObject, view);
        });
    }

    ASSERT(primitive.isUndefinedOrNull() || primitive.isNumber() || primitive.isSymbol());
    throwTypeError(globalObject, scope, "Invalid argument type in ToBigInt operation"_s);
    return jsUndefined();
}

// https://tc39.es/ecma262/#sec-tobigint64
int64_t JSValue::toBigInt64(JSGlobalObject* globalObject) const
{
    VM& vm = globalObject->vm();
    auto scope = DECLARE_THROW_SCOPE(vm);

    JSValue value = toBigInt(globalObject);
    RETURN_IF_EXCEPTION(scope, { });
    return JSBigInt::toBigInt64(value);
}

// https://tc39.es/ecma262/#sec-tobiguint64
uint64_t JSValue::toBigUInt64(JSGlobalObject* globalObject) const
{
    VM& vm = globalObject->vm();
    auto scope = DECLARE_THROW_SCOPE(vm);

    JSValue value = toBigInt(globalObject);
    RETURN_IF_EXCEPTION(scope, { });
    return JSBigInt::toBigUInt64(value);
}

JSObject* JSValue::toObjectSlowCase(JSGlobalObject* globalObject) const
{
    VM& vm = globalObject->vm();
    auto scope = DECLARE_THROW_SCOPE(vm);
    ASSERT(!isCell());

    if (isInt32() || isDouble())
        return constructNumber(globalObject, asValue());
    if (isTrue() || isFalse())
        return constructBooleanFromImmediateBoolean(globalObject, asValue());
#if USE(BIGINT32)
    if (isBigInt32())
        return BigIntObject::create(vm, globalObject, *this);
#endif

    ASSERT(isUndefinedOrNull());
    throwException(globalObject, scope, createNotAnObjectError(globalObject, *this));
    return nullptr;
}

JSValue JSValue::toThisSloppySlowCase(JSGlobalObject* globalObject) const
{
    if (isInt32() || isDouble())
        return constructNumber(globalObject, asValue());
    if (isTrue() || isFalse())
        return constructBooleanFromImmediateBoolean(globalObject, asValue());
#if USE(BIGINT32)
    if (isBigInt32())
        return BigIntObject::create(globalObject->vm(), globalObject, *this);
#endif
    ASSERT(isCell());
    return toObject(globalObject);
}

JSObject* JSValue::synthesizePrototype(JSGlobalObject* globalObject) const
{
    VM& vm = globalObject->vm();
    auto scope = DECLARE_THROW_SCOPE(vm);

    if (isCell()) {
        if (isString())
            return globalObject->stringPrototype();
        if (isHeapBigInt())
            return globalObject->bigIntPrototype();
        ASSERT(isSymbol());
        return globalObject->symbolPrototype();
    }

    if (isNumber())
        return globalObject->numberPrototype();
    if (isBoolean())
        return globalObject->booleanPrototype();
#if USE(BIGINT32)
    if (isBigInt32())
        return globalObject->bigIntPrototype();
#endif

    ASSERT(isUndefinedOrNull());
    throwException(globalObject, scope, createNotAnObjectError(globalObject, *this));
    return nullptr;
}

// https://tc39.es/ecma262/#sec-ordinaryset
bool JSValue::putToPrimitive(JSGlobalObject* globalObject, PropertyName propertyName, JSValue value, PutPropertySlot& slot)
{
    VM& vm = globalObject->vm();
    auto scope = DECLARE_THROW_SCOPE(vm);

    if (std::optional<uint32_t> index = parseIndex(propertyName))
        RELEASE_AND_RETURN(scope, putToPrimitiveByIndex(globalObject, index.value(), value, slot.isStrictMode()));

    if (isString() && propertyName.uid() == vm.propertyNames->length.impl())
        return typeError(globalObject, scope, slot.isStrictMode(), ReadonlyPropertyWriteError);
    // Check if there are any setters or getters in the prototype chain
    JSObject* obj = synthesizePrototype(globalObject);
    EXCEPTION_ASSERT(!!scope.exception() == !obj);
    if (!obj) [[unlikely]]
        return false;
    RELEASE_AND_RETURN(scope, obj->methodTable()->put(obj, globalObject, propertyName, value, slot));
}

bool JSValue::putToPrimitiveByIndex(JSGlobalObject* globalObject, unsigned propertyName, JSValue value, bool shouldThrow)
{
    VM& vm = globalObject->vm();
    auto scope = DECLARE_THROW_SCOPE(vm);

    if (propertyName > MAX_ARRAY_INDEX) {
        PutPropertySlot slot(*this, shouldThrow);
        return putToPrimitive(globalObject, Identifier::from(vm, propertyName), value, slot);
    }

    JSObject* prototype = synthesizePrototype(globalObject);
    EXCEPTION_ASSERT(!!scope.exception() == !prototype);
    if (!prototype) [[unlikely]]
        return false;
    bool putResult = false;
    bool success = prototype->attemptToInterceptPutByIndexOnHoleForPrototype(globalObject, *this, propertyName, value, shouldThrow, putResult);
    RETURN_IF_EXCEPTION(scope, false);
    if (success)
        return putResult;

    return typeError(globalObject, scope, shouldThrow, ReadonlyPropertyWriteError);
}

void JSValue::dump(PrintStream& out) const
{
    dumpInContext(out, nullptr);
}

void JSValue::dumpInContext(PrintStream& out, DumpContext* context) const
{
    dumpInContextAssumingStructure(
        out, context, (!!*this && isCell()) ? asCell()->structure() : nullptr);
}

void JSValue::dumpInContextAssumingStructure(
    PrintStream& out, DumpContext* context, Structure* structure) const
{
    if (!*this)
        out.print("<JSValue()>");
    else if (isInt32())
        out.printf("Int32: %d", asInt32());
    else if (isDouble()) {
#if USE(JSVALUE64)
        out.printf("Double: %lld, %lf", (long long)reinterpretDoubleToInt64(asDouble()), asDouble());
#else
        WTF_ALLOW_UNSAFE_BUFFER_USAGE_BEGIN
        union {
            double asDouble;
            uint32_t asTwoInt32s[2];
        } u;
        u.asDouble = asDouble();
        out.printf("Double: %08x:%08x, %lf", u.asTwoInt32s[1], u.asTwoInt32s[0], asDouble());
        WTF_ALLOW_UNSAFE_BUFFER_USAGE_END
#endif
    } else if (isCell()) {
        if (structure->classInfoForCells()->isSubClassOf(JSString::info())) {
            JSString* string = asString(asCell());
            out.print("String");
            if (string->isRope())
                out.print(" (rope)");
            const StringImpl* impl = string->tryGetValueImpl();
            if (impl) {
                if (impl->isAtom())
                    out.print(" (atomic)");
                if (impl->isSymbol())
                    out.print(" (symbol)");
            } else
                out.print(" (unresolved)");
            if (string->is8Bit())
                out.print(",8Bit:(1)");
            else
                out.print(",8Bit:(0)");
            out.print(",length:(", string->length(), ")");
            out.print(": ", impl);
        } else if (structure->classInfoForCells()->isSubClassOf(RegExp::info()))
            out.print("RegExp: ", *jsCast<RegExp*>(asCell()));
        else if (structure->classInfoForCells()->isSubClassOf(Symbol::info()))
            out.print("Symbol: ", RawPointer(asCell()));
        else if (structure->classInfoForCells()->isSubClassOf(Structure::info()))
            out.print("Structure: ", inContext(*jsCast<Structure*>(asCell()), context));
        else if (isHeapBigInt())
            out.print("BigInt[heap-allocated]: addr=", RawPointer(asCell()), ", length=", jsCast<JSBigInt*>(asCell())->length(), ", sign=", jsCast<JSBigInt*>(asCell())->sign());
        else if (structure->classInfoForCells()->isSubClassOf(JSObject::info())) {
            out.print("Object: ", RawPointer(asCell()));
            out.print(" with butterfly ", RawPointer(asObject(asCell())->butterfly()), "(base=", RawPointer(asObject(asCell())->butterfly()->base(structure)), ")");
            out.print(" (Structure ", inContext(*structure, context), ")");
        } else {
            out.print("Cell: ", RawPointer(asCell()));
            out.print(" (", inContext(*structure, context), ")");
        }
#if USE(JSVALUE64)
        out.print(", StructureID: ", asCell()->structureID().bits());
#endif
    } else if (isTrue())
        out.print("True");
    else if (isFalse())
        out.print("False");
    else if (isNull())
        out.print("Null");
    else if (isUndefined())
        out.print("Undefined");
#if USE(BIGINT32)
    else if (isBigInt32())
        out.printf("BigInt[inline]: %d", bigInt32AsInt32());
#endif
    else
        out.print("INVALID");
}

void JSValue::dumpForBacktrace(PrintStream& out) const
{
    if (!*this)
        out.print("<JSValue()>");
    else if (isInt32())
        out.printf("%d", asInt32());
    else if (isDouble())
        out.printf("%lf", asDouble());
    else if (isCell()) {
        if (asCell()->inherits<JSString>()) {
            JSString* string = asString(asCell());
            const StringImpl* impl = string->tryGetValueImpl();
            if (impl)
                out.print("\"", impl, "\"");
            else
                out.print("(unresolved string)");
        } else if (asCell()->inherits<Structure>()) {
            out.print("Structure[ ", asCell()->structure()->classInfoForCells()->className);
            out.print("]: ", RawPointer(asCell()));
        } else {
            out.print("Cell[", asCell()->structure()->classInfoForCells()->className);
            out.print("]: ", RawPointer(asCell()));
        }
    } else if (isTrue())
        out.print("True");
    else if (isFalse())
        out.print("False");
    else if (isNull())
        out.print("Null");
    else if (isUndefined())
        out.print("Undefined");
#if USE(BIGINT32)
    else if (isBigInt32())
        out.printf("BigInt[inline]: %d", bigInt32AsInt32());
#endif
    else
        out.print("INVALID");
}

JSString* JSValue::toStringSlowCase(JSGlobalObject* globalObject, bool returnEmptyStringOnError) const
{
    VM& vm = globalObject->vm();
    auto scope = DECLARE_THROW_SCOPE(vm);

    auto errorValue = [&] () -> JSString* {
        if (returnEmptyStringOnError)
            return jsEmptyString(vm);
        return nullptr;
    };

    ASSERT(!isString());
    if (isInt32())
        return int32ToString(vm, asInt32(), 10);
    if (isDouble())
        return JSC::numberToString(vm, asDouble(), 10);
    if (isTrue())
        return vm.smallStrings.trueString();
    if (isFalse())
        return vm.smallStrings.falseString();
    if (isNull())
        return vm.smallStrings.nullString();
    if (isUndefined())
        return vm.smallStrings.undefinedString();
#if USE(BIGINT32)
    if (isBigInt32())
        return int32ToString(vm, bigInt32AsInt32(), 10);
#endif
    JSString* returnString = asCell()->toStringInline(globalObject);
    RETURN_IF_EXCEPTION(scope, errorValue());
    return returnString;
}

String JSValue::toWTFStringSlowCase(JSGlobalObject* globalObject) const
{
    VM& vm = globalObject->vm();
    auto scope = DECLARE_THROW_SCOPE(vm);
    if (isInt32())
        return vm.numericStrings.add(asInt32());
    if (isDouble())
        return vm.numericStrings.add(asDouble());
    if (isTrue())
        return vm.propertyNames->trueKeyword.string();
    if (isFalse())
        return vm.propertyNames->falseKeyword.string();
    if (isNull())
        return vm.propertyNames->nullKeyword.string();
    if (isUndefined())
        return vm.propertyNames->undefinedKeyword.string();
    JSString* string = toString(globalObject);
    RETURN_IF_EXCEPTION(scope, { });
    RELEASE_AND_RETURN(scope, string->value(globalObject));
}

WTF::String JSValue::toWTFStringForConsole(JSGlobalObject* globalObject) const
{
    VM& vm = globalObject->vm();
    auto scope = DECLARE_THROW_SCOPE(vm);
    JSString* string = toString(globalObject);
    RETURN_IF_EXCEPTION(scope, { });
    auto result = string->value(globalObject);
    RETURN_IF_EXCEPTION(scope, { });
    if (isString())
        return tryMakeString('"', result.data, '"');
    if (jsDynamicCast<JSArray*>(*this))
        return tryMakeString('[', result.data, ']');
    if (jsDynamicCast<JSBigInt*>(*this))
        return tryMakeString(result.data, 'n');
    return result;
}

} // namespace JSC

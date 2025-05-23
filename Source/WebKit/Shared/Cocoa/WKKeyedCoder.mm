/*
 * Copyright (C) 2023 Apple Inc. All rights reserved.
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

#import "config.h"
#import "ArgumentCodersCocoa.h"

@implementation WKKeyedCoder {
    RetainPtr<NSMutableDictionary> m_dictionary;
    bool m_failedDecoding;
}

- (instancetype)init
{
    if (!(self = [super init]))
        return nil;

    m_dictionary = adoptNS([NSMutableDictionary new]);
    return self;
}

- (instancetype)initWithDictionary:(NSDictionary *)dictionary
{
    if (!(self = [super init]))
        return nil;

    m_dictionary = adoptNS([dictionary mutableCopy]);
    return self;
}

- (BOOL)allowsKeyedCoding
{
    return YES;
}

- (BOOL)requiresSecureCoding
{
    return YES;
}

- (void)encodeObject:(id)object forKey:(NSString *)key
{
    if (!object)
        return;

    if (!IPC::isSerializableValue(object)) {
        ASSERT_NOT_REACHED_WITH_MESSAGE("WKKeyedCoder attempt to encode object of unsupported type %s", object_getClassName(object));
        return;
    }

    [m_dictionary setObject:object forKey:key];
}

- (BOOL)containsValueForKey:(NSString *)key
{
    return !![m_dictionary objectForKey:key];
}

- (id)decodeObjectOfClass:(Class)aClass forKey:(NSString *)key
{
    if (m_failedDecoding)
        return nil;

    RetainPtr<id> object = [m_dictionary objectForKey:key];
    if (object && ![object isKindOfClass:aClass]) {
        m_failedDecoding = YES;
        return nil;
    }

    return object.autorelease();
}

- (id)decodeObjectOfClasses:(NSSet<Class> *)classes forKey:(NSString *)key
{
    if (m_failedDecoding)
        return nil;

    RetainPtr<id> object = [m_dictionary objectForKey:key];
    if (!object)
        return nil;
    for (id aClass in classes) {
        if ([object isKindOfClass:aClass])
            return object.autorelease();
    }

    m_failedDecoding = YES;
    return nil;
}

- (id)decodeObjectForKey:(NSString *)key
{
    return [m_dictionary objectForKey:key];
}

- (void)encodeBool:(BOOL)value forKey:(NSString *)key
{
    [self encodeObject:@(value) forKey:key];
}

- (BOOL)decodeBoolForKey:(NSString *)key
{
    return [[self decodeObjectOfClass:[NSNumber class] forKey:key] boolValue];
}

- (void)encodeInt64:(int64_t)value forKey:(NSString *)key
{
    [self encodeObject:@(value) forKey:key];
}

- (int64_t)decodeInt64ForKey:(NSString *)key
{
    return [[self decodeObjectOfClass:[NSNumber class] forKey:key] longLongValue];
}

- (void)encodeInteger:(NSInteger)value forKey:(NSString *)key
{
    [self encodeObject:@(value) forKey:key];
}

- (NSInteger)decodeIntegerForKey:(NSString *)key
{
    return [[self decodeObjectOfClass:[NSNumber class] forKey:key] integerValue];
}

- (NSDictionary *)accumulatedDictionary
{
    return m_dictionary.get();
}

@end // @implementation WKKeyedCoder

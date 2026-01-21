//
//  CSCap.m
//  Formal cap implementation
//
//  NOTE: All type information is conveyed via mediaSpec fields containing spec IDs.
//

#import "include/CSCap.h"
#import "include/CSMediaSpec.h"

#pragma mark - CSArgumentValidation Implementation

@implementation CSArgumentValidation

+ (instancetype)validationWithMin:(nullable NSNumber *)min
                              max:(nullable NSNumber *)max
                        minLength:(nullable NSNumber *)minLength
                        maxLength:(nullable NSNumber *)maxLength
                          pattern:(nullable NSString *)pattern
                    allowedValues:(nullable NSArray<NSString *> *)allowedValues {
    CSArgumentValidation *validation = [[CSArgumentValidation alloc] init];
    validation->_min = min;
    validation->_max = max;
    validation->_minLength = minLength;
    validation->_maxLength = maxLength;
    validation->_pattern = [pattern copy];
    validation->_allowedValues = [allowedValues copy];
    return validation;
}

+ (instancetype)validationWithDictionary:(NSDictionary *)dictionary error:(NSError **)error {
    NSNumber *min = dictionary[@"min"];
    NSNumber *max = dictionary[@"max"];
    NSNumber *minLength = dictionary[@"min_length"];
    NSNumber *maxLength = dictionary[@"max_length"];
    NSString *pattern = dictionary[@"pattern"];
    NSArray<NSString *> *allowedValues = dictionary[@"allowed_values"];

    return [self validationWithMin:min
                               max:max
                         minLength:minLength
                         maxLength:maxLength
                           pattern:pattern
                     allowedValues:allowedValues];
}

- (id)copyWithZone:(NSZone *)zone {
    return [CSArgumentValidation validationWithMin:self.min
                                                max:self.max
                                          minLength:self.minLength
                                          maxLength:self.maxLength
                                            pattern:self.pattern
                                      allowedValues:self.allowedValues];
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.min forKey:@"min"];
    [coder encodeObject:self.max forKey:@"max"];
    [coder encodeObject:self.minLength forKey:@"minLength"];
    [coder encodeObject:self.maxLength forKey:@"maxLength"];
    [coder encodeObject:self.pattern forKey:@"pattern"];
    [coder encodeObject:self.allowedValues forKey:@"allowedValues"];
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        _min = [coder decodeObjectOfClass:[NSNumber class] forKey:@"min"];
        _max = [coder decodeObjectOfClass:[NSNumber class] forKey:@"max"];
        _minLength = [coder decodeObjectOfClass:[NSNumber class] forKey:@"minLength"];
        _maxLength = [coder decodeObjectOfClass:[NSNumber class] forKey:@"maxLength"];
        _pattern = [coder decodeObjectOfClass:[NSString class] forKey:@"pattern"];
        _allowedValues = [coder decodeObjectOfClass:[NSArray class] forKey:@"allowedValues"];
    }
    return self;
}

- (NSDictionary *)toDictionary {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];

    if (self.min) dict[@"min"] = self.min;
    if (self.max) dict[@"max"] = self.max;
    if (self.minLength) dict[@"min_length"] = self.minLength;
    if (self.maxLength) dict[@"max_length"] = self.maxLength;
    if (self.pattern) dict[@"pattern"] = self.pattern;
    if (self.allowedValues && self.allowedValues.count > 0) {
        dict[@"allowed_values"] = self.allowedValues;
    }

    return [dict copy];
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (BOOL)isEqual:(id)object {
    if (self == object) return YES;
    if (![object isKindOfClass:[CSArgumentValidation class]]) return NO;

    CSArgumentValidation *other = (CSArgumentValidation *)object;

    if ((self.min == nil) != (other.min == nil)) return NO;
    if (self.min && ![self.min isEqualToNumber:other.min]) return NO;

    if ((self.max == nil) != (other.max == nil)) return NO;
    if (self.max && ![self.max isEqualToNumber:other.max]) return NO;

    if ((self.minLength == nil) != (other.minLength == nil)) return NO;
    if (self.minLength && ![self.minLength isEqualToNumber:other.minLength]) return NO;

    if ((self.maxLength == nil) != (other.maxLength == nil)) return NO;
    if (self.maxLength && ![self.maxLength isEqualToNumber:other.maxLength]) return NO;

    if ((self.pattern == nil) != (other.pattern == nil)) return NO;
    if (self.pattern && ![self.pattern isEqualToString:other.pattern]) return NO;

    if ((self.allowedValues == nil) != (other.allowedValues == nil)) return NO;
    if (self.allowedValues && ![self.allowedValues isEqualToArray:other.allowedValues]) return NO;

    return YES;
}

- (NSUInteger)hash {
    return [self.min hash] ^ [self.max hash] ^ [self.minLength hash] ^
           [self.maxLength hash] ^ [self.pattern hash] ^ [self.allowedValues hash];
}

@end

#pragma mark - CSArgSource Implementation

@implementation CSArgSource

+ (instancetype)stdinSourceWithMediaUrn:(NSString *)mediaUrn {
    CSArgSource *source = [[CSArgSource alloc] init];
    source->_type = CSArgSourceTypeStdin;
    source->_stdinMediaUrn = [mediaUrn copy];
    source->_position = -1;
    source->_cliFlag = nil;
    return source;
}

+ (instancetype)positionSource:(NSInteger)position {
    CSArgSource *source = [[CSArgSource alloc] init];
    source->_type = CSArgSourceTypePosition;
    source->_stdinMediaUrn = nil;
    source->_position = position;
    source->_cliFlag = nil;
    return source;
}

+ (instancetype)cliFlagSource:(NSString *)cliFlag {
    CSArgSource *source = [[CSArgSource alloc] init];
    source->_type = CSArgSourceTypeCliFlag;
    source->_stdinMediaUrn = nil;
    source->_position = -1;
    source->_cliFlag = [cliFlag copy];
    return source;
}

+ (nullable instancetype)sourceWithDictionary:(NSDictionary *)dictionary error:(NSError **)error {
    // Check for stdin source
    NSString *stdinValue = dictionary[@"stdin"];
    if (stdinValue) {
        return [self stdinSourceWithMediaUrn:stdinValue];
    }

    // Check for position source
    NSNumber *positionValue = dictionary[@"position"];
    if (positionValue) {
        return [self positionSource:[positionValue integerValue]];
    }

    // Check for cli_flag source
    NSString *cliFlagValue = dictionary[@"cli_flag"];
    if (cliFlagValue) {
        return [self cliFlagSource:cliFlagValue];
    }

    // No valid source type found
    if (error) {
        *error = [NSError errorWithDomain:@"CSArgSourceError"
                                     code:1001
                                 userInfo:@{NSLocalizedDescriptionKey: @"Source must have one of: stdin, position, or cli_flag"}];
    }
    return nil;
}

- (NSDictionary *)toDictionary {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];

    switch (self.type) {
        case CSArgSourceTypeStdin:
            if (self.stdinMediaUrn) {
                dict[@"stdin"] = self.stdinMediaUrn;
            }
            break;
        case CSArgSourceTypePosition:
            dict[@"position"] = @(self.position);
            break;
        case CSArgSourceTypeCliFlag:
            if (self.cliFlag) {
                dict[@"cli_flag"] = self.cliFlag;
            }
            break;
    }

    return [dict copy];
}

- (BOOL)isStdin {
    return self.type == CSArgSourceTypeStdin;
}

- (BOOL)isPosition {
    return self.type == CSArgSourceTypePosition;
}

- (BOOL)isCliFlag {
    return self.type == CSArgSourceTypeCliFlag;
}

- (id)copyWithZone:(NSZone *)zone {
    CSArgSource *copy = [[CSArgSource alloc] init];
    copy->_type = self.type;
    copy->_stdinMediaUrn = [self.stdinMediaUrn copy];
    copy->_position = self.position;
    copy->_cliFlag = [self.cliFlag copy];
    return copy;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeInteger:self.type forKey:@"type"];
    [coder encodeObject:self.stdinMediaUrn forKey:@"stdinMediaUrn"];
    [coder encodeInteger:self.position forKey:@"position"];
    [coder encodeObject:self.cliFlag forKey:@"cliFlag"];
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        _type = [coder decodeIntegerForKey:@"type"];
        _stdinMediaUrn = [coder decodeObjectOfClass:[NSString class] forKey:@"stdinMediaUrn"];
        _position = [coder decodeIntegerForKey:@"position"];
        _cliFlag = [coder decodeObjectOfClass:[NSString class] forKey:@"cliFlag"];
    }
    return self;
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (BOOL)isEqual:(id)object {
    if (self == object) return YES;
    if (![object isKindOfClass:[CSArgSource class]]) return NO;

    CSArgSource *other = (CSArgSource *)object;

    if (self.type != other.type) return NO;

    switch (self.type) {
        case CSArgSourceTypeStdin:
            if ((self.stdinMediaUrn == nil) != (other.stdinMediaUrn == nil)) return NO;
            if (self.stdinMediaUrn && ![self.stdinMediaUrn isEqualToString:other.stdinMediaUrn]) return NO;
            break;
        case CSArgSourceTypePosition:
            if (self.position != other.position) return NO;
            break;
        case CSArgSourceTypeCliFlag:
            if ((self.cliFlag == nil) != (other.cliFlag == nil)) return NO;
            if (self.cliFlag && ![self.cliFlag isEqualToString:other.cliFlag]) return NO;
            break;
    }

    return YES;
}

- (NSUInteger)hash {
    NSUInteger hash = (NSUInteger)self.type;
    switch (self.type) {
        case CSArgSourceTypeStdin:
            hash ^= [self.stdinMediaUrn hash];
            break;
        case CSArgSourceTypePosition:
            hash ^= self.position;
            break;
        case CSArgSourceTypeCliFlag:
            hash ^= [self.cliFlag hash];
            break;
    }
    return hash;
}

@end

#pragma mark - CSCapArg Implementation

@implementation CSCapArg

+ (instancetype)argWithMediaUrn:(NSString *)mediaUrn
                       required:(BOOL)required
                        sources:(NSArray<CSArgSource *> *)sources {
    return [self argWithMediaUrn:mediaUrn
                        required:required
                         sources:sources
                  argDescription:nil
                      validation:nil
                    defaultValue:nil];
}

+ (instancetype)argWithMediaUrn:(NSString *)mediaUrn
                       required:(BOOL)required
                        sources:(NSArray<CSArgSource *> *)sources
                 argDescription:(nullable NSString *)argDescription
                     validation:(nullable CSArgumentValidation *)validation
                   defaultValue:(nullable id)defaultValue {
    CSCapArg *arg = [[CSCapArg alloc] init];
    arg->_mediaUrn = [mediaUrn copy];
    arg->_required = required;
    arg->_sources = [sources copy];
    arg->_argDescription = [argDescription copy];
    arg->_validation = validation;
    arg->_defaultValue = defaultValue;
    arg->_metadata = nil;
    return arg;
}

+ (nullable instancetype)argWithDictionary:(NSDictionary *)dictionary error:(NSError **)error {
    // Required: media_urn
    NSString *mediaUrn = dictionary[@"media_urn"];
    if (!mediaUrn) {
        if (error) {
            *error = [NSError errorWithDomain:@"CSCapArgError"
                                         code:1001
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing required field: media_urn"}];
        }
        return nil;
    }

    // Required: required (boolean)
    NSNumber *requiredValue = dictionary[@"required"];
    if (requiredValue == nil) {
        if (error) {
            *error = [NSError errorWithDomain:@"CSCapArgError"
                                         code:1002
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing required field: required"}];
        }
        return nil;
    }
    BOOL required = [requiredValue boolValue];

    // Required: sources (array)
    NSArray *sourcesArray = dictionary[@"sources"];
    if (!sourcesArray || ![sourcesArray isKindOfClass:[NSArray class]]) {
        if (error) {
            *error = [NSError errorWithDomain:@"CSCapArgError"
                                         code:1003
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing required field: sources"}];
        }
        return nil;
    }

    NSMutableArray<CSArgSource *> *sources = [NSMutableArray array];
    for (NSDictionary *sourceDict in sourcesArray) {
        CSArgSource *source = [CSArgSource sourceWithDictionary:sourceDict error:error];
        if (!source) {
            return nil;
        }
        [sources addObject:source];
    }

    // Optional fields
    NSString *argDescription = dictionary[@"arg_description"];
    id defaultValue = dictionary[@"default_value"];
    NSDictionary *metadata = dictionary[@"metadata"];

    // Parse validation if present
    CSArgumentValidation *validation = nil;
    NSDictionary *validationDict = dictionary[@"validation"];
    if (validationDict) {
        validation = [CSArgumentValidation validationWithDictionary:validationDict error:error];
        if (!validation && error && *error) {
            return nil;
        }
    }

    CSCapArg *arg = [[CSCapArg alloc] init];
    arg->_mediaUrn = [mediaUrn copy];
    arg->_required = required;
    arg->_sources = [sources copy];
    arg->_argDescription = [argDescription copy];
    arg->_validation = validation;
    arg->_defaultValue = defaultValue;
    arg->_metadata = [metadata copy];

    return arg;
}

- (NSDictionary *)toDictionary {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];

    dict[@"media_urn"] = self.mediaUrn;
    dict[@"required"] = @(self.required);

    NSMutableArray *sourceDicts = [NSMutableArray array];
    for (CSArgSource *source in self.sources) {
        [sourceDicts addObject:[source toDictionary]];
    }
    dict[@"sources"] = sourceDicts;

    if (self.argDescription) dict[@"arg_description"] = self.argDescription;
    if (self.validation) dict[@"validation"] = [self.validation toDictionary];
    if (self.defaultValue) dict[@"default_value"] = self.defaultValue;
    if (self.metadata) dict[@"metadata"] = self.metadata;

    return [dict copy];
}

- (BOOL)hasStdinSource {
    for (CSArgSource *source in self.sources) {
        if ([source isStdin]) {
            return YES;
        }
    }
    return NO;
}

- (nullable NSString *)getStdinMediaUrn {
    for (CSArgSource *source in self.sources) {
        if ([source isStdin]) {
            return source.stdinMediaUrn;
        }
    }
    return nil;
}

- (BOOL)hasPositionSource {
    for (CSArgSource *source in self.sources) {
        if ([source isPosition]) {
            return YES;
        }
    }
    return NO;
}

- (nullable NSNumber *)getPosition {
    for (CSArgSource *source in self.sources) {
        if ([source isPosition]) {
            return @(source.position);
        }
    }
    return nil;
}

- (BOOL)hasCliFlagSource {
    for (CSArgSource *source in self.sources) {
        if ([source isCliFlag]) {
            return YES;
        }
    }
    return NO;
}

- (nullable NSString *)getCliFlag {
    for (CSArgSource *source in self.sources) {
        if ([source isCliFlag]) {
            return source.cliFlag;
        }
    }
    return nil;
}

- (nullable NSDictionary *)getMetadata {
    return self.metadata;
}

- (void)setMetadata:(nullable NSDictionary *)metadata {
    _metadata = [metadata copy];
}

- (void)clearMetadata {
    _metadata = nil;
}

- (id)copyWithZone:(NSZone *)zone {
    CSCapArg *copy = [[CSCapArg alloc] init];
    copy->_mediaUrn = [self.mediaUrn copy];
    copy->_required = self.required;
    copy->_sources = [[NSArray alloc] initWithArray:self.sources copyItems:YES];
    copy->_argDescription = [self.argDescription copy];
    copy->_validation = [self.validation copy];
    copy->_defaultValue = self.defaultValue;
    copy->_metadata = [self.metadata copy];
    return copy;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.mediaUrn forKey:@"mediaUrn"];
    [coder encodeBool:self.required forKey:@"required"];
    [coder encodeObject:self.sources forKey:@"sources"];
    [coder encodeObject:self.argDescription forKey:@"argDescription"];
    [coder encodeObject:self.validation forKey:@"validation"];
    [coder encodeObject:self.defaultValue forKey:@"defaultValue"];
    [coder encodeObject:self.metadata forKey:@"metadata"];
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    NSString *mediaUrn = [coder decodeObjectOfClass:[NSString class] forKey:@"mediaUrn"];

    // FAIL HARD on missing required fields
    if (!mediaUrn) {
        return nil;
    }

    self = [super init];
    if (self) {
        _mediaUrn = mediaUrn;
        _required = [coder decodeBoolForKey:@"required"];
        _sources = [coder decodeObjectOfClasses:[NSSet setWithObjects:[NSArray class], [CSArgSource class], nil] forKey:@"sources"];
        _argDescription = [coder decodeObjectOfClass:[NSString class] forKey:@"argDescription"];
        _validation = [coder decodeObjectOfClass:[CSArgumentValidation class] forKey:@"validation"];
        _defaultValue = [coder decodeObjectForKey:@"defaultValue"];
        _metadata = [coder decodeObjectOfClass:[NSDictionary class] forKey:@"metadata"];
    }
    return self;
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (BOOL)isEqual:(id)object {
    if (self == object) return YES;
    if (![object isKindOfClass:[CSCapArg class]]) return NO;

    CSCapArg *other = (CSCapArg *)object;

    if (![self.mediaUrn isEqualToString:other.mediaUrn]) return NO;
    if (self.required != other.required) return NO;
    if (![self.sources isEqualToArray:other.sources]) return NO;

    if ((self.argDescription == nil) != (other.argDescription == nil)) return NO;
    if (self.argDescription && ![self.argDescription isEqualToString:other.argDescription]) return NO;

    if ((self.validation == nil) != (other.validation == nil)) return NO;
    if (self.validation && ![self.validation isEqual:other.validation]) return NO;

    if ((self.defaultValue == nil) != (other.defaultValue == nil)) return NO;
    if (self.defaultValue && ![self.defaultValue isEqual:other.defaultValue]) return NO;

    if ((self.metadata == nil) != (other.metadata == nil)) return NO;
    if (self.metadata && ![self.metadata isEqualToDictionary:other.metadata]) return NO;

    return YES;
}

- (NSUInteger)hash {
    return [self.mediaUrn hash] ^ (self.required ? 1 : 0) ^ [self.sources hash] ^
           [self.argDescription hash] ^ [self.validation hash] ^
           [self.defaultValue hash] ^ [self.metadata hash];
}

@end

#pragma mark - CSCapOutput Implementation

@implementation CSCapOutput

+ (instancetype)outputWithMediaUrn:(NSString *)mediaUrn
                        validation:(nullable CSArgumentValidation *)validation
                 outputDescription:(NSString *)outputDescription {
    CSCapOutput *output = [[CSCapOutput alloc] init];
    output->_mediaUrn = [mediaUrn copy];
    output->_validation = validation;
    output->_outputDescription = [outputDescription copy];
    output->_metadata = nil;
    return output;
}

+ (instancetype)outputWithDictionary:(NSDictionary *)dictionary error:(NSError **)error {
    NSString *mediaUrn = dictionary[@"media_urn"];
    NSString *outputDescription = dictionary[@"output_description"];
    NSDictionary *metadata = dictionary[@"metadata"];

    // FAIL HARD on missing required fields
    if (!mediaUrn) {
        if (error) {
            *error = [NSError errorWithDomain:@"CSCapOutputError"
                                         code:1001
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing required field 'media_urn' for output"}];
        }
        return nil;
    }

    if (!outputDescription) {
        if (error) {
            *error = [NSError errorWithDomain:@"CSCapOutputError"
                                         code:1002
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing required field 'output_description' for output"}];
        }
        return nil;
    }

    // Parse validation if present
    CSArgumentValidation *validation = nil;
    NSDictionary *validationDict = dictionary[@"validation"];
    if (validationDict) {
        validation = [CSArgumentValidation validationWithDictionary:validationDict error:error];
        if (!validation && error && *error) {
            return nil;
        }
    }

    CSCapOutput *output = [[CSCapOutput alloc] init];
    output->_mediaUrn = [mediaUrn copy];
    output->_validation = validation;
    output->_outputDescription = [outputDescription copy];
    output->_metadata = [metadata copy];

    return output;
}

- (id)copyWithZone:(NSZone *)zone {
    CSCapOutput *copy = [[CSCapOutput alloc] init];
    copy->_mediaUrn = [self.mediaUrn copy];
    copy->_validation = [self.validation copy];
    copy->_outputDescription = [self.outputDescription copy];
    copy->_metadata = [self.metadata copy];
    return copy;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.mediaUrn forKey:@"mediaUrn"];
    [coder encodeObject:self.validation forKey:@"validation"];
    [coder encodeObject:self.outputDescription forKey:@"outputDescription"];
    [coder encodeObject:self.metadata forKey:@"metadata"];
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    NSString *mediaUrn = [coder decodeObjectOfClass:[NSString class] forKey:@"mediaUrn"];
    NSString *outputDescription = [coder decodeObjectOfClass:[NSString class] forKey:@"outputDescription"];

    // FAIL HARD on missing required fields
    if (!mediaUrn || !outputDescription) {
        return nil;
    }

    self = [super init];
    if (self) {
        _mediaUrn = mediaUrn;
        _validation = [coder decodeObjectOfClass:[CSArgumentValidation class] forKey:@"validation"];
        _outputDescription = outputDescription;
        _metadata = [coder decodeObjectOfClass:[NSDictionary class] forKey:@"metadata"];
    }
    return self;
}

- (NSDictionary *)toDictionary {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];

    dict[@"media_urn"] = self.mediaUrn;
    dict[@"output_description"] = self.outputDescription;

    if (self.validation) dict[@"validation"] = [self.validation toDictionary];
    if (self.metadata) dict[@"metadata"] = self.metadata;

    return [dict copy];
}

- (nullable NSDictionary *)getMetadata {
    return self.metadata;
}

- (void)setMetadata:(nullable NSDictionary *)metadata {
    _metadata = [metadata copy];
}

- (void)clearMetadata {
    _metadata = nil;
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (BOOL)isEqual:(id)object {
    if (self == object) return YES;
    if (![object isKindOfClass:[CSCapOutput class]]) return NO;

    CSCapOutput *other = (CSCapOutput *)object;

    if (![self.mediaUrn isEqualToString:other.mediaUrn]) return NO;

    if ((self.validation == nil) != (other.validation == nil)) return NO;
    if (self.validation && ![self.validation isEqual:other.validation]) return NO;

    if (![self.outputDescription isEqualToString:other.outputDescription]) return NO;

    if ((self.metadata == nil) != (other.metadata == nil)) return NO;
    if (self.metadata && ![self.metadata isEqualToDictionary:other.metadata]) return NO;

    return YES;
}

- (NSUInteger)hash {
    return [self.mediaUrn hash] ^ [self.validation hash] ^ [self.outputDescription hash] ^ [self.metadata hash];
}

@end

#pragma mark - CSRegisteredBy Implementation

@implementation CSRegisteredBy

+ (instancetype)registeredByWithUsername:(NSString *)username
                            registeredAt:(NSString *)registeredAt {
    CSRegisteredBy *registeredBy = [[CSRegisteredBy alloc] init];
    registeredBy->_username = [username copy];
    registeredBy->_registeredAt = [registeredAt copy];
    return registeredBy;
}

+ (nullable instancetype)registeredByWithDictionary:(NSDictionary *)dictionary
                                              error:(NSError * _Nullable * _Nullable)error {
    NSString *username = dictionary[@"username"];
    NSString *registeredAt = dictionary[@"registered_at"];

    if (!username || ![username isKindOfClass:[NSString class]]) {
        if (error) {
            *error = [NSError errorWithDomain:@"CSRegisteredByError"
                                         code:1001
                                     userInfo:@{NSLocalizedDescriptionKey: @"username is required and must be a string"}];
        }
        return nil;
    }

    if (!registeredAt || ![registeredAt isKindOfClass:[NSString class]]) {
        if (error) {
            *error = [NSError errorWithDomain:@"CSRegisteredByError"
                                         code:1002
                                     userInfo:@{NSLocalizedDescriptionKey: @"registered_at is required and must be a string"}];
        }
        return nil;
    }

    return [self registeredByWithUsername:username registeredAt:registeredAt];
}

- (NSDictionary *)toDictionary {
    return @{
        @"username": self.username,
        @"registered_at": self.registeredAt
    };
}

- (id)copyWithZone:(NSZone *)zone {
    return [CSRegisteredBy registeredByWithUsername:self.username registeredAt:self.registeredAt];
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.username forKey:@"username"];
    [coder encodeObject:self.registeredAt forKey:@"registeredAt"];
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        _username = [coder decodeObjectOfClass:[NSString class] forKey:@"username"];
        _registeredAt = [coder decodeObjectOfClass:[NSString class] forKey:@"registeredAt"];
    }
    return self;
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (BOOL)isEqual:(id)object {
    if (self == object) return YES;
    if (![object isKindOfClass:[CSRegisteredBy class]]) return NO;

    CSRegisteredBy *other = (CSRegisteredBy *)object;
    return [self.username isEqualToString:other.username] &&
           [self.registeredAt isEqualToString:other.registeredAt];
}

- (NSUInteger)hash {
    return [self.username hash] ^ [self.registeredAt hash];
}

@end

#pragma mark - CSCap Implementation

@implementation CSCap

+ (instancetype)capWithDictionary:(NSDictionary *)dictionary error:(NSError **)error {
    // Required fields
    id urnField = dictionary[@"urn"];
    NSString *command = dictionary[@"command"];
    NSString *title = dictionary[@"title"];

    // FAIL HARD on missing required fields
    if (!urnField) {
        if (error) {
            *error = [NSError errorWithDomain:@"CSCapError"
                                         code:1001
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing required field: urn"}];
        }
        return nil;
    }

    if (!command) {
        if (error) {
            *error = [NSError errorWithDomain:@"CSCapError"
                                         code:1002
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing required field: command"}];
        }
        return nil;
    }

    if (!title) {
        if (error) {
            *error = [NSError errorWithDomain:@"CSCapError"
                                         code:1003
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing required field: title"}];
        }
        return nil;
    }

    // Parse cap URN - handle both string and object formats
    NSError *keyError;
    CSCapUrn *capUrn = nil;

    if ([urnField isKindOfClass:[NSString class]]) {
        capUrn = [CSCapUrn fromString:(NSString *)urnField error:&keyError];
    } else if ([urnField isKindOfClass:[NSDictionary class]]) {
        NSDictionary *urnDict = (NSDictionary *)urnField;
        NSDictionary *tags = urnDict[@"tags"];

        if ([tags isKindOfClass:[NSDictionary class]]) {
            capUrn = [CSCapUrn fromTags:tags error:&keyError];
        } else {
            if (error) {
                *error = [NSError errorWithDomain:@"CSCapError"
                                             code:1004
                                         userInfo:@{NSLocalizedDescriptionKey: @"Invalid URN object format - missing or invalid tags"}];
            }
            return nil;
        }
    } else {
        if (error) {
            *error = [NSError errorWithDomain:@"CSCapError"
                                         code:1005
                                     userInfo:@{NSLocalizedDescriptionKey: @"URN must be string or object"}];
        }
        return nil;
    }

    if (!capUrn) {
        if (error) *error = keyError;
        return nil;
    }

    // Optional fields
    NSString *capDescription = dictionary[@"cap_description"];
    NSDictionary *metadata = dictionary[@"metadata"] ?: @{};
    NSDictionary *mediaSpecs = dictionary[@"media_specs"] ?: @{};
    NSDictionary *metadataJSON = dictionary[@"metadata_json"];

    // Parse args (new unified array format)
    NSMutableArray<CSCapArg *> *args = [NSMutableArray array];
    NSArray *argsArray = dictionary[@"args"];
    if (argsArray && [argsArray isKindOfClass:[NSArray class]]) {
        for (NSDictionary *argDict in argsArray) {
            CSCapArg *arg = [CSCapArg argWithDictionary:argDict error:error];
            if (!arg) {
                return nil;
            }
            [args addObject:arg];
        }
    }

    // Parse output
    CSCapOutput *output = nil;
    NSDictionary *outputDict = dictionary[@"output"];
    if (outputDict) {
        output = [CSCapOutput outputWithDictionary:outputDict error:error];
        if (!output && error && *error) {
            return nil;
        }
    }

    // Parse registered_by
    CSRegisteredBy *registeredBy = nil;
    NSDictionary *registeredByDict = dictionary[@"registered_by"];
    if (registeredByDict) {
        registeredBy = [CSRegisteredBy registeredByWithDictionary:registeredByDict error:error];
        if (!registeredBy && error && *error) {
            return nil;
        }
    }

    CSCap *cap = [self capWithUrn:capUrn
                            title:title
                          command:command
                      description:capDescription
                         metadata:metadata
                       mediaSpecs:mediaSpecs
                             args:args
                           output:output
                     metadataJSON:metadataJSON];
    cap->_registeredBy = registeredBy;
    return cap;
}

- (NSDictionary *)toDictionary {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];

    dict[@"urn"] = [self.capUrn toString];
    dict[@"title"] = self.title;
    dict[@"command"] = self.command;

    if (self.capDescription) {
        dict[@"cap_description"] = self.capDescription;
    }

    dict[@"metadata"] = self.metadata ?: @{};

    if (self.mediaSpecs && self.mediaSpecs.count > 0) {
        dict[@"media_specs"] = self.mediaSpecs;
    }

    if (self.args && self.args.count > 0) {
        NSMutableArray *argsDicts = [NSMutableArray array];
        for (CSCapArg *arg in self.args) {
            [argsDicts addObject:[arg toDictionary]];
        }
        dict[@"args"] = argsDicts;
    }

    if (self.output) {
        dict[@"output"] = [self.output toDictionary];
    }

    if (self.metadataJSON) {
        dict[@"metadata_json"] = self.metadataJSON;
    }

    if (self.registeredBy) {
        dict[@"registered_by"] = [self.registeredBy toDictionary];
    }

    return [dict copy];
}

- (BOOL)matchesRequest:(NSString *)request {
    NSError *error;
    CSCapUrn *requestId = [CSCapUrn fromString:request error:&error];
    if (!requestId) return NO;
    return [self.capUrn canHandle:requestId];
}

- (BOOL)canHandleRequest:(CSCapUrn *)request {
    return [self.capUrn canHandle:request];
}

- (BOOL)isMoreSpecificThan:(CSCap *)other {
    if (!other) return YES;
    return [self.capUrn isMoreSpecificThan:other.capUrn];
}

- (nullable NSString *)metadataForKey:(NSString *)key {
    return self.metadata[key];
}

- (BOOL)hasMetadataForKey:(NSString *)key {
    return self.metadata[key] != nil;
}

- (NSString *)urnString {
    return [self.capUrn toString];
}

- (NSString *)description {
    NSMutableString *desc = [NSMutableString stringWithFormat:@"CSCap(urn: %@, title: %@, command: %@",
                            [self.capUrn toString], self.title, self.command];

    if (self.capDescription) {
        [desc appendFormat:@", description: %@", self.capDescription];
    }

    if (self.metadata.count > 0) {
        [desc appendFormat:@", metadata: %@", self.metadata];
    }

    if (self.mediaSpecs.count > 0) {
        [desc appendFormat:@", mediaSpecs: %lu entries", (unsigned long)self.mediaSpecs.count];
    }

    if (self.args.count > 0) {
        [desc appendFormat:@", args: %lu", (unsigned long)self.args.count];
    }

    [desc appendString:@")"];
    return desc;
}

- (BOOL)isEqual:(id)object {
    if (self == object) return YES;
    if (![object isKindOfClass:[CSCap class]]) return NO;

    CSCap *other = (CSCap *)object;

    // Required fields
    if (![self.capUrn isEqual:other.capUrn]) return NO;
    if (![self.title isEqualToString:other.title]) return NO;
    if (![self.command isEqualToString:other.command]) return NO;

    // Optional string field
    if ((self.capDescription == nil) != (other.capDescription == nil)) return NO;
    if (self.capDescription && ![self.capDescription isEqualToString:other.capDescription]) return NO;

    // Metadata dictionary
    if (![self.metadata isEqualToDictionary:other.metadata]) return NO;

    // MediaSpecs dictionary
    if ((self.mediaSpecs == nil) != (other.mediaSpecs == nil)) return NO;
    if (self.mediaSpecs && ![self.mediaSpecs isEqualToDictionary:other.mediaSpecs]) return NO;

    // Args
    if ((self.args == nil) != (other.args == nil)) return NO;
    if (self.args && ![self.args isEqualToArray:other.args]) return NO;

    // Output
    if ((self.output == nil) != (other.output == nil)) return NO;
    if (self.output && ![self.output isEqual:other.output]) return NO;

    // MetadataJSON
    if ((self.metadataJSON == nil) != (other.metadataJSON == nil)) return NO;
    if (self.metadataJSON && ![self.metadataJSON isEqualToDictionary:other.metadataJSON]) return NO;

    // RegisteredBy
    if ((self.registeredBy == nil) != (other.registeredBy == nil)) return NO;
    if (self.registeredBy && ![self.registeredBy isEqual:other.registeredBy]) return NO;

    return YES;
}

- (NSUInteger)hash {
    NSUInteger hash = [self.capUrn hash];
    hash ^= [self.title hash];
    hash ^= [self.command hash];
    hash ^= [self.metadata hash];
    hash ^= [self.mediaSpecs hash];
    hash ^= [self.args hash];
    hash ^= [self.output hash];
    hash ^= [self.metadataJSON hash];
    hash ^= [self.registeredBy hash];
    return hash;
}

- (id)copyWithZone:(NSZone *)zone {
    // FAIL HARD if required fields are nil
    if (!self.command || !self.title) {
        return nil;
    }
    CSCap *copy = [CSCap capWithUrn:self.capUrn
                             title:self.title
                           command:self.command
                       description:self.capDescription
                          metadata:self.metadata
                        mediaSpecs:self.mediaSpecs
                              args:self.args
                            output:self.output
                      metadataJSON:self.metadataJSON];
    copy->_registeredBy = [self.registeredBy copy];
    return copy;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.capUrn forKey:@"capUrn"];
    [coder encodeObject:self.title forKey:@"title"];
    [coder encodeObject:self.command forKey:@"command"];
    [coder encodeObject:self.capDescription forKey:@"capDescription"];
    [coder encodeObject:self.metadata forKey:@"metadata"];
    [coder encodeObject:self.mediaSpecs forKey:@"mediaSpecs"];
    [coder encodeObject:self.args forKey:@"args"];
    [coder encodeObject:self.output forKey:@"output"];
    [coder encodeObject:self.metadataJSON forKey:@"metadataJSON"];
    [coder encodeObject:self.registeredBy forKey:@"registeredBy"];
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    CSCapUrn *capUrn = [coder decodeObjectOfClass:[CSCapUrn class] forKey:@"capUrn"];
    NSString *title = [coder decodeObjectOfClass:[NSString class] forKey:@"title"];
    NSString *command = [coder decodeObjectOfClass:[NSString class] forKey:@"command"];
    NSString *description = [coder decodeObjectOfClass:[NSString class] forKey:@"capDescription"];
    NSDictionary *metadata = [coder decodeObjectOfClass:[NSDictionary class] forKey:@"metadata"];
    NSDictionary *mediaSpecs = [coder decodeObjectOfClass:[NSDictionary class] forKey:@"mediaSpecs"];
    NSArray *args = [coder decodeObjectOfClasses:[NSSet setWithObjects:[NSArray class], [CSCapArg class], nil] forKey:@"args"];
    CSCapOutput *output = [coder decodeObjectOfClass:[CSCapOutput class] forKey:@"output"];
    NSDictionary *metadataJSON = [coder decodeObjectOfClass:[NSDictionary class] forKey:@"metadataJSON"];
    CSRegisteredBy *registeredBy = [coder decodeObjectOfClass:[CSRegisteredBy class] forKey:@"registeredBy"];

    // FAIL HARD if required fields are missing
    if (!capUrn || !title || !command || !metadata) {
        return nil;
    }

    CSCap *cap = [CSCap capWithUrn:capUrn
                            title:title
                          command:command
                      description:description
                         metadata:metadata
                       mediaSpecs:mediaSpecs ?: @{}
                             args:args ?: @[]
                           output:output
                     metadataJSON:metadataJSON];
    cap->_registeredBy = registeredBy;
    return cap;
}

+ (instancetype)capWithUrn:(CSCapUrn *)capUrn
                     title:(NSString *)title
                   command:(NSString *)command {
    return [self capWithUrn:capUrn
                      title:title
                    command:command
                description:nil
                   metadata:@{}
                 mediaSpecs:@{}
                       args:@[]
                     output:nil
               metadataJSON:nil];
}

+ (instancetype)capWithUrn:(CSCapUrn *)capUrn
                     title:(NSString *)title
                   command:(NSString *)command
               description:(nullable NSString *)description
                  metadata:(NSDictionary<NSString *, NSString *> *)metadata
                mediaSpecs:(NSDictionary<NSString *, id> *)mediaSpecs
                      args:(NSArray<CSCapArg *> *)args
                    output:(nullable CSCapOutput *)output
              metadataJSON:(nullable NSDictionary *)metadataJSON {
    // FAIL HARD if required fields are nil
    if (!capUrn || !title || !command || !metadata || !mediaSpecs || !args) {
        return nil;
    }

    CSCap *cap = [[CSCap alloc] init];
    cap->_capUrn = [capUrn copy];
    cap->_title = [title copy];
    cap->_command = [command copy];
    cap->_capDescription = [description copy];
    cap->_metadata = [metadata copy];
    cap->_mediaSpecs = [mediaSpecs copy];
    cap->_args = [args copy];
    cap->_output = output;
    cap->_metadataJSON = [metadataJSON copy];
    return cap;
}

- (nullable NSString *)getCommand {
    return self.command;
}

- (nullable CSCapOutput *)getOutput {
    return self.output;
}

- (NSArray<CSCapArg *> *)getArgs {
    return self.args ?: @[];
}

- (NSArray<CSCapArg *> *)getRequiredArgs {
    NSMutableArray<CSCapArg *> *required = [NSMutableArray array];
    for (CSCapArg *arg in self.args) {
        if (arg.required) {
            [required addObject:arg];
        }
    }
    return [required copy];
}

- (NSArray<CSCapArg *> *)getOptionalArgs {
    NSMutableArray<CSCapArg *> *optional = [NSMutableArray array];
    for (CSCapArg *arg in self.args) {
        if (!arg.required) {
            [optional addObject:arg];
        }
    }
    return [optional copy];
}

- (void)addArg:(CSCapArg *)arg {
    NSMutableArray *mutableArgs = [_args mutableCopy];
    [mutableArgs addObject:arg];
    _args = [mutableArgs copy];
}

- (nullable CSCapArg *)findArgByMediaUrn:(NSString *)mediaUrn {
    for (CSCapArg *arg in self.args) {
        if ([arg.mediaUrn isEqualToString:mediaUrn]) {
            return arg;
        }
    }
    return nil;
}

- (NSArray<CSCapArg *> *)getPositionalArgs {
    NSMutableArray<CSCapArg *> *positional = [NSMutableArray array];
    for (CSCapArg *arg in self.args) {
        if ([arg hasPositionSource]) {
            [positional addObject:arg];
        }
    }

    // Sort by position
    [positional sortUsingComparator:^NSComparisonResult(CSCapArg *a, CSCapArg *b) {
        NSNumber *posA = [a getPosition];
        NSNumber *posB = [b getPosition];
        if (posA && posB) {
            return [posA compare:posB];
        }
        return NSOrderedSame;
    }];

    return [positional copy];
}

- (NSArray<CSCapArg *> *)getFlagArgs {
    NSMutableArray<CSCapArg *> *flagArgs = [NSMutableArray array];
    for (CSCapArg *arg in self.args) {
        if ([arg hasCliFlagSource]) {
            [flagArgs addObject:arg];
        }
    }
    return [flagArgs copy];
}

- (nullable NSString *)getStdinMediaUrn {
    for (CSCapArg *arg in self.args) {
        NSString *stdinUrn = [arg getStdinMediaUrn];
        if (stdinUrn) {
            return stdinUrn;
        }
    }
    return nil;
}

- (BOOL)acceptsStdin {
    return [self getStdinMediaUrn] != nil;
}

- (nullable NSDictionary *)getMetadataJSON {
    return self.metadataJSON;
}

- (void)setMetadataJSON:(nullable NSDictionary *)metadata {
    _metadataJSON = [metadata copy];
}

- (void)clearMetadataJSON {
    _metadataJSON = nil;
}

- (nullable CSMediaSpec *)resolveSpecId:(NSString *)specId error:(NSError **)error {
    return CSResolveMediaUrn(specId, self.mediaSpecs, error);
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

@end

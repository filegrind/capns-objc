//
//  CSCap.m
//  Formal cap implementation
//
//  NOTE: ArgumentType and OutputType enums have been REMOVED.
//  All type information is now conveyed via mediaSpec fields containing spec IDs.
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

#pragma mark - CSCapArgument Implementation

@implementation CSCapArgument

+ (instancetype)argumentWithName:(NSString *)name
                       mediaSpec:(NSString *)mediaSpec
                   argDescription:(NSString *)argDescription
                         cliFlag:(NSString *)cliFlag
                        position:(nullable NSNumber *)position
                      validation:(nullable CSArgumentValidation *)validation
                    defaultValue:(nullable id)defaultValue {
    CSCapArgument *argument = [[CSCapArgument alloc] init];
    argument->_name = [name copy];
    argument->_mediaSpec = [mediaSpec copy];
    argument->_argDescription = [argDescription copy];
    argument->_cliFlag = [cliFlag copy];
    argument->_position = position;
    argument->_validation = validation;
    argument->_defaultValue = defaultValue;
    argument->_metadata = nil;
    return argument;
}

+ (instancetype)argumentWithDictionary:(NSDictionary *)dictionary error:(NSError **)error {
    NSString *name = dictionary[@"name"];
    NSString *mediaUrn = dictionary[@"media_urn"];
    NSString *argDescription = dictionary[@"arg_description"];
    NSString *cliFlag = dictionary[@"cli_flag"];
    NSNumber *position = dictionary[@"position"];
    id defaultValue = dictionary[@"default_value"];
    NSDictionary *metadata = dictionary[@"metadata"];

    // FAIL HARD on missing required fields
    if (!name) {
        if (error) {
            *error = [NSError errorWithDomain:@"CSCapArgumentError"
                                         code:1001
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing required field: name"}];
        }
        return nil;
    }

    if (!mediaUrn) {
        if (error) {
            *error = [NSError errorWithDomain:@"CSCapArgumentError"
                                         code:1002
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Missing required field 'media_urn' for argument '%@'", name]}];
        }
        return nil;
    }

    if (!argDescription) {
        if (error) {
            *error = [NSError errorWithDomain:@"CSCapArgumentError"
                                         code:1003
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Missing required field 'arg_description' for argument '%@'", name]}];
        }
        return nil;
    }

    if (!cliFlag) {
        if (error) {
            *error = [NSError errorWithDomain:@"CSCapArgumentError"
                                         code:1004
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Missing required field 'cli_flag' for argument '%@'", name]}];
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

    CSCapArgument *argument = [[CSCapArgument alloc] init];
    argument->_name = [name copy];
    argument->_mediaSpec = [mediaUrn copy];
    argument->_argDescription = [argDescription copy];
    argument->_cliFlag = [cliFlag copy];
    argument->_position = position;
    argument->_validation = validation;
    argument->_defaultValue = defaultValue;
    argument->_metadata = [metadata copy];

    return argument;
}

- (id)copyWithZone:(NSZone *)zone {
    CSCapArgument *copy = [[CSCapArgument alloc] init];
    copy->_name = [self.name copy];
    copy->_mediaSpec = [self.mediaSpec copy];
    copy->_argDescription = [self.argDescription copy];
    copy->_cliFlag = [self.cliFlag copy];
    copy->_position = self.position;
    copy->_validation = [self.validation copy];
    copy->_defaultValue = self.defaultValue;
    copy->_metadata = [self.metadata copy];
    return copy;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.name forKey:@"name"];
    [coder encodeObject:self.mediaSpec forKey:@"mediaSpec"];
    [coder encodeObject:self.argDescription forKey:@"argDescription"];
    [coder encodeObject:self.cliFlag forKey:@"cliFlag"];
    [coder encodeObject:self.position forKey:@"position"];
    [coder encodeObject:self.validation forKey:@"validation"];
    [coder encodeObject:self.defaultValue forKey:@"defaultValue"];
    [coder encodeObject:self.metadata forKey:@"metadata"];
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    NSString *name = [coder decodeObjectOfClass:[NSString class] forKey:@"name"];
    NSString *mediaSpec = [coder decodeObjectOfClass:[NSString class] forKey:@"mediaSpec"];
    NSString *argDescription = [coder decodeObjectOfClass:[NSString class] forKey:@"argDescription"];

    // FAIL HARD on missing required fields
    if (!name || !mediaSpec || !argDescription) {
        return nil;
    }

    self = [super init];
    if (self) {
        _name = name;
        _mediaSpec = mediaSpec;
        _argDescription = argDescription;
        _cliFlag = [coder decodeObjectOfClass:[NSString class] forKey:@"cliFlag"];
        _position = [coder decodeObjectOfClass:[NSNumber class] forKey:@"position"];
        _validation = [coder decodeObjectOfClass:[CSArgumentValidation class] forKey:@"validation"];
        _defaultValue = [coder decodeObjectForKey:@"defaultValue"];
        _metadata = [coder decodeObjectOfClass:[NSDictionary class] forKey:@"metadata"];
    }
    return self;
}

- (NSDictionary *)toDictionary {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];

    dict[@"name"] = self.name;
    dict[@"media_urn"] = self.mediaSpec;
    dict[@"arg_description"] = self.argDescription;
    dict[@"cli_flag"] = self.cliFlag;

    if (self.position) dict[@"position"] = self.position;
    if (self.defaultValue) dict[@"default_value"] = self.defaultValue;
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
    if (![object isKindOfClass:[CSCapArgument class]]) return NO;

    CSCapArgument *other = (CSCapArgument *)object;

    if (![self.name isEqualToString:other.name]) return NO;
    if (![self.mediaSpec isEqualToString:other.mediaSpec]) return NO;
    if (![self.argDescription isEqualToString:other.argDescription]) return NO;
    if (![self.cliFlag isEqualToString:other.cliFlag]) return NO;

    if ((self.position == nil) != (other.position == nil)) return NO;
    if (self.position && ![self.position isEqualToNumber:other.position]) return NO;

    if ((self.validation == nil) != (other.validation == nil)) return NO;
    if (self.validation && ![self.validation isEqual:other.validation]) return NO;

    if ((self.defaultValue == nil) != (other.defaultValue == nil)) return NO;
    if (self.defaultValue && ![self.defaultValue isEqual:other.defaultValue]) return NO;

    if ((self.metadata == nil) != (other.metadata == nil)) return NO;
    if (self.metadata && ![self.metadata isEqualToDictionary:other.metadata]) return NO;

    return YES;
}

- (NSUInteger)hash {
    return [self.name hash] ^ [self.mediaSpec hash] ^ [self.argDescription hash] ^
           [self.cliFlag hash] ^ [self.position hash] ^ [self.validation hash] ^
           [self.defaultValue hash] ^ [self.metadata hash];
}

@end

#pragma mark - CSCapArguments Implementation

@implementation CSCapArguments

+ (instancetype)arguments {
    return [[CSCapArguments alloc] init];
}

+ (instancetype)argumentsWithRequired:(NSArray<CSCapArgument *> *)required
                             optional:(NSArray<CSCapArgument *> *)optional {
    // FAIL HARD if arrays are nil
    if (!required || !optional) {
        return nil;
    }
    CSCapArguments *arguments = [[CSCapArguments alloc] init];
    arguments->_required = [required copy];
    arguments->_optional = [optional copy];
    return arguments;
}

+ (instancetype)argumentsWithDictionary:(NSDictionary *)dictionary error:(NSError **)error {
    NSArray *requiredArray = dictionary[@"required"];
    NSArray *optionalArray = dictionary[@"optional"];

    NSMutableArray<CSCapArgument *> *required = [NSMutableArray array];
    NSMutableArray<CSCapArgument *> *optional = [NSMutableArray array];

    if (requiredArray) {
        for (NSDictionary *argDict in requiredArray) {
            CSCapArgument *argument = [CSCapArgument argumentWithDictionary:argDict error:error];
            if (!argument) {
                return nil;
            }
            [required addObject:argument];
        }
    }

    if (optionalArray) {
        for (NSDictionary *argDict in optionalArray) {
            CSCapArgument *argument = [CSCapArgument argumentWithDictionary:argDict error:error];
            if (!argument) {
                return nil;
            }
            [optional addObject:argument];
        }
    }

    return [self argumentsWithRequired:required optional:optional];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _required = @[];
        _optional = @[];
    }
    return self;
}

- (void)addRequiredArgument:(CSCapArgument *)argument {
    NSMutableArray *mutableRequired = [_required mutableCopy];
    [mutableRequired addObject:argument];
    _required = [mutableRequired copy];
}

- (void)addOptionalArgument:(CSCapArgument *)argument {
    NSMutableArray *mutableOptional = [_optional mutableCopy];
    [mutableOptional addObject:argument];
    _optional = [mutableOptional copy];
}

- (nullable CSCapArgument *)findArgumentWithName:(NSString *)name {
    for (CSCapArgument *arg in self.required) {
        if ([arg.name isEqualToString:name]) return arg;
    }
    for (CSCapArgument *arg in self.optional) {
        if ([arg.name isEqualToString:name]) return arg;
    }
    return nil;
}

- (NSArray<CSCapArgument *> *)positionalArguments {
    NSMutableArray *positional = [[NSMutableArray alloc] init];

    for (CSCapArgument *arg in self.required) {
        if (arg.position) [positional addObject:arg];
    }
    for (CSCapArgument *arg in self.optional) {
        if (arg.position) [positional addObject:arg];
    }

    [positional sortUsingComparator:^NSComparisonResult(CSCapArgument *a, CSCapArgument *b) {
        return [a.position compare:b.position];
    }];

    return [positional copy];
}

- (NSArray<CSCapArgument *> *)flagArguments {
    NSMutableArray *flags = [[NSMutableArray alloc] init];

    for (CSCapArgument *arg in self.required) {
        if (arg.cliFlag) [flags addObject:arg];
    }
    for (CSCapArgument *arg in self.optional) {
        if (arg.cliFlag) [flags addObject:arg];
    }

    return [flags copy];
}

- (BOOL)isEmpty {
    return self.required.count == 0 && self.optional.count == 0;
}

- (id)copyWithZone:(NSZone *)zone {
    return [CSCapArguments argumentsWithRequired:self.required optional:self.optional];
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.required forKey:@"required"];
    [coder encodeObject:self.optional forKey:@"optional"];
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        NSArray *required = [coder decodeObjectOfClass:[NSArray class] forKey:@"required"];
        NSArray *optional = [coder decodeObjectOfClass:[NSArray class] forKey:@"optional"];

        // FAIL HARD if required arrays are missing
        if (!required || !optional) {
            return nil;
        }

        _required = required;
        _optional = optional;
    }
    return self;
}

- (NSDictionary *)toDictionary {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];

    NSMutableArray *requiredDicts = [NSMutableArray array];
    for (CSCapArgument *arg in self.required) {
        [requiredDicts addObject:[arg toDictionary]];
    }
    if (requiredDicts.count > 0) {
        dict[@"required"] = requiredDicts;
    }

    NSMutableArray *optionalDicts = [NSMutableArray array];
    for (CSCapArgument *arg in self.optional) {
        [optionalDicts addObject:[arg toDictionary]];
    }
    if (optionalDicts.count > 0) {
        dict[@"optional"] = optionalDicts;
    }

    return [dict copy];
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (BOOL)isEqual:(id)object {
    if (self == object) return YES;
    if (![object isKindOfClass:[CSCapArguments class]]) return NO;

    CSCapArguments *other = (CSCapArguments *)object;
    return [self.required isEqualToArray:other.required] &&
           [self.optional isEqualToArray:other.optional];
}

- (NSUInteger)hash {
    return [self.required hash] ^ [self.optional hash];
}

@end

#pragma mark - CSCapOutput Implementation

@implementation CSCapOutput

+ (instancetype)outputWithMediaSpec:(NSString *)mediaSpec
                         validation:(nullable CSArgumentValidation *)validation
                  outputDescription:(NSString *)outputDescription {
    CSCapOutput *output = [[CSCapOutput alloc] init];
    output->_mediaSpec = [mediaSpec copy];
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
    output->_mediaSpec = [mediaUrn copy];
    output->_validation = validation;
    output->_outputDescription = [outputDescription copy];
    output->_metadata = [metadata copy];

    return output;
}

- (id)copyWithZone:(NSZone *)zone {
    CSCapOutput *copy = [[CSCapOutput alloc] init];
    copy->_mediaSpec = [self.mediaSpec copy];
    copy->_validation = [self.validation copy];
    copy->_outputDescription = [self.outputDescription copy];
    copy->_metadata = [self.metadata copy];
    return copy;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.mediaSpec forKey:@"mediaSpec"];
    [coder encodeObject:self.validation forKey:@"validation"];
    [coder encodeObject:self.outputDescription forKey:@"outputDescription"];
    [coder encodeObject:self.metadata forKey:@"metadata"];
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    NSString *mediaSpec = [coder decodeObjectOfClass:[NSString class] forKey:@"mediaSpec"];
    NSString *outputDescription = [coder decodeObjectOfClass:[NSString class] forKey:@"outputDescription"];

    // FAIL HARD on missing required fields
    if (!mediaSpec || !outputDescription) {
        return nil;
    }

    self = [super init];
    if (self) {
        _mediaSpec = mediaSpec;
        _validation = [coder decodeObjectOfClass:[CSArgumentValidation class] forKey:@"validation"];
        _outputDescription = outputDescription;
        _metadata = [coder decodeObjectOfClass:[NSDictionary class] forKey:@"metadata"];
    }
    return self;
}

- (NSDictionary *)toDictionary {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];

    dict[@"media_urn"] = self.mediaSpec;
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

    if (![self.mediaSpec isEqualToString:other.mediaSpec]) return NO;

    if ((self.validation == nil) != (other.validation == nil)) return NO;
    if (self.validation && ![self.validation isEqual:other.validation]) return NO;

    if (![self.outputDescription isEqualToString:other.outputDescription]) return NO;

    if ((self.metadata == nil) != (other.metadata == nil)) return NO;
    if (self.metadata && ![self.metadata isEqualToDictionary:other.metadata]) return NO;

    return YES;
}

- (NSUInteger)hash {
    return [self.mediaSpec hash] ^ [self.validation hash] ^ [self.outputDescription hash] ^ [self.metadata hash];
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
            // Use fromTags: which properly extracts 'in' and 'out' from the tags dictionary
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
    BOOL acceptsStdin = [dictionary[@"accepts_stdin"] boolValue];
    NSDictionary *metadataJSON = dictionary[@"metadata_json"];

    // Parse arguments
    CSCapArguments *arguments;
    NSDictionary *argumentsDict = dictionary[@"arguments"];
    if (argumentsDict) {
        arguments = [CSCapArguments argumentsWithDictionary:argumentsDict error:error];
        if (!arguments && error && *error) {
            return nil;
        }
    } else {
        arguments = [CSCapArguments arguments];
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
                        arguments:arguments
                           output:output
                     acceptsStdin:acceptsStdin
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

    if (self.arguments && !self.arguments.isEmpty) {
        dict[@"arguments"] = [self.arguments toDictionary];
    }

    if (self.output) {
        dict[@"output"] = [self.output toDictionary];
    }

    dict[@"accepts_stdin"] = @(self.acceptsStdin);

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

    [desc appendString:@")"];
    return desc;
}

// Compares all fields to match Rust reference implementation
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

    // Arguments
    if ((self.arguments == nil) != (other.arguments == nil)) return NO;
    if (self.arguments && ![self.arguments isEqual:other.arguments]) return NO;

    // Output
    if ((self.output == nil) != (other.output == nil)) return NO;
    if (self.output && ![self.output isEqual:other.output]) return NO;

    // AcceptsStdin
    if (self.acceptsStdin != other.acceptsStdin) return NO;

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
    hash ^= [self.arguments hash];
    hash ^= [self.output hash];
    hash ^= self.acceptsStdin ? 1 : 0;
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
                         arguments:self.arguments
                            output:self.output
                      acceptsStdin:self.acceptsStdin
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
    [coder encodeObject:self.arguments forKey:@"arguments"];
    [coder encodeObject:self.output forKey:@"output"];
    [coder encodeBool:self.acceptsStdin forKey:@"acceptsStdin"];
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
    CSCapArguments *arguments = [coder decodeObjectOfClass:[CSCapArguments class] forKey:@"arguments"];
    CSCapOutput *output = [coder decodeObjectOfClass:[CSCapOutput class] forKey:@"output"];
    BOOL acceptsStdin = [coder decodeBoolForKey:@"acceptsStdin"];
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
                        arguments:arguments ?: [CSCapArguments arguments]
                           output:output
                     acceptsStdin:acceptsStdin
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
                  arguments:[CSCapArguments arguments]
                     output:nil
               acceptsStdin:NO
               metadataJSON:nil];
}

+ (instancetype)capWithUrn:(CSCapUrn *)capUrn
                     title:(NSString *)title
                   command:(NSString *)command
               description:(nullable NSString *)description
                  metadata:(NSDictionary<NSString *, NSString *> *)metadata
                mediaSpecs:(NSDictionary<NSString *, id> *)mediaSpecs
                 arguments:(CSCapArguments *)arguments
                    output:(nullable CSCapOutput *)output
              acceptsStdin:(BOOL)acceptsStdin
              metadataJSON:(nullable NSDictionary *)metadataJSON {
    // FAIL HARD if required fields are nil
    if (!capUrn || !title || !command || !metadata || !mediaSpecs || !arguments) {
        return nil;
    }

    CSCap *cap = [[CSCap alloc] init];
    cap->_capUrn = [capUrn copy];
    cap->_title = [title copy];
    cap->_command = [command copy];
    cap->_capDescription = [description copy];
    cap->_metadata = [metadata copy];
    cap->_mediaSpecs = [mediaSpecs copy];
    cap->_arguments = arguments;
    cap->_output = output;
    cap->_acceptsStdin = acceptsStdin;
    cap->_metadataJSON = [metadataJSON copy];
    return cap;
}

- (nullable NSString *)getCommand {
    return self.command;
}

- (CSCapArguments *)getArguments {
    return self.arguments ?: [CSCapArguments arguments];
}

- (nullable CSCapOutput *)getOutput {
    return self.output;
}

- (void)addRequiredArgument:(CSCapArgument *)argument {
    if (!_arguments) {
        _arguments = [CSCapArguments arguments];
    }
    [_arguments addRequiredArgument:argument];
}

- (void)addOptionalArgument:(CSCapArgument *)argument {
    if (!_arguments) {
        _arguments = [CSCapArguments arguments];
    }
    [_arguments addOptionalArgument:argument];
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

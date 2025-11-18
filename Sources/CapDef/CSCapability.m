//
//  CSCapability.m
//  Formal capability implementation
//

#import "CSCapability.h"

@implementation CSCapability

+ (instancetype)capabilityWithId:(CSCapabilityKey *)capabilityKey version:(NSString *)version command:(NSString *)command {
    return [self capabilityWithId:capabilityKey version:version description:nil metadata:@{} command:command arguments:[CSCapabilityArguments arguments] output:nil acceptsStdin:NO];
}

+ (instancetype)capabilityWithId:(CSCapabilityKey *)capabilityKey 
                         version:(NSString *)version
                         command:(NSString *)command
                     description:(NSString *)description {
    return [self capabilityWithId:capabilityKey version:version description:description metadata:@{} command:command arguments:[CSCapabilityArguments arguments] output:nil acceptsStdin:NO];
}

+ (instancetype)capabilityWithId:(CSCapabilityKey *)capabilityKey 
                         version:(NSString *)version
                         command:(NSString *)command
                        metadata:(NSDictionary<NSString *, NSString *> *)metadata {
    return [self capabilityWithId:capabilityKey version:version description:nil metadata:metadata command:command arguments:[CSCapabilityArguments arguments] output:nil acceptsStdin:NO];
}

+ (instancetype)capabilityWithId:(CSCapabilityKey *)capabilityKey 
                         version:(NSString *)version
                         command:(NSString *)command
                     description:(nullable NSString *)description 
                        metadata:(NSDictionary<NSString *, NSString *> *)metadata {
    return [self capabilityWithId:capabilityKey version:version description:description metadata:metadata command:command arguments:[CSCapabilityArguments arguments] output:nil acceptsStdin:NO];
}

- (BOOL)matchesRequest:(NSString *)request {
    NSError *error;
    CSCapabilityKey *requestId = [CSCapabilityKey fromString:request error:&error];
    if (!requestId) {
        return NO;
    }
    return [self.capabilityKey canHandle:requestId];
}

- (BOOL)canHandleRequest:(CSCapabilityKey *)request {
    return [self.capabilityKey canHandle:request];
}

- (BOOL)isMoreSpecificThan:(CSCapability *)other {
    if (!other) {
        return YES;
    }
    return [self.capabilityKey isMoreSpecificThan:other.capabilityKey];
}

- (nullable NSString *)metadataForKey:(NSString *)key {
    return self.metadata[key];
}

- (BOOL)hasMetadataForKey:(NSString *)key {
    return self.metadata[key] != nil;
}

- (NSString *)idString {
    return [self.capabilityKey toString];
}

- (NSString *)description {
    NSMutableString *desc = [NSMutableString stringWithFormat:@"CSCapability(id: %@, version: %@", 
                            [self.capabilityKey toString], self.version];
    
    if (self.capabilityDescription) {
        [desc appendFormat:@", description: %@", self.capabilityDescription];
    }
    
    if (self.metadata.count > 0) {
        [desc appendFormat:@", metadata: %@", self.metadata];
    }
    
    [desc appendString:@")"];
    return desc;
}

- (BOOL)isEqual:(id)object {
    if (self == object) return YES;
    if (![object isKindOfClass:[CSCapability class]]) return NO;
    
    CSCapability *other = (CSCapability *)object;
    return [self.capabilityKey isEqual:other.capabilityKey] &&
           [self.version isEqualToString:other.version] &&
           ((self.capabilityDescription == nil && other.capabilityDescription == nil) ||
            [self.capabilityDescription isEqualToString:other.capabilityDescription]) &&
           [self.metadata isEqualToDictionary:other.metadata];
}

- (NSUInteger)hash {
    return [self.capabilityKey hash] ^ [self.version hash] ^ [self.metadata hash];
}

- (id)copyWithZone:(NSZone *)zone {
    return [CSCapability capabilityWithId:self.capabilityKey 
                                   version:self.version
                               description:self.capabilityDescription 
                                  metadata:self.metadata
                                   command:self.command ?: @"unknown"
                                 arguments:self.arguments
                                    output:self.output
                              acceptsStdin:self.acceptsStdin];
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.capabilityKey forKey:@"capabilityKey"];
    [coder encodeObject:self.version forKey:@"version"];
    [coder encodeObject:self.command forKey:@"command"];
    [coder encodeObject:self.capabilityDescription forKey:@"capabilityDescription"];
    [coder encodeObject:self.metadata forKey:@"metadata"];
    [coder encodeBool:self.acceptsStdin forKey:@"acceptsStdin"];
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    CSCapabilityKey *capabilityKey = [coder decodeObjectOfClass:[CSCapabilityKey class] forKey:@"capabilityKey"];
    NSString *version = [coder decodeObjectOfClass:[NSString class] forKey:@"version"];
    NSString *command = [coder decodeObjectOfClass:[NSString class] forKey:@"command"];
    NSString *description = [coder decodeObjectOfClass:[NSString class] forKey:@"capabilityDescription"];
    NSDictionary *metadata = [coder decodeObjectOfClass:[NSDictionary class] forKey:@"metadata"];
    BOOL acceptsStdin = [coder decodeBoolForKey:@"acceptsStdin"];
    
    if (!capabilityKey || !version) return nil;
    
    return [CSCapability capabilityWithId:capabilityKey 
                                   version:version
                               description:description 
                                  metadata:metadata ?: @{}
                                   command:command ?: @"unknown"
                                 arguments:[CSCapabilityArguments arguments]
                                    output:nil
                              acceptsStdin:acceptsStdin];
}

- (instancetype)initWithId:(CSCapabilityKey *)capabilityKey
					version:(NSString *)version
					command:(NSString *)command {
	self = [super init];
	if (self) {
		_capabilityKey = [capabilityKey copy];
		_version = [version copy];
		_command = [command copy];
		_metadata = @{};
		_arguments = [CSCapabilityArguments arguments];
	}
	return self;
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

#pragma mark - Missing Methods

+ (instancetype)capabilityWithId:(CSCapabilityKey *)capabilityKey
                         version:(NSString *)version
                         command:(NSString *)command
                       arguments:(CSCapabilityArguments *)arguments {
    return [self capabilityWithId:capabilityKey version:version description:nil metadata:@{} command:command arguments:arguments output:nil acceptsStdin:NO];
}

+ (instancetype)capabilityWithId:(CSCapabilityKey *)capabilityKey
                         version:(NSString *)version
                     description:(nullable NSString *)description
                        metadata:(NSDictionary<NSString *, NSString *> *)metadata
                         command:(NSString *)command
                       arguments:(CSCapabilityArguments *)arguments
                          output:(nullable CSCapabilityOutput *)output
                    acceptsStdin:(BOOL)acceptsStdin {
    CSCapability *capability = [[CSCapability alloc] init];
    capability->_capabilityKey = [capabilityKey copy];
    capability->_version = [version copy];
    capability->_capabilityDescription = [description copy];
    capability->_metadata = [metadata copy] ?: @{};
    capability->_command = [command copy];
    capability->_arguments = arguments ?: [CSCapabilityArguments arguments];
    capability->_output = output;
    capability->_acceptsStdin = acceptsStdin;
    return capability;
}

- (nullable NSString *)getCommand {
    return self.command;
}

- (CSCapabilityArguments *)getArguments {
    return self.arguments ?: [CSCapabilityArguments arguments];
}

- (nullable CSCapabilityOutput *)getOutput {
    return self.output;
}

- (void)addRequiredArgument:(CSCapabilityArgument *)argument {
    if (!_arguments) {
        _arguments = [CSCapabilityArguments arguments];
    }
    [_arguments addRequiredArgument:argument];
}

- (void)addOptionalArgument:(CSCapabilityArgument *)argument {
    if (!_arguments) {
        _arguments = [CSCapabilityArguments arguments];
    }
    [_arguments addOptionalArgument:argument];
}

@end

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

+ (BOOL)supportsSecureCoding {
    return YES;
}

@end

#pragma mark - CSCapabilityArgument Implementation

@implementation CSCapabilityArgument

+ (instancetype)argumentWithName:(NSString *)name
                            type:(CSArgumentType)type
                     description:(NSString *)description
                         cliFlag:(NSString *)cliFlag
                        position:(nullable NSNumber *)position
                      validation:(nullable CSArgumentValidation *)validation
                    defaultValue:(nullable id)defaultValue {
    CSCapabilityArgument *argument = [[CSCapabilityArgument alloc] init];
    argument->_name = [name copy];
    argument->_type = type;
    argument->_argumentDescription = [description copy];
    argument->_cliFlag = [cliFlag copy];
    argument->_position = position;
    argument->_validation = validation;
    argument->_defaultValue = defaultValue;
    return argument;
}

- (id)copyWithZone:(NSZone *)zone {
    return [CSCapabilityArgument argumentWithName:self.name
                                              type:self.type
                                       description:self.argumentDescription
                                           cliFlag:self.cliFlag
                                          position:self.position
                                        validation:self.validation
                                      defaultValue:self.defaultValue];
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.name forKey:@"name"];
    [coder encodeInteger:self.type forKey:@"type"];
    [coder encodeObject:self.argumentDescription forKey:@"argumentDescription"];
    [coder encodeObject:self.cliFlag forKey:@"cli_flag"];
    [coder encodeObject:self.position forKey:@"position"];
    [coder encodeObject:self.validation forKey:@"validation"];
    [coder encodeObject:self.defaultValue forKey:@"defaultValue"];
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    NSString *name = [coder decodeObjectOfClass:[NSString class] forKey:@"name"];
    CSArgumentType type = (CSArgumentType)[coder decodeIntegerForKey:@"type"];
    NSString *description = [coder decodeObjectOfClass:[NSString class] forKey:@"argumentDescription"];
    
    if (!name || !description) return nil;
    
    self = [super init];
    if (self) {
        _name = name;
        _type = type;
        _argumentDescription = description;
        _cliFlag = [coder decodeObjectOfClass:[NSString class] forKey:@"cli_flag"];
        _position = [coder decodeObjectOfClass:[NSNumber class] forKey:@"position"];
        _validation = [coder decodeObjectOfClass:[CSArgumentValidation class] forKey:@"validation"];
        _defaultValue = [coder decodeObjectForKey:@"defaultValue"];
    }
    return self;
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

@end

#pragma mark - CSCapabilityArguments Implementation

@implementation CSCapabilityArguments

+ (instancetype)arguments {
    return [[CSCapabilityArguments alloc] init];
}

+ (instancetype)argumentsWithRequired:(NSArray<CSCapabilityArgument *> *)required
                             optional:(NSArray<CSCapabilityArgument *> *)optional {
    CSCapabilityArguments *arguments = [[CSCapabilityArguments alloc] init];
    arguments->_required = [required copy] ?: @[];
    arguments->_optional = [optional copy] ?: @[];
    return arguments;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _required = @[];
        _optional = @[];
    }
    return self;
}

- (void)addRequiredArgument:(CSCapabilityArgument *)argument {
    NSMutableArray *mutableRequired = [_required mutableCopy];
    [mutableRequired addObject:argument];
    _required = [mutableRequired copy];
}

- (void)addOptionalArgument:(CSCapabilityArgument *)argument {
    NSMutableArray *mutableOptional = [_optional mutableCopy];
    [mutableOptional addObject:argument];
    _optional = [mutableOptional copy];
}

- (nullable CSCapabilityArgument *)findArgumentWithName:(NSString *)name {
    for (CSCapabilityArgument *arg in self.required) {
        if ([arg.name isEqualToString:name]) {
            return arg;
        }
    }
    for (CSCapabilityArgument *arg in self.optional) {
        if ([arg.name isEqualToString:name]) {
            return arg;
        }
    }
    return nil;
}

- (NSArray<CSCapabilityArgument *> *)positionalArguments {
    NSMutableArray *positional = [[NSMutableArray alloc] init];
    
    for (CSCapabilityArgument *arg in self.required) {
        if (arg.position) {
            [positional addObject:arg];
        }
    }
    for (CSCapabilityArgument *arg in self.optional) {
        if (arg.position) {
            [positional addObject:arg];
        }
    }
    
    // Sort by position
    [positional sortUsingComparator:^NSComparisonResult(CSCapabilityArgument *a, CSCapabilityArgument *b) {
        return [a.position compare:b.position];
    }];
    
    return [positional copy];
}

- (NSArray<CSCapabilityArgument *> *)flagArguments {
    NSMutableArray *flags = [[NSMutableArray alloc] init];
    
    for (CSCapabilityArgument *arg in self.required) {
        if (arg.cliFlag) {
            [flags addObject:arg];
        }
    }
    for (CSCapabilityArgument *arg in self.optional) {
        if (arg.cliFlag) {
            [flags addObject:arg];
        }
    }
    
    return [flags copy];
}

- (BOOL)isEmpty {
    return self.required.count == 0 && self.optional.count == 0;
}

- (id)copyWithZone:(NSZone *)zone {
    return [CSCapabilityArguments argumentsWithRequired:self.required optional:self.optional];
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.required forKey:@"required"];
    [coder encodeObject:self.optional forKey:@"optional"];
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        _required = [coder decodeObjectOfClass:[NSArray class] forKey:@"required"] ?: @[];
        _optional = [coder decodeObjectOfClass:[NSArray class] forKey:@"optional"] ?: @[];
    }
    return self;
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

@end

#pragma mark - CSCapabilityOutput Implementation

@implementation CSCapabilityOutput

+ (instancetype)outputWithType:(CSOutputType)type
                     schemaRef:(nullable NSString *)schemaRef
                   contentType:(nullable NSString *)contentType
                    validation:(nullable CSArgumentValidation *)validation
                   description:(NSString *)description {
    CSCapabilityOutput *output = [[CSCapabilityOutput alloc] init];
    output->_type = type;
    output->_schemaRef = [schemaRef copy];
    output->_contentType = [contentType copy];
    output->_validation = validation;
    output->_outputDescription = [description copy];
    return output;
}

- (id)copyWithZone:(NSZone *)zone {
    return [CSCapabilityOutput outputWithType:self.type
                                     schemaRef:self.schemaRef
                                   contentType:self.contentType
                                    validation:self.validation
                                   description:self.outputDescription];
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeInteger:self.type forKey:@"type"];
    [coder encodeObject:self.schemaRef forKey:@"schemaRef"];
    [coder encodeObject:self.contentType forKey:@"contentType"];
    [coder encodeObject:self.validation forKey:@"validation"];
    [coder encodeObject:self.outputDescription forKey:@"outputDescription"];
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    NSString *description = [coder decodeObjectOfClass:[NSString class] forKey:@"outputDescription"];
    if (!description) return nil;
    
    self = [super init];
    if (self) {
        _type = (CSOutputType)[coder decodeIntegerForKey:@"type"];
        _schemaRef = [coder decodeObjectOfClass:[NSString class] forKey:@"schemaRef"];
        _contentType = [coder decodeObjectOfClass:[NSString class] forKey:@"contentType"];
        _validation = [coder decodeObjectOfClass:[CSArgumentValidation class] forKey:@"validation"];
        _outputDescription = description;
    }
    return self;
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

@end
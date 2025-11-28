//
//  CSCap.m
//  Formal cap implementation
//

#import "CSCap.h"

@implementation CSCap

+ (instancetype)capWithDictionary:(NSDictionary *)dictionary error:(NSError **)error {
    // Required fields
    NSString *urnString = dictionary[@"id"];
    NSString *version = dictionary[@"version"];
    NSString *command = dictionary[@"command"];
    
    if (!urnString || !version || !command) {
        if (error) {
            *error = [NSError errorWithDomain:@"CSCapError"
                                         code:1001
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing required cap fields: id, version, or command"}];
        }
        return nil;
    }
    
    // Parse cap URN
    NSError *keyError;
    CSCapUrn *capUrn = [CSCapUrn fromString:urnString error:&keyError];
    if (!capUrn) {
        if (error) {
            *error = keyError;
        }
        return nil;
    }
    
    // Optional fields
    NSString *description = dictionary[@"description"];
    NSDictionary *metadata = dictionary[@"metadata"] ?: @{};
    BOOL acceptsStdin = [dictionary[@"accepts_stdin"] boolValue]; // defaults to NO if missing
    
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
    
    return [self capWithId:capUrn
                          version:version
                      description:description
                         metadata:metadata
                          command:command
                        arguments:arguments
                           output:output
                     acceptsStdin:acceptsStdin];
}

- (BOOL)matchesRequest:(NSString *)request {
    NSError *error;
    CSCapUrn *requestId = [CSCapUrn fromString:request error:&error];
    if (!requestId) {
        return NO;
    }
    return [self.capUrn canHandle:requestId];
}

- (BOOL)canHandleRequest:(CSCapUrn *)request {
    return [self.capUrn canHandle:request];
}

- (BOOL)isMoreSpecificThan:(CSCap *)other {
    if (!other) {
        return YES;
    }
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
    NSMutableString *desc = [NSMutableString stringWithFormat:@"CSCap(id: %@, version: %@", 
                            [self.capUrn toString], self.version];
    
    if (self.capDescription) {
        [desc appendFormat:@", description: %@", self.capDescription];
    }
    
    if (self.metadata.count > 0) {
        [desc appendFormat:@", metadata: %@", self.metadata];
    }
    
    [desc appendString:@")"];
    return desc;
}

- (BOOL)isEqual:(id)object {
    if (self == object) return YES;
    if (![object isKindOfClass:[CSCap class]]) return NO;
    
    CSCap *other = (CSCap *)object;
    return [self.capUrn isEqual:other.capUrn] &&
           [self.version isEqualToString:other.version] &&
           ((self.capDescription == nil && other.capDescription == nil) ||
            [self.capDescription isEqualToString:other.capDescription]) &&
           [self.metadata isEqualToDictionary:other.metadata];
}

- (NSUInteger)hash {
    return [self.capUrn hash] ^ [self.version hash] ^ [self.metadata hash];
}

- (id)copyWithZone:(NSZone *)zone {
    // Fail hard if command is nil - this should never happen in a properly constructed cap
    if (!self.command) {
        return nil;
    }
    return [CSCap capWithId:self.capUrn 
                                   version:self.version
                               description:self.capDescription 
                                  metadata:self.metadata
                                   command:self.command
                                 arguments:self.arguments
                                    output:self.output
                              acceptsStdin:self.acceptsStdin];
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.capUrn forKey:@"capUrn"];
    [coder encodeObject:self.version forKey:@"version"];
    [coder encodeObject:self.command forKey:@"command"];
    [coder encodeObject:self.capDescription forKey:@"capDescription"];
    [coder encodeObject:self.metadata forKey:@"metadata"];
    [coder encodeBool:self.acceptsStdin forKey:@"acceptsStdin"];
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    CSCapUrn *capUrn = [coder decodeObjectOfClass:[CSCapUrn class] forKey:@"capUrn"];
    NSString *version = [coder decodeObjectOfClass:[NSString class] forKey:@"version"];
    NSString *command = [coder decodeObjectOfClass:[NSString class] forKey:@"command"];
    NSString *description = [coder decodeObjectOfClass:[NSString class] forKey:@"capDescription"];
    NSDictionary *metadata = [coder decodeObjectOfClass:[NSDictionary class] forKey:@"metadata"];
    BOOL acceptsStdin = [coder decodeBoolForKey:@"acceptsStdin"];
    
    // Fail hard if required fields are missing
    if (!capUrn || !version || !command || !metadata) {
        return nil;
    }
    
    return [CSCap capWithId:capUrn 
                                   version:version
                               description:description 
                                  metadata:metadata
                                   command:command
                                 arguments:[CSCapArguments arguments]
                                    output:nil
                              acceptsStdin:acceptsStdin];
}

- (instancetype)initWithId:(CSCapUrn *)capUrn
					version:(NSString *)version
					command:(NSString *)command {
	self = [super init];
	if (self) {
		_capUrn = [capUrn copy];
		_version = [version copy];
		_command = [command copy];
		_metadata = @{};
		_arguments = [CSCapArguments arguments];
	}
	return self;
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

#pragma mark - Missing Methods


+ (instancetype)capWithId:(CSCapUrn *)capUrn
                         version:(NSString *)version
                     description:(nullable NSString *)description
                        metadata:(NSDictionary<NSString *, NSString *> *)metadata
                         command:(NSString *)command
                       arguments:(CSCapArguments *)arguments
                          output:(nullable CSCapOutput *)output
                    acceptsStdin:(BOOL)acceptsStdin {
    CSCap *cap = [[CSCap alloc] init];
    cap->_capUrn = [capUrn copy];
    cap->_version = [version copy];
    cap->_capDescription = [description copy];
    // Fail hard if required fields are nil
    if (!metadata || !arguments) {
        return nil;
    }
    cap->_metadata = [metadata copy];
    cap->_command = [command copy];
    cap->_arguments = arguments;
    cap->_output = output;
    cap->_acceptsStdin = acceptsStdin;
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

+ (BOOL)supportsSecureCoding {
    return YES;
}

@end

#pragma mark - CSCapArgument Implementation

@implementation CSCapArgument

+ (instancetype)argumentWithName:(NSString *)name
                            type:(CSArgumentType)type
                     description:(NSString *)description
                         cliFlag:(NSString *)cliFlag
                        position:(nullable NSNumber *)position
                      validation:(nullable CSArgumentValidation *)validation
                    defaultValue:(nullable id)defaultValue {
    CSCapArgument *argument = [[CSCapArgument alloc] init];
    argument->_name = [name copy];
    argument->_type = type;
    argument->_argumentDescription = [description copy];
    argument->_cliFlag = [cliFlag copy];
    argument->_position = position;
    argument->_validation = validation;
    argument->_defaultValue = defaultValue;
    return argument;
}

+ (instancetype)argumentWithDictionary:(NSDictionary *)dictionary error:(NSError **)error {
    NSString *name = dictionary[@"name"];
    NSString *typeString = dictionary[@"type"];
    NSString *description = dictionary[@"description"];
    NSString *cliFlag = dictionary[@"cli_flag"];
    NSNumber *position = dictionary[@"position"];
    id defaultValue = dictionary[@"default_value"];
    
    if (!name || !typeString || !description || !cliFlag) {
        if (error) {
            *error = [NSError errorWithDomain:@"CSCapArgumentError"
                                         code:1002
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing required argument fields: name, type, description, or cli_flag"}];
        }
        return nil;
    }
    
    // Parse type
    CSArgumentType type;
    if ([typeString isEqualToString:@"string"]) {
        type = CSArgumentTypeString;
    } else if ([typeString isEqualToString:@"integer"]) {
        type = CSArgumentTypeInteger;
    } else if ([typeString isEqualToString:@"number"]) {
        type = CSArgumentTypeNumber;
    } else if ([typeString isEqualToString:@"boolean"]) {
        type = CSArgumentTypeBoolean;
    } else if ([typeString isEqualToString:@"array"]) {
        type = CSArgumentTypeArray;
    } else if ([typeString isEqualToString:@"object"]) {
        type = CSArgumentTypeObject;
    } else {
        if (error) {
            *error = [NSError errorWithDomain:@"CSCapArgumentError"
                                         code:1003
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unknown argument type: %@", typeString]}];
        }
        return nil;
    }
    
    // Parse validation
    CSArgumentValidation *validation = nil;
    NSDictionary *validationDict = dictionary[@"validation"];
    if (validationDict) {
        validation = [CSArgumentValidation validationWithDictionary:validationDict error:error];
        if (!validation && error && *error) {
            return nil;
        }
    }
    
    return [self argumentWithName:name
                             type:type
                      description:description
                          cliFlag:cliFlag
                         position:position
                       validation:validation
                     defaultValue:defaultValue];
}

- (id)copyWithZone:(NSZone *)zone {
    return [CSCapArgument argumentWithName:self.name
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

#pragma mark - CSCapArguments Implementation

@implementation CSCapArguments

+ (instancetype)arguments {
    return [[CSCapArguments alloc] init];
}

+ (instancetype)argumentsWithRequired:(NSArray<CSCapArgument *> *)required
                             optional:(NSArray<CSCapArgument *> *)optional {
    // Fail hard if arrays are nil
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
    
    // Parse required arguments
    if (requiredArray) {
        for (NSDictionary *argDict in requiredArray) {
            CSCapArgument *argument = [CSCapArgument argumentWithDictionary:argDict error:error];
            if (!argument) {
                return nil;
            }
            [required addObject:argument];
        }
    }
    
    // Parse optional arguments
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
        if ([arg.name isEqualToString:name]) {
            return arg;
        }
    }
    for (CSCapArgument *arg in self.optional) {
        if ([arg.name isEqualToString:name]) {
            return arg;
        }
    }
    return nil;
}

- (NSArray<CSCapArgument *> *)positionalArguments {
    NSMutableArray *positional = [[NSMutableArray alloc] init];
    
    for (CSCapArgument *arg in self.required) {
        if (arg.position) {
            [positional addObject:arg];
        }
    }
    for (CSCapArgument *arg in self.optional) {
        if (arg.position) {
            [positional addObject:arg];
        }
    }
    
    // Sort by position
    [positional sortUsingComparator:^NSComparisonResult(CSCapArgument *a, CSCapArgument *b) {
        return [a.position compare:b.position];
    }];
    
    return [positional copy];
}

- (NSArray<CSCapArgument *> *)flagArguments {
    NSMutableArray *flags = [[NSMutableArray alloc] init];
    
    for (CSCapArgument *arg in self.required) {
        if (arg.cliFlag) {
            [flags addObject:arg];
        }
    }
    for (CSCapArgument *arg in self.optional) {
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
        
        // Fail hard if required arrays are missing
        if (!required || !optional) {
            return nil;
        }
        
        _required = required;
        _optional = optional;
    }
    return self;
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

@end

#pragma mark - CSCapOutput Implementation

@implementation CSCapOutput

+ (instancetype)outputWithType:(CSOutputType)type
                     schemaRef:(nullable NSString *)schemaRef
                   contentType:(nullable NSString *)contentType
                    validation:(nullable CSArgumentValidation *)validation
                   description:(NSString *)description {
    CSCapOutput *output = [[CSCapOutput alloc] init];
    output->_type = type;
    output->_schemaRef = [schemaRef copy];
    output->_contentType = [contentType copy];
    output->_validation = validation;
    output->_outputDescription = [description copy];
    return output;
}

+ (instancetype)outputWithDictionary:(NSDictionary *)dictionary error:(NSError **)error {
    NSString *typeString = dictionary[@"type"];
    NSString *schemaRef = dictionary[@"schema_ref"];
    NSString *contentType = dictionary[@"content_type"];
    NSString *description = dictionary[@"description"];
    
    if (!typeString || !description) {
        if (error) {
            *error = [NSError errorWithDomain:@"CSCapOutputError"
                                         code:1004
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing required output fields: type or description"}];
        }
        return nil;
    }
    
    // Parse type
    CSOutputType type;
    if ([typeString isEqualToString:@"string"]) {
        type = CSOutputTypeString;
    } else if ([typeString isEqualToString:@"integer"]) {
        type = CSOutputTypeInteger;
    } else if ([typeString isEqualToString:@"number"]) {
        type = CSOutputTypeNumber;
    } else if ([typeString isEqualToString:@"boolean"]) {
        type = CSOutputTypeBoolean;
    } else if ([typeString isEqualToString:@"array"]) {
        type = CSOutputTypeArray;
    } else if ([typeString isEqualToString:@"object"]) {
        type = CSOutputTypeObject;
    } else if ([typeString isEqualToString:@"binary"]) {
        type = CSOutputTypeBinary;
    } else {
        if (error) {
            *error = [NSError errorWithDomain:@"CSCapOutputError"
                                         code:1005
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unknown output type: %@", typeString]}];
        }
        return nil;
    }
    
    // Parse validation
    CSArgumentValidation *validation = nil;
    NSDictionary *validationDict = dictionary[@"validation"];
    if (validationDict) {
        validation = [CSArgumentValidation validationWithDictionary:validationDict error:error];
        if (!validation && error && *error) {
            return nil;
        }
    }
    
    return [self outputWithType:type
                      schemaRef:schemaRef
                    contentType:contentType
                     validation:validation
                    description:description];
}

- (id)copyWithZone:(NSZone *)zone {
    return [CSCapOutput outputWithType:self.type
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
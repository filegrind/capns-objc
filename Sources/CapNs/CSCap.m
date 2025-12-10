//
//  CSCap.m
//  Formal cap implementation
//

#import "CSCap.h"

@implementation CSCap

+ (instancetype)capWithDictionary:(NSDictionary *)dictionary error:(NSError **)error {
    // Required fields
    id urnField = dictionary[@"urn"];
    NSString *command = dictionary[@"command"];
    NSString *title = dictionary[@"title"];
    
    if (!urnField || !command || !title) {
        if (error) {
            *error = [NSError errorWithDomain:@"CSCapError"
                                         code:1001
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing required cap fields: urn, command, or title"}];
        }
        return nil;
    }
    
    // Parse cap URN - handle both string and object formats
    NSError *keyError;
    CSCapUrn *capUrn = nil;
    
    if ([urnField isKindOfClass:[NSString class]]) {
        // Standard string format
        capUrn = [CSCapUrn fromString:(NSString *)urnField error:&keyError];
    } else if ([urnField isKindOfClass:[NSDictionary class]]) {
        // Registry object format with tags
        NSDictionary *urnDict = (NSDictionary *)urnField;
        NSDictionary *tags = urnDict[@"tags"];
        
        if ([tags isKindOfClass:[NSDictionary class]]) {
            CSCapUrnBuilder *builder = [CSCapUrnBuilder new];
            for (NSString *key in tags) {
                NSString *value = tags[key];
                if ([value isKindOfClass:[NSString class]]) {
                    builder = [builder tag:key value:value];
                }
            }
            capUrn = [builder build:&keyError];
        } else {
            if (error) {
                *error = [NSError errorWithDomain:@"CSCapError"
                                             code:1002
                                         userInfo:@{NSLocalizedDescriptionKey: @"Invalid URN object format - missing or invalid tags"}];
            }
            return nil;
        }
    } else {
        if (error) {
            *error = [NSError errorWithDomain:@"CSCapError"
                                         code:1003
                                     userInfo:@{NSLocalizedDescriptionKey: @"URN must be string or object"}];
        }
        return nil;
    }
    
    if (!capUrn) {
        if (error) {
            *error = keyError;
        }
        return nil;
    }
    
    // Optional fields
    NSString *capDescription = dictionary[@"cap_description"];
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
    
    return [self capWithUrn:capUrn
                          title:title
                        command:command
                    description:capDescription
                       metadata:metadata
                      arguments:arguments
                         output:output
                   acceptsStdin:acceptsStdin];
}

- (NSDictionary *)toDictionary {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    
    dict[@"urn"] = [self.capUrn toString];
    dict[@"title"] = self.title;
    dict[@"command"] = self.command;
    
    if (self.capDescription) {
        dict[@"cap_description"] = self.capDescription;
    }
    
    // Always include metadata (empty or populated)
    dict[@"metadata"] = self.metadata ?: @{};
    
    if (self.arguments && !self.arguments.isEmpty) {
        dict[@"arguments"] = [self.arguments toDictionary];
    }
    
    if (self.output) {
        dict[@"output"] = [self.output toDictionary];
    }
    
    dict[@"accepts_stdin"] = @(self.acceptsStdin);
    
    return [dict copy];
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
    NSMutableString *desc = [NSMutableString stringWithFormat:@"CSCap(urn: %@, title: %@, command: %@", 
                            [self.capUrn toString], self.title, self.command];
    
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
           [self.title isEqualToString:other.title] &&
           [self.command isEqualToString:other.command] &&
           ((self.capDescription == nil && other.capDescription == nil) ||
            [self.capDescription isEqualToString:other.capDescription]) &&
           [self.metadata isEqualToDictionary:other.metadata];
}

- (NSUInteger)hash {
    return [self.capUrn hash] ^ [self.title hash] ^ [self.command hash] ^ [self.metadata hash];
}

- (id)copyWithZone:(NSZone *)zone {
    // Fail hard if required fields are nil - this should never happen in a properly constructed cap
    if (!self.command || !self.title) {
        return nil;
    }
    return [CSCap capWithUrn:self.capUrn
                       title:self.title
                     command:self.command
                 description:self.capDescription 
                    metadata:self.metadata
                   arguments:self.arguments
                      output:self.output
                acceptsStdin:self.acceptsStdin];
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.capUrn forKey:@"capUrn"];
    [coder encodeObject:self.title forKey:@"title"];
    [coder encodeObject:self.command forKey:@"command"];
    [coder encodeObject:self.capDescription forKey:@"capDescription"];
    [coder encodeObject:self.metadata forKey:@"metadata"];
    [coder encodeObject:self.arguments forKey:@"arguments"];
    [coder encodeObject:self.output forKey:@"output"];
    [coder encodeBool:self.acceptsStdin forKey:@"acceptsStdin"];
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    CSCapUrn *capUrn = [coder decodeObjectOfClass:[CSCapUrn class] forKey:@"capUrn"];
    NSString *title = [coder decodeObjectOfClass:[NSString class] forKey:@"title"];
    NSString *command = [coder decodeObjectOfClass:[NSString class] forKey:@"command"];
    NSString *description = [coder decodeObjectOfClass:[NSString class] forKey:@"capDescription"];
    NSDictionary *metadata = [coder decodeObjectOfClass:[NSDictionary class] forKey:@"metadata"];
    CSCapArguments *arguments = [coder decodeObjectOfClass:[CSCapArguments class] forKey:@"arguments"];
    CSCapOutput *output = [coder decodeObjectOfClass:[CSCapOutput class] forKey:@"output"];
    BOOL acceptsStdin = [coder decodeBoolForKey:@"acceptsStdin"];
    
    // Fail hard if required fields are missing
    if (!capUrn || !title || !command || !metadata) {
        return nil;
    }
    
    return [CSCap capWithUrn:capUrn
                       title:title
                     command:command
                 description:description 
                    metadata:metadata
                   arguments:arguments ?: [CSCapArguments arguments]
                      output:output
                acceptsStdin:acceptsStdin];
}

- (instancetype)initWithUrn:(CSCapUrn *)capUrn
					  title:(NSString *)title
					command:(NSString *)command {
	self = [super init];
	if (self) {
		_capUrn = [capUrn copy];
		_title = [title copy];
		_command = [command copy];
		_metadata = @{};
		_arguments = [CSCapArguments arguments];
		_acceptsStdin = NO;
	}
	return self;
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

#pragma mark - Missing Methods


+ (instancetype)capWithUrn:(CSCapUrn *)capUrn
                     title:(NSString *)title
                   command:(NSString *)command {
    return [self capWithUrn:capUrn
                      title:title
                    command:command
                description:nil
                   metadata:@{}
                  arguments:[CSCapArguments arguments]
                     output:nil
               acceptsStdin:NO];
}

+ (instancetype)capWithUrn:(CSCapUrn *)capUrn
                     title:(NSString *)title
                   command:(NSString *)command
               description:(nullable NSString *)description
                  metadata:(NSDictionary<NSString *, NSString *> *)metadata
                 arguments:(CSCapArguments *)arguments
                    output:(nullable CSCapOutput *)output
              acceptsStdin:(BOOL)acceptsStdin {
    CSCap *cap = [[CSCap alloc] init];
    cap->_capUrn = [capUrn copy];
    cap->_title = [title copy];
    cap->_command = [command copy];
    cap->_capDescription = [description copy];
    // Fail hard if required fields are nil
    if (!title || !metadata || !arguments) {
        return nil;
    }
    cap->_metadata = [metadata copy];
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

- (NSDictionary *)toDictionary {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    
    if (self.min) {
        dict[@"min"] = self.min;
    }
    
    if (self.max) {
        dict[@"max"] = self.max;
    }
    
    if (self.minLength) {
        dict[@"min_length"] = self.minLength;
    }
    
    if (self.maxLength) {
        dict[@"max_length"] = self.maxLength;
    }
    
    if (self.pattern) {
        dict[@"pattern"] = self.pattern;
    }
    
    if (self.allowedValues && self.allowedValues.count > 0) {
        dict[@"allowed_values"] = self.allowedValues;
    }
    
    return [dict copy];
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

@end

#pragma mark - CSCapArgument Implementation

@implementation CSCapArgument

+ (instancetype)argumentWithName:(NSString *)name
                         argType:(CSArgumentType)argType
                   argDescription:(NSString *)argDescription
                         cliFlag:(NSString *)cliFlag
                        position:(nullable NSNumber *)position
                      validation:(nullable CSArgumentValidation *)validation
                    defaultValue:(nullable id)defaultValue {
    CSCapArgument *argument = [[CSCapArgument alloc] init];
    argument->_name = [name copy];
    argument->_argType = argType;
    argument->_argDescription = [argDescription copy];
    argument->_cliFlag = [cliFlag copy];
    argument->_position = position;
    argument->_validation = validation;
    argument->_defaultValue = defaultValue;
    argument->_schemaRef = nil;
    argument->_schema = nil;
    return argument;
}

+ (instancetype)argumentWithName:(NSString *)name
                         argType:(CSArgumentType)argType
                   argDescription:(NSString *)argDescription
                         cliFlag:(NSString *)cliFlag
                          schema:(NSDictionary *)schema {
    CSCapArgument *argument = [[CSCapArgument alloc] init];
    argument->_name = [name copy];
    argument->_argType = argType;
    argument->_argDescription = [argDescription copy];
    argument->_cliFlag = [cliFlag copy];
    argument->_position = nil;
    argument->_validation = nil;
    argument->_defaultValue = nil;
    argument->_schemaRef = nil;
    argument->_schema = [schema copy];
    return argument;
}

+ (instancetype)argumentWithName:(NSString *)name
                         argType:(CSArgumentType)argType
                   argDescription:(NSString *)argDescription
                         cliFlag:(NSString *)cliFlag
                       schemaRef:(NSString *)schemaRef {
    CSCapArgument *argument = [[CSCapArgument alloc] init];
    argument->_name = [name copy];
    argument->_argType = argType;
    argument->_argDescription = [argDescription copy];
    argument->_cliFlag = [cliFlag copy];
    argument->_position = nil;
    argument->_validation = nil;
    argument->_defaultValue = nil;
    argument->_schemaRef = [schemaRef copy];
    argument->_schema = nil;
    return argument;
}

+ (instancetype)argumentWithDictionary:(NSDictionary *)dictionary error:(NSError **)error {
    NSString *name = dictionary[@"name"];
    NSString *typeString = dictionary[@"arg_type"];
    NSString *argDescription = dictionary[@"arg_description"];
    NSString *cliFlag = dictionary[@"cli_flag"];
    NSNumber *position = dictionary[@"position"];
    id defaultValue = dictionary[@"default_value"];
    NSString *schemaRef = dictionary[@"schema_ref"];
    NSDictionary *schema = dictionary[@"schema"];
    
    if (!name || !typeString || !argDescription || !cliFlag) {
        if (error) {
            *error = [NSError errorWithDomain:@"CSCapArgumentError"
                                         code:1002
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing required argument fields: name, arg_type, arg_description, or cli_flag"}];
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
    
    // Create argument with all fields
    CSCapArgument *argument = [[CSCapArgument alloc] init];
    argument->_name = [name copy];
    argument->_argType = type;
    argument->_argDescription = [argDescription copy];
    argument->_cliFlag = [cliFlag copy];
    argument->_position = position;
    argument->_validation = validation;
    argument->_defaultValue = defaultValue;
    argument->_schemaRef = [schemaRef copy];
    argument->_schema = [schema copy];
    
    return argument;
}

- (id)copyWithZone:(NSZone *)zone {
    CSCapArgument *copy = [[CSCapArgument alloc] init];
    copy->_name = [self.name copy];
    copy->_argType = self.argType;
    copy->_argDescription = [self.argDescription copy];
    copy->_cliFlag = [self.cliFlag copy];
    copy->_position = self.position;
    copy->_validation = [self.validation copy];
    copy->_defaultValue = self.defaultValue;
    copy->_schemaRef = [self.schemaRef copy];
    copy->_schema = [self.schema copy];
    return copy;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.name forKey:@"name"];
    [coder encodeInteger:self.argType forKey:@"argType"];
    [coder encodeObject:self.argDescription forKey:@"argDescription"];
    [coder encodeObject:self.cliFlag forKey:@"cli_flag"];
    [coder encodeObject:self.position forKey:@"position"];
    [coder encodeObject:self.validation forKey:@"validation"];
    [coder encodeObject:self.defaultValue forKey:@"defaultValue"];
    [coder encodeObject:self.schemaRef forKey:@"schemaRef"];
    [coder encodeObject:self.schema forKey:@"schema"];
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    NSString *name = [coder decodeObjectOfClass:[NSString class] forKey:@"name"];
    CSArgumentType argType = (CSArgumentType)[coder decodeIntegerForKey:@"argType"];
    NSString *argDescription = [coder decodeObjectOfClass:[NSString class] forKey:@"argDescription"];
    
    if (!name || !argDescription) return nil;
    
    self = [super init];
    if (self) {
        _name = name;
        _argType = argType;
        _argDescription = argDescription;
        _cliFlag = [coder decodeObjectOfClass:[NSString class] forKey:@"cli_flag"];
        _position = [coder decodeObjectOfClass:[NSNumber class] forKey:@"position"];
        _validation = [coder decodeObjectOfClass:[CSArgumentValidation class] forKey:@"validation"];
        _defaultValue = [coder decodeObjectForKey:@"defaultValue"];
        _schemaRef = [coder decodeObjectOfClass:[NSString class] forKey:@"schemaRef"];
        _schema = [coder decodeObjectOfClass:[NSDictionary class] forKey:@"schema"];
    }
    return self;
}

- (NSDictionary *)toDictionary {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    
    dict[@"name"] = self.name;
    dict[@"arg_type"] = [self argTypeString];
    dict[@"arg_description"] = self.argDescription;
    dict[@"cli_flag"] = self.cliFlag;
    
    if (self.position) {
        dict[@"position"] = self.position;
    }
    
    if (self.defaultValue) {
        dict[@"default_value"] = self.defaultValue;
    }
    
    // Add validation if present
    if (self.validation) {
        dict[@"validation"] = [self.validation toDictionary];
    }
    
    // Add schema fields
    if (self.schemaRef) {
        dict[@"schema_ref"] = self.schemaRef;
    }
    
    if (self.schema) {
        dict[@"schema"] = self.schema;
    }
    
    return [dict copy];
}

- (NSString *)argTypeString {
    switch (self.argType) {
        case CSArgumentTypeString: return @"string";
        case CSArgumentTypeInteger: return @"integer";
        case CSArgumentTypeNumber: return @"number";
        case CSArgumentTypeBoolean: return @"boolean";
        case CSArgumentTypeArray: return @"array";
        case CSArgumentTypeObject: return @"object";
        case CSArgumentTypeBinary: return @"binary";
        default: return @"string";
    }
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

@end

#pragma mark - CSCapOutput Implementation

@implementation CSCapOutput

+ (instancetype)outputWithType:(CSOutputType)outputType
                     schemaRef:(nullable NSString *)schemaRef
                   contentType:(nullable NSString *)contentType
                    validation:(nullable CSArgumentValidation *)validation
           outputDescription:(NSString *)outputDescription {
    CSCapOutput *output = [[CSCapOutput alloc] init];
    output->_outputType = outputType;
    output->_schemaRef = [schemaRef copy];
    output->_schema = nil;
    output->_contentType = [contentType copy];
    output->_validation = validation;
    output->_outputDescription = [outputDescription copy];
    return output;
}

+ (instancetype)outputWithType:(CSOutputType)outputType
                        schema:(NSDictionary *)schema
               outputDescription:(NSString *)outputDescription {
    CSCapOutput *output = [[CSCapOutput alloc] init];
    output->_outputType = outputType;
    output->_schemaRef = nil;
    output->_schema = [schema copy];
    output->_contentType = nil;
    output->_validation = nil;
    output->_outputDescription = [outputDescription copy];
    return output;
}

+ (instancetype)outputWithType:(CSOutputType)outputType
                     schemaRef:(NSString *)schemaRef
               outputDescription:(NSString *)outputDescription {
    CSCapOutput *output = [[CSCapOutput alloc] init];
    output->_outputType = outputType;
    output->_schemaRef = [schemaRef copy];
    output->_schema = nil;
    output->_contentType = nil;
    output->_validation = nil;
    output->_outputDescription = [outputDescription copy];
    return output;
}

+ (instancetype)outputWithDictionary:(NSDictionary *)dictionary error:(NSError **)error {
    NSString *typeString = dictionary[@"output_type"];
    NSString *schemaRef = dictionary[@"schema_ref"];
    NSDictionary *schema = dictionary[@"schema"];
    NSString *contentType = dictionary[@"content_type"];
    NSString *outputDescription = dictionary[@"output_description"];
    
    if (!typeString || !outputDescription) {
        if (error) {
            *error = [NSError errorWithDomain:@"CSCapOutputError"
                                         code:1004
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing required output fields: output_type or output_description"}];
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
    
    // Create output with all fields
    CSCapOutput *output = [[CSCapOutput alloc] init];
    output->_outputType = type;
    output->_schemaRef = [schemaRef copy];
    output->_schema = [schema copy];
    output->_contentType = [contentType copy];
    output->_validation = validation;
    output->_outputDescription = [outputDescription copy];
    
    return output;
}

- (id)copyWithZone:(NSZone *)zone {
    CSCapOutput *copy = [[CSCapOutput alloc] init];
    copy->_outputType = self.outputType;
    copy->_schemaRef = [self.schemaRef copy];
    copy->_schema = [self.schema copy];
    copy->_contentType = [self.contentType copy];
    copy->_validation = [self.validation copy];
    copy->_outputDescription = [self.outputDescription copy];
    return copy;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeInteger:self.outputType forKey:@"outputType"];
    [coder encodeObject:self.schemaRef forKey:@"schemaRef"];
    [coder encodeObject:self.schema forKey:@"schema"];
    [coder encodeObject:self.contentType forKey:@"contentType"];
    [coder encodeObject:self.validation forKey:@"validation"];
    [coder encodeObject:self.outputDescription forKey:@"outputDescription"];
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    NSString *outputDescription = [coder decodeObjectOfClass:[NSString class] forKey:@"outputDescription"];
    if (!outputDescription) return nil;
    
    self = [super init];
    if (self) {
        _outputType = (CSOutputType)[coder decodeIntegerForKey:@"outputType"];
        _schemaRef = [coder decodeObjectOfClass:[NSString class] forKey:@"schemaRef"];
        _schema = [coder decodeObjectOfClass:[NSDictionary class] forKey:@"schema"];
        _contentType = [coder decodeObjectOfClass:[NSString class] forKey:@"contentType"];
        _validation = [coder decodeObjectOfClass:[CSArgumentValidation class] forKey:@"validation"];
        _outputDescription = outputDescription;
    }
    return self;
}

- (NSDictionary *)toDictionary {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    
    dict[@"output_type"] = [self outputTypeString];
    dict[@"output_description"] = self.outputDescription;
    
    if (self.schemaRef) {
        dict[@"schema_ref"] = self.schemaRef;
    }
    
    if (self.schema) {
        dict[@"schema"] = self.schema;
    }
    
    if (self.contentType) {
        dict[@"content_type"] = self.contentType;
    }
    
    if (self.validation) {
        dict[@"validation"] = [self.validation toDictionary];
    }
    
    return [dict copy];
}

- (NSString *)outputTypeString {
    switch (self.outputType) {
        case CSOutputTypeString: return @"string";
        case CSOutputTypeInteger: return @"integer";
        case CSOutputTypeNumber: return @"number";
        case CSOutputTypeBoolean: return @"boolean";
        case CSOutputTypeArray: return @"array";
        case CSOutputTypeObject: return @"object";
        case CSOutputTypeBinary: return @"binary";
        default: return @"string";
    }
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

@end
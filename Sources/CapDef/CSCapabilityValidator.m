//
//  CSCapabilityValidator.m
//  Capability schema validation for plugin interactions
//
//  This provides strict validation of inputs and outputs against
//  advertised capability schemas from plugins.
//

#import "CSCapabilityValidator.h"

// Error domain
NSErrorDomain const CSValidationErrorDomain = @"CSValidationErrorDomain";

// Error user info keys
NSString * const CSValidationErrorCapabilityIdKey = @"CSValidationErrorCapabilityIdKey";
NSString * const CSValidationErrorArgumentNameKey = @"CSValidationErrorArgumentNameKey";
NSString * const CSValidationErrorValidationRuleKey = @"CSValidationErrorValidationRuleKey";
NSString * const CSValidationErrorActualValueKey = @"CSValidationErrorActualValueKey";
NSString * const CSValidationErrorActualTypeKey = @"CSValidationErrorActualTypeKey";
NSString * const CSValidationErrorExpectedTypeKey = @"CSValidationErrorExpectedTypeKey";

@implementation CSValidationError

@synthesize validationType = _validationType;
@synthesize capabilityId = _capabilityId;
@synthesize argumentName = _argumentName;
@synthesize validationRule = _validationRule;
@synthesize actualValue = _actualValue;
@synthesize actualType = _actualType;
@synthesize expectedType = _expectedType;

- (instancetype)initWithType:(CSValidationErrorType)type 
                capabilityId:(NSString *)capabilityId 
                 description:(NSString *)description 
                    userInfo:(NSDictionary *)userInfo {
    self = [super initWithDomain:CSValidationErrorDomain code:type userInfo:userInfo];
    if (self) {
        _validationType = type;
        _capabilityId = [capabilityId copy];
        _argumentName = [userInfo[CSValidationErrorArgumentNameKey] copy];
        _validationRule = [userInfo[CSValidationErrorValidationRuleKey] copy];
        _actualValue = userInfo[CSValidationErrorActualValueKey];
        _actualType = [userInfo[CSValidationErrorActualTypeKey] copy];
        _expectedType = [userInfo[CSValidationErrorExpectedTypeKey] copy];
    }
    return self;
}

+ (NSString *)argumentTypeToString:(CSArgumentType)type {
    switch (type) {
        case CSArgumentTypeString: return @"string";
        case CSArgumentTypeInteger: return @"integer";
        case CSArgumentTypeNumber: return @"number";
        case CSArgumentTypeBoolean: return @"boolean";
        case CSArgumentTypeArray: return @"array";
        case CSArgumentTypeObject: return @"object";
        case CSArgumentTypeBinary: return @"binary";
        default: return @"unknown";
    }
}

+ (NSString *)outputTypeToString:(CSOutputType)type {
    switch (type) {
        case CSOutputTypeString: return @"string";
        case CSOutputTypeInteger: return @"integer";
        case CSOutputTypeNumber: return @"number";
        case CSOutputTypeBoolean: return @"boolean";
        case CSOutputTypeArray: return @"array";
        case CSOutputTypeObject: return @"object";
        case CSOutputTypeBinary: return @"binary";
        default: return @"unknown";
    }
}

+ (instancetype)unknownCapabilityError:(NSString *)capabilityId {
    NSString *description = [NSString stringWithFormat:@"Unknown capability '%@' - capability not registered or advertised", capabilityId];
    return [[self alloc] initWithType:CSValidationErrorTypeUnknownCapability 
                         capabilityId:capabilityId 
                          description:description 
                             userInfo:@{NSLocalizedDescriptionKey: description}];
}

+ (instancetype)missingRequiredArgumentError:(NSString *)capabilityId argumentName:(NSString *)argumentName {
    NSString *description = [NSString stringWithFormat:@"Capability '%@' requires argument '%@' but it was not provided", capabilityId, argumentName];
    return [[self alloc] initWithType:CSValidationErrorTypeMissingRequiredArgument 
                         capabilityId:capabilityId 
                          description:description 
                             userInfo:@{
                                 NSLocalizedDescriptionKey: description,
                                 CSValidationErrorArgumentNameKey: argumentName
                             }];
}

+ (instancetype)invalidArgumentTypeError:(NSString *)capabilityId 
                            argumentName:(NSString *)argumentName 
                            expectedType:(CSArgumentType)expectedType 
                              actualType:(NSString *)actualType 
                             actualValue:(id)actualValue {
    NSString *expectedTypeName = [self argumentTypeToString:expectedType];
    NSString *description = [NSString stringWithFormat:@"Capability '%@' argument '%@' expects type '%@' but received '%@' with value: %@", 
                            capabilityId, argumentName, expectedTypeName, actualType, actualValue];
    return [[self alloc] initWithType:CSValidationErrorTypeInvalidArgumentType 
                         capabilityId:capabilityId 
                          description:description 
                             userInfo:@{
                                 NSLocalizedDescriptionKey: description,
                                 CSValidationErrorArgumentNameKey: argumentName,
                                 CSValidationErrorExpectedTypeKey: expectedTypeName,
                                 CSValidationErrorActualTypeKey: actualType,
                                 CSValidationErrorActualValueKey: actualValue ?: [NSNull null]
                             }];
}

+ (instancetype)argumentValidationFailedError:(NSString *)capabilityId 
                                 argumentName:(NSString *)argumentName 
                               validationRule:(NSString *)validationRule 
                                  actualValue:(id)actualValue {
    NSString *description = [NSString stringWithFormat:@"Capability '%@' argument '%@' failed validation rule '%@' with value: %@", 
                            capabilityId, argumentName, validationRule, actualValue];
    return [[self alloc] initWithType:CSValidationErrorTypeArgumentValidationFailed 
                         capabilityId:capabilityId 
                          description:description 
                             userInfo:@{
                                 NSLocalizedDescriptionKey: description,
                                 CSValidationErrorArgumentNameKey: argumentName,
                                 CSValidationErrorValidationRuleKey: validationRule,
                                 CSValidationErrorActualValueKey: actualValue ?: [NSNull null]
                             }];
}

+ (instancetype)invalidOutputTypeError:(NSString *)capabilityId 
                          expectedType:(CSOutputType)expectedType 
                            actualType:(NSString *)actualType 
                           actualValue:(id)actualValue {
    NSString *expectedTypeName = [self outputTypeToString:expectedType];
    NSString *description = [NSString stringWithFormat:@"Capability '%@' output expects type '%@' but received '%@' with value: %@", 
                            capabilityId, expectedTypeName, actualType, actualValue];
    return [[self alloc] initWithType:CSValidationErrorTypeInvalidOutputType 
                         capabilityId:capabilityId 
                          description:description 
                             userInfo:@{
                                 NSLocalizedDescriptionKey: description,
                                 CSValidationErrorExpectedTypeKey: expectedTypeName,
                                 CSValidationErrorActualTypeKey: actualType,
                                 CSValidationErrorActualValueKey: actualValue ?: [NSNull null]
                             }];
}

+ (instancetype)outputValidationFailedError:(NSString *)capabilityId 
                             validationRule:(NSString *)validationRule 
                                actualValue:(id)actualValue {
    NSString *description = [NSString stringWithFormat:@"Capability '%@' output failed validation rule '%@' with value: %@", 
                            capabilityId, validationRule, actualValue];
    return [[self alloc] initWithType:CSValidationErrorTypeOutputValidationFailed 
                         capabilityId:capabilityId 
                          description:description 
                             userInfo:@{
                                 NSLocalizedDescriptionKey: description,
                                 CSValidationErrorValidationRuleKey: validationRule,
                                 CSValidationErrorActualValueKey: actualValue ?: [NSNull null]
                             }];
}

+ (instancetype)invalidCapabilitySchemaError:(NSString *)capabilityId issue:(NSString *)issue {
    NSString *description = [NSString stringWithFormat:@"Capability '%@' has invalid schema: %@", capabilityId, issue];
    return [[self alloc] initWithType:CSValidationErrorTypeInvalidCapabilitySchema 
                         capabilityId:capabilityId 
                          description:description 
                             userInfo:@{NSLocalizedDescriptionKey: description}];
}

+ (instancetype)tooManyArgumentsError:(NSString *)capabilityId 
                          maxExpected:(NSInteger)maxExpected 
                          actualCount:(NSInteger)actualCount {
    NSString *description = [NSString stringWithFormat:@"Capability '%@' expects at most %ld arguments but received %ld", 
                            capabilityId, (long)maxExpected, (long)actualCount];
    return [[self alloc] initWithType:CSValidationErrorTypeTooManyArguments 
                         capabilityId:capabilityId 
                          description:description 
                             userInfo:@{NSLocalizedDescriptionKey: description}];
}

+ (instancetype)jsonParseError:(NSString *)capabilityId error:(NSString *)error {
    NSString *description = [NSString stringWithFormat:@"Capability '%@' JSON parsing failed: %@", capabilityId, error];
    return [[self alloc] initWithType:CSValidationErrorTypeJSONParseError 
                         capabilityId:capabilityId 
                          description:description 
                             userInfo:@{NSLocalizedDescriptionKey: description}];
}

@end

// Internal helper functions
@interface CSInputValidator ()
+ (NSString *)getJsonTypeName:(id)value;
+ (NSNumber *)getNumericValue:(id)value;
+ (BOOL)validateSingleArgument:(CSCapabilityArgument *)argDef 
                         value:(id)value 
                    capability:(CSCapability *)capability 
                         error:(NSError **)error;
+ (BOOL)validateArgumentType:(CSCapabilityArgument *)argDef 
                       value:(id)value 
                  capability:(CSCapability *)capability 
                       error:(NSError **)error;
+ (BOOL)validateArgumentRules:(CSCapabilityArgument *)argDef 
                        value:(id)value 
                   capability:(CSCapability *)capability 
                        error:(NSError **)error;
@end

@implementation CSInputValidator

+ (BOOL)validateArguments:(NSArray *)arguments 
               capability:(CSCapability *)capability 
                    error:(NSError **)error {
    NSString *capabilityId = [capability idString];
    CSCapabilityArguments *args = [capability getArguments];
    
    // Check if too many arguments provided
    NSInteger maxArgs = args.required.count + args.optional.count;
    if (arguments.count > maxArgs) {
        if (error) {
            *error = [CSValidationError tooManyArgumentsError:capabilityId 
                                                  maxExpected:maxArgs 
                                                  actualCount:arguments.count];
        }
        return NO;
    }
    
    // Validate required arguments
    for (NSInteger index = 0; index < args.required.count; index++) {
        if (index >= arguments.count) {
            if (error) {
                CSCapabilityArgument *reqArg = args.required[index];
                *error = [CSValidationError missingRequiredArgumentError:capabilityId 
                                                            argumentName:reqArg.name];
            }
            return NO;
        }
        
        CSCapabilityArgument *reqArg = args.required[index];
        if (![self validateSingleArgument:reqArg 
                                    value:arguments[index] 
                               capability:capability 
                                    error:error]) {
            return NO;
        }
    }
    
    // Validate optional arguments if provided
    NSInteger requiredCount = args.required.count;
    for (NSInteger index = 0; index < args.optional.count; index++) {
        NSInteger argIndex = requiredCount + index;
        if (argIndex < arguments.count) {
            CSCapabilityArgument *optArg = args.optional[index];
            if (![self validateSingleArgument:optArg 
                                        value:arguments[argIndex] 
                                   capability:capability 
                                        error:error]) {
                return NO;
            }
        }
    }
    
    return YES;
}

+ (BOOL)validateSingleArgument:(CSCapabilityArgument *)argDef 
                         value:(id)value 
                    capability:(CSCapability *)capability 
                         error:(NSError **)error {
    // Type validation
    if (![self validateArgumentType:argDef value:value capability:capability error:error]) {
        return NO;
    }
    
    // Validation rules
    if (![self validateArgumentRules:argDef value:value capability:capability error:error]) {
        return NO;
    }
    
    return YES;
}

+ (BOOL)validateArgumentType:(CSCapabilityArgument *)argDef 
                       value:(id)value 
                  capability:(CSCapability *)capability 
                       error:(NSError **)error {
    NSString *capabilityId = [capability idString];
    NSString *actualType = [self getJsonTypeName:value];
    
    BOOL typeMatches = NO;
    switch (argDef.type) {
        case CSArgumentTypeString:
            typeMatches = [value isKindOfClass:[NSString class]];
            break;
        case CSArgumentTypeInteger:
            if ([value isKindOfClass:[NSNumber class]]) {
                NSNumber *num = (NSNumber *)value;
                typeMatches = !CFNumberIsFloatType((__bridge CFNumberRef)num) && 
                              CFGetTypeID((__bridge CFTypeRef)num) != CFBooleanGetTypeID();
            }
            break;
        case CSArgumentTypeNumber:
            typeMatches = [value isKindOfClass:[NSNumber class]];
            break;
        case CSArgumentTypeBoolean:
            typeMatches = [value isKindOfClass:[NSNumber class]] && 
                          CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID();
            break;
        case CSArgumentTypeArray:
            typeMatches = [value isKindOfClass:[NSArray class]];
            break;
        case CSArgumentTypeObject:
            typeMatches = [value isKindOfClass:[NSDictionary class]];
            break;
        case CSArgumentTypeBinary:
            typeMatches = [value isKindOfClass:[NSString class]]; // Binary as base64 string
            break;
    }
    
    if (!typeMatches) {
        if (error) {
            *error = [CSValidationError invalidArgumentTypeError:capabilityId 
                                                    argumentName:argDef.name 
                                                    expectedType:argDef.type 
                                                      actualType:actualType 
                                                     actualValue:value];
        }
        return NO;
    }
    
    return YES;
}

+ (BOOL)validateArgumentRules:(CSCapabilityArgument *)argDef 
                        value:(id)value 
                   capability:(CSCapability *)capability 
                        error:(NSError **)error {
    NSString *capabilityId = [capability idString];
    CSArgumentValidation *validation = argDef.validation;
    
    if (!validation) {
        return YES;
    }
    
    // Numeric validation
    if (validation.min) {
        NSNumber *numValue = [self getNumericValue:value];
        if (numValue && [numValue doubleValue] < [validation.min doubleValue]) {
            if (error) {
                NSString *rule = [NSString stringWithFormat:@"minimum value %@", validation.min];
                *error = [CSValidationError argumentValidationFailedError:capabilityId 
                                                             argumentName:argDef.name 
                                                           validationRule:rule 
                                                              actualValue:value];
            }
            return NO;
        }
    }
    
    if (validation.max) {
        NSNumber *numValue = [self getNumericValue:value];
        if (numValue && [numValue doubleValue] > [validation.max doubleValue]) {
            if (error) {
                NSString *rule = [NSString stringWithFormat:@"maximum value %@", validation.max];
                *error = [CSValidationError argumentValidationFailedError:capabilityId 
                                                             argumentName:argDef.name 
                                                           validationRule:rule 
                                                              actualValue:value];
            }
            return NO;
        }
    }
    
    // String length validation
    if (validation.minLength && [value isKindOfClass:[NSString class]]) {
        NSString *stringValue = (NSString *)value;
        if (stringValue.length < [validation.minLength integerValue]) {
            if (error) {
                NSString *rule = [NSString stringWithFormat:@"minimum length %@", validation.minLength];
                *error = [CSValidationError argumentValidationFailedError:capabilityId 
                                                             argumentName:argDef.name 
                                                           validationRule:rule 
                                                              actualValue:value];
            }
            return NO;
        }
    }
    
    if (validation.maxLength && [value isKindOfClass:[NSString class]]) {
        NSString *stringValue = (NSString *)value;
        if (stringValue.length > [validation.maxLength integerValue]) {
            if (error) {
                NSString *rule = [NSString stringWithFormat:@"maximum length %@", validation.maxLength];
                *error = [CSValidationError argumentValidationFailedError:capabilityId 
                                                             argumentName:argDef.name 
                                                           validationRule:rule 
                                                              actualValue:value];
            }
            return NO;
        }
    }
    
    // Pattern validation
    if (validation.pattern && [value isKindOfClass:[NSString class]]) {
        NSString *stringValue = (NSString *)value;
        NSError *regexError = nil;
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:validation.pattern 
                                                                               options:0 
                                                                                 error:&regexError];
        if (regex) {
            NSRange range = NSMakeRange(0, stringValue.length);
            NSTextCheckingResult *match = [regex firstMatchInString:stringValue options:0 range:range];
            if (!match) {
                if (error) {
                    NSString *rule = [NSString stringWithFormat:@"pattern '%@'", validation.pattern];
                    *error = [CSValidationError argumentValidationFailedError:capabilityId 
                                                                 argumentName:argDef.name 
                                                               validationRule:rule 
                                                                  actualValue:value];
                }
                return NO;
            }
        }
        // Invalid regex pattern in schema - silently ignore like Rust reference
    }
    
    // Allowed values validation
    if (validation.allowedValues.count > 0 && [value isKindOfClass:[NSString class]]) {
        NSString *stringValue = (NSString *)value;
        if (![validation.allowedValues containsObject:stringValue]) {
            if (error) {
                NSString *rule = [NSString stringWithFormat:@"allowed values: %@", validation.allowedValues];
                *error = [CSValidationError argumentValidationFailedError:capabilityId 
                                                             argumentName:argDef.name 
                                                           validationRule:rule 
                                                              actualValue:value];
            }
            return NO;
        }
    }
    
    return YES;
}

+ (NSString *)getJsonTypeName:(id)value {
    if ([value isKindOfClass:[NSNull class]]) {
        return @"null";
    } else if ([value isKindOfClass:[NSNumber class]]) {
        NSNumber *num = (NSNumber *)value;
        if (CFGetTypeID((__bridge CFTypeRef)num) == CFBooleanGetTypeID()) {
            return @"boolean";
        } else if (!CFNumberIsFloatType((__bridge CFNumberRef)num)) {
            return @"integer";
        } else {
            return @"number";
        }
    } else if ([value isKindOfClass:[NSString class]]) {
        return @"string";
    } else if ([value isKindOfClass:[NSArray class]]) {
        return @"array";
    } else if ([value isKindOfClass:[NSDictionary class]]) {
        return @"object";
    } else {
        return NSStringFromClass([value class]);
    }
}

+ (NSNumber *)getNumericValue:(id)value {
    if ([value isKindOfClass:[NSNumber class]]) {
        return (NSNumber *)value;
    }
    return nil;
}

@end

@interface CSOutputValidator ()
+ (BOOL)validateOutputType:(CSCapabilityOutput *)outputDef 
                     value:(id)value 
                capability:(CSCapability *)capability 
                     error:(NSError **)error;
+ (BOOL)validateOutputRules:(CSCapabilityOutput *)outputDef 
                      value:(id)value 
                 capability:(CSCapability *)capability 
                      error:(NSError **)error;
@end

@implementation CSOutputValidator

+ (BOOL)validateOutput:(id)output 
            capability:(CSCapability *)capability 
                 error:(NSError **)error {
    NSString *capabilityId = [capability idString];
    
    CSCapabilityOutput *outputDef = [capability getOutput];
    if (!outputDef) {
        if (error) {
            *error = [CSValidationError invalidCapabilitySchemaError:capabilityId 
                                                               issue:@"No output definition specified"];
        }
        return NO;
    }
    
    // Type validation
    if (![self validateOutputType:outputDef value:output capability:capability error:error]) {
        return NO;
    }
    
    // Validation rules
    if (![self validateOutputRules:outputDef value:output capability:capability error:error]) {
        return NO;
    }
    
    return YES;
}

+ (BOOL)validateOutputType:(CSCapabilityOutput *)outputDef 
                     value:(id)value 
                capability:(CSCapability *)capability 
                     error:(NSError **)error {
    NSString *capabilityId = [capability idString];
    NSString *actualType = [CSInputValidator getJsonTypeName:value];
    
    BOOL typeMatches = NO;
    switch (outputDef.type) {
        case CSOutputTypeString:
            typeMatches = [value isKindOfClass:[NSString class]];
            break;
        case CSOutputTypeInteger:
            if ([value isKindOfClass:[NSNumber class]]) {
                NSNumber *num = (NSNumber *)value;
                typeMatches = !CFNumberIsFloatType((__bridge CFNumberRef)num) && 
                              CFGetTypeID((__bridge CFTypeRef)num) != CFBooleanGetTypeID();
            }
            break;
        case CSOutputTypeNumber:
            typeMatches = [value isKindOfClass:[NSNumber class]];
            break;
        case CSOutputTypeBoolean:
            typeMatches = [value isKindOfClass:[NSNumber class]] && 
                          CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID();
            break;
        case CSOutputTypeArray:
            typeMatches = [value isKindOfClass:[NSArray class]];
            break;
        case CSOutputTypeObject:
            typeMatches = [value isKindOfClass:[NSDictionary class]];
            break;
        case CSOutputTypeBinary:
            typeMatches = [value isKindOfClass:[NSString class]]; // Binary as base64 string
            break;
    }
    
    if (!typeMatches) {
        if (error) {
            *error = [CSValidationError invalidOutputTypeError:capabilityId 
                                                  expectedType:outputDef.type 
                                                    actualType:actualType 
                                                   actualValue:value];
        }
        return NO;
    }
    
    return YES;
}

+ (BOOL)validateOutputRules:(CSCapabilityOutput *)outputDef 
                      value:(id)value 
                 capability:(CSCapability *)capability 
                      error:(NSError **)error {
    NSString *capabilityId = [capability idString];
    CSArgumentValidation *validation = outputDef.validation;
    
    if (!validation) {
        return YES;
    }
    
    // Apply same validation rules as arguments
    if (validation.min) {
        NSNumber *numValue = [CSInputValidator getNumericValue:value];
        if (numValue && [numValue doubleValue] < [validation.min doubleValue]) {
            if (error) {
                NSString *rule = [NSString stringWithFormat:@"minimum value %@", validation.min];
                *error = [CSValidationError outputValidationFailedError:capabilityId 
                                                         validationRule:rule 
                                                            actualValue:value];
            }
            return NO;
        }
    }
    
    if (validation.max) {
        NSNumber *numValue = [CSInputValidator getNumericValue:value];
        if (numValue && [numValue doubleValue] > [validation.max doubleValue]) {
            if (error) {
                NSString *rule = [NSString stringWithFormat:@"maximum value %@", validation.max];
                *error = [CSValidationError outputValidationFailedError:capabilityId 
                                                         validationRule:rule 
                                                            actualValue:value];
            }
            return NO;
        }
    }
    
    if (validation.minLength && [value isKindOfClass:[NSString class]]) {
        NSString *stringValue = (NSString *)value;
        if (stringValue.length < [validation.minLength integerValue]) {
            if (error) {
                NSString *rule = [NSString stringWithFormat:@"minimum length %@", validation.minLength];
                *error = [CSValidationError outputValidationFailedError:capabilityId 
                                                         validationRule:rule 
                                                            actualValue:value];
            }
            return NO;
        }
    }
    
    if (validation.maxLength && [value isKindOfClass:[NSString class]]) {
        NSString *stringValue = (NSString *)value;
        if (stringValue.length > [validation.maxLength integerValue]) {
            if (error) {
                NSString *rule = [NSString stringWithFormat:@"maximum length %@", validation.maxLength];
                *error = [CSValidationError outputValidationFailedError:capabilityId 
                                                         validationRule:rule 
                                                            actualValue:value];
            }
            return NO;
        }
    }
    
    if (validation.pattern && [value isKindOfClass:[NSString class]]) {
        NSString *stringValue = (NSString *)value;
        NSError *regexError = nil;
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:validation.pattern 
                                                                               options:0 
                                                                                 error:&regexError];
        if (regex) {
            NSRange range = NSMakeRange(0, stringValue.length);
            NSTextCheckingResult *match = [regex firstMatchInString:stringValue options:0 range:range];
            if (!match) {
                if (error) {
                    NSString *rule = [NSString stringWithFormat:@"pattern '%@'", validation.pattern];
                    *error = [CSValidationError outputValidationFailedError:capabilityId 
                                                             validationRule:rule 
                                                                actualValue:value];
                }
                return NO;
            }
        }
        // Invalid regex pattern in schema - silently ignore like Rust reference
    }
    
    if (validation.allowedValues.count > 0 && [value isKindOfClass:[NSString class]]) {
        NSString *stringValue = (NSString *)value;
        if (![validation.allowedValues containsObject:stringValue]) {
            if (error) {
                NSString *rule = [NSString stringWithFormat:@"allowed values: %@", validation.allowedValues];
                *error = [CSValidationError outputValidationFailedError:capabilityId 
                                                         validationRule:rule 
                                                            actualValue:value];
            }
            return NO;
        }
    }
    
    return YES;
}

@end

@implementation CSCapabilityValidator

+ (BOOL)validateCapability:(CSCapability *)capability 
                     error:(NSError **)error {
    NSString *capabilityId = [capability idString];
    CSCapabilityArguments *args = [capability getArguments];
    
    // Validate that required arguments don't have default values
    for (CSCapabilityArgument *arg in args.required) {
        if (arg.defaultValue) {
            if (error) {
                NSString *issue = [NSString stringWithFormat:@"Required argument '%@' cannot have a default value", arg.name];
                *error = [CSValidationError invalidCapabilitySchemaError:capabilityId issue:issue];
            }
            return NO;
        }
    }
    
    // Validate argument position uniqueness
    NSMutableSet<NSNumber *> *positions = [NSMutableSet set];
    NSArray<CSCapabilityArgument *> *allArgs = [args.required arrayByAddingObjectsFromArray:args.optional];
    for (CSCapabilityArgument *arg in allArgs) {
        if (arg.position) {
            if ([positions containsObject:arg.position]) {
                if (error) {
                    NSString *issue = [NSString stringWithFormat:@"Duplicate argument position %@ for argument '%@'", arg.position, arg.name];
                    *error = [CSValidationError invalidCapabilitySchemaError:capabilityId issue:issue];
                }
                return NO;
            }
            [positions addObject:arg.position];
        }
    }
    
    // Validate CLI flag uniqueness
    NSMutableSet<NSString *> *cliFlags = [NSMutableSet set];
    for (CSCapabilityArgument *arg in allArgs) {
        if (arg.cliFlag) {
            if ([cliFlags containsObject:arg.cliFlag]) {
                if (error) {
                    NSString *issue = [NSString stringWithFormat:@"Duplicate CLI flag '%@' for argument '%@'", arg.cliFlag, arg.name];
                    *error = [CSValidationError invalidCapabilitySchemaError:capabilityId issue:issue];
                }
                return NO;
            }
            [cliFlags addObject:arg.cliFlag];
        }
    }
    
    return YES;
}

@end

@implementation CSSchemaValidator {
    NSMutableDictionary<NSString *, CSCapability *> *_capabilities;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _capabilities = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)registerCapability:(CSCapability *)capability {
    NSString *capabilityId = [capability idString];
    _capabilities[capabilityId] = capability;
}

- (nullable CSCapability *)getCapability:(NSString *)capabilityId {
    return _capabilities[capabilityId];
}

- (BOOL)validateInputs:(NSArray *)arguments 
          capabilityId:(NSString *)capabilityId 
                 error:(NSError **)error {
    CSCapability *capability = [self getCapability:capabilityId];
    if (!capability) {
        if (error) {
            *error = [CSValidationError unknownCapabilityError:capabilityId];
        }
        return NO;
    }
    
    return [CSInputValidator validateArguments:arguments capability:capability error:error];
}

- (BOOL)validateOutput:(id)output 
          capabilityId:(NSString *)capabilityId 
                 error:(NSError **)error {
    CSCapability *capability = [self getCapability:capabilityId];
    if (!capability) {
        if (error) {
            *error = [CSValidationError unknownCapabilityError:capabilityId];
        }
        return NO;
    }
    
    return [CSOutputValidator validateOutput:output capability:capability error:error];
}

- (BOOL)validateBinaryOutput:(NSData *)outputData 
                capabilityId:(NSString *)capabilityId 
                       error:(NSError **)error {
    CSCapability *capability = [self getCapability:capabilityId];
    if (!capability) {
        if (error) {
            *error = [CSValidationError unknownCapabilityError:capabilityId];
        }
        return NO;
    }
    
    // For binary outputs, we primarily validate existence and basic constraints
    CSCapabilityOutput *output = [capability getOutput];
    if (!output) {
        // No output definition means any output is acceptable
        return YES;
    }
    
    // Verify output type is binary
    if (output.type != CSOutputTypeBinary) {
        if (error) {
            *error = [CSValidationError invalidOutputTypeError:capabilityId
                                                  expectedType:output.type
                                                    actualType:@"binary"
                                                   actualValue:outputData];
        }
        return NO;
    }
    
    // Validate binary data size constraints if defined
    CSArgumentValidation *validation = output.validation;
    if (validation && validation.min) {
        if (outputData.length < [validation.min integerValue]) {
            if (error) {
                NSString *rule = [NSString stringWithFormat:@"minimum size %@ bytes", validation.min];
                *error = [CSValidationError outputValidationFailedError:capabilityId
                                                         validationRule:rule
                                                            actualValue:@(outputData.length)];
            }
            return NO;
        }
    }
    
    if (validation && validation.max) {
        if (outputData.length > [validation.max integerValue]) {
            if (error) {
                NSString *rule = [NSString stringWithFormat:@"maximum size %@ bytes", validation.max];
                *error = [CSValidationError outputValidationFailedError:capabilityId
                                                         validationRule:rule
                                                            actualValue:@(outputData.length)];
            }
            return NO;
        }
    }
    
    return YES;
}

- (BOOL)validateCapabilitySchema:(CSCapability *)capability 
                           error:(NSError **)error {
    return [CSCapabilityValidator validateCapability:capability error:error];
}

@end
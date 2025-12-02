//
//  CSCapValidator.m
//  Cap schema validation for plugin interactions
//
//  This provides strict validation of inputs and outputs against
//  advertised cap schemas from plugins.
//

#import "CSCapValidator.h"
#import "CSSchemaValidator.h"

// Error domain
NSErrorDomain const CSValidationErrorDomain = @"CSValidationErrorDomain";

// Error user info keys
NSString * const CSValidationErrorCapUrnKey = @"CSValidationErrorCapUrnKey";
NSString * const CSValidationErrorArgumentNameKey = @"CSValidationErrorArgumentNameKey";
NSString * const CSValidationErrorValidationRuleKey = @"CSValidationErrorValidationRuleKey";
NSString * const CSValidationErrorActualValueKey = @"CSValidationErrorActualValueKey";
NSString * const CSValidationErrorActualTypeKey = @"CSValidationErrorActualTypeKey";
NSString * const CSValidationErrorExpectedTypeKey = @"CSValidationErrorExpectedTypeKey";

@implementation CSValidationError

@synthesize validationType = _validationType;
@synthesize capUrn = _capUrn;
@synthesize argumentName = _argumentName;
@synthesize validationRule = _validationRule;
@synthesize actualValue = _actualValue;
@synthesize actualType = _actualType;
@synthesize expectedType = _expectedType;

- (instancetype)initWithType:(CSValidationErrorType)type 
                capUrn:(NSString *)capUrn 
                 description:(NSString *)description 
                    userInfo:(NSDictionary *)userInfo {
    self = [super initWithDomain:CSValidationErrorDomain code:type userInfo:userInfo];
    if (self) {
        _validationType = type;
        _capUrn = [capUrn copy];
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

+ (instancetype)unknownCapError:(NSString *)capUrn {
    NSString *description = [NSString stringWithFormat:@"Unknown cap '%@' - cap not registered or advertised", capUrn];
    return [[self alloc] initWithType:CSValidationErrorTypeUnknownCap 
                         capUrn:capUrn 
                          description:description 
                             userInfo:@{NSLocalizedDescriptionKey: description}];
}

+ (instancetype)missingRequiredArgumentError:(NSString *)capUrn argumentName:(NSString *)argumentName {
    NSString *description = [NSString stringWithFormat:@"Cap '%@' requires argument '%@' but it was not provided", capUrn, argumentName];
    return [[self alloc] initWithType:CSValidationErrorTypeMissingRequiredArgument 
                         capUrn:capUrn 
                          description:description 
                             userInfo:@{
                                 NSLocalizedDescriptionKey: description,
                                 CSValidationErrorArgumentNameKey: argumentName
                             }];
}

+ (instancetype)invalidArgumentTypeError:(NSString *)capUrn 
                            argumentName:(NSString *)argumentName 
                            expectedType:(CSArgumentType)expectedType 
                              actualType:(NSString *)actualType 
                             actualValue:(id)actualValue {
    NSString *expectedTypeName = [self argumentTypeToString:expectedType];
    NSString *description = [NSString stringWithFormat:@"Cap '%@' argument '%@' expects type '%@' but received '%@' with value: %@", 
                            capUrn, argumentName, expectedTypeName, actualType, actualValue];
    return [[self alloc] initWithType:CSValidationErrorTypeInvalidArgumentType 
                         capUrn:capUrn 
                          description:description 
                             userInfo:@{
                                 NSLocalizedDescriptionKey: description,
                                 CSValidationErrorArgumentNameKey: argumentName,
                                 CSValidationErrorExpectedTypeKey: expectedTypeName,
                                 CSValidationErrorActualTypeKey: actualType,
                                 CSValidationErrorActualValueKey: actualValue ?: [NSNull null]
                             }];
}

+ (instancetype)argumentValidationFailedError:(NSString *)capUrn 
                                 argumentName:(NSString *)argumentName 
                               validationRule:(NSString *)validationRule 
                                  actualValue:(id)actualValue {
    NSString *description = [NSString stringWithFormat:@"Cap '%@' argument '%@' failed validation rule '%@' with value: %@", 
                            capUrn, argumentName, validationRule, actualValue];
    return [[self alloc] initWithType:CSValidationErrorTypeArgumentValidationFailed 
                         capUrn:capUrn 
                          description:description 
                             userInfo:@{
                                 NSLocalizedDescriptionKey: description,
                                 CSValidationErrorArgumentNameKey: argumentName,
                                 CSValidationErrorValidationRuleKey: validationRule,
                                 CSValidationErrorActualValueKey: actualValue ?: [NSNull null]
                             }];
}

+ (instancetype)invalidOutputTypeError:(NSString *)capUrn 
                          expectedType:(CSOutputType)expectedType 
                            actualType:(NSString *)actualType 
                           actualValue:(id)actualValue {
    NSString *expectedTypeName = [self outputTypeToString:expectedType];
    NSString *description = [NSString stringWithFormat:@"Cap '%@' output expects type '%@' but received '%@' with value: %@", 
                            capUrn, expectedTypeName, actualType, actualValue];
    return [[self alloc] initWithType:CSValidationErrorTypeInvalidOutputType 
                         capUrn:capUrn 
                          description:description 
                             userInfo:@{
                                 NSLocalizedDescriptionKey: description,
                                 CSValidationErrorExpectedTypeKey: expectedTypeName,
                                 CSValidationErrorActualTypeKey: actualType,
                                 CSValidationErrorActualValueKey: actualValue ?: [NSNull null]
                             }];
}

+ (instancetype)outputValidationFailedError:(NSString *)capUrn 
                             validationRule:(NSString *)validationRule 
                                actualValue:(id)actualValue {
    NSString *description = [NSString stringWithFormat:@"Cap '%@' output failed validation rule '%@' with value: %@", 
                            capUrn, validationRule, actualValue];
    return [[self alloc] initWithType:CSValidationErrorTypeOutputValidationFailed 
                         capUrn:capUrn 
                          description:description 
                             userInfo:@{
                                 NSLocalizedDescriptionKey: description,
                                 CSValidationErrorValidationRuleKey: validationRule,
                                 CSValidationErrorActualValueKey: actualValue ?: [NSNull null]
                             }];
}

+ (instancetype)invalidCapSchemaError:(NSString *)capUrn issue:(NSString *)issue {
    NSString *description = [NSString stringWithFormat:@"Cap '%@' has invalid schema: %@", capUrn, issue];
    return [[self alloc] initWithType:CSValidationErrorTypeInvalidCapSchema 
                         capUrn:capUrn 
                          description:description 
                             userInfo:@{NSLocalizedDescriptionKey: description}];
}

+ (instancetype)tooManyArgumentsError:(NSString *)capUrn 
                          maxExpected:(NSInteger)maxExpected 
                          actualCount:(NSInteger)actualCount {
    NSString *description = [NSString stringWithFormat:@"Cap '%@' expects at most %ld arguments but received %ld", 
                            capUrn, (long)maxExpected, (long)actualCount];
    return [[self alloc] initWithType:CSValidationErrorTypeTooManyArguments 
                         capUrn:capUrn 
                          description:description 
                             userInfo:@{NSLocalizedDescriptionKey: description}];
}

+ (instancetype)jsonParseError:(NSString *)capUrn error:(NSString *)error {
    NSString *description = [NSString stringWithFormat:@"Cap '%@' JSON parsing failed: %@", capUrn, error];
    return [[self alloc] initWithType:CSValidationErrorTypeJSONParseError 
                         capUrn:capUrn 
                          description:description 
                             userInfo:@{NSLocalizedDescriptionKey: description}];
}

+ (instancetype)schemaValidationFailedError:(NSString *)capUrn 
                               argumentName:(nullable NSString *)argumentName 
                           underlyingError:(NSError *)underlyingError {
    NSString *context = argumentName ? [NSString stringWithFormat:@"argument '%@'", argumentName] : @"output";
    NSString *description = [NSString stringWithFormat:@"Cap '%@' %@ failed schema validation: %@", 
                            capUrn, context, underlyingError.localizedDescription];
    
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObject:description 
                                                                       forKey:NSLocalizedDescriptionKey];
    if (argumentName) {
        userInfo[CSValidationErrorArgumentNameKey] = argumentName;
    }
    userInfo[NSUnderlyingErrorKey] = underlyingError;
    
    return [[self alloc] initWithType:CSValidationErrorTypeSchemaValidationFailed 
                         capUrn:capUrn 
                          description:description 
                             userInfo:userInfo];
}

@end

// Internal helper functions
@interface CSInputValidator ()
+ (NSString *)getJsonTypeName:(id)value;
+ (NSNumber *)getNumericValue:(id)value;
+ (BOOL)validateSingleArgument:(CSCapArgument *)argDef 
                         value:(id)value 
                    cap:(CSCap *)cap 
                         error:(NSError **)error;
+ (BOOL)validateArgumentType:(CSCapArgument *)argDef 
                       value:(id)value 
                  cap:(CSCap *)cap 
                       error:(NSError **)error;
+ (BOOL)validateArgumentRules:(CSCapArgument *)argDef 
                        value:(id)value 
                   cap:(CSCap *)cap 
                        error:(NSError **)error;
@end

@implementation CSInputValidator

+ (BOOL)validateArguments:(NSArray *)arguments 
               cap:(CSCap *)cap 
                    error:(NSError **)error {
    NSString *capUrn = [cap urnString];
    CSCapArguments *args = [cap getArguments];
    
    // Check if too many arguments provided
    NSInteger maxArgs = args.required.count + args.optional.count;
    if (arguments.count > maxArgs) {
        if (error) {
            *error = [CSValidationError tooManyArgumentsError:capUrn 
                                                  maxExpected:maxArgs 
                                                  actualCount:arguments.count];
        }
        return NO;
    }
    
    // Validate required arguments
    for (NSInteger index = 0; index < args.required.count; index++) {
        if (index >= arguments.count) {
            if (error) {
                CSCapArgument *reqArg = args.required[index];
                *error = [CSValidationError missingRequiredArgumentError:capUrn 
                                                            argumentName:reqArg.name];
            }
            return NO;
        }
        
        CSCapArgument *reqArg = args.required[index];
        if (![self validateSingleArgument:reqArg 
                                    value:arguments[index] 
                               cap:cap 
                                    error:error]) {
            return NO;
        }
    }
    
    // Validate optional arguments if provided
    NSInteger requiredCount = args.required.count;
    for (NSInteger index = 0; index < args.optional.count; index++) {
        NSInteger argIndex = requiredCount + index;
        if (argIndex < arguments.count) {
            CSCapArgument *optArg = args.optional[index];
            if (![self validateSingleArgument:optArg 
                                        value:arguments[argIndex] 
                                   cap:cap 
                                        error:error]) {
                return NO;
            }
        }
    }
    
    return YES;
}

+ (BOOL)validateSingleArgument:(CSCapArgument *)argDef 
                         value:(id)value 
                    cap:(CSCap *)cap 
                         error:(NSError **)error {
    // Type validation
    if (![self validateArgumentType:argDef value:value cap:cap error:error]) {
        return NO;
    }
    
    // Validation rules
    if (![self validateArgumentRules:argDef value:value cap:cap error:error]) {
        return NO;
    }
    
    // Schema validation for structured types
    if ((argDef.argType == CSArgumentTypeObject || argDef.argType == CSArgumentTypeArray) &&
        (argDef.schema || argDef.schemaRef)) {
        CSJSONSchemaValidator *schemaValidator = [CSJSONSchemaValidator validator];
        NSError *schemaError = nil;
        
        if (![schemaValidator validateArgument:argDef withValue:value error:&schemaError]) {
            if (error) {
                NSString *capUrn = [cap urnString];
                *error = [CSValidationError schemaValidationFailedError:capUrn 
                                                           argumentName:argDef.name 
                                                        underlyingError:schemaError];
            }
            return NO;
        }
    }
    
    return YES;
}

+ (BOOL)validateArgumentType:(CSCapArgument *)argDef 
                       value:(id)value 
                  cap:(CSCap *)cap 
                       error:(NSError **)error {
    NSString *capUrn = [cap urnString];
    NSString *actualType = [self getJsonTypeName:value];
    
    BOOL typeMatches = NO;
    switch (argDef.argType) {
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
            *error = [CSValidationError invalidArgumentTypeError:capUrn 
                                                    argumentName:argDef.name 
                                                    expectedType:argDef.argType 
                                                      actualType:actualType 
                                                     actualValue:value];
        }
        return NO;
    }
    
    return YES;
}

+ (BOOL)validateArgumentRules:(CSCapArgument *)argDef 
                        value:(id)value 
                   cap:(CSCap *)cap 
                        error:(NSError **)error {
    NSString *capUrn = [cap urnString];
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
                *error = [CSValidationError argumentValidationFailedError:capUrn 
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
                *error = [CSValidationError argumentValidationFailedError:capUrn 
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
                *error = [CSValidationError argumentValidationFailedError:capUrn 
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
                *error = [CSValidationError argumentValidationFailedError:capUrn 
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
                    *error = [CSValidationError argumentValidationFailedError:capUrn 
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
                *error = [CSValidationError argumentValidationFailedError:capUrn 
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
+ (BOOL)validateOutputType:(CSCapOutput *)outputDef 
                     value:(id)value 
                cap:(CSCap *)cap 
                     error:(NSError **)error;
+ (BOOL)validateOutputRules:(CSCapOutput *)outputDef 
                      value:(id)value 
                 cap:(CSCap *)cap 
                      error:(NSError **)error;
@end

@implementation CSOutputValidator

+ (BOOL)validateOutput:(id)output 
            cap:(CSCap *)cap 
                 error:(NSError **)error {
    NSString *capUrn = [cap urnString];
    
    CSCapOutput *outputDef = [cap getOutput];
    if (!outputDef) {
        if (error) {
            *error = [CSValidationError invalidCapSchemaError:capUrn 
                                                               issue:@"No output definition specified"];
        }
        return NO;
    }
    
    // Type validation
    if (![self validateOutputType:outputDef value:output cap:cap error:error]) {
        return NO;
    }
    
    // Validation rules
    if (![self validateOutputRules:outputDef value:output cap:cap error:error]) {
        return NO;
    }
    
    // Schema validation for structured types
    if ((outputDef.outputType == CSOutputTypeObject || outputDef.outputType == CSOutputTypeArray) &&
        (outputDef.schema || outputDef.schemaRef)) {
        CSJSONSchemaValidator *schemaValidator = [CSJSONSchemaValidator validator];
        NSError *schemaError = nil;
        
        if (![schemaValidator validateOutput:outputDef withValue:output error:&schemaError]) {
            if (error) {
                *error = [CSValidationError schemaValidationFailedError:capUrn 
                                                           argumentName:nil 
                                                        underlyingError:schemaError];
            }
            return NO;
        }
    }
    
    return YES;
}

+ (BOOL)validateOutputType:(CSCapOutput *)outputDef 
                     value:(id)value 
                cap:(CSCap *)cap 
                     error:(NSError **)error {
    NSString *capUrn = [cap urnString];
    NSString *actualType = [CSInputValidator getJsonTypeName:value];
    
    BOOL typeMatches = NO;
    switch (outputDef.outputType) {
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
            *error = [CSValidationError invalidOutputTypeError:capUrn 
                                                  expectedType:outputDef.outputType 
                                                    actualType:actualType 
                                                   actualValue:value];
        }
        return NO;
    }
    
    return YES;
}

+ (BOOL)validateOutputRules:(CSCapOutput *)outputDef 
                      value:(id)value 
                 cap:(CSCap *)cap 
                      error:(NSError **)error {
    NSString *capUrn = [cap urnString];
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
                *error = [CSValidationError outputValidationFailedError:capUrn 
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
                *error = [CSValidationError outputValidationFailedError:capUrn 
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
                *error = [CSValidationError outputValidationFailedError:capUrn 
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
                *error = [CSValidationError outputValidationFailedError:capUrn 
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
                    *error = [CSValidationError outputValidationFailedError:capUrn 
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
                *error = [CSValidationError outputValidationFailedError:capUrn 
                                                         validationRule:rule 
                                                            actualValue:value];
            }
            return NO;
        }
    }
    
    return YES;
}

@end

@implementation CSCapValidator

+ (BOOL)validateCap:(CSCap *)cap 
                     error:(NSError **)error {
    NSString *capUrn = [cap urnString];
    CSCapArguments *args = [cap getArguments];
    
    // Validate that required arguments don't have default values
    for (CSCapArgument *arg in args.required) {
        if (arg.defaultValue) {
            if (error) {
                NSString *issue = [NSString stringWithFormat:@"Required argument '%@' cannot have a default value", arg.name];
                *error = [CSValidationError invalidCapSchemaError:capUrn issue:issue];
            }
            return NO;
        }
    }
    
    // Validate argument position uniqueness
    NSMutableSet<NSNumber *> *positions = [NSMutableSet set];
    NSArray<CSCapArgument *> *allArgs = [args.required arrayByAddingObjectsFromArray:args.optional];
    for (CSCapArgument *arg in allArgs) {
        if (arg.position) {
            if ([positions containsObject:arg.position]) {
                if (error) {
                    NSString *issue = [NSString stringWithFormat:@"Duplicate argument position %@ for argument '%@'", arg.position, arg.name];
                    *error = [CSValidationError invalidCapSchemaError:capUrn issue:issue];
                }
                return NO;
            }
            [positions addObject:arg.position];
        }
    }
    
    // Validate CLI flag uniqueness
    NSMutableSet<NSString *> *cliFlags = [NSMutableSet set];
    for (CSCapArgument *arg in allArgs) {
        if (arg.cliFlag) {
            if ([cliFlags containsObject:arg.cliFlag]) {
                if (error) {
                    NSString *issue = [NSString stringWithFormat:@"Duplicate CLI flag '%@' for argument '%@'", arg.cliFlag, arg.name];
                    *error = [CSValidationError invalidCapSchemaError:capUrn issue:issue];
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
    NSMutableDictionary<NSString *, CSCap *> *_caps;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _caps = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)registerCap:(CSCap *)cap {
    NSString *capUrn = [cap urnString];
    _caps[capUrn] = cap;
}

- (nullable CSCap *)getCap:(NSString *)capUrn {
    return _caps[capUrn];
}

- (BOOL)validateInputs:(NSArray *)arguments 
          capUrn:(NSString *)capUrn 
                 error:(NSError **)error {
    CSCap *cap = [self getCap:capUrn];
    if (!cap) {
        if (error) {
            *error = [CSValidationError unknownCapError:capUrn];
        }
        return NO;
    }
    
    return [CSInputValidator validateArguments:arguments cap:cap error:error];
}

- (BOOL)validateOutput:(id)output 
          capUrn:(NSString *)capUrn 
                 error:(NSError **)error {
    CSCap *cap = [self getCap:capUrn];
    if (!cap) {
        if (error) {
            *error = [CSValidationError unknownCapError:capUrn];
        }
        return NO;
    }
    
    return [CSOutputValidator validateOutput:output cap:cap error:error];
}

- (BOOL)validateBinaryOutput:(NSData *)outputData 
                capUrn:(NSString *)capUrn 
                       error:(NSError **)error {
    CSCap *cap = [self getCap:capUrn];
    if (!cap) {
        if (error) {
            *error = [CSValidationError unknownCapError:capUrn];
        }
        return NO;
    }
    
    // For binary outputs, we primarily validate existence and basic constraints
    CSCapOutput *output = [cap getOutput];
    if (!output) {
        // No output definition means any output is acceptable
        return YES;
    }
    
    // Verify output type is binary
    if (output.outputType != CSOutputTypeBinary) {
        if (error) {
            *error = [CSValidationError invalidOutputTypeError:capUrn
                                                  expectedType:output.outputType
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
                *error = [CSValidationError outputValidationFailedError:capUrn
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
                *error = [CSValidationError outputValidationFailedError:capUrn
                                                         validationRule:rule
                                                            actualValue:@(outputData.length)];
            }
            return NO;
        }
    }
    
    return YES;
}

- (BOOL)validateCapSchema:(CSCap *)cap 
                           error:(NSError **)error {
    return [CSCapValidator validateCap:cap error:error];
}

@end
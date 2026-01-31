//
//  CSCapValidator.m
//  Cap schema validation for plugin interactions
//
//  NOTE: Type validation now uses mediaSpec -> spec ID resolution.
//  The old CSArgumentType and CSOutputType enums have been removed.
//

#import "include/CSCapValidator.h"
#import "include/CSSchemaValidator.h"
#import "include/CSMediaSpec.h"

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

+ (instancetype)unknownArgumentError:(NSString *)capUrn argumentName:(NSString *)argumentName {
    NSString *description = [NSString stringWithFormat:@"Cap '%@' has no argument named '%@'", capUrn, argumentName];
    return [[self alloc] initWithType:CSValidationErrorTypeUnknownArgument
                         capUrn:capUrn
                          description:description
                             userInfo:@{
                                 NSLocalizedDescriptionKey: description,
                                 CSValidationErrorArgumentNameKey: argumentName
                             }];
}

+ (instancetype)invalidArgumentTypeError:(NSString *)capUrn
                            argumentName:(NSString *)argumentName
                            expectedType:(NSString *)expectedType
                              actualType:(NSString *)actualType
                             actualValue:(id)actualValue {
    NSString *description = [NSString stringWithFormat:@"Cap '%@' argument '%@' expects type '%@' but received '%@' with value: %@",
                            capUrn, argumentName, expectedType, actualType, actualValue];
    return [[self alloc] initWithType:CSValidationErrorTypeInvalidArgumentType
                         capUrn:capUrn
                          description:description
                             userInfo:@{
                                 NSLocalizedDescriptionKey: description,
                                 CSValidationErrorArgumentNameKey: argumentName,
                                 CSValidationErrorExpectedTypeKey: expectedType,
                                 CSValidationErrorActualTypeKey: actualType,
                                 CSValidationErrorActualValueKey: actualValue ?: [NSNull null]
                             }];
}

+ (instancetype)mediaValidationFailedError:(NSString *)capUrn
                                 argumentName:(NSString *)argumentName
                               validationRule:(NSString *)validationRule
                                  actualValue:(id)actualValue {
    NSString *description = [NSString stringWithFormat:@"Cap '%@' argument '%@' failed validation rule '%@' with value: %@",
                            capUrn, argumentName, validationRule, actualValue];
    return [[self alloc] initWithType:CSValidationErrorTypeMediaValidationFailed
                         capUrn:capUrn
                          description:description
                             userInfo:@{
                                 NSLocalizedDescriptionKey: description,
                                 CSValidationErrorArgumentNameKey: argumentName,
                                 CSValidationErrorValidationRuleKey: validationRule,
                                 CSValidationErrorActualValueKey: actualValue ?: [NSNull null]
                             }];
}

+ (instancetype)mediaSpecValidationFailedError:(NSString *)capUrn
                                  argumentName:(NSString *)argumentName
                                      mediaUrn:(NSString *)mediaUrn
                                validationRule:(NSString *)validationRule
                                   actualValue:(id)actualValue {
    NSString *description = [NSString stringWithFormat:@"Cap '%@' argument '%@' failed media spec '%@' validation rule '%@' with value: %@",
                            capUrn, argumentName, mediaUrn, validationRule, actualValue];
    return [[self alloc] initWithType:CSValidationErrorTypeMediaSpecValidationFailed
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
                          expectedType:(NSString *)expectedType
                            actualType:(NSString *)actualType
                           actualValue:(id)actualValue {
    NSString *description = [NSString stringWithFormat:@"Cap '%@' output expects type '%@' but received '%@' with value: %@",
                            capUrn, expectedType, actualType, actualValue];
    return [[self alloc] initWithType:CSValidationErrorTypeInvalidOutputType
                         capUrn:capUrn
                          description:description
                             userInfo:@{
                                 NSLocalizedDescriptionKey: description,
                                 CSValidationErrorExpectedTypeKey: expectedType,
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

+ (instancetype)outputMediaSpecValidationFailedError:(NSString *)capUrn
                                            mediaUrn:(NSString *)mediaUrn
                                      validationRule:(NSString *)validationRule
                                         actualValue:(id)actualValue {
    NSString *description = [NSString stringWithFormat:@"Cap '%@' output failed media spec '%@' validation rule '%@' with value: %@",
                            capUrn, mediaUrn, validationRule, actualValue];
    return [[self alloc] initWithType:CSValidationErrorTypeOutputMediaSpecValidationFailed
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

+ (instancetype)inlineMediaSpecRedefinesRegistryError:(NSString *)mediaUrn {
    NSString *description = [NSString stringWithFormat:@"XV5: Inline media spec '%@' redefines existing registry spec", mediaUrn];
    return [[self alloc] initWithType:CSValidationErrorTypeInlineMediaSpecRedefinesRegistry
                         capUrn:@""
                          description:description
                             userInfo:@{NSLocalizedDescriptionKey: description}];
}

@end

// Internal helper functions
@interface CSInputValidator ()
+ (NSString *)getJsonTypeName:(id)value;
+ (NSNumber *)getNumericValue:(id)value;
+ (BOOL)validateSingleArgument:(CSCapArg *)argDef
                         value:(id)value
                    cap:(CSCap *)cap
                         error:(NSError **)error;
+ (BOOL)validateArgumentType:(CSCapArg *)argDef
                       value:(id)value
                  cap:(CSCap *)cap
                       error:(NSError **)error;
+ (BOOL)validateMediaSpecRules:(CSCapArg *)argDef
                     mediaSpec:(CSMediaSpec *)mediaSpec
                         value:(id)value
                    cap:(CSCap *)cap
                         error:(NSError **)error;
@end

@implementation CSInputValidator

+ (BOOL)validateArguments:(NSArray *)arguments
               cap:(CSCap *)cap
                    error:(NSError **)error {
    NSString *capUrn = [cap urnString];
    NSArray<CSCapArg *> *requiredArgs = [cap getRequiredArgs];
    NSArray<CSCapArg *> *optionalArgs = [cap getOptionalArgs];

    // Check if too many arguments provided
    NSInteger maxArgs = requiredArgs.count + optionalArgs.count;
    if (arguments.count > maxArgs) {
        if (error) {
            *error = [CSValidationError tooManyArgumentsError:capUrn
                                                  maxExpected:maxArgs
                                                  actualCount:arguments.count];
        }
        return NO;
    }

    // Validate required arguments
    for (NSInteger index = 0; index < requiredArgs.count; index++) {
        if (index >= arguments.count) {
            if (error) {
                CSCapArg *reqArg = requiredArgs[index];
                *error = [CSValidationError missingRequiredArgumentError:capUrn
                                                            argumentName:reqArg.mediaUrn];
            }
            return NO;
        }

        CSCapArg *reqArg = requiredArgs[index];
        if (![self validateSingleArgument:reqArg
                                    value:arguments[index]
                               cap:cap
                                    error:error]) {
            return NO;
        }
    }

    // Validate optional arguments if provided
    NSInteger requiredCount = requiredArgs.count;
    for (NSInteger index = 0; index < optionalArgs.count; index++) {
        NSInteger argIndex = requiredCount + index;
        if (argIndex < arguments.count) {
            CSCapArg *optArg = optionalArgs[index];
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

+ (BOOL)validateNamedArguments:(NSArray *)namedArguments
                           cap:(CSCap *)cap
                         error:(NSError **)error {
    // For now, delegate to regular validation
    return [self validateArguments:namedArguments cap:cap error:error];
}

+ (BOOL)validateSingleArgument:(CSCapArg *)argDef
                         value:(id)value
                    cap:(CSCap *)cap
                         error:(NSError **)error {
    // Resolve mediaSpec first - needed for type validation and media spec validation
    CSMediaSpec *mediaSpec = nil;
    if (argDef.mediaUrn) {
        NSError *resolveError = nil;
        mediaSpec = CSResolveMediaUrn(argDef.mediaUrn, cap.mediaSpecs, &resolveError);
        if (!mediaSpec) {
            // FAIL HARD on unresolvable spec ID
            if (error) {
                NSString *capUrn = [cap urnString];
                *error = [CSValidationError invalidCapSchemaError:capUrn
                                                            issue:[NSString stringWithFormat:@"Cannot resolve spec ID '%@' for argument '%@': %@",
                                                                   argDef.mediaUrn, argDef.mediaUrn, resolveError.localizedDescription]];
            }
            return NO;
        }
    }

    // Type validation
    if (![self validateArgumentType:argDef value:value cap:cap error:error]) {
        return NO;
    }

    // Media spec validation rules (inherent to the semantic type)
    if (mediaSpec && mediaSpec.validation) {
        if (![self validateMediaSpecRules:argDef mediaSpec:mediaSpec value:value cap:cap error:error]) {
            return NO;
        }
    }

    // Schema validation
    if (mediaSpec && mediaSpec.schema) {
        CSJSONSchemaValidator *schemaValidator = [CSJSONSchemaValidator validator];
        NSError *schemaError = nil;

        if (![schemaValidator validateArgument:argDef withValue:value mediaSpecs:cap.mediaSpecs error:&schemaError]) {
            if (error) {
                NSString *capUrn = [cap urnString];
                *error = [CSValidationError schemaValidationFailedError:capUrn
                                                           argumentName:argDef.mediaUrn
                                                        underlyingError:schemaError];
            }
            return NO;
        }
    }

    return YES;
}

+ (BOOL)validateArgumentType:(CSCapArg *)argDef
                       value:(id)value
                  cap:(CSCap *)cap
                       error:(NSError **)error {
    NSString *capUrn = [cap urnString];
    NSString *actualType = [self getJsonTypeName:value];

    // If no mediaSpec, skip type validation
    if (!argDef.mediaUrn) {
        return YES;
    }

    // Resolve mediaSpec to determine expected type
    NSError *resolveError = nil;
    CSMediaSpec *mediaSpec = CSResolveMediaUrn(argDef.mediaUrn, cap.mediaSpecs, &resolveError);
    if (!mediaSpec) {
        // FAIL HARD on unresolvable spec ID
        if (error) {
            *error = [CSValidationError invalidCapSchemaError:capUrn
                                                        issue:[NSString stringWithFormat:@"Cannot resolve spec ID '%@' for argument '%@': %@",
                                                               argDef.mediaUrn, argDef.mediaUrn, resolveError.localizedDescription]];
        }
        return NO;
    }

    // Determine expected type from profile
    NSString *profile = mediaSpec.profile;
    BOOL typeMatches = YES;
    NSString *expectedType = argDef.mediaUrn;

    if (profile) {
        if ([profile containsString:@"/schema/str"] && ![profile containsString:@"-array"]) {
            typeMatches = [value isKindOfClass:[NSString class]];
            expectedType = @"string";
        } else if ([profile containsString:@"/schema/int"] && ![profile containsString:@"-array"]) {
            if ([value isKindOfClass:[NSNumber class]]) {
                NSNumber *num = (NSNumber *)value;
                typeMatches = !CFNumberIsFloatType((__bridge CFNumberRef)num) &&
                              CFGetTypeID((__bridge CFTypeRef)num) != CFBooleanGetTypeID();
            } else {
                typeMatches = NO;
            }
            expectedType = @"integer";
        } else if ([profile containsString:@"/schema/num"] && ![profile containsString:@"-array"]) {
            typeMatches = [value isKindOfClass:[NSNumber class]];
            expectedType = @"number";
        } else if ([profile containsString:@"/schema/bool"] && ![profile containsString:@"-array"]) {
            typeMatches = [value isKindOfClass:[NSNumber class]] &&
                          CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID();
            expectedType = @"boolean";
        } else if ([profile containsString:@"/schema/obj"] && ![profile containsString:@"-array"]) {
            typeMatches = [value isKindOfClass:[NSDictionary class]];
            expectedType = @"object";
        } else if ([profile containsString:@"-array"]) {
            typeMatches = [value isKindOfClass:[NSArray class]];
            expectedType = @"array";
        }
    }

    // Check for binary based on media type
    if ([mediaSpec isBinary]) {
        typeMatches = [value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSData class]];
        expectedType = @"binary";
    }

    if (!typeMatches) {
        if (error) {
            *error = [CSValidationError invalidArgumentTypeError:capUrn
                                                    argumentName:argDef.mediaUrn
                                                    expectedType:expectedType
                                                      actualType:actualType
                                                     actualValue:value];
        }
        return NO;
    }

    return YES;
}

+ (BOOL)validateMediaSpecRules:(CSCapArg *)argDef
                     mediaSpec:(CSMediaSpec *)mediaSpec
                         value:(id)value
                    cap:(CSCap *)cap
                         error:(NSError **)error {
    NSString *capUrn = [cap urnString];
    CSMediaValidation *validation = mediaSpec.validation;
    NSString *mediaUrn = mediaSpec.mediaUrn ?: argDef.mediaUrn;

    if (!validation) {
        return YES;
    }

    // Numeric validation
    if (validation.min) {
        NSNumber *numValue = [self getNumericValue:value];
        if (numValue && [numValue doubleValue] < [validation.min doubleValue]) {
            if (error) {
                NSString *rule = [NSString stringWithFormat:@"minimum value %@", validation.min];
                *error = [CSValidationError mediaSpecValidationFailedError:capUrn
                                                              argumentName:argDef.mediaUrn
                                                                  mediaUrn:mediaUrn
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
                *error = [CSValidationError mediaSpecValidationFailedError:capUrn
                                                              argumentName:argDef.mediaUrn
                                                                  mediaUrn:mediaUrn
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
                *error = [CSValidationError mediaSpecValidationFailedError:capUrn
                                                              argumentName:argDef.mediaUrn
                                                                  mediaUrn:mediaUrn
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
                *error = [CSValidationError mediaSpecValidationFailedError:capUrn
                                                              argumentName:argDef.mediaUrn
                                                                  mediaUrn:mediaUrn
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
                    *error = [CSValidationError mediaSpecValidationFailedError:capUrn
                                                                  argumentName:argDef.mediaUrn
                                                                      mediaUrn:mediaUrn
                                                                validationRule:rule
                                                                   actualValue:value];
                }
                return NO;
            }
        }
    }

    // Allowed values validation
    if (validation.allowedValues.count > 0 && [value isKindOfClass:[NSString class]]) {
        NSString *stringValue = (NSString *)value;
        if (![validation.allowedValues containsObject:stringValue]) {
            if (error) {
                NSString *rule = [NSString stringWithFormat:@"allowed values: %@", validation.allowedValues];
                *error = [CSValidationError mediaSpecValidationFailedError:capUrn
                                                              argumentName:argDef.mediaUrn
                                                                  mediaUrn:mediaUrn
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
+ (BOOL)validateOutputMediaSpecRules:(CSCapOutput *)outputDef
                           mediaSpec:(CSMediaSpec *)mediaSpec
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
        // No output definition means any output is acceptable
        return YES;
    }

    // Resolve mediaSpec first - needed for type validation and media spec validation
    CSMediaSpec *mediaSpec = nil;
    if (outputDef.mediaUrn) {
        NSError *resolveError = nil;
        mediaSpec = CSResolveMediaUrn(outputDef.mediaUrn, cap.mediaSpecs, &resolveError);
        if (!mediaSpec) {
            // FAIL HARD on unresolvable spec ID
            if (error) {
                *error = [CSValidationError invalidCapSchemaError:capUrn
                                                            issue:[NSString stringWithFormat:@"Cannot resolve spec ID '%@' for output: %@",
                                                                   outputDef.mediaUrn, resolveError.localizedDescription]];
            }
            return NO;
        }
    }

    // Type validation
    if (![self validateOutputType:outputDef value:output cap:cap error:error]) {
        return NO;
    }

    // Media spec validation rules (inherent to the semantic type)
    if (mediaSpec && mediaSpec.validation) {
        if (![self validateOutputMediaSpecRules:outputDef mediaSpec:mediaSpec value:output cap:cap error:error]) {
            return NO;
        }
    }

    // Schema validation
    if (mediaSpec && mediaSpec.schema) {
        CSJSONSchemaValidator *schemaValidator = [CSJSONSchemaValidator validator];
        NSError *schemaError = nil;

        if (![schemaValidator validateOutput:outputDef withValue:output mediaSpecs:cap.mediaSpecs error:&schemaError]) {
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

    // If no mediaSpec, skip type validation
    if (!outputDef.mediaUrn) {
        return YES;
    }

    // Resolve mediaSpec to determine expected type
    NSError *resolveError = nil;
    CSMediaSpec *mediaSpec = CSResolveMediaUrn(outputDef.mediaUrn, cap.mediaSpecs, &resolveError);
    if (!mediaSpec) {
        // FAIL HARD on unresolvable spec ID
        if (error) {
            *error = [CSValidationError invalidCapSchemaError:capUrn
                                                        issue:[NSString stringWithFormat:@"Cannot resolve spec ID '%@' for output: %@",
                                                               outputDef.mediaUrn, resolveError.localizedDescription]];
        }
        return NO;
    }

    // Determine expected type from profile
    NSString *profile = mediaSpec.profile;
    BOOL typeMatches = YES;
    NSString *expectedType = outputDef.mediaUrn;

    if (profile) {
        if ([profile containsString:@"/schema/str"] && ![profile containsString:@"-array"]) {
            typeMatches = [value isKindOfClass:[NSString class]];
            expectedType = @"string";
        } else if ([profile containsString:@"/schema/int"] && ![profile containsString:@"-array"]) {
            if ([value isKindOfClass:[NSNumber class]]) {
                NSNumber *num = (NSNumber *)value;
                typeMatches = !CFNumberIsFloatType((__bridge CFNumberRef)num) &&
                              CFGetTypeID((__bridge CFTypeRef)num) != CFBooleanGetTypeID();
            } else {
                typeMatches = NO;
            }
            expectedType = @"integer";
        } else if ([profile containsString:@"/schema/num"] && ![profile containsString:@"-array"]) {
            typeMatches = [value isKindOfClass:[NSNumber class]];
            expectedType = @"number";
        } else if ([profile containsString:@"/schema/bool"] && ![profile containsString:@"-array"]) {
            typeMatches = [value isKindOfClass:[NSNumber class]] &&
                          CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID();
            expectedType = @"boolean";
        } else if ([profile containsString:@"/schema/obj"] && ![profile containsString:@"-array"]) {
            typeMatches = [value isKindOfClass:[NSDictionary class]];
            expectedType = @"object";
        } else if ([profile containsString:@"-array"]) {
            typeMatches = [value isKindOfClass:[NSArray class]];
            expectedType = @"array";
        }
    }

    // Check for binary based on media type
    if ([mediaSpec isBinary]) {
        typeMatches = [value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSData class]];
        expectedType = @"binary";
    }

    if (!typeMatches) {
        if (error) {
            *error = [CSValidationError invalidOutputTypeError:capUrn
                                                  expectedType:expectedType
                                                    actualType:actualType
                                                   actualValue:value];
        }
        return NO;
    }

    return YES;
}

+ (BOOL)validateOutputMediaSpecRules:(CSCapOutput *)outputDef
                           mediaSpec:(CSMediaSpec *)mediaSpec
                               value:(id)value
                          cap:(CSCap *)cap
                               error:(NSError **)error {
    NSString *capUrn = [cap urnString];
    CSMediaValidation *validation = mediaSpec.validation;
    NSString *mediaUrn = mediaSpec.mediaUrn ?: outputDef.mediaUrn;

    if (!validation) {
        return YES;
    }

    // Numeric validation
    if (validation.min) {
        NSNumber *numValue = [CSInputValidator getNumericValue:value];
        if (numValue && [numValue doubleValue] < [validation.min doubleValue]) {
            if (error) {
                NSString *rule = [NSString stringWithFormat:@"minimum value %@", validation.min];
                *error = [CSValidationError outputMediaSpecValidationFailedError:capUrn
                                                                        mediaUrn:mediaUrn
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
                *error = [CSValidationError outputMediaSpecValidationFailedError:capUrn
                                                                        mediaUrn:mediaUrn
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
                *error = [CSValidationError outputMediaSpecValidationFailedError:capUrn
                                                                        mediaUrn:mediaUrn
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
                *error = [CSValidationError outputMediaSpecValidationFailedError:capUrn
                                                                        mediaUrn:mediaUrn
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
                    *error = [CSValidationError outputMediaSpecValidationFailedError:capUrn
                                                                            mediaUrn:mediaUrn
                                                                      validationRule:rule
                                                                         actualValue:value];
                }
                return NO;
            }
        }
    }

    // Allowed values validation
    if (validation.allowedValues.count > 0 && [value isKindOfClass:[NSString class]]) {
        NSString *stringValue = (NSString *)value;
        if (![validation.allowedValues containsObject:stringValue]) {
            if (error) {
                NSString *rule = [NSString stringWithFormat:@"allowed values: %@", validation.allowedValues];
                *error = [CSValidationError outputMediaSpecValidationFailedError:capUrn
                                                                        mediaUrn:mediaUrn
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
    NSArray<CSCapArg *> *requiredArgs = [cap getRequiredArgs];
    NSArray<CSCapArg *> *optionalArgs = [cap getOptionalArgs];

    // Validate that required arguments don't have default values
    for (CSCapArg *arg in requiredArgs) {
        if (arg.defaultValue) {
            if (error) {
                NSString *issue = [NSString stringWithFormat:@"Required argument '%@' cannot have a default value", arg.mediaUrn];
                *error = [CSValidationError invalidCapSchemaError:capUrn issue:issue];
            }
            return NO;
        }
    }

    // Validate argument position uniqueness
    NSMutableSet<NSNumber *> *positions = [NSMutableSet set];
    NSArray<CSCapArg *> *allArgs = [requiredArgs arrayByAddingObjectsFromArray:optionalArgs];
    for (CSCapArg *arg in allArgs) {
        NSNumber *argPosition = [arg getPosition];
        if (argPosition) {
            if ([positions containsObject:argPosition]) {
                if (error) {
                    NSString *issue = [NSString stringWithFormat:@"Duplicate argument position %@ for argument '%@'", argPosition, arg.mediaUrn];
                    *error = [CSValidationError invalidCapSchemaError:capUrn issue:issue];
                }
                return NO;
            }
            [positions addObject:argPosition];
        }
    }

    // Validate CLI flag uniqueness
    NSMutableSet<NSString *> *cliFlags = [NSMutableSet set];
    for (CSCapArg *arg in allArgs) {
        NSString *argCliFlag = [arg getCliFlag];
        if (argCliFlag) {
            if ([cliFlags containsObject:argCliFlag]) {
                if (error) {
                    NSString *issue = [NSString stringWithFormat:@"Duplicate CLI flag '%@' for argument '%@'", argCliFlag, arg.mediaUrn];
                    *error = [CSValidationError invalidCapSchemaError:capUrn issue:issue];
                }
                return NO;
            }
            [cliFlags addObject:argCliFlag];
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

    // Resolve mediaSpec to check if it's binary - fail hard if resolution fails
    if (output.mediaUrn) {
        NSError *resolveError = nil;
        CSMediaSpec *mediaSpec = CSResolveMediaUrn(output.mediaUrn, cap.mediaSpecs, &resolveError);

        if (!mediaSpec) {
            // FAIL HARD on unresolvable spec ID
            if (error) {
                NSString *message = [NSString stringWithFormat:@"Cannot resolve output spec ID '%@' for cap '%@': %@",
                                   output.mediaUrn, capUrn, resolveError.localizedDescription];
                *error = [NSError errorWithDomain:@"CSCapValidator"
                                             code:1001
                                         userInfo:@{NSLocalizedDescriptionKey: message}];
            }
            return NO;
        }

        if (![mediaSpec isBinary]) {
            if (error) {
                *error = [CSValidationError invalidOutputTypeError:capUrn
                                                      expectedType:output.mediaUrn
                                                        actualType:@"binary"
                                                       actualValue:outputData];
            }
            return NO;
        }

        // Validate binary data size constraints using media spec validation if defined
        CSMediaValidation *validation = mediaSpec.validation;
        if (validation && validation.min) {
            if (outputData.length < [validation.min integerValue]) {
                if (error) {
                    NSString *rule = [NSString stringWithFormat:@"minimum size %@ bytes", validation.min];
                    *error = [CSValidationError outputMediaSpecValidationFailedError:capUrn
                                                                            mediaUrn:mediaSpec.mediaUrn
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
                    *error = [CSValidationError outputMediaSpecValidationFailedError:capUrn
                                                                            mediaUrn:mediaSpec.mediaUrn
                                                                      validationRule:rule
                                                                         actualValue:@(outputData.length)];
                }
                return NO;
            }
        }
    }

    return YES;
}

- (BOOL)validateCapSchema:(CSCap *)cap
                           error:(NSError **)error {
    return [CSCapValidator validateCap:cap error:error];
}

@end

// ============================================================================
// XV5 VALIDATION - No Redefinition of Registry Media Specs
// ============================================================================

@implementation CSXV5ValidationResult

+ (instancetype)validResult {
    CSXV5ValidationResult *result = [[CSXV5ValidationResult alloc] init];
    result->_valid = YES;
    result->_error = nil;
    result->_redefines = nil;
    return result;
}

+ (instancetype)invalidResultWithError:(NSString *)error redefines:(NSArray<NSString *> *)redefines {
    CSXV5ValidationResult *result = [[CSXV5ValidationResult alloc] init];
    result->_valid = NO;
    result->_error = error;
    result->_redefines = redefines;
    return result;
}

@end

@implementation CSXV5Validator

+ (CSXV5ValidationResult *)validateNoInlineMediaSpecRedefinition:(NSArray<NSDictionary *> *)mediaSpecs
                                               existsInRegistry:(CSMediaUrnExistsInRegistryBlock)existsInRegistry {
    if (!mediaSpecs || mediaSpecs.count == 0) {
        return [CSXV5ValidationResult validResult];
    }

    // If no registry check provided, degrade gracefully and allow
    if (!existsInRegistry) {
        return [CSXV5ValidationResult validResult];
    }

    NSMutableArray<NSString *> *redefines = [NSMutableArray array];

    for (NSDictionary *spec in mediaSpecs) {
        // Extract the URN from the spec object
        NSString *mediaUrn = spec[@"urn"];
        if (!mediaUrn) continue;

        // Check if this media URN already exists in the registry
        if (existsInRegistry(mediaUrn)) {
            [redefines addObject:mediaUrn];
        }
    }

    if (redefines.count > 0) {
        NSString *error = [NSString stringWithFormat:@"XV5: Inline media specs redefine existing registry specs: %@",
                           [redefines componentsJoinedByString:@", "]];
        return [CSXV5ValidationResult invalidResultWithError:error redefines:redefines];
    }

    return [CSXV5ValidationResult validResult];
}

@end

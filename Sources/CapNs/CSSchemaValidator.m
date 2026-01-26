//
//  CSSchemaValidator.m
//  JSON Schema validation implementation
//
//  Provides comprehensive JSON Schema Draft-7 validation using native
//  Foundation classes with proper error reporting and caching.
//
//  NOTE: Schema resolution now uses the mediaSpec -> spec ID -> MediaSpec flow.
//  Schemas are stored in the resolved MediaSpec's schema property.
//

#import "include/CSSchemaValidator.h"
#import "include/CSMediaSpec.h"

// Error domain
NSErrorDomain const CSSchemaValidationErrorDomain = @"CSSchemaValidationErrorDomain";

// Error user info keys
NSString * const CSSchemaValidationErrorCapUrnKey = @"CSSchemaValidationErrorCapUrnKey";
NSString * const CSSchemaValidationErrorArgumentNameKey = @"CSSchemaValidationErrorArgumentNameKey";
NSString * const CSSchemaValidationErrorContextKey = @"CSSchemaValidationErrorContextKey";
NSString * const CSSchemaValidationErrorValueKey = @"CSSchemaValidationErrorValueKey";
NSString * const CSSchemaValidationErrorValidationErrorsKey = @"CSSchemaValidationErrorValidationErrorsKey";

@implementation CSSchemaValidationError

@synthesize schemaErrorType = _schemaErrorType;
@synthesize capUrn = _capUrn;
@synthesize argumentName = _argumentName;
@synthesize context = _context;
@synthesize value = _value;
@synthesize validationErrors = _validationErrors;

- (instancetype)initWithType:(CSSchemaValidationErrorType)type
                   userInfo:(NSDictionary *)userInfo {
    NSString *description = userInfo[NSLocalizedDescriptionKey] ?: @"Schema validation failed";
    self = [super initWithDomain:CSSchemaValidationErrorDomain code:type userInfo:userInfo];
    if (self) {
        _schemaErrorType = type;
        _capUrn = [userInfo[CSSchemaValidationErrorCapUrnKey] copy];
        _argumentName = [userInfo[CSSchemaValidationErrorArgumentNameKey] copy];
        _context = [userInfo[CSSchemaValidationErrorContextKey] copy];
        _value = userInfo[CSSchemaValidationErrorValueKey];
        _validationErrors = [userInfo[CSSchemaValidationErrorValidationErrorsKey] copy];
    }
    return self;
}

+ (instancetype)mediaValidationError:(NSString *)argumentName
                        validationErrors:(NSArray<NSString *> *)validationErrors
                                   value:(nullable id)value {
    NSString *description = [NSString stringWithFormat:@"Schema validation failed for argument '%@': %@",
                           argumentName, [validationErrors componentsJoinedByString:@"; "]];
    NSDictionary *userInfo = @{
        NSLocalizedDescriptionKey: description,
        CSSchemaValidationErrorArgumentNameKey: argumentName,
        CSSchemaValidationErrorValidationErrorsKey: validationErrors,
        CSSchemaValidationErrorValueKey: value ?: [NSNull null]
    };
    return [[self alloc] initWithType:CSSchemaValidationErrorTypeMediaValidation userInfo:userInfo];
}

+ (instancetype)outputValidationError:(NSArray<NSString *> *)validationErrors
                                value:(nullable id)value {
    NSString *description = [NSString stringWithFormat:@"Schema validation failed for output: %@",
                           [validationErrors componentsJoinedByString:@"; "]];
    NSDictionary *userInfo = @{
        NSLocalizedDescriptionKey: description,
        CSSchemaValidationErrorValidationErrorsKey: validationErrors,
        CSSchemaValidationErrorValueKey: value ?: [NSNull null]
    };
    return [[self alloc] initWithType:CSSchemaValidationErrorTypeOutputValidation userInfo:userInfo];
}

+ (instancetype)schemaCompilationError:(NSString *)details
                                schema:(nullable id)schema {
    NSString *description = [NSString stringWithFormat:@"Failed to compile schema: %@", details];
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObject:description
                                                                       forKey:NSLocalizedDescriptionKey];
    if (schema) {
        userInfo[@"schema"] = schema;
    }
    return [[self alloc] initWithType:CSSchemaValidationErrorTypeSchemaCompilation userInfo:userInfo];
}

+ (instancetype)schemaRefNotResolvedError:(NSString *)schemaRef
                                  context:(NSString *)context {
    NSString *description = [NSString stringWithFormat:@"Schema reference '%@' could not be resolved in context: %@",
                           schemaRef, context];
    NSDictionary *userInfo = @{
        NSLocalizedDescriptionKey: description,
        CSSchemaValidationErrorContextKey: context,
        @"schemaRef": schemaRef
    };
    return [[self alloc] initWithType:CSSchemaValidationErrorTypeSchemaRefNotResolved userInfo:userInfo];
}

+ (instancetype)invalidJsonError:(NSString *)details
                           value:(nullable id)value {
    NSString *description = [NSString stringWithFormat:@"Invalid JSON for validation: %@", details];
    NSDictionary *userInfo = @{
        NSLocalizedDescriptionKey: description,
        CSSchemaValidationErrorValueKey: value ?: [NSNull null]
    };
    return [[self alloc] initWithType:CSSchemaValidationErrorTypeInvalidJson userInfo:userInfo];
}

+ (instancetype)unsupportedSchemaVersionError:(NSString *)version {
    NSString *description = [NSString stringWithFormat:@"Unsupported JSON Schema version: %@. Only Draft-7 is supported.", version];
    NSDictionary *userInfo = @{
        NSLocalizedDescriptionKey: description,
        @"version": version
    };
    return [[self alloc] initWithType:CSSchemaValidationErrorTypeUnsupportedSchemaVersion userInfo:userInfo];
}

@end

#pragma mark - CSFileSchemaResolver Implementation

@implementation CSFileSchemaResolver

+ (instancetype)resolverWithBasePath:(NSString *)basePath {
    return [[self alloc] initWithBasePath:basePath];
}

- (instancetype)initWithBasePath:(NSString *)basePath {
    self = [super init];
    if (self) {
        _basePath = [basePath copy];
    }
    return self;
}

- (nullable NSDictionary *)resolveSchema:(NSString *)schemaRef error:(NSError **)error {
    NSString *fullPath;

    // Handle relative and absolute paths
    if ([schemaRef hasPrefix:@"/"]) {
        fullPath = schemaRef;
    } else {
        fullPath = [self.basePath stringByAppendingPathComponent:schemaRef];
    }

    // Add .json extension if not present
    if (![fullPath.pathExtension isEqualToString:@"json"]) {
        fullPath = [fullPath stringByAppendingPathExtension:@"json"];
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:fullPath]) {
        if (error) {
            *error = [CSSchemaValidationError schemaRefNotResolvedError:schemaRef
                                                               context:[NSString stringWithFormat:@"File not found at path: %@", fullPath]];
        }
        return nil;
    }

    NSData *data = [NSData dataWithContentsOfFile:fullPath];
    if (!data) {
        if (error) {
            *error = [CSSchemaValidationError schemaRefNotResolvedError:schemaRef
                                                               context:[NSString stringWithFormat:@"Could not read file at path: %@", fullPath]];
        }
        return nil;
    }

    NSError *jsonError;
    id jsonObject = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
    if (!jsonObject) {
        if (error) {
            *error = [CSSchemaValidationError invalidJsonError:[NSString stringWithFormat:@"Invalid JSON in schema file %@: %@",
                                                              fullPath, jsonError.localizedDescription]
                                                        value:nil];
        }
        return nil;
    }

    if (![jsonObject isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [CSSchemaValidationError schemaCompilationError:@"Schema file must contain a JSON object at root level"
                                                             schema:jsonObject];
        }
        return nil;
    }

    return (NSDictionary *)jsonObject;
}

@end

#pragma mark - CSJSONSchemaValidator Implementation

@interface CSJSONSchemaValidator ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *schemaCache;
@end

@implementation CSJSONSchemaValidator

+ (instancetype)validator {
    return [[self alloc] init];
}

+ (instancetype)validatorWithResolver:(id<CSSchemaResolver>)resolver {
    CSJSONSchemaValidator *validator = [[self alloc] init];
    validator.resolver = resolver;
    return validator;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _schemaCache = [NSMutableDictionary dictionary];
    }
    return self;
}

- (BOOL)validateArgument:(CSCapArg *)argument
               withValue:(id)value
              mediaSpecs:(NSDictionary *)mediaSpecs
                   error:(NSError **)error {
    // Resolve the mediaUrn to get the schema
    NSDictionary *schema = [self resolveArgumentSchema:argument mediaSpecs:mediaSpecs error:error];
    if (!schema) {
        // If there's an error, it's already set
        // If no schema, validation passes (no schema means no validation needed)
        return error == nil || *error == nil;
    }

    return [self validateValue:value
                 againstSchema:schema
                       context:[NSString stringWithFormat:@"argument '%@'", argument.mediaUrn]
                         error:error];
}

- (BOOL)validateOutput:(CSCapOutput *)output
             withValue:(id)value
            mediaSpecs:(NSDictionary *)mediaSpecs
                 error:(NSError **)error {
    // Resolve the mediaUrn to get the schema
    NSDictionary *schema = [self resolveOutputSchema:output mediaSpecs:mediaSpecs error:error];
    if (!schema) {
        // If there's an error, it's already set
        // If no schema, validation passes
        return error == nil || *error == nil;
    }

    return [self validateValue:value
                 againstSchema:schema
                       context:@"output"
                         error:error];
}

- (BOOL)validateArguments:(CSCap *)cap
          positionalArgs:(nullable NSArray *)positionalArgs
               namedArgs:(nullable NSDictionary<NSString *, id> *)namedArgs
                   error:(NSError **)error {
    NSArray<CSCapArg *> *args = [cap getArgs];
    if (!args || args.count == 0) {
        return YES;
    }

    // Validate required arguments
    NSArray<CSCapArg *> *requiredArgs = [cap getRequiredArgs];
    for (NSUInteger i = 0; i < requiredArgs.count; i++) {
        CSCapArg *argDef = requiredArgs[i];
        id value = nil;
        BOOL found = NO;

        // Check positional arguments
        NSNumber *position = [argDef getPosition];
        if (position) {
            NSUInteger pos = position.unsignedIntegerValue;
            if (positionalArgs && pos < positionalArgs.count) {
                value = positionalArgs[pos];
                found = YES;
            }
        } else if (positionalArgs && i < positionalArgs.count) {
            value = positionalArgs[i];
            found = YES;
        }

        // Check named arguments by media_urn (takes precedence)
        if (namedArgs && namedArgs[argDef.mediaUrn]) {
            value = namedArgs[argDef.mediaUrn];
            found = YES;
        }

        if (found) {
            if (![self validateArgument:argDef withValue:value mediaSpecs:cap.mediaSpecs error:error]) {
                return NO;
            }
        }
    }

    // Validate optional arguments if provided
    NSArray<CSCapArg *> *optionalArgs = [cap getOptionalArgs];
    for (CSCapArg *argDef in optionalArgs) {
        id value = nil;
        BOOL found = NO;

        // Check named arguments first for optional args (by media_urn)
        if (namedArgs && namedArgs[argDef.mediaUrn]) {
            value = namedArgs[argDef.mediaUrn];
            found = YES;
        }

        // Check positional if not found in named args
        NSNumber *position = [argDef getPosition];
        if (!found && position) {
            NSUInteger pos = position.unsignedIntegerValue;
            if (positionalArgs && pos < positionalArgs.count) {
                value = positionalArgs[pos];
                found = YES;
            }
        }

        if (found) {
            if (![self validateArgument:argDef withValue:value mediaSpecs:cap.mediaSpecs error:error]) {
                return NO;
            }
        }
    }

    return YES;
}

#pragma mark - Private Methods

- (nullable NSDictionary *)resolveArgumentSchema:(CSCapArg *)argument
                                      mediaSpecs:(NSDictionary *)mediaSpecs
                                           error:(NSError **)error {
    // Get the media URN from the argument
    NSString *specId = argument.mediaUrn;
    if (!specId) {
        // No mediaUrn, no schema validation needed
        return nil;
    }

    // Resolve the spec ID to a MediaSpec
    NSError *resolveError = nil;
    CSMediaSpec *mediaSpec = CSResolveMediaUrn(specId, mediaSpecs, &resolveError);
    if (!mediaSpec) {
        // FAIL HARD on unresolvable spec ID
        if (error && resolveError) {
            *error = resolveError;
        }
        return nil;
    }

    // Return the schema from the resolved MediaSpec
    return mediaSpec.schema;
}

- (nullable NSDictionary *)resolveOutputSchema:(CSCapOutput *)output
                                    mediaSpecs:(NSDictionary *)mediaSpecs
                                         error:(NSError **)error {
    // Get the media URN from the output
    NSString *specId = output.mediaUrn;
    if (!specId) {
        // No mediaUrn, no schema validation needed
        return nil;
    }

    // Resolve the spec ID to a MediaSpec
    NSError *resolveError = nil;
    CSMediaSpec *mediaSpec = CSResolveMediaUrn(specId, mediaSpecs, &resolveError);
    if (!mediaSpec) {
        // FAIL HARD on unresolvable spec ID
        if (error && resolveError) {
            *error = resolveError;
        }
        return nil;
    }

    // Return the schema from the resolved MediaSpec
    return mediaSpec.schema;
}

- (BOOL)validateValue:(id)value
        againstSchema:(NSDictionary *)schema
              context:(NSString *)context
                error:(NSError **)error {
    // Basic JSON Schema Draft-7 validation implementation
    // This is a simplified implementation - for production use, consider a full JSON Schema library

    NSMutableArray<NSString *> *errors = [NSMutableArray array];

    // Validate type
    NSString *expectedType = schema[@"type"];
    if (expectedType) {
        if (![self validateValueType:value expectedType:expectedType errors:errors]) {
            // Type validation failed, add to errors array
        }
    }

    // Validate properties for objects
    if ([expectedType isEqualToString:@"object"] && [value isKindOfClass:[NSDictionary class]]) {
        [self validateObjectProperties:(NSDictionary *)value schema:schema errors:errors];
    }

    // Validate items for arrays
    if ([expectedType isEqualToString:@"array"] && [value isKindOfClass:[NSArray class]]) {
        [self validateArrayItems:(NSArray *)value schema:schema errors:errors];
    }

    // Validate string constraints
    if ([expectedType isEqualToString:@"string"] && [value isKindOfClass:[NSString class]]) {
        [self validateStringConstraints:(NSString *)value schema:schema errors:errors];
    }

    // Validate number constraints
    if (([expectedType isEqualToString:@"number"] || [expectedType isEqualToString:@"integer"]) &&
        [value isKindOfClass:[NSNumber class]]) {
        [self validateNumberConstraints:(NSNumber *)value schema:schema errors:errors];
    }

    // Check for validation errors
    if (errors.count > 0) {
        if (error) {
            if ([context hasPrefix:@"argument"]) {
                NSString *argumentName = [context stringByReplacingOccurrencesOfString:@"argument '" withString:@""];
                argumentName = [argumentName stringByReplacingOccurrencesOfString:@"'" withString:@""];
                *error = [CSSchemaValidationError mediaValidationError:argumentName
                                                         validationErrors:errors
                                                                    value:value];
            } else {
                *error = [CSSchemaValidationError outputValidationError:errors value:value];
            }
        }
        return NO;
    }

    return YES;
}

- (BOOL)validateValueType:(id)value expectedType:(NSString *)expectedType errors:(NSMutableArray<NSString *> *)errors {
    if ([expectedType isEqualToString:@"string"]) {
        if (![value isKindOfClass:[NSString class]]) {
            [errors addObject:[NSString stringWithFormat:@"Expected string but got %@", [value class]]];
            return NO;
        }
    } else if ([expectedType isEqualToString:@"integer"]) {
        if (![value isKindOfClass:[NSNumber class]] || ![self isInteger:(NSNumber *)value]) {
            [errors addObject:[NSString stringWithFormat:@"Expected integer but got %@", [value class]]];
            return NO;
        }
    } else if ([expectedType isEqualToString:@"number"]) {
        if (![value isKindOfClass:[NSNumber class]]) {
            [errors addObject:[NSString stringWithFormat:@"Expected number but got %@", [value class]]];
            return NO;
        }
    } else if ([expectedType isEqualToString:@"boolean"]) {
        if (![value isKindOfClass:[NSNumber class]] || ![self isBoolean:(NSNumber *)value]) {
            [errors addObject:[NSString stringWithFormat:@"Expected boolean but got %@", [value class]]];
            return NO;
        }
    } else if ([expectedType isEqualToString:@"array"]) {
        if (![value isKindOfClass:[NSArray class]]) {
            [errors addObject:[NSString stringWithFormat:@"Expected array but got %@", [value class]]];
            return NO;
        }
    } else if ([expectedType isEqualToString:@"object"]) {
        if (![value isKindOfClass:[NSDictionary class]]) {
            [errors addObject:[NSString stringWithFormat:@"Expected object but got %@", [value class]]];
            return NO;
        }
    }
    return YES;
}

- (void)validateObjectProperties:(NSDictionary *)object schema:(NSDictionary *)schema errors:(NSMutableArray<NSString *> *)errors {
    NSDictionary *properties = schema[@"properties"];
    NSArray *required = schema[@"required"];

    // Check required properties
    if (required) {
        for (NSString *requiredProp in required) {
            if (!object[requiredProp]) {
                [errors addObject:[NSString stringWithFormat:@"Missing required property '%@'", requiredProp]];
            }
        }
    }

    // Validate property types and constraints
    if (properties) {
        for (NSString *propName in object) {
            NSDictionary *propSchema = properties[propName];
            if (propSchema) {
                // Recursively validate property
                NSMutableArray *propErrors = [NSMutableArray array];
                if (![self validateValue:object[propName]
                          againstSchema:propSchema
                                context:[NSString stringWithFormat:@"property '%@'", propName]
                                  error:nil]) {
                    [errors addObject:[NSString stringWithFormat:@"Property '%@' validation failed", propName]];
                }
            }
        }
    }
}

- (void)validateArrayItems:(NSArray *)array schema:(NSDictionary *)schema errors:(NSMutableArray<NSString *> *)errors {
    NSDictionary *items = schema[@"items"];
    NSNumber *minItems = schema[@"minItems"];
    NSNumber *maxItems = schema[@"maxItems"];

    // Check array length constraints
    if (minItems && array.count < minItems.unsignedIntegerValue) {
        [errors addObject:[NSString stringWithFormat:@"Array must have at least %@ items but has %lu",
                         minItems, (unsigned long)array.count]];
    }

    if (maxItems && array.count > maxItems.unsignedIntegerValue) {
        [errors addObject:[NSString stringWithFormat:@"Array must have at most %@ items but has %lu",
                         maxItems, (unsigned long)array.count]];
    }

    // Validate each item
    if (items) {
        for (NSUInteger i = 0; i < array.count; i++) {
            NSMutableArray *itemErrors = [NSMutableArray array];
            if (![self validateValue:array[i]
                      againstSchema:items
                            context:[NSString stringWithFormat:@"array item %lu", (unsigned long)i]
                              error:nil]) {
                [errors addObject:[NSString stringWithFormat:@"Array item %lu validation failed", (unsigned long)i]];
            }
        }
    }
}

- (void)validateStringConstraints:(NSString *)string schema:(NSDictionary *)schema errors:(NSMutableArray<NSString *> *)errors {
    NSNumber *minLength = schema[@"minLength"];
    NSNumber *maxLength = schema[@"maxLength"];
    NSString *pattern = schema[@"pattern"];

    if (minLength && string.length < minLength.unsignedIntegerValue) {
        [errors addObject:[NSString stringWithFormat:@"String must be at least %@ characters but is %lu",
                         minLength, (unsigned long)string.length]];
    }

    if (maxLength && string.length > maxLength.unsignedIntegerValue) {
        [errors addObject:[NSString stringWithFormat:@"String must be at most %@ characters but is %lu",
                         maxLength, (unsigned long)string.length]];
    }

    if (pattern) {
        NSError *regexError;
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                               options:0
                                                                                 error:&regexError];
        if (regex) {
            NSUInteger matches = [regex numberOfMatchesInString:string
                                                        options:0
                                                          range:NSMakeRange(0, string.length)];
            if (matches == 0) {
                [errors addObject:[NSString stringWithFormat:@"String does not match pattern '%@'", pattern]];
            }
        } else {
            [errors addObject:[NSString stringWithFormat:@"Invalid regex pattern '%@': %@", pattern, regexError.localizedDescription]];
        }
    }
}

- (void)validateNumberConstraints:(NSNumber *)number schema:(NSDictionary *)schema errors:(NSMutableArray<NSString *> *)errors {
    NSNumber *minimum = schema[@"minimum"];
    NSNumber *maximum = schema[@"maximum"];
    NSNumber *multipleOf = schema[@"multipleOf"];

    if (minimum && [number compare:minimum] == NSOrderedAscending) {
        [errors addObject:[NSString stringWithFormat:@"Number must be >= %@ but is %@", minimum, number]];
    }

    if (maximum && [number compare:maximum] == NSOrderedDescending) {
        [errors addObject:[NSString stringWithFormat:@"Number must be <= %@ but is %@", maximum, number]];
    }

    if (multipleOf) {
        double quotient = number.doubleValue / multipleOf.doubleValue;
        if (fmod(quotient, 1.0) != 0.0) {
            [errors addObject:[NSString stringWithFormat:@"Number must be a multiple of %@", multipleOf]];
        }
    }
}

- (BOOL)isInteger:(NSNumber *)number {
    return strcmp([number objCType], @encode(int)) == 0 ||
           strcmp([number objCType], @encode(long)) == 0 ||
           strcmp([number objCType], @encode(long long)) == 0 ||
           strcmp([number objCType], @encode(unsigned int)) == 0 ||
           strcmp([number objCType], @encode(unsigned long)) == 0 ||
           strcmp([number objCType], @encode(unsigned long long)) == 0;
}

- (BOOL)isBoolean:(NSNumber *)number {
    return strcmp([number objCType], @encode(BOOL)) == 0 ||
           strcmp([number objCType], @encode(char)) == 0;
}

@end

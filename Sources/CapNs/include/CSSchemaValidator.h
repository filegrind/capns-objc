//
//  CSSchemaValidator.h
//  JSON Schema validation for Cap arguments and outputs
//
//  Provides comprehensive JSON Schema Draft-7 validation for structured data
//  in cap arguments and outputs. Supports both embedded schemas and external
//  schema references with proper error reporting.
//

#import <Foundation/Foundation.h>
#import "CSCap.h"

NS_ASSUME_NONNULL_BEGIN

/// Error domain for schema validation errors
FOUNDATION_EXPORT NSErrorDomain const CSSchemaValidationErrorDomain;

/// Schema validation error types
typedef NS_ENUM(NSInteger, CSSchemaValidationErrorType) {
    CSSchemaValidationErrorTypeArgumentValidation,
    CSSchemaValidationErrorTypeOutputValidation,
    CSSchemaValidationErrorTypeSchemaCompilation,
    CSSchemaValidationErrorTypeSchemaRefNotResolved,
    CSSchemaValidationErrorTypeInvalidJson,
    CSSchemaValidationErrorTypeUnsupportedSchemaVersion
};

/**
 * Schema validation error with detailed error information
 */
@interface CSSchemaValidationError : NSError

@property (nonatomic, readonly) CSSchemaValidationErrorType schemaErrorType;
@property (nonatomic, readonly, nullable) NSString *capUrn;
@property (nonatomic, readonly, nullable) NSString *argumentName;
@property (nonatomic, readonly, nullable) NSString *context;
@property (nonatomic, readonly, nullable) id value;
@property (nonatomic, readonly, nullable) NSArray<NSString *> *validationErrors;

+ (instancetype)argumentValidationError:(NSString *)argumentName 
                              validationErrors:(NSArray<NSString *> *)validationErrors
                                         value:(nullable id)value;

+ (instancetype)outputValidationError:(NSArray<NSString *> *)validationErrors
                                value:(nullable id)value;

+ (instancetype)schemaCompilationError:(NSString *)details
                                schema:(nullable id)schema;

+ (instancetype)schemaRefNotResolvedError:(NSString *)schemaRef
                                  context:(NSString *)context;

+ (instancetype)invalidJsonError:(NSString *)details
                           value:(nullable id)value;

+ (instancetype)unsupportedSchemaVersionError:(NSString *)version;

@end

/**
 * Schema resolver protocol for resolving external schema references
 */
@protocol CSSchemaResolver <NSObject>

/**
 * Resolve a schema reference to a JSON schema
 * @param schemaRef The schema reference to resolve
 * @return The resolved schema dictionary, or nil if not found
 * @throws NSError if resolution fails
 */
- (nullable NSDictionary *)resolveSchema:(NSString *)schemaRef error:(NSError **)error;

@end

/**
 * File-based schema resolver implementation
 */
@interface CSFileSchemaResolver : NSObject <CSSchemaResolver>

@property (nonatomic, readonly) NSString *basePath;

+ (instancetype)resolverWithBasePath:(NSString *)basePath;
- (instancetype)initWithBasePath:(NSString *)basePath;

@end

/**
 * JSON Schema Draft-7 validator for cap arguments and outputs
 */
@interface CSJSONSchemaValidator : NSObject

@property (nonatomic, strong, nullable) id<CSSchemaResolver> resolver;

/**
 * Create a new schema validator
 * @return A new CSJSONSchemaValidator instance
 */
+ (instancetype)validator;

/**
 * Create a new schema validator with a schema resolver
 * @param resolver The schema resolver to use for external references
 * @return A new CSJSONSchemaValidator instance
 */
+ (instancetype)validatorWithResolver:(id<CSSchemaResolver>)resolver;

/**
 * Validate an argument value against its schema
 * Schema is obtained by resolving the argument's mediaSpec to a MediaSpec with schema
 * @param argument The argument definition with mediaSpec
 * @param value The value to validate
 * @param mediaSpecs The mediaSpecs lookup table for spec ID resolution
 * @param error Pointer to NSError for error reporting
 * @return YES if validation succeeds, NO if it fails
 */
- (BOOL)validateArgument:(CSCapArg *)argument
               withValue:(id)value
              mediaSpecs:(NSDictionary *)mediaSpecs
                   error:(NSError **)error;

/**
 * Validate an output value against its schema
 * Schema is obtained by resolving the output's mediaSpec to a MediaSpec with schema
 * @param output The output definition with mediaSpec
 * @param value The value to validate
 * @param mediaSpecs The mediaSpecs lookup table for spec ID resolution
 * @param error Pointer to NSError for error reporting
 * @return YES if validation succeeds, NO if it fails
 */
- (BOOL)validateOutput:(CSCapOutput *)output
             withValue:(id)value
            mediaSpecs:(NSDictionary *)mediaSpecs
                 error:(NSError **)error;

/**
 * Validate all arguments for a capability
 * @param cap The capability with argument definitions
 * @param positionalArgs Array of positional argument values
 * @param namedArgs Dictionary of named argument values
 * @param error Pointer to NSError for error reporting
 * @return YES if validation succeeds, NO if it fails
 */
- (BOOL)validateArguments:(CSCap *)cap
          positionalArgs:(nullable NSArray *)positionalArgs
               namedArgs:(nullable NSDictionary<NSString *, id> *)namedArgs
                   error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
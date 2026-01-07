//
//  CSCapValidator.h
//  Cap schema validation for plugin interactions
//
//  This provides strict validation of inputs and outputs against
//  advertised cap schemas from plugins.
//

#import <Foundation/Foundation.h>
#import "CSCap.h"

NS_ASSUME_NONNULL_BEGIN

/// Error domain for validation errors
FOUNDATION_EXPORT NSErrorDomain const CSValidationErrorDomain;

/// Validation error types
typedef NS_ENUM(NSInteger, CSValidationErrorType) {
    CSValidationErrorTypeUnknownCap,
    CSValidationErrorTypeMissingRequiredArgument,
    CSValidationErrorTypeUnknownArgument,
    CSValidationErrorTypeInvalidArgumentType,
    CSValidationErrorTypeArgumentValidationFailed,
    CSValidationErrorTypeInvalidOutputType,
    CSValidationErrorTypeOutputValidationFailed,
    CSValidationErrorTypeInvalidCapSchema,
    CSValidationErrorTypeTooManyArguments,
    CSValidationErrorTypeJSONParseError,
    CSValidationErrorTypeSchemaValidationFailed
};

/// Validation error information
@interface CSValidationError : NSError

@property (nonatomic, readonly) CSValidationErrorType validationType;
@property (nonatomic, readonly, copy) NSString *capUrn;
@property (nonatomic, readonly, copy, nullable) NSString *argumentName;
@property (nonatomic, readonly, copy, nullable) NSString *validationRule;
@property (nonatomic, readonly, strong, nullable) id actualValue;
@property (nonatomic, readonly, copy, nullable) NSString *actualType;
@property (nonatomic, readonly, copy, nullable) NSString *expectedType;

+ (instancetype)unknownCapError:(NSString *)capUrn;
+ (instancetype)missingRequiredArgumentError:(NSString *)capUrn argumentName:(NSString *)argumentName;
+ (instancetype)unknownArgumentError:(NSString *)capUrn argumentName:(NSString *)argumentName;
+ (instancetype)invalidArgumentTypeError:(NSString *)capUrn
                            argumentName:(NSString *)argumentName
                            expectedType:(NSString *)expectedType
                              actualType:(NSString *)actualType
                             actualValue:(id)actualValue;
+ (instancetype)argumentValidationFailedError:(NSString *)capUrn
                                 argumentName:(NSString *)argumentName
                               validationRule:(NSString *)validationRule
                                  actualValue:(id)actualValue;
+ (instancetype)invalidOutputTypeError:(NSString *)capUrn
                          expectedType:(NSString *)expectedType
                            actualType:(NSString *)actualType
                           actualValue:(id)actualValue;
+ (instancetype)outputValidationFailedError:(NSString *)capUrn 
                             validationRule:(NSString *)validationRule 
                                actualValue:(id)actualValue;
+ (instancetype)invalidCapSchemaError:(NSString *)capUrn issue:(NSString *)issue;
+ (instancetype)tooManyArgumentsError:(NSString *)capUrn 
                          maxExpected:(NSInteger)maxExpected 
                          actualCount:(NSInteger)actualCount;
+ (instancetype)jsonParseError:(NSString *)capUrn error:(NSString *)error;
+ (instancetype)schemaValidationFailedError:(NSString *)capUrn 
                               argumentName:(nullable NSString *)argumentName 
                           underlyingError:(NSError *)underlyingError;

@end

/// Input argument validator
@interface CSInputValidator : NSObject

/// Validate positional arguments against cap input schema
+ (BOOL)validateArguments:(NSArray * _Nonnull)arguments 
               cap:(CSCap * _Nonnull)cap 
                    error:(NSError * _Nullable * _Nullable)error;

/// Validate named arguments against cap input schema
+ (BOOL)validateNamedArguments:(NSArray * _Nonnull)namedArguments 
                           cap:(CSCap * _Nonnull)cap 
                         error:(NSError * _Nullable * _Nullable)error;

@end

/// Output validator
@interface CSOutputValidator : NSObject

/// Validate output against cap output schema
+ (BOOL)validateOutput:(id _Nonnull)output 
            cap:(CSCap * _Nonnull)cap 
                 error:(NSError * _Nullable * _Nullable)error;

@end

/// Cap schema validator
@interface CSCapValidator : NSObject

/// Validate a cap definition itself
+ (BOOL)validateCap:(CSCap * _Nonnull)cap 
                     error:(NSError * _Nullable * _Nullable)error;

@end

/// Main validation coordinator that orchestrates input and output validation
@interface CSSchemaValidator : NSObject

/// Register a cap schema for validation
- (void)registerCap:(CSCap * _Nonnull)cap;

/// Get a cap by ID
- (nullable CSCap *)getCap:(NSString * _Nonnull)capUrn;

/// Validate arguments against a cap's input schema
- (BOOL)validateInputs:(NSArray * _Nonnull)arguments 
          capUrn:(NSString * _Nonnull)capUrn 
                 error:(NSError * _Nullable * _Nullable)error;

/// Validate output against a cap's output schema
- (BOOL)validateOutput:(id _Nonnull)output 
          capUrn:(NSString * _Nonnull)capUrn 
                 error:(NSError * _Nullable * _Nullable)error;

/// Validate binary output against a cap's output schema
- (BOOL)validateBinaryOutput:(NSData * _Nonnull)outputData 
                capUrn:(NSString * _Nonnull)capUrn 
                       error:(NSError * _Nullable * _Nullable)error;

/// Validate a cap definition itself  
- (BOOL)validateCapSchema:(CSCap * _Nonnull)cap 
                           error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
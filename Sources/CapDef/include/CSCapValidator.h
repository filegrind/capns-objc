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
    CSValidationErrorTypeInvalidArgumentType,
    CSValidationErrorTypeArgumentValidationFailed,
    CSValidationErrorTypeInvalidOutputType,
    CSValidationErrorTypeOutputValidationFailed,
    CSValidationErrorTypeInvalidCapSchema,
    CSValidationErrorTypeTooManyArguments,
    CSValidationErrorTypeJSONParseError
};

/// Validation error information
@interface CSValidationError : NSError

@property (nonatomic, readonly) CSValidationErrorType validationType;
@property (nonatomic, readonly, copy) NSString *capCard;
@property (nonatomic, readonly, copy, nullable) NSString *argumentName;
@property (nonatomic, readonly, copy, nullable) NSString *validationRule;
@property (nonatomic, readonly, strong, nullable) id actualValue;
@property (nonatomic, readonly, copy, nullable) NSString *actualType;
@property (nonatomic, readonly, copy, nullable) NSString *expectedType;

+ (instancetype)unknownCapError:(NSString *)capCard;
+ (instancetype)missingRequiredArgumentError:(NSString *)capCard argumentName:(NSString *)argumentName;
+ (instancetype)invalidArgumentTypeError:(NSString *)capCard 
                            argumentName:(NSString *)argumentName 
                            expectedType:(CSArgumentType)expectedType 
                              actualType:(NSString *)actualType 
                             actualValue:(id)actualValue;
+ (instancetype)argumentValidationFailedError:(NSString *)capCard 
                                 argumentName:(NSString *)argumentName 
                               validationRule:(NSString *)validationRule 
                                  actualValue:(id)actualValue;
+ (instancetype)invalidOutputTypeError:(NSString *)capCard 
                          expectedType:(CSOutputType)expectedType 
                            actualType:(NSString *)actualType 
                           actualValue:(id)actualValue;
+ (instancetype)outputValidationFailedError:(NSString *)capCard 
                             validationRule:(NSString *)validationRule 
                                actualValue:(id)actualValue;
+ (instancetype)invalidCapSchemaError:(NSString *)capCard issue:(NSString *)issue;
+ (instancetype)tooManyArgumentsError:(NSString *)capCard 
                          maxExpected:(NSInteger)maxExpected 
                          actualCount:(NSInteger)actualCount;
+ (instancetype)jsonParseError:(NSString *)capCard error:(NSString *)error;

@end

/// Input argument validator
@interface CSInputValidator : NSObject

/// Validate arguments against cap input schema
+ (BOOL)validateArguments:(NSArray * _Nonnull)arguments 
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
- (nullable CSCap *)getCap:(NSString * _Nonnull)capCard;

/// Validate arguments against a cap's input schema
- (BOOL)validateInputs:(NSArray * _Nonnull)arguments 
          capCard:(NSString * _Nonnull)capCard 
                 error:(NSError * _Nullable * _Nullable)error;

/// Validate output against a cap's output schema
- (BOOL)validateOutput:(id _Nonnull)output 
          capCard:(NSString * _Nonnull)capCard 
                 error:(NSError * _Nullable * _Nullable)error;

/// Validate binary output against a cap's output schema
- (BOOL)validateBinaryOutput:(NSData * _Nonnull)outputData 
                capCard:(NSString * _Nonnull)capCard 
                       error:(NSError * _Nullable * _Nullable)error;

/// Validate a cap definition itself  
- (BOOL)validateCapSchema:(CSCap * _Nonnull)cap 
                           error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
//
//  CSCapabilityValidator.h
//  Capability schema validation for plugin interactions
//
//  This provides strict validation of inputs and outputs against
//  advertised capability schemas from plugins.
//

#import <Foundation/Foundation.h>
#import "CSCapability.h"

NS_ASSUME_NONNULL_BEGIN

/// Error domain for validation errors
FOUNDATION_EXPORT NSErrorDomain const CSValidationErrorDomain;

/// Validation error types
typedef NS_ENUM(NSInteger, CSValidationErrorType) {
    CSValidationErrorTypeUnknownCapability,
    CSValidationErrorTypeMissingRequiredArgument,
    CSValidationErrorTypeInvalidArgumentType,
    CSValidationErrorTypeArgumentValidationFailed,
    CSValidationErrorTypeInvalidOutputType,
    CSValidationErrorTypeOutputValidationFailed,
    CSValidationErrorTypeInvalidCapabilitySchema,
    CSValidationErrorTypeTooManyArguments,
    CSValidationErrorTypeJSONParseError
};

/// Validation error information
@interface CSValidationError : NSError

@property (nonatomic, readonly) CSValidationErrorType validationType;
@property (nonatomic, readonly, copy) NSString *capabilityId;
@property (nonatomic, readonly, copy, nullable) NSString *argumentName;
@property (nonatomic, readonly, copy, nullable) NSString *validationRule;
@property (nonatomic, readonly, strong, nullable) id actualValue;
@property (nonatomic, readonly, copy, nullable) NSString *actualType;
@property (nonatomic, readonly, copy, nullable) NSString *expectedType;

+ (instancetype)unknownCapabilityError:(NSString *)capabilityId;
+ (instancetype)missingRequiredArgumentError:(NSString *)capabilityId argumentName:(NSString *)argumentName;
+ (instancetype)invalidArgumentTypeError:(NSString *)capabilityId 
                            argumentName:(NSString *)argumentName 
                            expectedType:(CSArgumentType)expectedType 
                              actualType:(NSString *)actualType 
                             actualValue:(id)actualValue;
+ (instancetype)argumentValidationFailedError:(NSString *)capabilityId 
                                 argumentName:(NSString *)argumentName 
                               validationRule:(NSString *)validationRule 
                                  actualValue:(id)actualValue;
+ (instancetype)invalidOutputTypeError:(NSString *)capabilityId 
                          expectedType:(CSOutputType)expectedType 
                            actualType:(NSString *)actualType 
                           actualValue:(id)actualValue;
+ (instancetype)outputValidationFailedError:(NSString *)capabilityId 
                             validationRule:(NSString *)validationRule 
                                actualValue:(id)actualValue;
+ (instancetype)invalidCapabilitySchemaError:(NSString *)capabilityId issue:(NSString *)issue;
+ (instancetype)tooManyArgumentsError:(NSString *)capabilityId 
                          maxExpected:(NSInteger)maxExpected 
                          actualCount:(NSInteger)actualCount;
+ (instancetype)jsonParseError:(NSString *)capabilityId error:(NSString *)error;

@end

/// Input argument validator
@interface CSInputValidator : NSObject

/// Validate arguments against capability input schema
+ (BOOL)validateArguments:(NSArray * _Nonnull)arguments 
               capability:(CSCapability * _Nonnull)capability 
                    error:(NSError * _Nullable * _Nullable)error;

@end

/// Output validator
@interface CSOutputValidator : NSObject

/// Validate output against capability output schema
+ (BOOL)validateOutput:(id _Nonnull)output 
            capability:(CSCapability * _Nonnull)capability 
                 error:(NSError * _Nullable * _Nullable)error;

@end

/// Capability schema validator
@interface CSCapabilityValidator : NSObject

/// Validate a capability definition itself
+ (BOOL)validateCapability:(CSCapability * _Nonnull)capability 
                     error:(NSError * _Nullable * _Nullable)error;

@end

/// Main validation coordinator that orchestrates input and output validation
@interface CSSchemaValidator : NSObject

/// Register a capability schema for validation
- (void)registerCapability:(CSCapability * _Nonnull)capability;

/// Get a capability by ID
- (nullable CSCapability *)getCapability:(NSString * _Nonnull)capabilityId;

/// Validate arguments against a capability's input schema
- (BOOL)validateInputs:(NSArray * _Nonnull)arguments 
          capabilityId:(NSString * _Nonnull)capabilityId 
                 error:(NSError * _Nullable * _Nullable)error;

/// Validate output against a capability's output schema
- (BOOL)validateOutput:(id _Nonnull)output 
          capabilityId:(NSString * _Nonnull)capabilityId 
                 error:(NSError * _Nullable * _Nullable)error;

/// Validate a capability definition itself  
- (BOOL)validateCapabilitySchema:(CSCapability * _Nonnull)capability 
                           error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
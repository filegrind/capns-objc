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
+ (BOOL)validateArguments:(NSArray *)arguments 
               capability:(CSCapability *)capability 
                    error:(NSError **)error;

@end

/// Output validator
@interface CSOutputValidator : NSObject

/// Validate output against capability output schema
+ (BOOL)validateOutput:(id)output 
            capability:(CSCapability *)capability 
                 error:(NSError **)error;

@end

/// Capability schema validator
@interface CSCapabilityValidator : NSObject

/// Validate a capability definition itself
+ (BOOL)validateCapability:(CSCapability *)capability 
                     error:(NSError **)error;

@end

/// Main validation coordinator that orchestrates input and output validation
@interface CSSchemaValidator : NSObject

/// Register a capability schema for validation
- (void)registerCapability:(CSCapability *)capability;

/// Get a capability by ID
- (nullable CSCapability *)getCapability:(NSString *)capabilityId;

/// Validate arguments against a capability's input schema
- (BOOL)validateInputs:(NSArray *)arguments 
          capabilityId:(NSString *)capabilityId 
                 error:(NSError **)error;

/// Validate output against a capability's output schema
- (BOOL)validateOutput:(id)output 
          capabilityId:(NSString *)capabilityId 
                 error:(NSError **)error;

/// Validate a capability definition itself  
- (BOOL)validateCapabilitySchema:(CSCapability *)capability 
                           error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
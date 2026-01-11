//
//  CSCap.h
//  Formal cap definition
//
//  This defines the structure for formal cap definitions that include
//  the cap URN, versioning, and metadata. Caps are general-purpose
//  and do not assume any specific domain like files or documents.
//
//  NOTE: ArgumentType and OutputType enums have been REMOVED.
//  All type information is now conveyed via mediaSpec fields that
//  contain spec IDs (e.g., "std:str.v1") which resolve to
//  MediaSpec definitions via the mediaSpecs table.
//

#import <Foundation/Foundation.h>
#import "CSCapUrn.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Argument validation rules
 */
@interface CSArgumentValidation : NSObject <NSCopying, NSCoding>

@property (nonatomic, readonly, nullable) NSNumber *min;
@property (nonatomic, readonly, nullable) NSNumber *max;
@property (nonatomic, readonly, nullable) NSNumber *minLength;
@property (nonatomic, readonly, nullable) NSNumber *maxLength;
@property (nonatomic, readonly, nullable) NSString *pattern;
@property (nonatomic, readonly, nullable) NSArray<NSString *> *allowedValues;

+ (instancetype)validationWithMin:(nullable NSNumber *)min
                              max:(nullable NSNumber *)max
                        minLength:(nullable NSNumber *)minLength
                        maxLength:(nullable NSNumber *)maxLength
                          pattern:(nullable NSString *)pattern
                    allowedValues:(nullable NSArray<NSString *> *)allowedValues;
+ (instancetype)validationWithDictionary:(NSDictionary * _Nonnull)dictionary error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(init(dictionary:error:));

/**
 * Convert validation to dictionary representation
 * @return Dictionary representation of the validation
 */
- (NSDictionary * _Nonnull)toDictionary;

@end

/**
 * Cap argument definition
 *
 * NOTE: argType enum has been replaced with mediaSpec string field.
 * The mediaSpec contains a spec ID (e.g., "std:str.v1") that resolves
 * to a MediaSpec definition. Schema is now stored in the cap's mediaSpecs table.
 */
@interface CSCapArgument : NSObject <NSCopying, NSCoding>

@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) NSString *mediaSpec;  // Spec ID (e.g., "std:str.v1")
@property (nonatomic, readonly) NSString *argDescription;
@property (nonatomic, readonly) NSString *cliFlag;
@property (nonatomic, readonly, nullable) NSNumber *position;
@property (nonatomic, readonly, nullable) CSArgumentValidation *validation;
@property (nonatomic, readonly, nullable) id defaultValue;
@property (nonatomic, readonly, nullable) NSDictionary *metadata;

/**
 * Create an argument with spec ID
 * @param name Argument name
 * @param mediaSpec Spec ID (e.g., "std:str.v1")
 * @param argDescription Argument description
 * @param cliFlag CLI flag
 * @param position Optional position for positional arguments
 * @param validation Optional validation rules
 * @param defaultValue Optional default value
 * @return A new CSCapArgument instance
 */
+ (instancetype)argumentWithName:(NSString * _Nonnull)name
                       mediaSpec:(NSString * _Nonnull)mediaSpec
                   argDescription:(NSString * _Nonnull)argDescription
                         cliFlag:(NSString * _Nonnull)cliFlag
                        position:(nullable NSNumber *)position
                      validation:(nullable CSArgumentValidation *)validation
                    defaultValue:(nullable id)defaultValue;

+ (instancetype)argumentWithDictionary:(NSDictionary * _Nonnull)dictionary error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(init(dictionary:error:));

/**
 * Convert argument to dictionary representation
 * @return Dictionary representation of the argument
 */
- (NSDictionary * _Nonnull)toDictionary;

/**
 * Get the metadata JSON
 * @return The metadata JSON dictionary or nil
 */
- (nullable NSDictionary *)getMetadata;

/**
 * Set the metadata JSON
 * @param metadata The metadata JSON dictionary
 */
- (void)setMetadata:(nullable NSDictionary *)metadata;

/**
 * Clear the metadata JSON
 */
- (void)clearMetadata;

@end

/**
 * Cap arguments collection
 */
@interface CSCapArguments : NSObject <NSCopying, NSCoding>

@property (nonatomic, readonly) NSArray<CSCapArgument *> *required;
@property (nonatomic, readonly) NSArray<CSCapArgument *> *optional;

+ (instancetype)arguments;
+ (instancetype)argumentsWithRequired:(NSArray<CSCapArgument *> * _Nonnull)required
                             optional:(NSArray<CSCapArgument *> * _Nonnull)optional;
+ (instancetype)argumentsWithDictionary:(NSDictionary * _Nonnull)dictionary error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(init(dictionary:error:));

/**
 * Convert arguments to dictionary representation
 * @return Dictionary representation of the arguments
 */
- (NSDictionary * _Nonnull)toDictionary;

- (void)addRequiredArgument:(CSCapArgument * _Nonnull)argument;
- (void)addOptionalArgument:(CSCapArgument * _Nonnull)argument;
- (nullable CSCapArgument *)findArgumentWithName:(NSString * _Nonnull)name;
- (NSArray<CSCapArgument *> *)positionalArguments;
- (NSArray<CSCapArgument *> *)flagArguments;
- (BOOL)isEmpty;

@end


/**
 * Output definition
 *
 * NOTE: outputType enum has been replaced with mediaSpec string field.
 * The mediaSpec contains a spec ID (e.g., "std:obj.v1") that resolves
 * to a MediaSpec definition. Schema is now stored in the cap's mediaSpecs table.
 */
@interface CSCapOutput : NSObject <NSCopying, NSCoding>

@property (nonatomic, readonly) NSString *mediaSpec;  // Spec ID (e.g., "std:obj.v1")
@property (nonatomic, readonly, nullable) CSArgumentValidation *validation;
@property (nonatomic, readonly) NSString *outputDescription;
@property (nonatomic, readonly, nullable) NSDictionary *metadata;

/**
 * Create an output with spec ID
 * @param mediaSpec Spec ID (e.g., "std:obj.v1")
 * @param validation Optional validation rules
 * @param outputDescription Description of the output
 * @return A new CSCapOutput instance
 */
+ (instancetype)outputWithMediaSpec:(NSString * _Nonnull)mediaSpec
                         validation:(nullable CSArgumentValidation *)validation
                  outputDescription:(NSString * _Nonnull)outputDescription;

+ (instancetype)outputWithDictionary:(NSDictionary * _Nonnull)dictionary error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(init(dictionary:error:));

/**
 * Convert output to dictionary representation
 * @return Dictionary representation of the output
 */
- (NSDictionary * _Nonnull)toDictionary;

/**
 * Get the metadata JSON
 * @return The metadata JSON dictionary or nil
 */
- (nullable NSDictionary *)getMetadata;

/**
 * Set the metadata JSON
 * @param metadata The metadata JSON dictionary
 */
- (void)setMetadata:(nullable NSDictionary *)metadata;

/**
 * Clear the metadata JSON
 */
- (void)clearMetadata;

@end

/**
 * Registration attribution - who registered a capability and when
 */
@interface CSRegisteredBy : NSObject <NSCopying, NSCoding>

/// Username of the user who registered this capability
@property (nonatomic, readonly) NSString *username;

/// ISO 8601 timestamp of when the capability was registered
@property (nonatomic, readonly) NSString *registeredAt;

/**
 * Create a new registration attribution
 * @param username The username of the user who registered this capability
 * @param registeredAt ISO 8601 timestamp of when the capability was registered
 * @return A new CSRegisteredBy instance
 */
+ (instancetype)registeredByWithUsername:(NSString *)username
                            registeredAt:(NSString *)registeredAt;

/**
 * Create from a dictionary representation
 * @param dictionary The dictionary containing registration data
 * @param error Error pointer for validation errors
 * @return A new CSRegisteredBy instance or nil on error
 */
+ (nullable instancetype)registeredByWithDictionary:(NSDictionary *)dictionary
                                              error:(NSError * _Nullable * _Nullable)error;

/**
 * Convert to dictionary representation
 * @return Dictionary representation of the registration attribution
 */
- (NSDictionary *)toDictionary;

@end

@class CSMediaSpec;

/**
 * Formal cap definition
 *
 * The mediaSpecs property is a resolution table that maps spec IDs to MediaSpec definitions.
 * Arguments and output use spec IDs in their mediaSpec fields, which resolve via this table.
 */
@interface CSCap : NSObject <NSCopying, NSCoding>

/// Formal cap URN with hierarchical naming
@property (nonatomic, readonly) CSCapUrn *capUrn;

/// Human-readable title of the capability (required)
@property (nonatomic, readonly) NSString *title;

/// Optional description
@property (nonatomic, readonly, nullable) NSString *capDescription;

/// Optional metadata as key-value pairs
@property (nonatomic, readonly) NSDictionary<NSString *, NSString *> *metadata;

/// Command string for CLI execution
@property (nonatomic, readonly) NSString *command;

/// Media specs resolution table: maps spec ID -> string or object definition
/// String form: "text/plain; profile=https://..." (canonical)
/// Object form: { media_type, profile_uri, schema? }
@property (nonatomic, readonly) NSDictionary<NSString *, id> *mediaSpecs;

/// Cap arguments
@property (nonatomic, readonly) CSCapArguments *arguments;

/// Output definition
@property (nonatomic, readonly, nullable) CSCapOutput *output;

/// Whether this cap accepts input via stdin
@property (nonatomic, readonly) BOOL acceptsStdin;

/// Arbitrary metadata as JSON object
@property (nonatomic, readonly, nullable) NSDictionary *metadataJSON;

/// Registration attribution - who registered this capability and when
@property (nonatomic, readonly, nullable) CSRegisteredBy *registeredBy;


/**
 * Create a fully specified cap
 * @param capUrn The cap URN
 * @param title The human-readable title (required)
 * @param command The command string
 * @param description The cap description
 * @param metadata The cap metadata
 * @param mediaSpecs Media spec resolution table (spec ID -> definition)
 * @param arguments The cap arguments
 * @param output The output definition
 * @param acceptsStdin Whether this cap accepts stdin input
 * @param metadataJSON Arbitrary metadata as JSON object
 * @return A new CSCap instance
 */
+ (instancetype)capWithUrn:(CSCapUrn * _Nonnull)capUrn
                     title:(NSString * _Nonnull)title
                   command:(NSString * _Nonnull)command
               description:(nullable NSString *)description
                  metadata:(NSDictionary<NSString *, NSString *> * _Nonnull)metadata
                mediaSpecs:(NSDictionary<NSString *, id> * _Nonnull)mediaSpecs
                 arguments:(CSCapArguments * _Nonnull)arguments
                    output:(nullable CSCapOutput *)output
              acceptsStdin:(BOOL)acceptsStdin
              metadataJSON:(nullable NSDictionary *)metadataJSON;

/**
 * Create a cap with URN, title and command (minimal constructor)
 * @param capUrn The cap URN
 * @param title The human-readable title (required)
 * @param command The command string
 * @return A new CSCap instance
 */
+ (instancetype)capWithUrn:(CSCapUrn * _Nonnull)capUrn
                     title:(NSString * _Nonnull)title
                   command:(NSString * _Nonnull)command;

/**
 * Create a cap from a dictionary representation
 * @param dictionary The dictionary containing cap data
 * @param error Pointer to NSError for error reporting
 * @return A new CSCap instance, or nil if parsing fails
 */
+ (instancetype)capWithDictionary:(NSDictionary * _Nonnull)dictionary error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(init(dictionary:error:));

/**
 * Convert cap to dictionary representation
 * @return Dictionary representation of the cap
 */
- (NSDictionary * _Nonnull)toDictionary;


/**
 * Check if this cap matches a request string
 * @param request The request string
 * @return YES if this cap matches the request
 */
- (BOOL)matchesRequest:(NSString * _Nonnull)request;

/**
 * Check if this cap can handle a request
 * @param request The request cap URN
 * @return YES if this cap can handle the request
 */
- (BOOL)canHandleRequest:(CSCapUrn * _Nonnull)request;

/**
 * Check if this cap is more specific than another
 * @param other The other cap to compare with
 * @return YES if this cap is more specific
 */
- (BOOL)isMoreSpecificThan:(CSCap * _Nonnull)other;

/**
 * Get a metadata value by key
 * @param key The metadata key
 * @return The metadata value or nil if not found
 */
- (nullable NSString *)metadataForKey:(NSString * _Nonnull)key;

/**
 * Check if this cap has specific metadata
 * @param key The metadata key to check
 * @return YES if the metadata key exists
 */
- (BOOL)hasMetadataForKey:(NSString * _Nonnull)key;

/**
 * Get the cap URN as a string
 * @return The cap URN string
 */
- (NSString *)urnString;

/**
 * Get the command if defined
 * @return The command string or nil
 */
- (nullable NSString *)getCommand;

/**
 * Get the arguments
 * @return The cap arguments
 */
- (CSCapArguments *)getArguments;

/**
 * Get the output definition if defined
 * @return The output definition or nil
 */
- (nullable CSCapOutput *)getOutput;

/**
 * Add a required argument
 * @param argument The argument to add
 */
- (void)addRequiredArgument:(CSCapArgument * _Nonnull)argument;

/**
 * Add an optional argument
 * @param argument The argument to add
 */
- (void)addOptionalArgument:(CSCapArgument * _Nonnull)argument;

/**
 * Get the metadata JSON
 * @return The metadata JSON dictionary or nil
 */
- (nullable NSDictionary *)getMetadataJSON;

/**
 * Set the metadata JSON
 * @param metadata The metadata JSON dictionary
 */
- (void)setMetadataJSON:(nullable NSDictionary *)metadata;

/**
 * Clear the metadata JSON
 */
- (void)clearMetadataJSON;

/**
 * Resolve a spec ID to a MediaSpec using this cap's mediaSpecs table
 * @param specId The spec ID (e.g., "std:str.v1")
 * @param error Error if spec ID cannot be resolved
 * @return The resolved MediaSpec or nil on error
 */
- (nullable CSMediaSpec *)resolveSpecId:(NSString * _Nonnull)specId error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
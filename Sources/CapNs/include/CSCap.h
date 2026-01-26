//
//  CSCap.h
//  Formal cap definition
//
//  This defines the structure for formal cap definitions that include
//  the cap URN, versioning, and metadata. Caps are general-purpose
//  and do not assume any specific domain like files or documents.
//
//  NOTE: All type information is conveyed via mediaSpec fields that
//  contain spec IDs (e.g., "media:string") which resolve to
//  MediaSpec definitions via the mediaSpecs table.
//

#import <Foundation/Foundation.h>
#import "CSCapUrn.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Media validation rules
 */
@interface CSMediaValidation : NSObject <NSCopying, NSCoding>

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

#pragma mark - CSArgSource

/**
 * Source type enum for CSArgSource
 */
typedef NS_ENUM(NSInteger, CSArgSourceType) {
    CSArgSourceTypeStdin,
    CSArgSourceTypePosition,
    CSArgSourceTypeCliFlag
};

/**
 * Specifies how an argument can be provided
 */
@interface CSArgSource : NSObject <NSCopying, NSCoding>

/// The type of this source
@property (nonatomic, readonly) CSArgSourceType type;

/// For stdin type - the media URN expected on stdin
@property (nonatomic, readonly, nullable) NSString *stdinMediaUrn;

/// For position type - the positional index (-1 if not set)
@property (nonatomic, readonly) NSInteger position;

/// For cli_flag type - the CLI flag string
@property (nonatomic, readonly, nullable) NSString *cliFlag;

/**
 * Create a stdin source
 * @param mediaUrn The media URN expected on stdin
 * @return A new CSArgSource instance
 */
+ (instancetype)stdinSourceWithMediaUrn:(NSString *)mediaUrn;

/**
 * Create a position source
 * @param position The positional index
 * @return A new CSArgSource instance
 */
+ (instancetype)positionSource:(NSInteger)position;

/**
 * Create a cli_flag source
 * @param cliFlag The CLI flag string
 * @return A new CSArgSource instance
 */
+ (instancetype)cliFlagSource:(NSString *)cliFlag;

/**
 * Create from dictionary representation
 * @param dictionary The dictionary containing source data
 * @param error Pointer to NSError for error reporting
 * @return A new CSArgSource instance, or nil if parsing fails
 */
+ (nullable instancetype)sourceWithDictionary:(NSDictionary *)dictionary error:(NSError * _Nullable * _Nullable)error;

/**
 * Convert to dictionary representation
 * @return Dictionary representation of the source
 */
- (NSDictionary *)toDictionary;

/**
 * Check if this is a stdin source
 */
- (BOOL)isStdin;

/**
 * Check if this is a position source
 */
- (BOOL)isPosition;

/**
 * Check if this is a cli_flag source
 */
- (BOOL)isCliFlag;

@end

#pragma mark - CSCapArg

/**
 * Unified argument definition with sources
 */
@interface CSCapArg : NSObject <NSCopying, NSCoding>

/// Unique identifier (media URN)
@property (nonatomic, readonly) NSString *mediaUrn;

/// Whether this argument is required
@property (nonatomic, readonly) BOOL required;

/// Array of sources for this argument
@property (nonatomic, readonly) NSArray<CSArgSource *> *sources;

/// Optional description
@property (nonatomic, readonly, nullable) NSString *argDescription;

/// Optional default value
@property (nonatomic, readonly, nullable) id defaultValue;

/// Optional metadata
@property (nonatomic, readonly, nullable) NSDictionary *metadata;

/**
 * Create an argument with minimal fields
 * @param mediaUrn The media URN identifier
 * @param required Whether this argument is required
 * @param sources Array of sources
 * @return A new CSCapArg instance
 */
+ (instancetype)argWithMediaUrn:(NSString *)mediaUrn
                       required:(BOOL)required
                        sources:(NSArray<CSArgSource *> *)sources;

/**
 * Create an argument with all fields
 * @param mediaUrn The media URN identifier
 * @param required Whether this argument is required
 * @param sources Array of sources
 * @param argDescription Optional description
 * @param defaultValue Optional default value
 * @return A new CSCapArg instance
 */
+ (instancetype)argWithMediaUrn:(NSString *)mediaUrn
                       required:(BOOL)required
                        sources:(NSArray<CSArgSource *> *)sources
                 argDescription:(nullable NSString *)argDescription
                   defaultValue:(nullable id)defaultValue;

/**
 * Create from dictionary representation
 * @param dictionary The dictionary containing argument data
 * @param error Pointer to NSError for error reporting
 * @return A new CSCapArg instance, or nil if parsing fails
 */
+ (nullable instancetype)argWithDictionary:(NSDictionary *)dictionary error:(NSError * _Nullable * _Nullable)error;

/**
 * Convert to dictionary representation
 * @return Dictionary representation of the argument
 */
- (NSDictionary *)toDictionary;

/**
 * Check if this argument has a stdin source
 */
- (BOOL)hasStdinSource;

/**
 * Get the stdin media URN if present
 * @return The stdin media URN or nil
 */
- (nullable NSString *)getStdinMediaUrn;

/**
 * Check if this argument has a position source
 */
- (BOOL)hasPositionSource;

/**
 * Get the position if present
 * @return The position as NSNumber or nil
 */
- (nullable NSNumber *)getPosition;

/**
 * Check if this argument has a cli_flag source
 */
- (BOOL)hasCliFlagSource;

/**
 * Get the cli_flag if present
 * @return The cli_flag or nil
 */
- (nullable NSString *)getCliFlag;

/**
 * Get the metadata
 * @return The metadata dictionary or nil
 */
- (nullable NSDictionary *)getMetadata;

/**
 * Set the metadata
 * @param metadata The metadata dictionary
 */
- (void)setMetadata:(nullable NSDictionary *)metadata;

/**
 * Clear the metadata
 */
- (void)clearMetadata;

@end

#pragma mark - CSCapOutput

/**
 * Output definition
 */
@interface CSCapOutput : NSObject <NSCopying, NSCoding>

@property (nonatomic, readonly) NSString *mediaUrn;
@property (nonatomic, readonly) NSString *outputDescription;
@property (nonatomic, readonly, nullable) NSDictionary *metadata;

/**
 * Create an output with media URN
 * @param mediaUrn Media URN (e.g., "media:object")
 * @param outputDescription Description of the output
 * @return A new CSCapOutput instance
 */
+ (instancetype)outputWithMediaUrn:(NSString * _Nonnull)mediaUrn
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

#pragma mark - CSRegisteredBy

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

#pragma mark - CSCap

/**
 * Formal cap definition
 *
 * The mediaSpecs property is a resolution table that maps spec IDs to MediaSpec definitions.
 * Arguments and output use spec IDs in their mediaUrn fields, which resolve via this table.
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
@property (nonatomic, readonly) NSDictionary<NSString *, id> *mediaSpecs;

/// Cap arguments (new unified args array)
@property (nonatomic, readonly) NSArray<CSCapArg *> *args;

/// Output definition
@property (nonatomic, readonly, nullable) CSCapOutput *output;

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
 * @param args The cap arguments array
 * @param output The output definition
 * @param metadataJSON Arbitrary metadata as JSON object
 * @return A new CSCap instance
 */
+ (instancetype)capWithUrn:(CSCapUrn * _Nonnull)capUrn
                     title:(NSString * _Nonnull)title
                   command:(NSString * _Nonnull)command
               description:(nullable NSString *)description
                  metadata:(NSDictionary<NSString *, NSString *> * _Nonnull)metadata
                mediaSpecs:(NSDictionary<NSString *, id> * _Nonnull)mediaSpecs
                      args:(NSArray<CSCapArg *> * _Nonnull)args
                    output:(nullable CSCapOutput *)output
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
 * Get the output definition if defined
 * @return The output definition or nil
 */
- (nullable CSCapOutput *)getOutput;

/**
 * Get all arguments
 * @return Array of all arguments
 */
- (NSArray<CSCapArg *> *)getArgs;

/**
 * Get required arguments
 * @return Array of required arguments
 */
- (NSArray<CSCapArg *> *)getRequiredArgs;

/**
 * Get optional arguments
 * @return Array of optional arguments
 */
- (NSArray<CSCapArg *> *)getOptionalArgs;

/**
 * Add an argument
 * @param arg The argument to add
 */
- (void)addArg:(CSCapArg * _Nonnull)arg;

/**
 * Find an argument by media URN
 * @param mediaUrn The media URN to find
 * @return The argument or nil if not found
 */
- (nullable CSCapArg *)findArgByMediaUrn:(NSString * _Nonnull)mediaUrn;

/**
 * Get positional arguments (sorted by position)
 * @return Array of arguments with position sources
 */
- (NSArray<CSCapArg *> *)getPositionalArgs;

/**
 * Get flag arguments
 * @return Array of arguments with cli_flag sources
 */
- (NSArray<CSCapArg *> *)getFlagArgs;

/**
 * Get stdin media URN from args (first stdin source found)
 * @return The stdin media URN or nil
 */
- (nullable NSString *)getStdinMediaUrn;

/**
 * Check if this cap accepts stdin
 * @return YES if any argument has a stdin source
 */
- (BOOL)acceptsStdin;

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
 * @param specId The spec ID (e.g., "media:string")
 * @param error Error if spec ID cannot be resolved
 * @return The resolved MediaSpec or nil on error
 */
- (nullable CSMediaSpec *)resolveSpecId:(NSString * _Nonnull)specId error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END

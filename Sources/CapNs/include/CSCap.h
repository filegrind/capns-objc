//
//  CSCap.h
//  Formal cap definition
//
//  This defines the structure for formal cap definitions that include
//  the cap URN, versioning, and metadata. Caps are general-purpose
//  and do not assume any specific domain like files or documents.
//

#import <Foundation/Foundation.h>
#import "CSCapUrn.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Argument type enumeration
 */
typedef NS_ENUM(NSInteger, CSArgumentType) {
    CSArgumentTypeString,
    CSArgumentTypeInteger,
    CSArgumentTypeNumber,
    CSArgumentTypeBoolean,
    CSArgumentTypeArray,
    CSArgumentTypeObject,
    CSArgumentTypeBinary
};

/**
 * Output type enumeration
 */
typedef NS_ENUM(NSInteger, CSOutputType) {
    CSOutputTypeString,
    CSOutputTypeInteger,
    CSOutputTypeNumber,
    CSOutputTypeBoolean,
    CSOutputTypeArray,
    CSOutputTypeObject,
    CSOutputTypeBinary
};

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
 */
@interface CSCapArgument : NSObject <NSCopying, NSCoding>

@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) CSArgumentType argType;
@property (nonatomic, readonly) NSString *argDescription;
@property (nonatomic, readonly) NSString *cliFlag;
@property (nonatomic, readonly, nullable) NSNumber *position;
@property (nonatomic, readonly, nullable) CSArgumentValidation *validation;
@property (nonatomic, readonly, nullable) id defaultValue;
@property (nonatomic, readonly, nullable) NSString *schemaRef;
@property (nonatomic, readonly, nullable) NSDictionary *schema;
@property (nonatomic, readonly, nullable) NSDictionary *metadata;

+ (instancetype)argumentWithName:(NSString * _Nonnull)name
                         argType:(CSArgumentType)argType
                   argDescription:(NSString * _Nonnull)argDescription
                         cliFlag:(NSString * _Nonnull)cliFlag
                        position:(nullable NSNumber *)position
                      validation:(nullable CSArgumentValidation *)validation
                    defaultValue:(nullable id)defaultValue;

/**
 * Create an argument with schema validation
 * @param name Argument name
 * @param argType Argument type
 * @param argDescription Argument description
 * @param cliFlag CLI flag
 * @param schema JSON schema for validation (takes precedence over schemaRef)
 * @return A new CSCapArgument instance
 */
+ (instancetype)argumentWithName:(NSString * _Nonnull)name
                         argType:(CSArgumentType)argType
                   argDescription:(NSString * _Nonnull)argDescription
                         cliFlag:(NSString * _Nonnull)cliFlag
                          schema:(NSDictionary * _Nonnull)schema;

/**
 * Create an argument with schema reference
 * @param name Argument name
 * @param argType Argument type
 * @param argDescription Argument description
 * @param cliFlag CLI flag
 * @param schemaRef Reference to external schema
 * @return A new CSCapArgument instance
 */
+ (instancetype)argumentWithName:(NSString * _Nonnull)name
                         argType:(CSArgumentType)argType
                   argDescription:(NSString * _Nonnull)argDescription
                         cliFlag:(NSString * _Nonnull)cliFlag
                       schemaRef:(NSString * _Nonnull)schemaRef;
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
 */
@interface CSCapOutput : NSObject <NSCopying, NSCoding>

@property (nonatomic, readonly) CSOutputType outputType;
@property (nonatomic, readonly, nullable) NSString *schemaRef;
@property (nonatomic, readonly, nullable) NSDictionary *schema;
@property (nonatomic, readonly, nullable) NSString *contentType;
@property (nonatomic, readonly, nullable) CSArgumentValidation *validation;
@property (nonatomic, readonly) NSString *outputDescription;
@property (nonatomic, readonly, nullable) NSDictionary *metadata;

+ (instancetype)outputWithType:(CSOutputType)outputType
                     schemaRef:(nullable NSString *)schemaRef
                   contentType:(nullable NSString *)contentType
                    validation:(nullable CSArgumentValidation *)validation
           outputDescription:(NSString * _Nonnull)outputDescription;

/**
 * Create an output with embedded schema
 * @param outputType The output type
 * @param schema JSON schema for validation (takes precedence over schemaRef)
 * @param outputDescription Description of the output
 * @return A new CSCapOutput instance
 */
+ (instancetype)outputWithType:(CSOutputType)outputType
                        schema:(NSDictionary * _Nonnull)schema
               outputDescription:(NSString * _Nonnull)outputDescription;

/**
 * Create an output with schema reference
 * @param outputType The output type
 * @param schemaRef Reference to external schema
 * @param outputDescription Description of the output
 * @return A new CSCapOutput instance
 */
+ (instancetype)outputWithType:(CSOutputType)outputType
                     schemaRef:(NSString * _Nonnull)schemaRef
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
 * Formal cap definition
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

/// Cap arguments
@property (nonatomic, readonly) CSCapArguments *arguments;

/// Output definition
@property (nonatomic, readonly, nullable) CSCapOutput *output;

/// Whether this cap accepts input via stdin
@property (nonatomic, readonly) BOOL acceptsStdin;

/// Arbitrary metadata as JSON object
@property (nonatomic, readonly, nullable) NSDictionary *metadataJSON;


/**
 * Create a fully specified cap
 * @param capUrn The cap URN
 * @param title The human-readable title (required)
 * @param command The command string
 * @param description The cap description
 * @param metadata The cap metadata
 * @param arguments The cap arguments
 * @param output The output definition
 * @param acceptsStdin Whether this cap accepts stdin input
 * @return A new CSCap instance
 */
+ (instancetype)capWithUrn:(CSCapUrn * _Nonnull)capUrn
                     title:(NSString * _Nonnull)title
                   command:(NSString * _Nonnull)command
               description:(nullable NSString *)description
                  metadata:(NSDictionary<NSString *, NSString *> * _Nonnull)metadata
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

@end

NS_ASSUME_NONNULL_END
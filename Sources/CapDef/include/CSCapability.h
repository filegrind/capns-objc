//
//  CSCapability.h
//  Formal capability definition
//
//  This defines the structure for formal capability definitions that include
//  the capability identifier, versioning, and metadata. Capabilities are general-purpose
//  and do not assume any specific domain like files or documents.
//

#import <Foundation/Foundation.h>
#import "CSCapabilityKey.h"

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

@end

/**
 * Capability argument definition
 */
@interface CSCapabilityArgument : NSObject <NSCopying, NSCoding>

@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) CSArgumentType type;
@property (nonatomic, readonly) NSString *argumentDescription;
@property (nonatomic, readonly) NSString *cliFlag;
@property (nonatomic, readonly, nullable) NSNumber *position;
@property (nonatomic, readonly, nullable) CSArgumentValidation *validation;
@property (nonatomic, readonly, nullable) id defaultValue;

+ (instancetype)argumentWithName:(NSString * _Nonnull)name
                            type:(CSArgumentType)type
                     description:(NSString * _Nonnull)description
                         cliFlag:(NSString * _Nonnull)cliFlag
                        position:(nullable NSNumber *)position
                      validation:(nullable CSArgumentValidation *)validation
                    defaultValue:(nullable id)defaultValue;

@end

/**
 * Capability arguments collection
 */
@interface CSCapabilityArguments : NSObject <NSCopying, NSCoding>

@property (nonatomic, readonly) NSArray<CSCapabilityArgument *> *required;
@property (nonatomic, readonly) NSArray<CSCapabilityArgument *> *optional;

+ (instancetype)arguments;
+ (instancetype)argumentsWithRequired:(NSArray<CSCapabilityArgument *> * _Nonnull)required
                             optional:(NSArray<CSCapabilityArgument *> * _Nonnull)optional;

- (void)addRequiredArgument:(CSCapabilityArgument * _Nonnull)argument;
- (void)addOptionalArgument:(CSCapabilityArgument * _Nonnull)argument;
- (nullable CSCapabilityArgument *)findArgumentWithName:(NSString * _Nonnull)name;
- (NSArray<CSCapabilityArgument *> *)positionalArguments;
- (NSArray<CSCapabilityArgument *> *)flagArguments;
- (BOOL)isEmpty;

@end


/**
 * Output definition
 */
@interface CSCapabilityOutput : NSObject <NSCopying, NSCoding>

@property (nonatomic, readonly) CSOutputType type;
@property (nonatomic, readonly, nullable) NSString *schemaRef;
@property (nonatomic, readonly, nullable) NSString *contentType;
@property (nonatomic, readonly, nullable) CSArgumentValidation *validation;
@property (nonatomic, readonly) NSString *outputDescription;

+ (instancetype)outputWithType:(CSOutputType)type
                     schemaRef:(nullable NSString *)schemaRef
                   contentType:(nullable NSString *)contentType
                    validation:(nullable CSArgumentValidation *)validation
                   description:(NSString * _Nonnull)description;

@end

/**
 * Formal capability definition
 */
@interface CSCapability : NSObject <NSCopying, NSCoding>

/// Formal capability identifier with hierarchical naming
@property (nonatomic, readonly) CSCapabilityKey *capabilityKey;

/// Capability version
@property (nonatomic, readonly) NSString *version;

/// Optional description
@property (nonatomic, readonly, nullable) NSString *capabilityDescription;

/// Optional metadata as key-value pairs
@property (nonatomic, readonly) NSDictionary<NSString *, NSString *> *metadata;

/// Command string for CLI execution
@property (nonatomic, readonly) NSString *command;

/// Capability arguments
@property (nonatomic, readonly) CSCapabilityArguments *arguments;

/// Output definition
@property (nonatomic, readonly, nullable) CSCapabilityOutput *output;

/// Whether this capability accepts input via stdin
@property (nonatomic, readonly) BOOL acceptsStdin;

/**
 * Create a new capability
 * @param capabilityKey The capability identifier
 * @param version The capability version
 * @return A new CSCapability instance
 */
+ (instancetype)capabilityWithId:(CSCapabilityKey * _Nonnull)capabilityKey version:(NSString * _Nonnull)version command:(NSString * _Nonnull)command;

/**
 * Create a new capability with description
 * @param capabilityKey The capability identifier
 * @param version The capability version
 * @param description The capability description
 * @return A new CSCapability instance
 */
+ (instancetype)capabilityWithId:(CSCapabilityKey * _Nonnull)capabilityKey 
                         version:(NSString * _Nonnull)version
                         command:(NSString * _Nonnull)command
                     description:(NSString * _Nonnull)description;

/**
 * Create a new capability with metadata
 * @param capabilityKey The capability identifier
 * @param version The capability version
 * @param metadata The capability metadata
 * @return A new CSCapability instance
 */
+ (instancetype)capabilityWithId:(CSCapabilityKey * _Nonnull)capabilityKey 
                         version:(NSString * _Nonnull)version
                         command:(NSString * _Nonnull)command
                        metadata:(NSDictionary<NSString *, NSString *> * _Nonnull)metadata;

/**
 * Create a new capability with description and metadata
 * @param capabilityKey The capability identifier
 * @param version The capability version
 * @param description The capability description
 * @param metadata The capability metadata
 * @return A new CSCapability instance
 */
+ (instancetype)capabilityWithId:(CSCapabilityKey * _Nonnull)capabilityKey 
                         version:(NSString * _Nonnull)version
                         command:(NSString * _Nonnull)command
                     description:(nullable NSString *)description 
                        metadata:(NSDictionary<NSString *, NSString *> * _Nonnull)metadata;

/**
 * Create a new capability with arguments
 * @param capabilityKey The capability identifier
 * @param version The capability version
 * @param arguments The capability arguments
 * @return A new CSCapability instance
 */
+ (instancetype)capabilityWithId:(CSCapabilityKey * _Nonnull)capabilityKey
                         version:(NSString * _Nonnull)version
                         command:(NSString * _Nonnull)command
                       arguments:(CSCapabilityArguments * _Nonnull)arguments;

/**
 * Create a fully specified capability
 * @param capabilityKey The capability identifier
 * @param version The capability version
 * @param description The capability description
 * @param metadata The capability metadata
 * @param command The command string
 * @param arguments The capability arguments
 * @param output The output definition
 * @param acceptsStdin Whether this capability accepts stdin input
 * @return A new CSCapability instance
 */
+ (instancetype)capabilityWithId:(CSCapabilityKey * _Nonnull)capabilityKey
                         version:(NSString * _Nonnull)version
                     description:(nullable NSString *)description
                        metadata:(NSDictionary<NSString *, NSString *> * _Nonnull)metadata
                         command:(NSString * _Nonnull)command
                       arguments:(CSCapabilityArguments * _Nonnull)arguments
                          output:(nullable CSCapabilityOutput *)output
                    acceptsStdin:(BOOL)acceptsStdin;

/**
 * Check if this capability matches a request string
 * @param request The request string
 * @return YES if this capability matches the request
 */
- (BOOL)matchesRequest:(NSString * _Nonnull)request;

/**
 * Check if this capability can handle a request
 * @param request The request capability identifier
 * @return YES if this capability can handle the request
 */
- (BOOL)canHandleRequest:(CSCapabilityKey * _Nonnull)request;

/**
 * Check if this capability is more specific than another
 * @param other The other capability to compare with
 * @return YES if this capability is more specific
 */
- (BOOL)isMoreSpecificThan:(CSCapability * _Nonnull)other;

/**
 * Get a metadata value by key
 * @param key The metadata key
 * @return The metadata value or nil if not found
 */
- (nullable NSString *)metadataForKey:(NSString * _Nonnull)key;

/**
 * Check if this capability has specific metadata
 * @param key The metadata key to check
 * @return YES if the metadata key exists
 */
- (BOOL)hasMetadataForKey:(NSString * _Nonnull)key;

/**
 * Get the capability identifier as a string
 * @return The capability identifier string
 */
- (NSString *)idString;

/**
 * Get the command if defined
 * @return The command string or nil
 */
- (nullable NSString *)getCommand;

/**
 * Get the arguments
 * @return The capability arguments
 */
- (CSCapabilityArguments *)getArguments;

/**
 * Get the output definition if defined
 * @return The output definition or nil
 */
- (nullable CSCapabilityOutput *)getOutput;

/**
 * Add a required argument
 * @param argument The argument to add
 */
- (void)addRequiredArgument:(CSCapabilityArgument * _Nonnull)argument;

/**
 * Add an optional argument
 * @param argument The argument to add
 */
- (void)addOptionalArgument:(CSCapabilityArgument * _Nonnull)argument;

@end

NS_ASSUME_NONNULL_END
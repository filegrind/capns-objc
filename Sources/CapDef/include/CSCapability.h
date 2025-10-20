//
//  CSCapability.h
//  Formal capability definition
//
//  This defines the structure for formal capability definitions that include
//  the capability identifier, versioning, and metadata. Capabilities are general-purpose
//  and do not assume any specific domain like files or documents.
//

#import <Foundation/Foundation.h>
#import "CSCapabilityId.h"

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
@property (nonatomic, readonly, nullable) NSString *cliFlag;
@property (nonatomic, readonly, nullable) NSNumber *position;
@property (nonatomic, readonly, nullable) CSArgumentValidation *validation;
@property (nonatomic, readonly, nullable) id defaultValue;

+ (instancetype)argumentWithName:(NSString *)name
                            type:(CSArgumentType)type
                     description:(NSString *)description
                         cliFlag:(nullable NSString *)cliFlag
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
+ (instancetype)argumentsWithRequired:(NSArray<CSCapabilityArgument *> *)required
                             optional:(NSArray<CSCapabilityArgument *> *)optional;

- (void)addRequiredArgument:(CSCapabilityArgument *)argument;
- (void)addOptionalArgument:(CSCapabilityArgument *)argument;
- (nullable CSCapabilityArgument *)findArgumentWithName:(NSString *)name;
- (NSArray<CSCapabilityArgument *> *)positionalArguments;
- (NSArray<CSCapabilityArgument *> *)flagArguments;
- (BOOL)isEmpty;

@end

/**
 * Command interface definition
 */
@interface CSCommandInterface : NSObject <NSCopying, NSCoding>

@property (nonatomic, readonly) NSString *cliFlag;
@property (nonatomic, readonly) NSString *usagePattern;

+ (instancetype)interfaceWithCliFlag:(NSString *)cliFlag
                        usagePattern:(NSString *)usagePattern;

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
                   description:(NSString *)description;

@end

/**
 * Formal capability definition
 */
@interface CSCapability : NSObject <NSCopying, NSCoding>

/// Formal capability identifier with hierarchical naming
@property (nonatomic, readonly) CSCapabilityId *capabilityId;

/// Capability version
@property (nonatomic, readonly) NSString *version;

/// Optional description
@property (nonatomic, readonly, nullable) NSString *capabilityDescription;

/// Optional metadata as key-value pairs
@property (nonatomic, readonly) NSDictionary<NSString *, NSString *> *metadata;

/// Command interface definition
@property (nonatomic, readonly, nullable) CSCommandInterface *commandInterface;

/// Capability arguments
@property (nonatomic, readonly) CSCapabilityArguments *arguments;

/// Output definition
@property (nonatomic, readonly, nullable) CSCapabilityOutput *output;

/**
 * Create a new capability
 * @param capabilityId The capability identifier
 * @param version The capability version
 * @return A new CSCapability instance
 */
+ (instancetype)capabilityWithId:(CSCapabilityId *)capabilityId version:(NSString *)version;

/**
 * Create a new capability with description
 * @param capabilityId The capability identifier
 * @param version The capability version
 * @param description The capability description
 * @return A new CSCapability instance
 */
+ (instancetype)capabilityWithId:(CSCapabilityId *)capabilityId 
                         version:(NSString *)version 
                     description:(NSString *)description;

/**
 * Create a new capability with metadata
 * @param capabilityId The capability identifier
 * @param version The capability version
 * @param metadata The capability metadata
 * @return A new CSCapability instance
 */
+ (instancetype)capabilityWithId:(CSCapabilityId *)capabilityId 
                         version:(NSString *)version 
                        metadata:(NSDictionary<NSString *, NSString *> *)metadata;

/**
 * Create a new capability with description and metadata
 * @param capabilityId The capability identifier
 * @param version The capability version
 * @param description The capability description
 * @param metadata The capability metadata
 * @return A new CSCapability instance
 */
+ (instancetype)capabilityWithId:(CSCapabilityId *)capabilityId 
                         version:(NSString *)version 
                     description:(nullable NSString *)description 
                        metadata:(NSDictionary<NSString *, NSString *> *)metadata;

/**
 * Create a new capability with arguments
 * @param capabilityId The capability identifier
 * @param version The capability version
 * @param arguments The capability arguments
 * @return A new CSCapability instance
 */
+ (instancetype)capabilityWithId:(CSCapabilityId *)capabilityId
                         version:(NSString *)version
                       arguments:(CSCapabilityArguments *)arguments;

/**
 * Create a fully specified capability
 * @param capabilityId The capability identifier
 * @param version The capability version
 * @param description The capability description
 * @param metadata The capability metadata
 * @param commandInterface The command interface
 * @param arguments The capability arguments
 * @param output The output definition
 * @return A new CSCapability instance
 */
+ (instancetype)capabilityWithId:(CSCapabilityId *)capabilityId
                         version:(NSString *)version
                     description:(nullable NSString *)description
                        metadata:(NSDictionary<NSString *, NSString *> *)metadata
                commandInterface:(nullable CSCommandInterface *)commandInterface
                       arguments:(CSCapabilityArguments *)arguments
                          output:(nullable CSCapabilityOutput *)output;

/**
 * Check if this capability matches a request string
 * @param request The request string
 * @return YES if this capability matches the request
 */
- (BOOL)matchesRequest:(NSString *)request;

/**
 * Check if this capability can handle a request
 * @param request The request capability identifier
 * @return YES if this capability can handle the request
 */
- (BOOL)canHandleRequest:(CSCapabilityId *)request;

/**
 * Check if this capability is more specific than another
 * @param other The other capability to compare with
 * @return YES if this capability is more specific
 */
- (BOOL)isMoreSpecificThan:(CSCapability *)other;

/**
 * Get a metadata value by key
 * @param key The metadata key
 * @return The metadata value or nil if not found
 */
- (nullable NSString *)metadataForKey:(NSString *)key;

/**
 * Check if this capability has specific metadata
 * @param key The metadata key to check
 * @return YES if the metadata key exists
 */
- (BOOL)hasMetadataForKey:(NSString *)key;

/**
 * Get the capability identifier as a string
 * @return The capability identifier string
 */
- (NSString *)idString;

/**
 * Get the command interface if defined
 * @return The command interface or nil
 */
- (nullable CSCommandInterface *)getCommandInterface;

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
- (void)addRequiredArgument:(CSCapabilityArgument *)argument;

/**
 * Add an optional argument
 * @param argument The argument to add
 */
- (void)addOptionalArgument:(CSCapabilityArgument *)argument;

@end

NS_ASSUME_NONNULL_END
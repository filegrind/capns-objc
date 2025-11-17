//
//  CSCapabilityKey.h
//  Flat Tag-Based Capability Identifier System
//
//  This provides a flat, tag-based capability identifier system that replaces
//  hierarchical naming with key-value tags to handle cross-cutting concerns and
//  multi-dimensional capability classification.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * A capability identifier using flat, ordered tags
 *
 * Examples:
 * - action=generate;format=pdf;output=binary;target=thumbnail;type=document
 * - action=extract;target=metadata;type=document
 * - action=analysis;format=en;type=inference
 */
@interface CSCapabilityKey : NSObject <NSCopying, NSCoding>

/// The tags that define this capability
@property (nonatomic, readonly) NSDictionary<NSString *, NSString *> *tags;

/**
 * Create a capability identifier from a string
 * @param string The capability identifier string (e.g., "action=generate;type=document")
 * @param error Error if the string format is invalid
 * @return A new CSCapabilityKey instance or nil if invalid
 */
+ (nullable instancetype)fromString:(NSString * _Nonnull)string error:(NSError * _Nullable * _Nullable)error;

/**
 * Create a capability identifier from tags
 * @param tags Dictionary of tag key-value pairs
 * @param error Error if tags are invalid
 * @return A new CSCapabilityKey instance or nil if invalid
 */
+ (nullable instancetype)fromTags:(NSDictionary<NSString *, NSString *> * _Nonnull)tags error:(NSError * _Nullable * _Nullable)error;

/**
 * Get the value of a specific tag
 * @param key The tag key
 * @return The tag value or nil if not found
 */
- (nullable NSString *)getTag:(NSString * _Nonnull)key;

/**
 * Check if this capability has a specific tag with a specific value
 * @param key The tag key
 * @param value The tag value to check
 * @return YES if the tag exists with the specified value
 */
- (BOOL)hasTag:(NSString * _Nonnull)key withValue:(NSString * _Nonnull)value;

/**
 * Create a new capability key with an added or updated tag
 * @param key The tag key
 * @param value The tag value
 * @return A new CSCapabilityKey instance with the tag added/updated
 */
- (CSCapabilityKey * _Nonnull)withTag:(NSString * _Nonnull)key value:(NSString * _Nonnull)value;

/**
 * Create a new capability key with a tag removed
 * @param key The tag key to remove
 * @return A new CSCapabilityKey instance with the tag removed
 */
- (CSCapabilityKey * _Nonnull)withoutTag:(NSString * _Nonnull)key;

/**
 * Check if this capability matches another based on tag compatibility
 * @param pattern The pattern capability to match against
 * @return YES if this capability matches the pattern
 */
- (BOOL)matches:(CSCapabilityKey * _Nonnull)pattern;

/**
 * Check if this capability can handle a request
 * @param request The requested capability
 * @return YES if this capability can handle the request
 */
- (BOOL)canHandle:(CSCapabilityKey * _Nonnull)request;

/**
 * Get the specificity score for capability matching
 * @return The number of non-wildcard tags
 */
- (NSUInteger)specificity;

/**
 * Check if this capability is more specific than another
 * @param other The other capability to compare specificity with
 * @return YES if this capability is more specific
 */
- (BOOL)isMoreSpecificThan:(CSCapabilityKey * _Nonnull)other;

/**
 * Check if this capability is compatible with another
 * @param other The other capability to check compatibility with
 * @return YES if the capabilities are compatible
 */
- (BOOL)isCompatibleWith:(CSCapabilityKey * _Nonnull)other;

/**
 * Get the type of this capability (convenience method)
 * @return The type tag value or nil if not set
 */
- (nullable NSString *)capabilityType;

/**
 * Get the action of this capability (convenience method)
 * @return The action tag value or nil if not set
 */
- (nullable NSString *)action;

/**
 * Get the target of this capability (convenience method)
 * @return The target tag value or nil if not set
 */
- (nullable NSString *)target;

/**
 * Get the format of this capability (convenience method)
 * @return The format tag value or nil if not set
 */
- (nullable NSString *)format;

/**
 * Get the output type of this capability (convenience method)
 * @return The output tag value or nil if not set
 */
- (nullable NSString *)output;

/**
 * Check if this capability produces binary output
 * @return YES if the output tag is set to "binary"
 */
- (BOOL)isBinary;

/**
 * Create a new capability with a specific tag set to wildcard
 * @param key The tag key to set to wildcard
 * @return A new CSCapabilityKey instance with the tag set to wildcard
 */
- (CSCapabilityKey * _Nonnull)withWildcardTag:(NSString * _Nonnull)key;

/**
 * Create a new capability with only specified tags
 * @param keys Array of tag keys to include
 * @return A new CSCapabilityKey instance with only the specified tags
 */
- (CSCapabilityKey * _Nonnull)subset:(NSArray<NSString *> * _Nonnull)keys;

/**
 * Merge with another capability (other takes precedence for conflicts)
 * @param other The capability to merge with
 * @return A new CSCapabilityKey instance with merged tags
 */
- (CSCapabilityKey * _Nonnull)merge:(CSCapabilityKey * _Nonnull)other;

/**
 * Get the canonical string representation of this capability
 * @return The capability identifier as a string
 */
- (NSString *)toString;

@end

/// Error domain for capability identifier errors
FOUNDATION_EXPORT NSErrorDomain const CSCapabilityKeyErrorDomain;

/// Error codes for capability identifier operations
typedef NS_ERROR_ENUM(CSCapabilityKeyErrorDomain, CSCapabilityKeyError) {
    CSCapabilityKeyErrorInvalidFormat = 1,
    CSCapabilityKeyErrorEmptyTag = 2,
    CSCapabilityKeyErrorInvalidCharacter = 3,
    CSCapabilityKeyErrorInvalidTagFormat = 4
};

/**
 * Builder for creating capability keys fluently
 */
@interface CSCapabilityKeyBuilder : NSObject

/**
 * Create a new builder
 * @return A new CSCapabilityKeyBuilder instance
 */
+ (instancetype)builder;

/**
 * Add or update a tag
 * @param key The tag key
 * @param value The tag value
 * @return This builder instance for chaining
 */
- (CSCapabilityKeyBuilder * _Nonnull)tag:(NSString * _Nonnull)key value:(NSString * _Nonnull)value;

/**
 * Set the type tag
 * @param value The type value
 * @return This builder instance for chaining
 */
- (CSCapabilityKeyBuilder * _Nonnull)type:(NSString * _Nonnull)value;

/**
 * Set the action tag
 * @param value The action value
 * @return This builder instance for chaining
 */
- (CSCapabilityKeyBuilder * _Nonnull)action:(NSString * _Nonnull)value;

/**
 * Set the target tag
 * @param value The target value
 * @return This builder instance for chaining
 */
- (CSCapabilityKeyBuilder * _Nonnull)target:(NSString * _Nonnull)value;

/**
 * Set the format tag
 * @param value The format value
 * @return This builder instance for chaining
 */
- (CSCapabilityKeyBuilder * _Nonnull)format:(NSString * _Nonnull)value;

/**
 * Set the output tag
 * @param value The output value
 * @return This builder instance for chaining
 */
- (CSCapabilityKeyBuilder * _Nonnull)output:(NSString * _Nonnull)value;

/**
 * Set output to binary
 * @return This builder instance for chaining
 */
- (CSCapabilityKeyBuilder * _Nonnull)binaryOutput;

/**
 * Set output to JSON
 * @return This builder instance for chaining
 */
- (CSCapabilityKeyBuilder * _Nonnull)jsonOutput;

/**
 * Build the final CapabilityKey
 * @param error Error if build fails
 * @return A new CSCapabilityKey instance or nil if error
 */
- (nullable CSCapabilityKey *)build:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
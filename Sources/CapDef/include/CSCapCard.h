//
//  CSCapCard.h
//  Flat Tag-Based Cap Identifier System
//
//  This provides a flat, tag-based cap identifier system that replaces
//  hierarchical naming with key-value tags to handle cross-cutting concerns and
//  multi-dimensional cap classification.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * A cap identifier using flat, ordered tags
 *
 * Examples:
 * - action=generate;format=pdf;output=binary;target=thumbnail;type=document
 * - action=extract;target=metadata;type=document
 * - action=analysis;format=en;type=inference
 */
@interface CSCapCard : NSObject <NSCopying, NSCoding>

/// The tags that define this cap
@property (nonatomic, readonly) NSDictionary<NSString *, NSString *> *tags;

/**
 * Create a cap identifier from a string
 * @param string The cap identifier string (e.g., "action=generate;type=document")
 * @param error Error if the string format is invalid
 * @return A new CSCapCard instance or nil if invalid
 */
+ (nullable instancetype)fromString:(NSString * _Nonnull)string error:(NSError * _Nullable * _Nullable)error;

/**
 * Create a cap identifier from tags
 * @param tags Dictionary of tag key-value pairs
 * @param error Error if tags are invalid
 * @return A new CSCapCard instance or nil if invalid
 */
+ (nullable instancetype)fromTags:(NSDictionary<NSString *, NSString *> * _Nonnull)tags error:(NSError * _Nullable * _Nullable)error;

/**
 * Get the value of a specific tag
 * @param key The tag key
 * @return The tag value or nil if not found
 */
- (nullable NSString *)getTag:(NSString * _Nonnull)key;

/**
 * Check if this cap has a specific tag with a specific value
 * @param key The tag key
 * @param value The tag value to check
 * @return YES if the tag exists with the specified value
 */
- (BOOL)hasTag:(NSString * _Nonnull)key withValue:(NSString * _Nonnull)value;

/**
 * Create a new cap card with an added or updated tag
 * @param key The tag key
 * @param value The tag value
 * @return A new CSCapCard instance with the tag added/updated
 */
- (CSCapCard * _Nonnull)withTag:(NSString * _Nonnull)key value:(NSString * _Nonnull)value;

/**
 * Create a new cap card with a tag removed
 * @param key The tag key to remove
 * @return A new CSCapCard instance with the tag removed
 */
- (CSCapCard * _Nonnull)withoutTag:(NSString * _Nonnull)key;

/**
 * Check if this cap matches another based on tag compatibility
 * @param pattern The pattern cap to match against
 * @return YES if this cap matches the pattern
 */
- (BOOL)matches:(CSCapCard * _Nonnull)pattern;

/**
 * Check if this cap can handle a request
 * @param request The requested cap
 * @return YES if this cap can handle the request
 */
- (BOOL)canHandle:(CSCapCard * _Nonnull)request;

/**
 * Get the specificity score for cap matching
 * @return The number of non-wildcard tags
 */
- (NSUInteger)specificity;

/**
 * Check if this cap is more specific than another
 * @param other The other cap to compare specificity with
 * @return YES if this cap is more specific
 */
- (BOOL)isMoreSpecificThan:(CSCapCard * _Nonnull)other;

/**
 * Check if this cap is compatible with another
 * @param other The other cap to check compatibility with
 * @return YES if the caps are compatible
 */
- (BOOL)isCompatibleWith:(CSCapCard * _Nonnull)other;

/**
 * Get the type of this cap (convenience method)
 * @return The type tag value or nil if not set
 */
- (nullable NSString *)capType;

/**
 * Get the action of this cap (convenience method)
 * @return The action tag value or nil if not set
 */
- (nullable NSString *)action;

/**
 * Get the target of this cap (convenience method)
 * @return The target tag value or nil if not set
 */
- (nullable NSString *)target;

/**
 * Get the format of this cap (convenience method)
 * @return The format tag value or nil if not set
 */
- (nullable NSString *)format;

/**
 * Get the output type of this cap (convenience method)
 * @return The output tag value or nil if not set
 */
- (nullable NSString *)output;

/**
 * Check if this cap produces binary output
 * @return YES if the output tag is set to "binary"
 */
- (BOOL)isBinary;

/**
 * Create a new cap with a specific tag set to wildcard
 * @param key The tag key to set to wildcard
 * @return A new CSCapCard instance with the tag set to wildcard
 */
- (CSCapCard * _Nonnull)withWildcardTag:(NSString * _Nonnull)key;

/**
 * Create a new cap with only specified tags
 * @param keys Array of tag keys to include
 * @return A new CSCapCard instance with only the specified tags
 */
- (CSCapCard * _Nonnull)subset:(NSArray<NSString *> * _Nonnull)keys;

/**
 * Merge with another cap (other takes precedence for conflicts)
 * @param other The cap to merge with
 * @return A new CSCapCard instance with merged tags
 */
- (CSCapCard * _Nonnull)merge:(CSCapCard * _Nonnull)other;

/**
 * Get the canonical string representation of this cap
 * @return The cap identifier as a string
 */
- (NSString *)toString;

@end

/// Error domain for cap identifier errors
FOUNDATION_EXPORT NSErrorDomain const CSCapCardErrorDomain;

/// Error codes for cap identifier operations
typedef NS_ERROR_ENUM(CSCapCardErrorDomain, CSCapCardError) {
    CSCapCardErrorInvalidFormat = 1,
    CSCapCardErrorEmptyTag = 2,
    CSCapCardErrorInvalidCharacter = 3,
    CSCapCardErrorInvalidTagFormat = 4
};

/**
 * Builder for creating cap cards fluently
 */
@interface CSCapCardBuilder : NSObject

/**
 * Create a new builder
 * @return A new CSCapCardBuilder instance
 */
+ (instancetype)builder;

/**
 * Add or update a tag
 * @param key The tag key
 * @param value The tag value
 * @return This builder instance for chaining
 */
- (CSCapCardBuilder * _Nonnull)tag:(NSString * _Nonnull)key value:(NSString * _Nonnull)value;

/**
 * Set the type tag
 * @param value The type value
 * @return This builder instance for chaining
 */
- (CSCapCardBuilder * _Nonnull)type:(NSString * _Nonnull)value;

/**
 * Set the action tag
 * @param value The action value
 * @return This builder instance for chaining
 */
- (CSCapCardBuilder * _Nonnull)action:(NSString * _Nonnull)value;

/**
 * Set the target tag
 * @param value The target value
 * @return This builder instance for chaining
 */
- (CSCapCardBuilder * _Nonnull)target:(NSString * _Nonnull)value;

/**
 * Set the format tag
 * @param value The format value
 * @return This builder instance for chaining
 */
- (CSCapCardBuilder * _Nonnull)format:(NSString * _Nonnull)value;

/**
 * Set the output tag
 * @param value The output value
 * @return This builder instance for chaining
 */
- (CSCapCardBuilder * _Nonnull)output:(NSString * _Nonnull)value;

/**
 * Set output to binary
 * @return This builder instance for chaining
 */
- (CSCapCardBuilder * _Nonnull)binaryOutput;

/**
 * Set output to JSON
 * @return This builder instance for chaining
 */
- (CSCapCardBuilder * _Nonnull)jsonOutput;

/**
 * Build the final CapCard
 * @param error Error if build fails
 * @return A new CSCapCard instance or nil if error
 */
- (nullable CSCapCard *)build:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
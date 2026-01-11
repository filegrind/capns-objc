//
//  CSCapUrn.h
//  Flat Tag-Based Cap Identifier System
//
//  This provides a flat, tag-based cap URN system that replaces
//  hierarchical naming with key-value tags to handle cross-cutting concerns and
//  multi-dimensional cap classification.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * A cap URN using flat, ordered tags
 *
 * Examples:
 * - cap:op=generate;ext=pdf;output=binary;target=thumbnail
 * - cap:op=extract;target=metadata
 * - cap:op=analysis;format=en;type=constrained
 */
@interface CSCapUrn : NSObject <NSCopying, NSSecureCoding>

/// The tags that define this cap
@property (nonatomic, readonly) NSDictionary<NSString *, NSString *> *tags;

/**
 * Create a cap URN from a string
 * @param string The cap URN string (e.g., "cap:op=generate")
 * @param error Error if the string format is invalid
 * @return A new CSCapUrn instance or nil if invalid
 */
+ (nullable instancetype)fromString:(NSString * _Nonnull)string error:(NSError * _Nullable * _Nullable)error;

/**
 * Create a cap URN from tags
 * @param tags Dictionary of tag key-value pairs
 * @param error Error if tags are invalid
 * @return A new CSCapUrn instance or nil if invalid
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
 * Create a new cap URN with an added or updated tag
 * @param key The tag key
 * @param value The tag value
 * @return A new CSCapUrn instance with the tag added/updated
 */
- (CSCapUrn * _Nonnull)withTag:(NSString * _Nonnull)key value:(NSString * _Nonnull)value;

/**
 * Create a new cap URN with a tag removed
 * @param key The tag key to remove
 * @return A new CSCapUrn instance with the tag removed
 */
- (CSCapUrn * _Nonnull)withoutTag:(NSString * _Nonnull)key;

/**
 * Check if this cap matches another based on tag compatibility
 * @param pattern The pattern cap to match against
 * @return YES if this cap matches the pattern
 */
- (BOOL)matches:(CSCapUrn * _Nonnull)pattern;

/**
 * Check if this cap can handle a request
 * @param request The requested cap
 * @return YES if this cap can handle the request
 */
- (BOOL)canHandle:(CSCapUrn * _Nonnull)request;

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
- (BOOL)isMoreSpecificThan:(CSCapUrn * _Nonnull)other;

/**
 * Check if this cap is compatible with another
 * @param other The other cap to check compatibility with
 * @return YES if the caps are compatible
 */
- (BOOL)isCompatibleWith:(CSCapUrn * _Nonnull)other;

/**
 * Create a new cap with a specific tag set to wildcard
 * @param key The tag key to set to wildcard
 * @return A new CSCapUrn instance with the tag set to wildcard
 */
- (CSCapUrn * _Nonnull)withWildcardTag:(NSString * _Nonnull)key;

/**
 * Create a new cap with only specified tags
 * @param keys Array of tag keys to include
 * @return A new CSCapUrn instance with only the specified tags
 */
- (CSCapUrn * _Nonnull)subset:(NSArray<NSString *> * _Nonnull)keys;

/**
 * Merge with another cap (other takes precedence for conflicts)
 * @param other The cap to merge with
 * @return A new CSCapUrn instance with merged tags
 */
- (CSCapUrn * _Nonnull)merge:(CSCapUrn * _Nonnull)other;

/**
 * Get the canonical string representation of this cap
 * @return The cap URN as a string
 */
- (NSString *)toString;


@end

/// Error domain for cap URN errors
FOUNDATION_EXPORT NSErrorDomain const CSCapUrnErrorDomain;

/// Error codes for cap URN operations
typedef NS_ERROR_ENUM(CSCapUrnErrorDomain, CSCapUrnError) {
    CSCapUrnErrorInvalidFormat = 1,
    CSCapUrnErrorEmptyTag = 2,
    CSCapUrnErrorInvalidCharacter = 3,
    CSCapUrnErrorInvalidTagFormat = 4,
    CSCapUrnErrorMissingCapPrefix = 5,
    CSCapUrnErrorDuplicateKey = 6,
    CSCapUrnErrorNumericKey = 7,
    CSCapUrnErrorUnterminatedQuote = 8,
    CSCapUrnErrorInvalidEscapeSequence = 9
};

/**
 * Builder for creating cap URNs fluently
 */
@interface CSCapUrnBuilder : NSObject

/**
 * Create a new builder
 * @return A new CSCapUrnBuilder instance
 */
+ (instancetype)builder;

/**
 * Add or update a tag
 * @param key The tag key
 * @param value The tag value
 * @return This builder instance for chaining
 */
- (CSCapUrnBuilder * _Nonnull)tag:(NSString * _Nonnull)key value:(NSString * _Nonnull)value;

/**
 * Build the final CapUrn
 * @param error Error if build fails
 * @return A new CSCapUrn instance or nil if error
 */
- (nullable CSCapUrn *)build:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
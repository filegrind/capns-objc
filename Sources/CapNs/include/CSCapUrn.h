//
//  CSCapUrn.h
//  Flat Tag-Based Cap Identifier System with Required Direction
//
//  This provides a flat, tag-based cap URN system with required direction (in→out).
//  Direction is now a REQUIRED first-class field:
//  - inSpec: The input media spec ID (required)
//  - outSpec: The output media spec ID (required)
//  - tags: Other optional tags (no longer contains in/out)
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * A cap URN with required direction (in→out) and optional tags
 *
 * Direction is integral to a cap's identity. Every cap MUST specify:
 * - inSpec: What type of input it accepts (use std:void.v1 for no input)
 * - outSpec: What type of output it produces
 *
 * Examples:
 * - cap:in=std:void.v1;op=generate;out=std:binary.v1;target=thumbnail
 * - cap:in=std:binary.v1;op=extract;out=std:obj.v1;target=metadata
 * - cap:in=std:str.v1;op=embed;out=std:num-array.v1
 */
@interface CSCapUrn : NSObject <NSCopying, NSSecureCoding>

/// The input media spec ID (required) - e.g., "std:void.v1", "std:str.v1"
@property (nonatomic, readonly) NSString *inSpec;

/// The output media spec ID (required) - e.g., "std:obj.v1", "std:binary.v1"
@property (nonatomic, readonly) NSString *outSpec;

/// Other tags that define this cap (excludes in/out)
@property (nonatomic, readonly) NSDictionary<NSString *, NSString *> *tags;

/**
 * Create a cap URN from a string
 * Format: cap:in=<spec>;out=<spec>;key1=value1;...
 * IMPORTANT: 'in' and 'out' tags are REQUIRED.
 *
 * @param string The cap URN string (e.g., "cap:in=std:void.v1;op=generate;out=std:obj.v1")
 * @param error Error if the string format is invalid or in/out missing
 * @return A new CSCapUrn instance or nil if invalid
 */
+ (nullable instancetype)fromString:(NSString * _Nonnull)string error:(NSError * _Nullable * _Nullable)error;

/**
 * Create a cap URN from tags
 * Extracts 'in' and 'out' from tags (required), stores rest as regular tags
 *
 * @param tags Dictionary containing all tags including 'in' and 'out'
 * @param error Error if tags are invalid or in/out missing
 * @return A new CSCapUrn instance or nil if invalid
 */
+ (nullable instancetype)fromTags:(NSDictionary<NSString *, NSString *> * _Nonnull)tags error:(NSError * _Nullable * _Nullable)error;

/**
 * Get the input spec ID
 * @return The input spec ID
 */
- (NSString *)getInSpec;

/**
 * Get the output spec ID
 * @return The output spec ID
 */
- (NSString *)getOutSpec;

/**
 * Get the value of a specific tag
 * Key is normalized to lowercase for lookup
 * Returns inSpec for "in" key, outSpec for "out" key
 *
 * @param key The tag key
 * @return The tag value or nil if not found
 */
- (nullable NSString *)getTag:(NSString * _Nonnull)key;

/**
 * Check if this cap has a specific tag with a specific value
 * Key is normalized to lowercase; value comparison is case-sensitive
 * Checks inSpec for "in" key, outSpec for "out" key
 *
 * @param key The tag key
 * @param value The tag value to check
 * @return YES if the tag exists with the specified value
 */
- (BOOL)hasTag:(NSString * _Nonnull)key withValue:(NSString * _Nonnull)value;

/**
 * Create a new cap URN with an added or updated tag
 * NOTE: For "in" or "out" keys, silently returns self unchanged.
 *       Use withInSpec: or withOutSpec: to change direction.
 *
 * @param key The tag key
 * @param value The tag value
 * @return A new CSCapUrn instance with the tag added/updated
 */
- (CSCapUrn * _Nonnull)withTag:(NSString * _Nonnull)key value:(NSString * _Nonnull)value;

/**
 * Create a new cap URN with a changed input spec
 * @param inSpec The new input spec ID
 * @return A new CSCapUrn instance with the changed inSpec
 */
- (CSCapUrn * _Nonnull)withInSpec:(NSString * _Nonnull)inSpec;

/**
 * Create a new cap URN with a changed output spec
 * @param outSpec The new output spec ID
 * @return A new CSCapUrn instance with the changed outSpec
 */
- (CSCapUrn * _Nonnull)withOutSpec:(NSString * _Nonnull)outSpec;

/**
 * Create a new cap URN with a tag removed
 * NOTE: For "in" or "out" keys, silently returns self unchanged.
 *       Direction tags cannot be removed.
 *
 * @param key The tag key to remove
 * @return A new CSCapUrn instance with the tag removed
 */
- (CSCapUrn * _Nonnull)withoutTag:(NSString * _Nonnull)key;

/**
 * Check if this cap matches another based on direction and tag compatibility
 * Direction (inSpec/outSpec) is checked FIRST, then other tags.
 *
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
 * Counts non-wildcard inSpec + outSpec + tags
 *
 * @return The number of non-wildcard direction specs and tags
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
 * For "in" key, uses withInSpec:@"*"
 * For "out" key, uses withOutSpec:@"*"
 *
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
    CSCapUrnErrorInvalidEscapeSequence = 9,
    CSCapUrnErrorMissingInSpec = 10,
    CSCapUrnErrorMissingOutSpec = 11
};

/**
 * Builder for creating cap URNs fluently
 * Both inSpec and outSpec MUST be set before build() succeeds.
 */
@interface CSCapUrnBuilder : NSObject

/**
 * Create a new builder
 * @return A new CSCapUrnBuilder instance
 */
+ (instancetype)builder;

/**
 * Set the input spec ID (required)
 * @param spec The input spec ID (e.g., "std:void.v1")
 * @return This builder instance for chaining
 */
- (CSCapUrnBuilder * _Nonnull)inSpec:(NSString * _Nonnull)spec;

/**
 * Set the output spec ID (required)
 * @param spec The output spec ID (e.g., "std:obj.v1")
 * @return This builder instance for chaining
 */
- (CSCapUrnBuilder * _Nonnull)outSpec:(NSString * _Nonnull)spec;

/**
 * Add or update a tag
 * NOTE: For "in" or "out" keys, silently ignores. Use inSpec: or outSpec: instead.
 *
 * @param key The tag key
 * @param value The tag value
 * @return This builder instance for chaining
 */
- (CSCapUrnBuilder * _Nonnull)tag:(NSString * _Nonnull)key value:(NSString * _Nonnull)value;

/**
 * Build the final CapUrn
 * Fails if inSpec or outSpec not set.
 *
 * @param error Error if build fails
 * @return A new CSCapUrn instance or nil if error
 */
- (nullable CSCapUrn *)build:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
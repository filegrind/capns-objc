//
//  CSCapabilityIdBuilder.h
//  Capability ID Builder API
//
//  Provides a fluent builder interface for constructing and manipulating capability identifiers.
//  This replaces manual creation and manipulation of capability IDs with a type-safe API.
//

#import <Foundation/Foundation.h>
#import "CSCapabilityId.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Builder for constructing CSCapabilityId instances with a fluent API
 */
@interface CSCapabilityIdBuilder : NSObject

/**
 * Create a new empty builder
 * @return A new CSCapabilityIdBuilder instance
 */
+ (instancetype)builder;

/**
 * Create a builder starting with a base capability ID
 * @param capabilityId The base capability ID to start with
 * @return A new CSCapabilityIdBuilder instance
 */
+ (instancetype)builderFromCapabilityId:(CSCapabilityId *)capabilityId;

/**
 * Create a builder from a capability string
 * @param string The capability identifier string
 * @param error Error if the string format is invalid
 * @return A new CSCapabilityIdBuilder instance or nil if invalid
 */
+ (nullable instancetype)builderFromString:(NSString *)string error:(NSError **)error;

/**
 * Add a segment to the capability ID
 * @param segment The segment to add
 * @return Self for method chaining
 */
- (instancetype)sub:(NSString *)segment;

/**
 * Add multiple segments to the capability ID
 * @param segments Array of segments to add
 * @return Self for method chaining
 */
- (instancetype)subs:(NSArray<NSString *> *)segments;

/**
 * Replace a segment at the given index
 * @param index The index of the segment to replace
 * @param segment The new segment value
 * @return Self for method chaining
 */
- (instancetype)replaceSegmentAtIndex:(NSUInteger)index withSegment:(NSString *)segment;

/**
 * Remove the last segment (make more general)
 * @return Self for method chaining
 */
- (instancetype)makeMoreGeneral;

/**
 * Remove segments from the given index onwards (make more general to that level)
 * @param level The level to truncate to
 * @return Self for method chaining
 */
- (instancetype)makeGeneralToLevel:(NSUInteger)level;

/**
 * Add a wildcard segment
 * @return Self for method chaining
 */
- (instancetype)addWildcard;

/**
 * Replace the last segment with a wildcard
 * @return Self for method chaining
 */
- (instancetype)makeWildcard;

/**
 * Replace all segments from the given index with a wildcard
 * @param level The level to replace with wildcard
 * @return Self for method chaining
 */
- (instancetype)makeWildcardFromLevel:(NSUInteger)level;

/**
 * Get the current segments as a copy
 * @return Array of current segments
 */
- (NSArray<NSString *> *)segments;

/**
 * Get the number of segments
 * @return The number of segments
 */
- (NSUInteger)count;

/**
 * Check if the builder is empty
 * @return YES if the builder has no segments
 */
- (BOOL)isEmpty;

/**
 * Clear all segments
 * @return Self for method chaining
 */
- (instancetype)clear;

/**
 * Create a copy of the builder
 * @return A new builder with the same segments
 */
- (instancetype)clone;

/**
 * Build the final CSCapabilityId
 * @param error Error if the segments are invalid
 * @return A new CSCapabilityId instance or nil if invalid
 */
- (nullable CSCapabilityId *)build:(NSError **)error;

/**
 * Build the final CSCapabilityId as a string
 * @param error Error if the segments are invalid
 * @return The capability identifier string or nil if invalid
 */
- (nullable NSString *)buildString:(NSError **)error;

/**
 * Get the current capability ID as a string (for debugging)
 * @return The current capability identifier string
 */
- (NSString *)toString;

@end

/**
 * Convenience category for creating builders from various types
 */
@interface NSString (CSCapabilityIdBuilder)

/**
 * Convert this string into a capability ID builder
 * @param error Error if the string format is invalid
 * @return A new CSCapabilityIdBuilder instance or nil if invalid
 */
- (nullable CSCapabilityIdBuilder *)cs_intoBuilder:(NSError **)error;

@end

@interface CSCapabilityId (CSCapabilityIdBuilder)

/**
 * Convert this capability ID into a builder
 * @return A new CSCapabilityIdBuilder instance
 */
- (CSCapabilityIdBuilder *)cs_intoBuilder;

@end

NS_ASSUME_NONNULL_END
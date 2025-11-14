//
//  CSCapabilityKeyBuilder.h
//  Capability ID Builder API
//
//  Provides a fluent builder interface for constructing and manipulating capability identifiers.
//  This replaces manual creation and manipulation of capability IDs with a type-safe API.
//

#import <Foundation/Foundation.h>
#import "CSCapabilityKey.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Builder for constructing CSCapabilityKey instances with a fluent API
 */
@interface CSCapabilityKeyBuilder : NSObject

/**
 * Create a new empty builder
 * @return A new CSCapabilityKeyBuilder instance
 */
+ (instancetype)builder;

/**
 * Create a builder starting with a base capability ID
 * @param capabilityKey The base capability ID to start with
 * @return A new CSCapabilityKeyBuilder instance
 */
+ (instancetype)builderFromCapabilityKey:(CSCapabilityKey * _Nonnull)capabilityKey;

/**
 * Create a builder from a capability string
 * @param string The capability identifier string
 * @param error Error if the string format is invalid
 * @return A new CSCapabilityKeyBuilder instance or nil if invalid
 */
+ (nullable instancetype)builderFromString:(NSString * _Nonnull)string error:(NSError * _Nullable * _Nullable)error;

/**
 * Add a segment to the capability ID
 * @param segment The segment to add
 * @return Self for method chaining
 */
- (instancetype)sub:(NSString * _Nonnull)segment;

/**
 * Add multiple segments to the capability ID
 * @param segments Array of segments to add
 * @return Self for method chaining
 */
- (instancetype)subs:(NSArray<NSString *> * _Nonnull)segments;

/**
 * Replace a segment at the given index
 * @param index The index of the segment to replace
 * @param segment The new segment value
 * @return Self for method chaining
 */
- (instancetype)replaceSegmentAtIndex:(NSUInteger)index withSegment:(NSString * _Nonnull)segment;

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
 * Build the final CSCapabilityKey
 * @param error Error if the segments are invalid
 * @return A new CSCapabilityKey instance or nil if invalid
 */
- (nullable CSCapabilityKey *)build:(NSError * _Nullable * _Nullable)error;

/**
 * Build the final CSCapabilityKey as a string
 * @param error Error if the segments are invalid
 * @return The capability identifier string or nil if invalid
 */
- (nullable NSString *)buildString:(NSError * _Nullable * _Nullable)error;

/**
 * Get the current capability ID as a string (for debugging)
 * @return The current capability identifier string
 */
- (NSString *)toString;

@end

/**
 * Convenience category for creating builders from various types
 */
@interface NSString (CSCapabilityKeyBuilder)

/**
 * Convert this string into a capability ID builder
 * @param error Error if the string format is invalid
 * @return A new CSCapabilityKeyBuilder instance or nil if invalid
 */
- (nullable CSCapabilityKeyBuilder *)cs_intoBuilder:(NSError * _Nullable * _Nullable)error;

@end

@interface CSCapabilityKey (CSCapabilityKeyBuilder)

/**
 * Convert this capability ID into a builder
 * @return A new CSCapabilityKeyBuilder instance
 */
- (CSCapabilityKeyBuilder *)cs_intoBuilder;

@end

NS_ASSUME_NONNULL_END
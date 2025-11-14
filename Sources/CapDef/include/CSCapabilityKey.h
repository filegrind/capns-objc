//
//  CSCapabilityKey.h
//  Formal Capability Identifier System
//
//  This provides a reference implementation for hierarchical capability identifiers
//  with wildcard support, compatibility checking, and specificity comparison.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * A formal capability identifier with hierarchical naming and wildcard support
 *
 * Examples:
 * - file_handling:thumbnail_generation:pdf
 * - file_handling:thumbnail_generation:*
 * - file_handling:*
 * - data_processing:transform:json
 */
@interface CSCapabilityKey : NSObject <NSCopying, NSCoding>

/// The segments of the capability identifier
@property (nonatomic, readonly) NSArray<NSString *> *segments;

/**
 * Create a capability identifier from a string
 * @param string The capability identifier string (e.g., "file_handling:thumbnail:pdf")
 * @param error Error if the string format is invalid
 * @return A new CSCapabilityKey instance or nil if invalid
 */
+ (nullable instancetype)fromString:(NSString * _Nonnull)string error:(NSError * _Nullable * _Nullable)error;

/**
 * Create a capability identifier from segments
 * @param segments Array of string segments
 * @param error Error if segments are invalid
 * @return A new CSCapabilityKey instance or nil if invalid
 */
+ (nullable instancetype)fromSegments:(NSArray<NSString *> * _Nonnull)segments error:(NSError * _Nullable * _Nullable)error;

/**
 * Check if this capability can handle a request
 * @param request The requested capability
 * @return YES if this capability can handle the request
 */
- (BOOL)canHandle:(CSCapabilityKey * _Nonnull)request;

/**
 * Check if this capability is compatible with another
 * @param other The other capability to check compatibility with
 * @return YES if the capabilities are compatible
 */
- (BOOL)isCompatibleWith:(CSCapabilityKey * _Nonnull)other;

/**
 * Check if this capability is more specific than another
 * @param other The other capability to compare specificity with
 * @return YES if this capability is more specific
 */
- (BOOL)isMoreSpecificThan:(CSCapabilityKey * _Nonnull)other;

/**
 * Get the specificity level of this capability
 * @return The number of non-wildcard segments
 */
- (NSUInteger)specificityLevel;

/**
 * Check if this capability is a wildcard at a given level
 * @param level The level to check (0-based)
 * @return YES if the capability is a wildcard at the specified level
 */
- (BOOL)isWildcardAtLevel:(NSUInteger)level;

/**
 * Get the string representation of this capability
 * @return The capability identifier as a string
 */
- (NSString *)toString;

/**
 * Check if this capability produces binary output
 * @return YES if the capability has the "bin:" prefix
 */
- (BOOL)isBinary;

@end

/// Error domain for capability identifier errors
FOUNDATION_EXPORT NSErrorDomain const CSCapabilityKeyErrorDomain;

/// Error codes for capability identifier operations
typedef NS_ERROR_ENUM(CSCapabilityKeyErrorDomain, CSCapabilityKeyError) {
    CSCapabilityKeyErrorInvalidFormat = 1,
    CSCapabilityKeyErrorEmptySegment = 2,
    CSCapabilityKeyErrorInvalidCharacter = 3
};

NS_ASSUME_NONNULL_END
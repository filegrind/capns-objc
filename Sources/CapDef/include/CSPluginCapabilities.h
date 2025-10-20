//
//  CSPluginCapabilities.h
//  Plugin capabilities collection
//
//  Manages a collection of capabilities with searching, matching, and querying functionality.
//

#import <Foundation/Foundation.h>
#import "CSCapability.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Plugin capabilities collection
 */
@interface CSPluginCapabilities : NSObject <NSCopying, NSCoding>

/// Array of capabilities
@property (nonatomic, readonly) NSArray<CSCapability *> *capabilities;

/**
 * Create a new empty capabilities collection
 * @return A new CSPluginCapabilities instance
 */
+ (instancetype)new;

/**
 * Create capabilities collection with an array of capabilities
 * @param capabilities Array of capabilities
 * @return A new CSPluginCapabilities instance
 */
+ (instancetype)capabilitiesWithArray:(NSArray<CSCapability *> *)capabilities;

/**
 * Add a capability to the collection
 * @param capability The capability to add
 */
- (void)addCapability:(CSCapability *)capability;

/**
 * Remove a capability from the collection
 * @param capability The capability to remove
 */
- (void)removeCapability:(CSCapability *)capability;

/**
 * Check if the plugin has a specific capability
 * @param capabilityRequest The capability request string
 * @return YES if the plugin can handle the capability request
 */
- (BOOL)canHandleCapability:(NSString *)capabilityRequest;

/**
 * Get all capability identifiers as strings
 * @return Array of capability identifier strings
 */
- (NSArray<NSString *> *)capabilityIdentifiers;

/**
 * Find a capability by identifier
 * @param identifier The capability identifier string
 * @return The capability or nil if not found
 */
- (nullable CSCapability *)findCapabilityWithIdentifier:(NSString *)identifier;

/**
 * Find the most specific capability that can handle a request
 * @param request The capability request string
 * @return The best matching capability or nil if none can handle the request
 */
- (nullable CSCapability *)findBestCapabilityForRequest:(NSString *)request;

/**
 * Get capabilities that have specific metadata
 * @param key The metadata key to search for
 * @param value The metadata value to match (nil to match any value)
 * @return Array of capabilities with the specified metadata
 */
- (NSArray<CSCapability *> *)capabilitiesWithMetadataKey:(NSString *)key value:(nullable NSString *)value;

/**
 * Get all unique metadata keys across all capabilities
 * @return Array of unique metadata keys
 */
- (NSArray<NSString *> *)allMetadataKeys;

/**
 * Get capabilities by version
 * @param version The version to search for
 * @return Array of capabilities with the specified version
 */
- (NSArray<CSCapability *> *)capabilitiesWithVersion:(NSString *)version;

/**
 * Get the count of capabilities
 * @return Number of capabilities in the collection
 */
- (NSUInteger)count;

/**
 * Check if the collection is empty
 * @return YES if the collection has no capabilities
 */
- (BOOL)isEmpty;

@end

NS_ASSUME_NONNULL_END
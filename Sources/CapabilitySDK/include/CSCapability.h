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

@end

NS_ASSUME_NONNULL_END
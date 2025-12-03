//
//  CSCapHostRegistry.h
//  CapHost registry for unified capability host discovery
//
//  Provides unified interface for finding capability hosts (both providers and plugins)
//  that can satisfy capability requests using subset matching.
//

#import <Foundation/Foundation.h>
#import "CSCap.h"
#import "CSCapCaller.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Error types for capability host registry operations
 */
typedef NS_ENUM(NSInteger, CSCapHostRegistryErrorType) {
    CSCapHostRegistryErrorTypeNoHostsFound,
    CSCapHostRegistryErrorTypeInvalidUrn,
    CSCapHostRegistryErrorTypeRegistryError
};

/**
 * Error class for capability host registry operations
 */
@interface CSCapHostRegistryError : NSError

+ (instancetype)noHostsFoundErrorForCapability:(NSString *)capability;
+ (instancetype)invalidUrnError:(NSString *)urn reason:(NSString *)reason;
+ (instancetype)registryError:(NSString *)message;

@end

/**
 * Unified registry for capability hosts (providers and plugins)
 */
@interface CSCapHostRegistry : NSObject

/**
 * Create a new empty capability host registry
 */
+ (instancetype)registry;

/**
 * Register a capability host with its supported capabilities
 * @param name Unique name for the capability host
 * @param host The capability host implementation
 * @param capabilities Array of capabilities this host supports
 * @return YES if registration succeeded, NO otherwise
 */
- (BOOL)registerCapHost:(NSString *)name
                   host:(id<CSCapHost>)host
           capabilities:(NSArray<CSCap *> *)capabilities;

/**
 * Register a capability host with its supported capabilities (with error handling)
 * @param name Unique name for the capability host
 * @param host The capability host implementation
 * @param capabilities Array of capabilities this host supports
 * @param error Error pointer for any registration failures
 * @return YES if registration succeeded, NO otherwise
 */
- (BOOL)registerCapHost:(NSString *)name
                   host:(id<CSCapHost>)host
           capabilities:(NSArray<CSCap *> *)capabilities
                  error:(NSError * _Nullable * _Nullable)error;

/**
 * Find capability hosts that can handle the requested capability
 * Uses subset matching: host capabilities must be a subset of or match the request
 * @param requestUrn The capability URN to find hosts for
 * @param error Error pointer for any lookup failures
 * @return Array of capability hosts that can handle the request, or nil on error
 */
- (nullable NSArray<id<CSCapHost>> *)findCapHosts:(NSString *)requestUrn
                                            error:(NSError * _Nullable * _Nullable)error;

/**
 * Find the best capability host and cap definition for the request using specificity ranking
 * @param requestUrn The capability URN to find the best host for
 * @param error Error pointer for any lookup failures
 * @param capDefinition Output parameter for the matching cap definition
 * @return The best capability host, or nil if none found or error occurred
 */
- (nullable id<CSCapHost>)findBestCapHost:(NSString *)requestUrn
                                    error:(NSError * _Nullable * _Nullable)error
                            capDefinition:(CSCap * _Nullable * _Nullable)capDefinition;

/**
 * Get all registered capability host names
 * @return Array of registered host names
 */
- (NSArray<NSString *> *)getHostNames;

/**
 * Get all capabilities from all registered hosts
 * @return Array of all capabilities
 */
- (NSArray<CSCap *> *)getAllCapabilities;

/**
 * Check if any host can handle the specified capability
 * @param requestUrn The capability URN to check
 * @return YES if at least one host can handle the capability
 */
- (BOOL)canHandle:(NSString *)requestUrn;

/**
 * Unregister a capability host
 * @param name The name of the host to unregister
 * @return YES if the host was found and removed, NO if not found
 */
- (BOOL)unregisterCapHost:(NSString *)name;

/**
 * Clear all registered hosts
 */
- (void)clear;

@end

NS_ASSUME_NONNULL_END
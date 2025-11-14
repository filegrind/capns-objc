//
//  CSCapabilityMatcher.h
//  Capability Matching Logic
//
//  Provides utilities for finding the best capability match from a collection
//  based on specificity and compatibility rules.
//

#import <Foundation/Foundation.h>
#import "CSCapabilityKey.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Utility class for capability matching operations
 */
@interface CSCapabilityMatcher : NSObject

/**
 * Find the most specific capability that can handle a request
 * @param capabilities Array of available capabilities
 * @param request The requested capability
 * @return The best matching capability or nil if none can handle the request
 */
+ (nullable CSCapabilityKey *)findBestMatchInCapabilities:(NSArray<CSCapabilityKey *> * _Nonnull)capabilities 
                                              forRequest:(CSCapabilityKey * _Nonnull)request;

/**
 * Find all capabilities that can handle a request
 * @param capabilities Array of available capabilities
 * @param request The requested capability
 * @return Array of capabilities that can handle the request, sorted by specificity (most specific first)
 */
+ (NSArray<CSCapabilityKey *> * _Nonnull)findAllMatchesInCapabilities:(NSArray<CSCapabilityKey *> * _Nonnull)capabilities 
                                                  forRequest:(CSCapabilityKey * _Nonnull)request;

/**
 * Sort capabilities by specificity
 * @param capabilities Array of capabilities to sort
 * @return Array sorted by specificity (most specific first)
 */
+ (NSArray<CSCapabilityKey *> * _Nonnull)sortCapabilitiesBySpecificity:(NSArray<CSCapabilityKey *> * _Nonnull)capabilities;

/**
 * Check if a capability can handle a request with additional context
 * @param capability The capability to check
 * @param request The requested capability
 * @param context Additional context for matching (optional)
 * @return YES if the capability can handle the request
 */
+ (BOOL)capability:(CSCapabilityKey * _Nonnull)capability 
    canHandleRequest:(CSCapabilityKey * _Nonnull)request 
         withContext:(nullable NSDictionary<NSString *, id> *)context;

@end

NS_ASSUME_NONNULL_END
//
//  CSCapCube.h
//  CapNs
//
//  Composite registry that wraps multiple CSCapMatrix instances
//  and finds the best match across all of them by specificity.
//

#import <Foundation/Foundation.h>
#import "CSCap.h"
#import "CSCapCaller.h"
#import "CSCapMatrix.h"
#import "CSCapGraph.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Result of finding the best match across registries
 */
@interface CSBestCapSetMatch : NSObject

/** The Cap definition that matched */
@property (nonatomic, strong, readonly) CSCap *cap;

/** The specificity score of the match */
@property (nonatomic, assign, readonly) NSInteger specificity;

/** The name of the registry that provided this match */
@property (nonatomic, strong, readonly) NSString *registryName;

/**
 * Create a new best cap set match
 * @param cap The matched capability definition
 * @param specificity The specificity score
 * @param registryName The registry that provided the match
 * @return A new match instance
 */
+ (instancetype)matchWithCap:(CSCap *)cap
                 specificity:(NSInteger)specificity
                registryName:(NSString *)registryName;

@end

/**
 * Composite CapSet that wraps multiple registries
 * and delegates execution to the best matching one.
 * Implements CSCapSet protocol for use with CSCapCaller.
 */
@interface CSCompositeCapSet : NSObject <CSCapSet>

/**
 * Create a composite CapSet wrapping multiple registries
 * @param registries Array of registry entries
 * @return A new composite cap set
 */
- (instancetype)initWithRegistries:(NSArray *)registries;

/**
 * Build a directed graph from all capabilities in the registries.
 * @return A CSCapGraph instance
 */
- (CSCapGraph *)graph;

@end

/**
 * Composite registry that wraps multiple CSCapMatrix instances
 * and finds the best match across all of them by specificity.
 *
 * When multiple registries can handle a request, this registry compares
 * specificity scores and returns the most specific match.
 * On tie, defaults to the first registry that was added (priority order).
 */
@interface CSCapCube : NSObject

/**
 * Create a new empty composite registry
 */
+ (instancetype)cube;

/**
 * Add a child registry with a name.
 * Registries are checked in order of addition for tie-breaking.
 * @param name Unique name for this registry
 * @param registry The CSCapMatrix to add
 */
- (void)addRegistry:(NSString *)name registry:(CSCapMatrix *)registry;

/**
 * Remove a child registry by name
 * @param name The name of the registry to remove
 * @return The removed registry, or nil if not found
 */
- (CSCapMatrix * _Nullable)removeRegistry:(NSString *)name;

/**
 * Get a child registry by name
 * @param name The name of the registry
 * @return The registry, or nil if not found
 */
- (CSCapMatrix * _Nullable)getRegistry:(NSString *)name;

/**
 * Get names of all child registries
 * @return Array of registry names in priority order
 */
- (NSArray<NSString *> *)getRegistryNames;

/**
 * Check if a capability is available and return a CSCapCaller.
 * This is the main entry point for capability lookup.
 * Finds the best (most specific) match across all child registries.
 * @param capUrn The capability URN to look up
 * @param error Error pointer for any lookup failures
 * @return A CSCapCaller ready to execute, or nil on error
 */
- (CSCapCaller * _Nullable)can:(NSString *)capUrn
                         error:(NSError * _Nullable * _Nullable)error;

/**
 * Find the best capability host across ALL child registries.
 * Polls all registries and compares their best matches by specificity.
 * On specificity tie, returns the match from the first registry.
 * @param requestUrn The capability URN to find the best host for
 * @param error Error pointer for any lookup failures
 * @return The best match, or nil if none found or error occurred
 */
- (CSBestCapSetMatch * _Nullable)findBestCapSet:(NSString *)requestUrn
                                          error:(NSError * _Nullable * _Nullable)error;

/**
 * Check if any registry accepts the specified capability request
 * @param requestUrn The capability URN to check
 * @return YES if at least one registry accepts the capability
 */
- (BOOL)acceptsRequest:(NSString *)requestUrn;

/**
 * Build a directed graph from all capabilities across all registries.
 * The graph represents all possible conversions where:
 * - Nodes are MediaSpec IDs (e.g., "media:string", "media:binary")
 * - Edges are capabilities that convert from one spec to another
 * This enables discovering conversion paths between different media formats.
 * @return A CSCapGraph instance
 */
- (CSCapGraph *)graph;

@end

NS_ASSUME_NONNULL_END

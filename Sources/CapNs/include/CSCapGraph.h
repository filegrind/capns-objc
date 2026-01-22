//
//  CSCapGraph.h
//  CapNs
//
//  Directed graph of capability conversions where nodes are MediaSpec IDs
//  and edges are capabilities that convert from one spec to another.
//

#import <Foundation/Foundation.h>
#import "CSCap.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * An edge in the capability graph representing a conversion from one MediaSpec to another.
 * Each edge corresponds to a capability that can transform data from fromSpec to toSpec.
 */
@interface CSCapGraphEdge : NSObject

/** The input MediaSpec ID (e.g., "media:binary") */
@property (nonatomic, strong, readonly) NSString *fromSpec;

/** The output MediaSpec ID (e.g., "media:string") */
@property (nonatomic, strong, readonly) NSString *toSpec;

/** The capability that performs this conversion */
@property (nonatomic, strong, readonly) CSCap *cap;

/** The registry that provided this capability */
@property (nonatomic, strong, readonly) NSString *registryName;

/** Specificity score for ranking multiple paths */
@property (nonatomic, assign, readonly) NSInteger specificity;

/**
 * Create a new edge
 * @param fromSpec The input MediaSpec ID
 * @param toSpec The output MediaSpec ID
 * @param cap The capability definition
 * @param registryName The registry providing this capability
 * @param specificity The specificity score
 * @return A new edge instance
 */
+ (instancetype)edgeWithFromSpec:(NSString *)fromSpec
                          toSpec:(NSString *)toSpec
                             cap:(CSCap *)cap
                    registryName:(NSString *)registryName
                     specificity:(NSInteger)specificity;

@end

/**
 * Statistics about a capability graph.
 */
@interface CSCapGraphStats : NSObject

/** Number of unique MediaSpec nodes */
@property (nonatomic, assign, readonly) NSInteger nodeCount;

/** Number of edges (capabilities) */
@property (nonatomic, assign, readonly) NSInteger edgeCount;

/** Number of specs that serve as inputs */
@property (nonatomic, assign, readonly) NSInteger inputSpecCount;

/** Number of specs that serve as outputs */
@property (nonatomic, assign, readonly) NSInteger outputSpecCount;

/**
 * Create graph statistics
 */
+ (instancetype)statsWithNodeCount:(NSInteger)nodeCount
                         edgeCount:(NSInteger)edgeCount
                    inputSpecCount:(NSInteger)inputSpecCount
                   outputSpecCount:(NSInteger)outputSpecCount;

@end

/**
 * A directed graph where nodes are MediaSpec IDs and edges are capabilities.
 * This graph enables discovering conversion paths between different media formats.
 */
@interface CSCapGraph : NSObject

/**
 * Create a new empty capability graph
 */
+ (instancetype)graph;

/**
 * Add a capability as an edge in the graph.
 * The cap's in_spec becomes the source node and out_spec becomes the target node.
 * @param cap The capability to add
 * @param registryName The name of the registry providing this capability
 */
- (void)addCap:(CSCap *)cap registryName:(NSString *)registryName;

/**
 * Get all nodes (MediaSpec IDs) in the graph.
 * @return Set of all MediaSpec IDs
 */
- (NSSet<NSString *> *)getNodes;

/**
 * Get all edges in the graph.
 * @return Array of all edges
 */
- (NSArray<CSCapGraphEdge *> *)getEdges;

/**
 * Get all edges originating from a spec (all caps that take this spec as input).
 * @param spec The MediaSpec ID
 * @return Array of edges from this spec
 */
- (NSArray<CSCapGraphEdge *> *)getOutgoing:(NSString *)spec;

/**
 * Get all edges targeting a spec (all caps that produce this spec as output).
 * @param spec The MediaSpec ID
 * @return Array of edges to this spec
 */
- (NSArray<CSCapGraphEdge *> *)getIncoming:(NSString *)spec;

/**
 * Check if there's any direct edge from one spec to another.
 * @param fromSpec The source MediaSpec ID
 * @param toSpec The target MediaSpec ID
 * @return YES if a direct edge exists
 */
- (BOOL)hasDirectEdge:(NSString *)fromSpec toSpec:(NSString *)toSpec;

/**
 * Get all direct edges from one spec to another, sorted by specificity (highest first).
 * @param fromSpec The source MediaSpec ID
 * @param toSpec The target MediaSpec ID
 * @return Array of edges sorted by specificity
 */
- (NSArray<CSCapGraphEdge *> *)getDirectEdges:(NSString *)fromSpec toSpec:(NSString *)toSpec;

/**
 * Check if a conversion path exists from one spec to another.
 * Uses BFS to find if there's any path (direct or through intermediates).
 * @param fromSpec The source MediaSpec ID
 * @param toSpec The target MediaSpec ID
 * @return YES if conversion is possible
 */
- (BOOL)canConvert:(NSString *)fromSpec toSpec:(NSString *)toSpec;

/**
 * Find the shortest conversion path from one spec to another.
 * @param fromSpec The source MediaSpec ID
 * @param toSpec The target MediaSpec ID
 * @return Array of edges representing the path, or nil if no path exists
 */
- (NSArray<CSCapGraphEdge *> * _Nullable)findPath:(NSString *)fromSpec toSpec:(NSString *)toSpec;

/**
 * Find all conversion paths from one spec to another (up to a maximum depth).
 * Returns all possible paths, sorted by total path length (shortest first).
 * @param fromSpec The source MediaSpec ID
 * @param toSpec The target MediaSpec ID
 * @param maxDepth Maximum path length to search
 * @return Array of paths (each path is an array of edges)
 */
- (NSArray<NSArray<CSCapGraphEdge *> *> *)findAllPaths:(NSString *)fromSpec
                                                toSpec:(NSString *)toSpec
                                              maxDepth:(NSInteger)maxDepth;

/**
 * Find the best (highest specificity) conversion path from one spec to another.
 * Unlike findPath which finds the shortest path, this finds the path with
 * the highest total specificity score.
 * @param fromSpec The source MediaSpec ID
 * @param toSpec The target MediaSpec ID
 * @param maxDepth Maximum path length to search
 * @return Array of edges representing the best path, or nil if no path exists
 */
- (NSArray<CSCapGraphEdge *> * _Nullable)findBestPath:(NSString *)fromSpec
                                               toSpec:(NSString *)toSpec
                                             maxDepth:(NSInteger)maxDepth;

/**
 * Get all specs that have at least one outgoing edge.
 * @return Array of input spec IDs
 */
- (NSArray<NSString *> *)getInputSpecs;

/**
 * Get all specs that have at least one incoming edge.
 * @return Array of output spec IDs
 */
- (NSArray<NSString *> *)getOutputSpecs;

/**
 * Get statistics about the graph.
 * @return Graph statistics
 */
- (CSCapGraphStats *)stats;

@end

NS_ASSUME_NONNULL_END

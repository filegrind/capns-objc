//
//  CSLiveCapGraph.h
//  CapDAG
//
//  Precomputed capability graph for path finding.
//  Mirrors Rust: src/planner/live_cap_graph.rs
//
//  Design:
//  1. Store MediaUrn/CapUrn directly (not strings) — avoids reparsing.
//  2. Exact matching for targets (isEquivalentTo:), conformsTo: for traversal.
//  3. Deterministic ordering: (cap_step_count, specificity desc, urn lex).
//

#import <Foundation/Foundation.h>
#import "CSCardinality.h"
#import "CSPlanBuilder.h"

@class CSCap;
@class CSMediaUrn;
@class CSCapUrn;

NS_ASSUME_NONNULL_BEGIN

// MARK: - Edge Type

/// Type of edge in the live capability graph
typedef NS_ENUM(NSInteger, CSLiveMachinePlanEdgeType) {
    /// A real capability that transforms media
    CSLiveMachinePlanEdgeTypeCap,
    /// Fan-out: splits a list into individual items
    CSLiveMachinePlanEdgeTypeForEach,
    /// Collect: gathers iteration results back into a list
    CSLiveMachinePlanEdgeTypeCollect,
    /// Wrap: wraps a single item into a list
    CSLiveMachinePlanEdgeTypeWrapInList,
};

// MARK: - LiveMachinePlanEdge

/// An edge in the live capability graph.
/// Represents either a real capability or a cardinality transition.
@interface CSLiveMachinePlanEdge : NSObject

/// Input media type (what this edge consumes)
@property (nonatomic, strong, readonly) CSMediaUrn *fromSpec;
/// Output media type (what this edge produces)
@property (nonatomic, strong, readonly) CSMediaUrn *toSpec;
/// Type of edge
@property (nonatomic, assign, readonly) CSLiveMachinePlanEdgeType edgeType;
/// Input cardinality
@property (nonatomic, assign, readonly) CSInputCardinality inputCardinality;
/// Output cardinality
@property (nonatomic, assign, readonly) CSInputCardinality outputCardinality;

/// Cap URN (for Cap edges only; nil for cardinality transitions)
@property (nonatomic, strong, readonly, nullable) CSCapUrn *capUrn;
/// Cap title (for Cap edges only)
@property (nonatomic, copy, readonly, nullable) NSString *capTitle;
/// Specificity score (0 for cardinality transitions)
@property (nonatomic, assign, readonly) NSUInteger specificity;

/// Human-readable title
- (NSString *)title;

/// Whether this is a real cap edge (not a cardinality transition)
- (BOOL)isCap;

/// Create a cap edge
+ (instancetype)capEdgeFrom:(CSMediaUrn *)from
                         to:(CSMediaUrn *)to
                     capUrn:(CSCapUrn *)capUrn
                      title:(NSString *)title
                specificity:(NSUInteger)specificity
           inputCardinality:(CSInputCardinality)inputCard
          outputCardinality:(CSInputCardinality)outputCard;

/// Create a ForEach edge (list -> item)
+ (instancetype)forEachEdgeFrom:(CSMediaUrn *)from to:(CSMediaUrn *)to;

/// Create a Collect edge (item -> list)
+ (instancetype)collectEdgeFrom:(CSMediaUrn *)from to:(CSMediaUrn *)to;

/// Create a WrapInList edge (scalar -> list)
+ (instancetype)wrapInListEdgeFrom:(CSMediaUrn *)from to:(CSMediaUrn *)to;

@end

// MARK: - LiveCapGraph

/// Precomputed capability graph for path finding and reachability queries.
/// Maintains a persistent graph structure updated when capabilities change.
@interface CSLiveCapGraph : NSObject

/// Create a new empty graph
+ (instancetype)graph;

/// Clear the graph completely
- (void)clear;

/// Rebuild from a list of capabilities (replaces current contents).
/// After adding all cap edges, inserts cardinality transitions (ForEach/Collect).
- (void)syncFromCaps:(NSArray<CSCap *> *)caps;

/// Rebuild from cap URN strings using the registry.
/// Looks up Cap definitions from the registry; skips identity caps.
- (void)syncFromCapUrns:(NSArray<NSString *> *)capUrns
               registry:(id<CSCapRegistryProtocol>)registry
             completion:(void (^)(void))completion;

/// Add a single capability as an edge. Skips empty specs and identity caps.
- (void)addCap:(CSCap *)cap;

/// Number of unique media URN nodes
- (NSUInteger)nodeCount;

/// Number of edges (cap + cardinality transitions)
- (NSUInteger)edgeCount;

/// BFS: find all reachable targets from source, up to maxDepth.
/// Returns targets sorted by (min_path_length, display_name).
- (NSArray<CSReachableTargetInfo *> *)getReachableTargetsFromSource:(CSMediaUrn *)source
                                                          maxDepth:(NSUInteger)maxDepth;

/// DFS: find all paths to exact target (uses isEquivalentTo: for matching).
/// Returns paths sorted by (cap_step_count, specificity desc, urn lex).
- (NSArray<CSStrand *> *)findPathsToExactTarget:(CSMediaUrn *)source
                                                   target:(CSMediaUrn *)target
                                                 maxDepth:(NSUInteger)maxDepth
                                                 maxPaths:(NSUInteger)maxPaths;

@end

NS_ASSUME_NONNULL_END

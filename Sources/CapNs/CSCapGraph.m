//
//  CSCapGraph.m
//  CapNs
//
//  Directed graph of capability conversions implementation.
//

#import "include/CSCapGraph.h"
#import "include/CSCapUrn.h"
#import "include/CSMediaSpec.h"
@import TaggedUrn;

// ============================================================================
// CSCapGraphEdge
// ============================================================================

@implementation CSCapGraphEdge

+ (instancetype)edgeWithFromSpec:(NSString *)fromSpec
                          toSpec:(NSString *)toSpec
                             cap:(CSCap *)cap
                    registryName:(NSString *)registryName
                     specificity:(NSInteger)specificity {
    CSCapGraphEdge *edge = [[CSCapGraphEdge alloc] init];
    if (edge) {
        edge->_fromSpec = [fromSpec copy];
        edge->_toSpec = [toSpec copy];
        edge->_cap = cap;
        edge->_registryName = [registryName copy];
        edge->_specificity = specificity;
    }
    return edge;
}

@end

// ============================================================================
// CSCapGraphStats
// ============================================================================

@implementation CSCapGraphStats

+ (instancetype)statsWithNodeCount:(NSInteger)nodeCount
                         edgeCount:(NSInteger)edgeCount
                    inputSpecCount:(NSInteger)inputSpecCount
                   outputSpecCount:(NSInteger)outputSpecCount {
    CSCapGraphStats *stats = [[CSCapGraphStats alloc] init];
    if (stats) {
        stats->_nodeCount = nodeCount;
        stats->_edgeCount = edgeCount;
        stats->_inputSpecCount = inputSpecCount;
        stats->_outputSpecCount = outputSpecCount;
    }
    return stats;
}

@end

// ============================================================================
// CSCapGraph
// ============================================================================

@interface CSCapGraph ()
@property (nonatomic, strong) NSMutableArray<CSCapGraphEdge *> *edges;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<NSNumber *> *> *outgoing;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<NSNumber *> *> *incoming;
@property (nonatomic, strong) NSMutableSet<NSString *> *nodes;
@end

@implementation CSCapGraph

+ (instancetype)graph {
    return [[self alloc] init];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _edges = [[NSMutableArray alloc] init];
        _outgoing = [[NSMutableDictionary alloc] init];
        _incoming = [[NSMutableDictionary alloc] init];
        _nodes = [[NSMutableSet alloc] init];
    }
    return self;
}

- (void)addCap:(CSCap *)cap registryName:(NSString *)registryName {
    NSString *fromSpec = [cap.capUrn inSpec];
    NSString *toSpec = [cap.capUrn outSpec];
    NSInteger specificity = [cap.capUrn specificity];

    // Add nodes
    [self.nodes addObject:fromSpec];
    [self.nodes addObject:toSpec];

    // Create edge
    NSInteger edgeIndex = self.edges.count;
    CSCapGraphEdge *edge = [CSCapGraphEdge edgeWithFromSpec:fromSpec
                                                    toSpec:toSpec
                                                       cap:cap
                                              registryName:registryName
                                               specificity:specificity];
    [self.edges addObject:edge];

    // Update outgoing index
    if (!self.outgoing[fromSpec]) {
        self.outgoing[fromSpec] = [[NSMutableArray alloc] init];
    }
    [self.outgoing[fromSpec] addObject:@(edgeIndex)];

    // Update incoming index
    if (!self.incoming[toSpec]) {
        self.incoming[toSpec] = [[NSMutableArray alloc] init];
    }
    [self.incoming[toSpec] addObject:@(edgeIndex)];
}

- (NSSet<NSString *> *)getNodes {
    return [self.nodes copy];
}

- (NSArray<CSCapGraphEdge *> *)getEdges {
    return [self.edges copy];
}

- (NSArray<CSCapGraphEdge *> *)getOutgoing:(NSString *)spec {
    // Use TaggedUrn matching: find all edges where the provided spec
    // satisfies the edge's input requirement (fromSpec)
    NSMutableArray<CSCapGraphEdge *> *result = [[NSMutableArray alloc] init];

    // Parse the provided spec
    NSError *parseError = nil;
    CSTaggedUrn *providedUrn = [CSTaggedUrn fromString:spec error:&parseError];
    if (parseError || !providedUrn) {
        return @[]; // Invalid URN, return empty
    }

    for (CSCapGraphEdge *edge in self.edges) {
        // Parse the requirement URN
        NSError *reqError = nil;
        CSTaggedUrn *requirementUrn = [CSTaggedUrn fromString:edge.fromSpec error:&reqError];
        if (reqError || !requirementUrn) {
            continue; // Invalid requirement URN, skip
        }

        // Use proper TaggedUrn matching
        NSError *matchError = nil;
        BOOL matches = [providedUrn matches:requirementUrn error:&matchError];
        if (!matchError && matches) {
            [result addObject:edge];
        }
    }

    // Sort by specificity (highest first) for consistent ordering
    [result sortUsingComparator:^NSComparisonResult(CSCapGraphEdge *a, CSCapGraphEdge *b) {
        if (a.specificity > b.specificity) return NSOrderedAscending;
        if (a.specificity < b.specificity) return NSOrderedDescending;
        return NSOrderedSame;
    }];

    return [result copy];
}

- (NSArray<CSCapGraphEdge *> *)getIncoming:(NSString *)spec {
    NSArray<NSNumber *> *indices = self.incoming[spec];
    if (!indices) {
        return @[];
    }

    NSMutableArray<CSCapGraphEdge *> *result = [[NSMutableArray alloc] initWithCapacity:indices.count];
    for (NSNumber *idx in indices) {
        [result addObject:self.edges[idx.integerValue]];
    }
    return [result copy];
}

- (BOOL)hasDirectEdge:(NSString *)fromSpec toSpec:(NSString *)toSpec {
    for (CSCapGraphEdge *edge in [self getOutgoing:fromSpec]) {
        if ([edge.toSpec isEqualToString:toSpec]) {
            return YES;
        }
    }
    return NO;
}

- (NSArray<CSCapGraphEdge *> *)getDirectEdges:(NSString *)fromSpec toSpec:(NSString *)toSpec {
    NSMutableArray<CSCapGraphEdge *> *result = [[NSMutableArray alloc] init];

    for (CSCapGraphEdge *edge in [self getOutgoing:fromSpec]) {
        if ([edge.toSpec isEqualToString:toSpec]) {
            [result addObject:edge];
        }
    }

    // Sort by specificity (highest first)
    [result sortUsingComparator:^NSComparisonResult(CSCapGraphEdge *a, CSCapGraphEdge *b) {
        if (a.specificity > b.specificity) return NSOrderedAscending;
        if (a.specificity < b.specificity) return NSOrderedDescending;
        return NSOrderedSame;
    }];

    return [result copy];
}

- (BOOL)canConvert:(NSString *)fromSpec toSpec:(NSString *)toSpec {
    if ([fromSpec isEqualToString:toSpec]) {
        return YES;
    }

    if (![self.nodes containsObject:fromSpec] || ![self.nodes containsObject:toSpec]) {
        return NO;
    }

    NSMutableSet<NSString *> *visited = [[NSMutableSet alloc] init];
    NSMutableArray<NSString *> *queue = [[NSMutableArray alloc] init];
    [queue addObject:fromSpec];
    [visited addObject:fromSpec];

    while (queue.count > 0) {
        NSString *current = queue.firstObject;
        [queue removeObjectAtIndex:0];

        for (CSCapGraphEdge *edge in [self getOutgoing:current]) {
            if ([edge.toSpec isEqualToString:toSpec]) {
                return YES;
            }
            if (![visited containsObject:edge.toSpec]) {
                [visited addObject:edge.toSpec];
                [queue addObject:edge.toSpec];
            }
        }
    }

    return NO;
}

- (NSArray<CSCapGraphEdge *> * _Nullable)findPath:(NSString *)fromSpec toSpec:(NSString *)toSpec {
    if ([fromSpec isEqualToString:toSpec]) {
        return @[];
    }

    if (![self.nodes containsObject:fromSpec] || ![self.nodes containsObject:toSpec]) {
        return nil;
    }

    // BFS to find shortest path
    // visited maps spec -> dictionary with "prevSpec" and "edgeIdx" (empty dict for start node)
    NSMutableDictionary<NSString *, NSDictionary *> *visited = [[NSMutableDictionary alloc] init];
    NSMutableArray<NSString *> *queue = [[NSMutableArray alloc] init];

    [queue addObject:fromSpec];
    visited[fromSpec] = @{};  // Empty dict marks the start node

    while (queue.count > 0) {
        NSString *current = queue.firstObject;
        [queue removeObjectAtIndex:0];

        NSArray<NSNumber *> *indices = self.outgoing[current];
        if (!indices) continue;

        for (NSNumber *edgeIdxNum in indices) {
            NSInteger edgeIdx = edgeIdxNum.integerValue;
            CSCapGraphEdge *edge = self.edges[edgeIdx];

            if ([edge.toSpec isEqualToString:toSpec]) {
                // Found the target - reconstruct path
                NSMutableArray<CSCapGraphEdge *> *path = [[NSMutableArray alloc] init];
                [path addObject:self.edges[edgeIdx]];

                NSString *backtrack = current;
                NSDictionary *backtrackInfo = visited[backtrack];
                while (backtrackInfo && backtrackInfo.count > 0) {
                    NSInteger prevEdgeIdx = [backtrackInfo[@"edgeIdx"] integerValue];
                    [path addObject:self.edges[prevEdgeIdx]];
                    backtrack = backtrackInfo[@"prevSpec"];
                    backtrackInfo = visited[backtrack];
                }

                // Reverse the path
                NSArray *reversedPath = [[path reverseObjectEnumerator] allObjects];
                return reversedPath;
            }

            if (!visited[edge.toSpec]) {
                visited[edge.toSpec] = @{@"prevSpec": current, @"edgeIdx": @(edgeIdx)};
                [queue addObject:edge.toSpec];
            }
        }
    }

    return nil;
}

- (NSArray<NSArray<CSCapGraphEdge *> *> *)findAllPaths:(NSString *)fromSpec
                                                toSpec:(NSString *)toSpec
                                              maxDepth:(NSInteger)maxDepth {
    if (![self.nodes containsObject:fromSpec] || ![self.nodes containsObject:toSpec]) {
        return @[];
    }

    NSMutableArray<NSMutableArray<NSNumber *> *> *allPaths = [[NSMutableArray alloc] init];
    NSMutableArray<NSNumber *> *currentPath = [[NSMutableArray alloc] init];
    NSMutableSet<NSString *> *visited = [[NSMutableSet alloc] init];

    [self dfsFindPaths:fromSpec
                target:toSpec
        remainingDepth:maxDepth
           currentPath:currentPath
               visited:visited
              allPaths:allPaths];

    // Sort by path length (shortest first)
    [allPaths sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) {
        if (a.count < b.count) return NSOrderedAscending;
        if (a.count > b.count) return NSOrderedDescending;
        return NSOrderedSame;
    }];

    // Convert indices to edge references
    NSMutableArray<NSArray<CSCapGraphEdge *> *> *result = [[NSMutableArray alloc] initWithCapacity:allPaths.count];
    for (NSArray<NSNumber *> *indices in allPaths) {
        NSMutableArray<CSCapGraphEdge *> *path = [[NSMutableArray alloc] initWithCapacity:indices.count];
        for (NSNumber *idx in indices) {
            [path addObject:self.edges[idx.integerValue]];
        }
        [result addObject:[path copy]];
    }

    return [result copy];
}

- (void)dfsFindPaths:(NSString *)current
              target:(NSString *)target
      remainingDepth:(NSInteger)remainingDepth
         currentPath:(NSMutableArray<NSNumber *> *)currentPath
             visited:(NSMutableSet<NSString *> *)visited
            allPaths:(NSMutableArray<NSMutableArray<NSNumber *> *> *)allPaths {

    if (remainingDepth == 0) {
        return;
    }

    NSArray<NSNumber *> *indices = self.outgoing[current];
    if (!indices) return;

    for (NSNumber *edgeIdxNum in indices) {
        NSInteger edgeIdx = edgeIdxNum.integerValue;
        CSCapGraphEdge *edge = self.edges[edgeIdx];

        if ([edge.toSpec isEqualToString:target]) {
            // Found a path
            NSMutableArray<NSNumber *> *path = [currentPath mutableCopy];
            [path addObject:@(edgeIdx)];
            [allPaths addObject:path];
        } else if (![visited containsObject:edge.toSpec]) {
            // Continue searching
            [visited addObject:edge.toSpec];
            [currentPath addObject:@(edgeIdx)];

            [self dfsFindPaths:edge.toSpec
                        target:target
                remainingDepth:remainingDepth - 1
                   currentPath:currentPath
                       visited:visited
                      allPaths:allPaths];

            [currentPath removeLastObject];
            [visited removeObject:edge.toSpec];
        }
    }
}

- (NSArray<CSCapGraphEdge *> * _Nullable)findBestPath:(NSString *)fromSpec
                                               toSpec:(NSString *)toSpec
                                             maxDepth:(NSInteger)maxDepth {
    NSArray<NSArray<CSCapGraphEdge *> *> *allPaths = [self findAllPaths:fromSpec toSpec:toSpec maxDepth:maxDepth];

    if (allPaths.count == 0) {
        return nil;
    }

    NSArray<CSCapGraphEdge *> *bestPath = nil;
    NSInteger bestScore = -1;

    for (NSArray<CSCapGraphEdge *> *path in allPaths) {
        NSInteger score = 0;
        for (CSCapGraphEdge *edge in path) {
            score += edge.specificity;
        }
        if (score > bestScore) {
            bestScore = score;
            bestPath = path;
        }
    }

    return bestPath;
}

- (NSArray<NSString *> *)getInputSpecs {
    return [self.outgoing.allKeys copy];
}

- (NSArray<NSString *> *)getOutputSpecs {
    return [self.incoming.allKeys copy];
}

- (CSCapGraphStats *)stats {
    return [CSCapGraphStats statsWithNodeCount:self.nodes.count
                                     edgeCount:self.edges.count
                                inputSpecCount:self.outgoing.count
                               outputSpecCount:self.incoming.count];
}

@end

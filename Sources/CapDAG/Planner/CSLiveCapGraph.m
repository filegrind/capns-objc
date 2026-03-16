//
//  CSLiveCapGraph.m
//  CapDAG
//
//  Precomputed capability graph for path finding.
//  Mirrors Rust: src/planner/live_cap_graph.rs (1466 lines)
//

#import "CSLiveCapGraph.h"
#import "CSCap.h"
#import "CSCapUrn.h"
#import "CSMediaUrn.h"
#import "CSStandardCaps.h"
#import "CSCardinality.h"

// =============================================================================
// CSLiveCapEdge
// =============================================================================

@interface CSLiveCapEdge ()
@property (nonatomic, strong, readwrite) CSMediaUrn *fromSpec;
@property (nonatomic, strong, readwrite) CSMediaUrn *toSpec;
@property (nonatomic, assign, readwrite) CSLiveCapEdgeType edgeType;
@property (nonatomic, assign, readwrite) CSInputCardinality inputCardinality;
@property (nonatomic, assign, readwrite) CSInputCardinality outputCardinality;
@property (nonatomic, strong, readwrite, nullable) CSCapUrn *capUrn;
@property (nonatomic, copy, readwrite, nullable) NSString *capTitle;
@property (nonatomic, assign, readwrite) NSUInteger specificity;
@end

@implementation CSLiveCapEdge

+ (instancetype)capEdgeFrom:(CSMediaUrn *)from
                         to:(CSMediaUrn *)to
                     capUrn:(CSCapUrn *)capUrn
                      title:(NSString *)title
                specificity:(NSUInteger)specificity
           inputCardinality:(CSInputCardinality)inputCard
          outputCardinality:(CSInputCardinality)outputCard {
    CSLiveCapEdge *edge = [[CSLiveCapEdge alloc] init];
    edge.fromSpec = from;
    edge.toSpec = to;
    edge.edgeType = CSLiveCapEdgeTypeCap;
    edge.capUrn = capUrn;
    edge.capTitle = title;
    edge.specificity = specificity;
    edge.inputCardinality = inputCard;
    edge.outputCardinality = outputCard;
    return edge;
}

+ (instancetype)forEachEdgeFrom:(CSMediaUrn *)from to:(CSMediaUrn *)to {
    CSLiveCapEdge *edge = [[CSLiveCapEdge alloc] init];
    edge.fromSpec = from;
    edge.toSpec = to;
    edge.edgeType = CSLiveCapEdgeTypeForEach;
    edge.inputCardinality = CSInputCardinalitySequence;
    edge.outputCardinality = CSInputCardinalitySingle;
    edge.specificity = 0;
    return edge;
}

+ (instancetype)collectEdgeFrom:(CSMediaUrn *)from to:(CSMediaUrn *)to {
    CSLiveCapEdge *edge = [[CSLiveCapEdge alloc] init];
    edge.fromSpec = from;
    edge.toSpec = to;
    edge.edgeType = CSLiveCapEdgeTypeCollect;
    edge.inputCardinality = CSInputCardinalitySingle;
    edge.outputCardinality = CSInputCardinalitySequence;
    edge.specificity = 0;
    return edge;
}

+ (instancetype)wrapInListEdgeFrom:(CSMediaUrn *)from to:(CSMediaUrn *)to {
    CSLiveCapEdge *edge = [[CSLiveCapEdge alloc] init];
    edge.fromSpec = from;
    edge.toSpec = to;
    edge.edgeType = CSLiveCapEdgeTypeWrapInList;
    edge.inputCardinality = CSInputCardinalitySingle;
    edge.outputCardinality = CSInputCardinalitySequence;
    edge.specificity = 0;
    return edge;
}

- (NSString *)title {
    switch (self.edgeType) {
        case CSLiveCapEdgeTypeCap:
            return self.capTitle ?: @"(unknown cap)";
        case CSLiveCapEdgeTypeForEach:
            return @"ForEach (iterate over list)";
        case CSLiveCapEdgeTypeCollect:
            return @"Collect (gather results)";
        case CSLiveCapEdgeTypeWrapInList:
            return @"WrapInList (create single-item list)";
    }
}

- (BOOL)isCap {
    return self.edgeType == CSLiveCapEdgeTypeCap;
}

@end

// =============================================================================
// CSLiveCapGraph
// =============================================================================

@interface CSLiveCapGraph ()
/// All edges in the graph
@property (nonatomic, strong) NSMutableArray<CSLiveCapEdge *> *edges;
/// Index: from_spec canonical -> edge indices
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<NSNumber *> *> *outgoing;
/// Index: to_spec canonical -> edge indices
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<NSNumber *> *> *incoming;
/// All unique media URN canonical strings
@property (nonatomic, strong) NSMutableSet<NSString *> *nodes;
/// Cap URN canonical -> edge indices (for removal)
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<NSNumber *> *> *capToEdges;
/// Cached identity URN for skip checks
@property (nonatomic, strong, nullable) CSCapUrn *identityUrn;
@end

@implementation CSLiveCapGraph

+ (instancetype)graph {
    CSLiveCapGraph *graph = [[CSLiveCapGraph alloc] init];
    graph.edges = [NSMutableArray array];
    graph.outgoing = [NSMutableDictionary dictionary];
    graph.incoming = [NSMutableDictionary dictionary];
    graph.nodes = [NSMutableSet set];
    graph.capToEdges = [NSMutableDictionary dictionary];
    // Parse identity URN once
    NSError *error = nil;
    graph.identityUrn = [CSCapUrn fromString:CSCapIdentity error:&error];
    return graph;
}

- (void)clear {
    [self.edges removeAllObjects];
    [self.outgoing removeAllObjects];
    [self.incoming removeAllObjects];
    [self.nodes removeAllObjects];
    [self.capToEdges removeAllObjects];
}

// MARK: - Sync

- (void)syncFromCaps:(NSArray<CSCap *> *)caps {
    [self clear];
    for (CSCap *cap in caps) {
        [self addCap:cap];
    }
    [self insertCardinalityTransitions];
}

- (void)syncFromCapUrns:(NSArray<NSString *> *)capUrns
               registry:(id<CSCapRegistryProtocol>)registry
             completion:(void (^)(void))completion {
    [self clear];

    [registry getCachedCaps:^(NSArray<CSCap *> * _Nullable allCaps, NSError * _Nullable error) {
        if (error || !allCaps) {
            completion();
            return;
        }

        for (NSString *capUrnStr in capUrns) {
            NSError *parseError = nil;
            CSCapUrn *capUrn = [CSCapUrn fromString:capUrnStr error:&parseError];
            if (!capUrn) continue;

            // Skip identity caps
            if (self.identityUrn && [capUrn isEquivalent:self.identityUrn]) {
                continue;
            }

            // Find matching Cap in registry using isDispatchable
            CSCap *matchingCap = nil;
            for (CSCap *registryCap in allCaps) {
                // Skip identity caps in registry
                if (self.identityUrn && [registryCap.capUrn isEquivalent:self.identityUrn]) {
                    continue;
                }
                if ([capUrn isDispatchable:registryCap.capUrn]) {
                    matchingCap = registryCap;
                    break;
                }
            }

            if (matchingCap) {
                [self addCap:matchingCap];
            }
        }

        [self insertCardinalityTransitions];
        completion();
    }];
}

// MARK: - Add Cap

- (void)addCap:(CSCap *)cap {
    NSString *inSpecStr = [cap.capUrn getInSpec];
    NSString *outSpecStr = [cap.capUrn getOutSpec];

    // Skip caps with empty specs
    if (inSpecStr.length == 0 || outSpecStr.length == 0) {
        return;
    }

    // Skip identity caps
    if (self.identityUrn && [cap.capUrn isEquivalent:self.identityUrn]) {
        return;
    }

    // Parse media URNs
    NSError *error = nil;
    CSMediaUrn *fromSpec = [CSMediaUrn fromString:inSpecStr error:&error];
    if (!fromSpec) return;

    error = nil;
    CSMediaUrn *toSpec = [CSMediaUrn fromString:outSpecStr error:&error];
    if (!toSpec) return;

    NSString *fromCanonical = [fromSpec toString];
    NSString *toCanonical = [toSpec toString];
    NSString *capCanonical = [cap.capUrn toString];

    // Determine cardinality from media URNs
    CSInputCardinality inputCard = CSInputCardinalityFromMediaUrn(fromCanonical);
    CSInputCardinality outputCard = CSInputCardinalityFromMediaUrn(toCanonical);

    // Create edge
    NSUInteger edgeIdx = self.edges.count;
    CSLiveCapEdge *edge = [CSLiveCapEdge capEdgeFrom:fromSpec
                                                  to:toSpec
                                              capUrn:cap.capUrn
                                               title:cap.title
                                         specificity:(NSUInteger)[cap.capUrn specificity]
                                    inputCardinality:inputCard
                                   outputCardinality:outputCard];
    [self.edges addObject:edge];

    // Update indices
    if (!self.outgoing[fromCanonical]) {
        self.outgoing[fromCanonical] = [NSMutableArray array];
    }
    [self.outgoing[fromCanonical] addObject:@(edgeIdx)];

    if (!self.incoming[toCanonical]) {
        self.incoming[toCanonical] = [NSMutableArray array];
    }
    [self.incoming[toCanonical] addObject:@(edgeIdx)];

    [self.nodes addObject:fromCanonical];
    [self.nodes addObject:toCanonical];

    if (!self.capToEdges[capCanonical]) {
        self.capToEdges[capCanonical] = [NSMutableArray array];
    }
    [self.capToEdges[capCanonical] addObject:@(edgeIdx)];
}

// MARK: - Stats

- (NSUInteger)nodeCount {
    return self.nodes.count;
}

- (NSUInteger)edgeCount {
    return self.edges.count;
}

// MARK: - Outgoing Edges (conformsTo matching)

/// Get all edges whose from_spec the source conforms to, with cardinality checks.
/// Scans ALL edges (not index) because conformsTo cannot use dictionary lookup.
- (NSArray<CSLiveCapEdge *> *)getOutgoingEdges:(CSMediaUrn *)source {
    NSMutableArray<CSLiveCapEdge *> *result = [NSMutableArray array];
    BOOL sourceIsList = [source isList];

    for (CSLiveCapEdge *edge in self.edges) {
        BOOL edgeExpectsList = [edge.fromSpec isList];

        // Check cardinality compatibility
        BOOL cardinalityCompatible = NO;
        switch (edge.edgeType) {
            case CSLiveCapEdgeTypeCap:
                cardinalityCompatible = (edgeExpectsList == sourceIsList);
                break;
            case CSLiveCapEdgeTypeForEach:
                cardinalityCompatible = (sourceIsList && ![edge.toSpec isList]);
                break;
            case CSLiveCapEdgeTypeCollect:
            case CSLiveCapEdgeTypeWrapInList:
                cardinalityCompatible = (!sourceIsList && [edge.toSpec isList]);
                break;
        }

        if (!cardinalityCompatible) continue;

        // Check type conformance
        if ([source conformsTo:edge.fromSpec]) {
            [result addObject:edge];
        }
    }

    return result;
}

// MARK: - Cardinality Transitions

- (void)insertCardinalityTransitions {
    // Collect all unique list-typed output specs from existing edges
    // Sort for deterministic iteration order
    NSMutableArray<CSMediaUrn *> *listOutputs = [NSMutableArray array];
    NSMutableSet<NSString *> *seenListCanonicals = [NSMutableSet set];

    for (CSLiveCapEdge *edge in self.edges) {
        if ([edge.toSpec isList]) {
            NSString *canonical = [edge.toSpec toString];
            if (![seenListCanonicals containsObject:canonical]) {
                [seenListCanonicals addObject:canonical];
                [listOutputs addObject:edge.toSpec];
            }
        }
    }

    // Sort for determinism
    [listOutputs sortUsingComparator:^NSComparisonResult(CSMediaUrn *a, CSMediaUrn *b) {
        return [[a toString] compare:[b toString]];
    }];

    if (listOutputs.count == 0) return;

    // For each list output, check if we have caps that accept the singular version
    NSMutableArray<NSArray<CSMediaUrn *> *> *foreachEdgesToAdd = [NSMutableArray array];

    for (CSMediaUrn *listSpec in listOutputs) {
        CSMediaUrn *itemSpec = [listSpec withoutTag:@"list"];

        // Check if any edge accepts the item spec
        BOOL hasSingularConsumer = NO;
        for (CSLiveCapEdge *edge in self.edges) {
            if ([itemSpec conformsTo:edge.fromSpec]) {
                hasSingularConsumer = YES;
                break;
            }
        }

        if (hasSingularConsumer) {
            [foreachEdgesToAdd addObject:@[listSpec, itemSpec]];
        }
    }

    // Add ForEach edges
    for (NSArray<CSMediaUrn *> *pair in foreachEdgesToAdd) {
        CSMediaUrn *listSpec = pair[0];
        CSMediaUrn *itemSpec = pair[1];
        NSString *listCanonical = [listSpec toString];
        NSString *itemCanonical = [itemSpec toString];

        NSUInteger edgeIdx = self.edges.count;
        CSLiveCapEdge *foreachEdge = [CSLiveCapEdge forEachEdgeFrom:listSpec to:itemSpec];
        [self.edges addObject:foreachEdge];

        if (!self.outgoing[listCanonical]) {
            self.outgoing[listCanonical] = [NSMutableArray array];
        }
        [self.outgoing[listCanonical] addObject:@(edgeIdx)];

        if (!self.incoming[itemCanonical]) {
            self.incoming[itemCanonical] = [NSMutableArray array];
        }
        [self.incoming[itemCanonical] addObject:@(edgeIdx)];

        [self.nodes addObject:listCanonical];
        [self.nodes addObject:itemCanonical];
    }

    // Insert Collect edges for existing list types
    [self insertCollectEdgesForExistingLists];
}

- (void)insertCollectEdgesForExistingLists {
    // Find all list specs that exist as Cap outputs (not synthetic edges)
    NSMutableArray<CSMediaUrn *> *existingListOutputs = [NSMutableArray array];
    NSMutableSet<NSString *> *seenCanonicals = [NSMutableSet set];

    for (CSLiveCapEdge *edge in self.edges) {
        if (edge.edgeType == CSLiveCapEdgeTypeCap && [edge.toSpec isList]) {
            NSString *canonical = [edge.toSpec toString];
            if (![seenCanonicals containsObject:canonical]) {
                [seenCanonicals addObject:canonical];
                [existingListOutputs addObject:edge.toSpec];
            }
        }
    }

    // Sort for determinism
    [existingListOutputs sortUsingComparator:^NSComparisonResult(CSMediaUrn *a, CSMediaUrn *b) {
        return [[a toString] compare:[b toString]];
    }];

    NSMutableArray<NSArray<CSMediaUrn *> *> *collectEdgesToAdd = [NSMutableArray array];

    for (CSMediaUrn *listSpec in existingListOutputs) {
        CSMediaUrn *itemSpec = [listSpec withoutTag:@"list"];

        // Check if we have any cap that outputs the singular version
        BOOL hasSingularOutput = NO;
        for (CSLiveCapEdge *edge in self.edges) {
            if (edge.edgeType == CSLiveCapEdgeTypeCap &&
                ![edge.toSpec isList] &&
                [edge.toSpec isEquivalentTo:itemSpec]) {
                hasSingularOutput = YES;
                break;
            }
        }

        // Also check if any cap can consume the item
        BOOL hasItemConsumer = NO;
        if (!hasSingularOutput) {
            for (CSLiveCapEdge *edge in self.edges) {
                if (edge.edgeType == CSLiveCapEdgeTypeCap &&
                    [itemSpec conformsTo:edge.fromSpec]) {
                    hasItemConsumer = YES;
                    break;
                }
            }
        }

        if (hasSingularOutput || hasItemConsumer) {
            [collectEdgesToAdd addObject:@[itemSpec, listSpec]];
        }
    }

    // Add Collect edges (checking for duplicates)
    for (NSArray<CSMediaUrn *> *pair in collectEdgesToAdd) {
        CSMediaUrn *itemSpec = pair[0];
        CSMediaUrn *listSpec = pair[1];

        // Check for duplicate
        BOOL alreadyExists = NO;
        for (CSLiveCapEdge *edge in self.edges) {
            if (edge.edgeType == CSLiveCapEdgeTypeCollect &&
                [edge.fromSpec isEquivalentTo:itemSpec] &&
                [edge.toSpec isEquivalentTo:listSpec]) {
                alreadyExists = YES;
                break;
            }
        }
        if (alreadyExists) continue;

        NSString *itemCanonical = [itemSpec toString];
        NSString *listCanonical = [listSpec toString];

        NSUInteger edgeIdx = self.edges.count;
        CSLiveCapEdge *collectEdge = [CSLiveCapEdge collectEdgeFrom:itemSpec to:listSpec];
        [self.edges addObject:collectEdge];

        if (!self.outgoing[itemCanonical]) {
            self.outgoing[itemCanonical] = [NSMutableArray array];
        }
        [self.outgoing[itemCanonical] addObject:@(edgeIdx)];

        if (!self.incoming[listCanonical]) {
            self.incoming[listCanonical] = [NSMutableArray array];
        }
        [self.incoming[listCanonical] addObject:@(edgeIdx)];

        [self.nodes addObject:itemCanonical];
        [self.nodes addObject:listCanonical];
    }
}

// MARK: - Reachable Targets (BFS)

- (NSArray<CSReachableTargetInfo *> *)getReachableTargetsFromSource:(CSMediaUrn *)source
                                                          maxDepth:(NSUInteger)maxDepth {
    NSMutableDictionary<NSString *, CSReachableTargetInfo *> *results = [NSMutableDictionary dictionary];
    NSMutableSet<NSString *> *visited = [NSMutableSet set];
    // Queue entries: [CSMediaUrn, NSNumber(depth)]
    NSMutableArray<NSArray *> *queue = [NSMutableArray array];

    NSString *sourceCanonical = [source toString];
    [queue addObject:@[source, @0]];
    [visited addObject:sourceCanonical];

    while (queue.count > 0) {
        NSArray *item = queue.firstObject;
        [queue removeObjectAtIndex:0];

        CSMediaUrn *current = item[0];
        NSUInteger depth = [item[1] unsignedIntegerValue];

        if (depth >= maxDepth) continue;

        NSArray<CSLiveCapEdge *> *outEdges = [self getOutgoingEdges:current];
        for (CSLiveCapEdge *edge in outEdges) {
            NSUInteger newDepth = depth + 1;
            NSString *outputCanonical = [edge.toSpec toString];

            // Record this target
            CSReachableTargetInfo *info = results[outputCanonical];
            if (!info) {
                info = [[CSReachableTargetInfo alloc] init];
                info.mediaUrn = outputCanonical;
                info.displayName = outputCanonical;
                info.minDepth = newDepth;
                info.pathCount = 0;
                results[outputCanonical] = info;
            }
            info.pathCount += 1;

            // Continue BFS if not visited
            if (![visited containsObject:outputCanonical]) {
                [visited addObject:outputCanonical];
                [queue addObject:@[edge.toSpec, @(newDepth)]];
            }
        }
    }

    // Sort by (minDepth, displayName)
    NSArray<CSReachableTargetInfo *> *sorted = [[results allValues] sortedArrayUsingComparator:
        ^NSComparisonResult(CSReachableTargetInfo *a, CSReachableTargetInfo *b) {
            if (a.minDepth != b.minDepth) {
                return a.minDepth < b.minDepth ? NSOrderedAscending : NSOrderedDescending;
            }
            return [a.displayName compare:b.displayName];
        }];

    return sorted;
}

// MARK: - Path Finding (DFS with exact target matching)

- (NSArray<CSCapChainPathInfo *> *)findPathsToExactTarget:(CSMediaUrn *)source
                                                   target:(CSMediaUrn *)target
                                                 maxDepth:(NSUInteger)maxDepth
                                                 maxPaths:(NSUInteger)maxPaths {
    // If source already satisfies target, return empty
    if ([source isEquivalentTo:target]) {
        return @[];
    }

    NSMutableArray<CSCapChainPathInfo *> *allPaths = [NSMutableArray array];
    NSMutableArray<CSCapChainStepInfo *> *currentPath = [NSMutableArray array];
    NSMutableSet<NSString *> *visited = [NSMutableSet set];

    [self dfsFindPaths:source
                target:target
               current:source
           currentPath:currentPath
               visited:visited
              allPaths:allPaths
              maxDepth:maxDepth
              maxPaths:maxPaths];

    // Sort paths deterministically
    [allPaths sortUsingComparator:^NSComparisonResult(CSCapChainPathInfo *a, CSCapChainPathInfo *b) {
        return [CSLiveCapGraph comparePaths:a with:b];
    }];

    return allPaths;
}

- (void)dfsFindPaths:(CSMediaUrn *)source
              target:(CSMediaUrn *)target
             current:(CSMediaUrn *)current
         currentPath:(NSMutableArray<CSCapChainStepInfo *> *)currentPath
             visited:(NSMutableSet<NSString *> *)visited
            allPaths:(NSMutableArray<CSCapChainPathInfo *> *)allPaths
            maxDepth:(NSUInteger)maxDepth
            maxPaths:(NSUInteger)maxPaths {

    if (allPaths.count >= maxPaths) return;

    // Check if we reached the EXACT target using isEquivalentTo:
    if ([current isEquivalentTo:target]) {
        NSMutableArray<NSString *> *titles = [NSMutableArray array];
        NSInteger capStepCount = 0;
        for (CSCapChainStepInfo *step in currentPath) {
            [titles addObject:[step title]];
            if ([step isCap]) capStepCount++;
        }

        CSCapChainPathInfo *path = [[CSCapChainPathInfo alloc] init];
        path.sourceSpec = [source toString];
        path.targetSpec = [target toString];
        path.steps = [currentPath copy];
        path.totalSteps = (NSInteger)currentPath.count;
        path.capStepCount = capStepCount;
        path.pathDescription = [titles componentsJoinedByString:@" → "];
        [allPaths addObject:path];
        return;
    }

    if (currentPath.count >= maxDepth) return;

    NSString *currentCanonical = [current toString];
    [visited addObject:currentCanonical];

    // Explore outgoing edges
    NSArray<CSLiveCapEdge *> *outEdges = [self getOutgoingEdges:current];
    for (CSLiveCapEdge *edge in outEdges) {
        NSString *nextCanonical = [edge.toSpec toString];

        if (![visited containsObject:nextCanonical]) {
            // Convert edge type to step info
            CSCapChainStepInfo *step = [[CSCapChainStepInfo alloc] init];
            step.fromSpec = [edge.fromSpec toString];
            step.toSpec = [edge.toSpec toString];

            switch (edge.edgeType) {
                case CSLiveCapEdgeTypeCap:
                    step.stepType = CSCapChainStepTypeCap;
                    step.capUrn = [edge.capUrn toString];
                    step.specificity = edge.specificity;
                    break;
                case CSLiveCapEdgeTypeForEach:
                    step.stepType = CSCapChainStepTypeForEach;
                    step.itemMediaUrn = [edge.toSpec toString];
                    step.listMediaUrn = [edge.fromSpec toString];
                    break;
                case CSLiveCapEdgeTypeCollect:
                    step.stepType = CSCapChainStepTypeCollect;
                    step.itemMediaUrn = [edge.fromSpec toString];
                    step.listMediaUrn = [edge.toSpec toString];
                    break;
                case CSLiveCapEdgeTypeWrapInList:
                    step.stepType = CSCapChainStepTypeWrapInList;
                    step.itemMediaUrn = [edge.fromSpec toString];
                    step.listMediaUrn = [edge.toSpec toString];
                    break;
            }

            [currentPath addObject:step];

            [self dfsFindPaths:source
                        target:target
                       current:edge.toSpec
                   currentPath:currentPath
                       visited:visited
                      allPaths:allPaths
                      maxDepth:maxDepth
                      maxPaths:maxPaths];

            [currentPath removeLastObject];
        }
    }

    // Remove from visited for backtracking (enables multiple paths through same node)
    [visited removeObject:currentCanonical];
}

// MARK: - Path Comparison (Deterministic Ordering)

/// Sort by: cap_step_count asc, total specificity desc, step keys lex
+ (NSComparisonResult)comparePaths:(CSCapChainPathInfo *)a with:(CSCapChainPathInfo *)b {
    // 1. Fewer cap steps first
    if (a.capStepCount != b.capStepCount) {
        return a.capStepCount < b.capStepCount ? NSOrderedAscending : NSOrderedDescending;
    }

    // 2. Higher total specificity first
    NSUInteger specA = 0, specB = 0;
    for (CSCapChainStepInfo *step in a.steps) {
        specA += step.specificity;
    }
    for (CSCapChainStepInfo *step in b.steps) {
        specB += step.specificity;
    }
    if (specA != specB) {
        return specA > specB ? NSOrderedAscending : NSOrderedDescending;
    }

    // 3. Lexicographic by step keys
    NSUInteger minCount = MIN(a.steps.count, b.steps.count);
    for (NSUInteger i = 0; i < minCount; i++) {
        NSString *keyA = [self stepKey:a.steps[i]];
        NSString *keyB = [self stepKey:b.steps[i]];
        NSComparisonResult cmp = [keyA compare:keyB];
        if (cmp != NSOrderedSame) return cmp;
    }

    // Shorter path first if all keys match so far
    if (a.steps.count != b.steps.count) {
        return a.steps.count < b.steps.count ? NSOrderedAscending : NSOrderedDescending;
    }

    return NSOrderedSame;
}

+ (NSString *)stepKey:(CSCapChainStepInfo *)step {
    switch (step.stepType) {
        case CSCapChainStepTypeCap:
            return step.capUrn ?: @"";
        case CSCapChainStepTypeForEach:
            return @"foreach";
        case CSCapChainStepTypeCollect:
            return @"collect";
        case CSCapChainStepTypeWrapInList:
            return @"wrapinlist";
    }
}

@end

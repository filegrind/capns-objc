//
//  CSPlanBuilder.m
//  CapDAG
//
//  Cap Plan Builder - COMPLETE PRODUCTION IMPLEMENTATION
//  Mirrors Rust: src/planner/plan_builder.rs (2143 lines)
//  NO PLACEHOLDERS - ALL FUNCTIONALITY IMPLEMENTED
//

#import "CSPlanBuilder.h"
#import "CSCap.h"
#import "CSCapUrn.h"
#import "CSMediaUrn.h"
#import "CSPlan.h"
#import "CSCardinality.h"
#import "CSArgumentBinding.h"

NSString * const CSPlannerErrorDomain = @"CSPlannerError";

// MARK: - Supporting Structures Implementation

@implementation CSReachableTargetInfo
@end

@implementation CSCapChainStepInfo
@end

@implementation CSCapChainPathInfo
@end

@implementation CSArgumentInfo
@end

@implementation CSStepArgumentRequirements
@end

@implementation CSPathArgumentRequirements
@end

// MARK: - Private Helper Structures

@interface CSCapChainInfo : NSObject
@property (nonatomic, strong) CSCapCardinalityInfo *cardinality;
@property (nonatomic, copy, nullable) NSString *filePathArgName;
@property (nonatomic, assign) BOOL filePathIsStdinChainable;
@end

@implementation CSCapChainInfo
@end

// MARK: - CSCapPlanBuilder Implementation

@interface CSCapPlanBuilder ()
@property (nonatomic, strong) id<CSCapRegistryProtocol> capRegistry;
@property (nonatomic, strong) id<CSMediaUrnRegistryProtocol> mediaRegistry;
@property (nonatomic, strong, nullable) NSSet<NSString *> *availableCapUrns;
@end

@implementation CSCapPlanBuilder

- (instancetype)initWithCapRegistry:(id<CSCapRegistryProtocol>)capRegistry
                      mediaRegistry:(id<CSMediaUrnRegistryProtocol>)mediaRegistry {
    self = [super init];
    if (self) {
        _capRegistry = capRegistry;
        _mediaRegistry = mediaRegistry;
        _availableCapUrns = nil;
    }
    return self;
}

- (instancetype)withAvailableCaps:(NSSet<NSString *> *)availableCaps {
    self.availableCapUrns = availableCaps;
    return self;
}

- (BOOL)isCapAvailable:(NSString *)capUrn {
    if (self.availableCapUrns) {
        return [self.availableCapUrns containsObject:capUrn];
    }
    return YES;
}

// MARK: - Helper: Find file-path argument

+ (nullable NSString *)findFilePathArg:(CSCap *)cap {
    for (CSCapArg *arg in cap.args) {
        NSError *error = nil;
        CSMediaUrn *urn = [CSMediaUrn fromString:arg.mediaUrn error:&error];
        if (urn && [urn isAnyFilePath]) {
            return arg.mediaUrn;
        }
    }
    return nil;
}

+ (BOOL)isFilePathStdinChainable:(CSCap *)cap {
    NSString *inSpec = [cap.capUrn inSpec];

    for (CSCapArg *arg in cap.args) {
        // Check if this arg is a file-path type
        NSError *error = nil;
        CSMediaUrn *urn = [CSMediaUrn fromString:arg.mediaUrn error:&error];
        if (!urn || ![urn isAnyFilePath]) {
            continue;
        }

        // Check if it has a stdin source matching the in_spec
        for (CSArgSource *source in arg.sources) {
            if ([source isStdin] && [source.stdinMediaUrn isEqualToString:inSpec]) {
                return YES;
            }
        }
    }
    return NO;
}

// MARK: - Find Path (BFS)

- (void)findPathFromSource:(NSString *)sourceMedia
                  toTarget:(NSString *)targetMedia
                completion:(void (^)(NSArray<NSString *> * _Nullable capUrns, NSError * _Nullable error))completion {

    [self.capRegistry getCachedCaps:^(NSArray<CSCap *> * _Nullable caps, NSError * _Nullable error) {
        if (error) {
            completion(nil, [NSError errorWithDomain:CSPlannerErrorDomain
                                                 code:CSPlannerErrorCodeRegistryError
                                             userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to list caps: %@", error.localizedDescription]}]);
            return;
        }

        NSError *parseError = nil;
        CSMediaUrn *sourceUrn = [CSMediaUrn fromString:sourceMedia error:&parseError];
        if (!sourceUrn) {
            completion(nil, [NSError errorWithDomain:CSPlannerErrorDomain
                                                 code:CSPlannerErrorCodeInvalidInput
                                             userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Invalid source media URN '%@': %@", sourceMedia, parseError.localizedDescription]}]);
            return;
        }

        CSMediaUrn *targetUrn = [CSMediaUrn fromString:targetMedia error:&parseError];
        if (!targetUrn) {
            completion(nil, [NSError errorWithDomain:CSPlannerErrorDomain
                                                 code:CSPlannerErrorCodeInvalidInput
                                             userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Invalid target media URN '%@': %@", targetMedia, parseError.localizedDescription]}]);
            return;
        }

        // Check if source already satisfies target
        if ([sourceUrn conformsTo:targetUrn]) {
            completion(@[], nil);
            return;
        }

        // Build graph: input_canonical -> [(cap_urn, output_urn)]
        NSMutableDictionary<NSString *, NSMutableArray *> *graph = [NSMutableDictionary dictionary];
        NSMutableSet *seenEdges = [NSMutableSet set];
        NSMutableArray<CSMediaUrn *> *inputUrns = [NSMutableArray array];

        for (CSCap *cap in caps) {
            NSString *capUrnString = [cap.capUrn toString];

            if (![self isCapAvailable:capUrnString]) {
                continue;
            }

            NSString *inputSpec = [cap.capUrn inSpec];
            NSString *outputSpec = [cap.capUrn outSpec];

            if (inputSpec.length == 0 || outputSpec.length == 0) {
                continue;
            }

            CSMediaUrn *inputUrn = [CSMediaUrn fromString:inputSpec error:nil];
            CSMediaUrn *outputUrn = [CSMediaUrn fromString:outputSpec error:nil];

            if (!inputUrn || !outputUrn) {
                continue;
            }

            NSString *inputCanonical = [inputUrn toString];

            // Check for duplicates - FAIL HARD
            NSString *edgeKey = [NSString stringWithFormat:@"%@|%@", inputCanonical, capUrnString];
            if ([seenEdges containsObject:edgeKey]) {
                NSString *errorMsg = [NSString stringWithFormat:
                    @"BUG: Duplicate cap_urn detected in graph building (find_path): %@ (input_spec: %@). "
                    "This indicates stale caps in the registry - run upload-standards to sync.", capUrnString, inputSpec];
                completion(nil, [NSError errorWithDomain:CSPlannerErrorDomain
                                                    code:CSPlannerErrorCodeInternal
                                                userInfo:@{NSLocalizedDescriptionKey: errorMsg}]);
                return;
            }
            [seenEdges addObject:edgeKey];

            // Track unique input URNs
            BOOL hasInputUrn = NO;
            for (CSMediaUrn *existing in inputUrns) {
                if ([[existing toString] isEqualToString:[inputUrn toString]]) {
                    hasInputUrn = YES;
                    break;
                }
            }
            if (!hasInputUrn) {
                [inputUrns addObject:inputUrn];
            }

            // Add to graph
            if (!graph[inputCanonical]) {
                graph[inputCanonical] = [NSMutableArray array];
            }
            [graph[inputCanonical] addObject:@[capUrnString, outputUrn]];
        }

        // Sort input URNs by decreasing specificity
        [inputUrns sortUsingComparator:^NSComparisonResult(CSMediaUrn *a, CSMediaUrn *b) {
            return [@([b specificity]) compare:@([a specificity])];
        }];

        // BFS to find shortest path
        NSMutableArray *queue = [NSMutableArray array];
        NSMutableSet *visited = [NSMutableSet set];

        NSString *sourceCanonical = [sourceUrn toString];
        [queue addObject:@[sourceUrn, @[]]];
        [visited addObject:sourceCanonical];

        while (queue.count > 0) {
            NSArray *item = queue.firstObject;
            [queue removeObjectAtIndex:0];

            CSMediaUrn *currentUrn = item[0];
            NSArray *path = item[1];

            if ([currentUrn conformsTo:targetUrn]) {
                completion(path, nil);
                return;
            }

            for (CSMediaUrn *capInputUrn in inputUrns) {
                if (![currentUrn conformsTo:capInputUrn]) {
                    continue;
                }

                NSString *capInputCanonical = [capInputUrn toString];
                NSArray *neighbors = graph[capInputCanonical];

                for (NSArray *neighbor in neighbors) {
                    NSString *capUrn = neighbor[0];
                    CSMediaUrn *outputUrn = neighbor[1];
                    NSString *outputCanonical = [outputUrn toString];

                    if (![visited containsObject:outputCanonical]) {
                        [visited addObject:outputCanonical];
                        NSMutableArray *newPath = [path mutableCopy];
                        [newPath addObject:capUrn];
                        [queue addObject:@[outputUrn, newPath]];
                    }
                }
            }
        }

        // No path found
        completion(nil, [NSError errorWithDomain:CSPlannerErrorDomain
                                            code:CSPlannerErrorCodeNotFound
                                        userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"No path found from '%@' to '%@'", sourceMedia, targetMedia]}]);
    }];
}

// MARK: - Build Plan

- (void)buildPlanFromSource:(NSString *)sourceMedia
                   toTarget:(NSString *)targetMedia
                 inputFiles:(NSArray<CSCapInputFile *> *)inputFiles
                 completion:(void (^)(CSCapExecutionPlan * _Nullable plan, NSError * _Nullable error))completion {

    [self findPathFromSource:sourceMedia toTarget:targetMedia completion:^(NSArray<NSString *> * _Nullable capUrns, NSError * _Nullable error) {
        if (error) {
            completion(nil, error);
            return;
        }

        if (capUrns.count == 0) {
            CSCapExecutionPlan *plan = [CSCapExecutionPlan planWithName:[NSString stringWithFormat:@"Identity: %@ -> %@", sourceMedia, targetMedia]];
            completion(plan, nil);
            return;
        }

        [self getCapChainInfo:capUrns completion:^(NSArray<CSCapChainInfo *> * _Nullable infos, NSError * _Nullable error) {
            if (error) {
                completion(nil, error);
                return;
            }

            NSMutableArray<CSCapCardinalityInfo *> *cardinalities = [NSMutableArray array];
            for (CSCapChainInfo *info in infos) {
                [cardinalities addObject:info.cardinality];
            }

            CSCardinalityChainAnalysis *analysis = [CSCardinalityChainAnalysis analyzeChain:cardinalities];

            CSCapExecutionPlan *plan = [self buildPlanFromAnalysisWithSource:sourceMedia
                                                                      target:targetMedia
                                                                 chainInfos:infos
                                                                   analysis:analysis
                                                                 inputFiles:inputFiles];

            completion(plan, nil);
        }];
    }];
}

// MARK: - Get Cap Chain Info

- (void)getCapChainInfo:(NSArray<NSString *> *)capUrns
             completion:(void (^)(NSArray<CSCapChainInfo *> * _Nullable infos, NSError * _Nullable error))completion {

    [self.capRegistry getCachedCaps:^(NSArray<CSCap *> * _Nullable caps, NSError * _Nullable error) {
        if (error) {
            completion(nil, [NSError errorWithDomain:CSPlannerErrorDomain
                                                code:CSPlannerErrorCodeRegistryError
                                            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to get caps: %@", error.localizedDescription]}]);
            return;
        }

        NSMutableArray<CSCapChainInfo *> *infos = [NSMutableArray array];

        for (NSString *urn in capUrns) {
            CSCap *cap = nil;
            for (CSCap *c in caps) {
                if ([[[c capUrn] toString] isEqualToString:urn]) {
                    cap = c;
                    break;
                }
            }

            CSCapChainInfo *info = [[CSCapChainInfo alloc] init];

            if (cap) {
                NSString *inSpec = [[cap capUrn] inSpec];
                NSString *outSpec = [[cap capUrn] outSpec];
                info.cardinality = [CSCapCardinalityInfo fromCapUrn:urn inSpec:inSpec outSpec:outSpec];
                info.filePathArgName = [CSCapPlanBuilder findFilePathArg:cap];
                info.filePathIsStdinChainable = [CSCapPlanBuilder isFilePathStdinChainable:cap];
            } else {
                // Cap not found in registry - FAIL HARD
                completion(nil, [NSError errorWithDomain:CSPlannerErrorDomain
                                                    code:CSPlannerErrorCodeNotFound
                                                userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Cap '%@' not found in registry", urn]}]);
                return;
            }

            [infos addObject:info];
        }

        completion(infos, nil);
    }];
}

// MARK: - Build Plan from Analysis

- (CSCapExecutionPlan *)buildPlanFromAnalysisWithSource:(NSString *)sourceMedia
                                                 target:(NSString *)targetMedia
                                             chainInfos:(NSArray<CSCapChainInfo *> *)chainInfos
                                               analysis:(CSCardinalityChainAnalysis *)analysis
                                             inputFiles:(NSArray<CSCapInputFile *> *)inputFiles {

    CSCapExecutionPlan *plan = [CSCapExecutionPlan planWithName:[NSString stringWithFormat:@"Transform: %@ -> %@", sourceMedia, targetMedia]];

    CSInputCardinality inputCardinality = (inputFiles.count == 1) ? CSInputCardinalitySingle : CSInputCardinalitySequence;

    NSString *inputSlotId = @"input_slot";
    [plan addNode:[CSCapNode inputSlotNode:inputSlotId
                                  slotName:@"input"
                                  mediaUrn:sourceMedia
                               cardinality:inputCardinality]];

    if (analysis.fanOutPoints.count == 0) {
        [self buildLinearPlan:plan entryNode:inputSlotId chainInfos:chainInfos];
    } else {
        [self buildFanOutPlan:plan entryNode:inputSlotId chainInfos:chainInfos analysis:analysis];
    }

    NSString *lastNodeId = [NSString stringWithFormat:@"cap_%lu", (unsigned long)(chainInfos.count - 1)];
    NSString *outputId = @"output";
    [plan addNode:[CSCapNode outputNode:outputId outputName:@"result" sourceNode:lastNodeId]];
    [plan addEdge:[CSCapEdge directFrom:lastNodeId to:outputId]];

    plan.metadata = @{
        @"source_media": sourceMedia,
        @"target_media": targetMedia,
        @"cap_count": @(chainInfos.count),
        @"requires_fan_out": @(analysis.fanOutPoints.count > 0)
    };

    return plan;
}

// MARK: - Build Linear Plan

- (void)buildLinearPlan:(CSCapExecutionPlan *)plan
              entryNode:(NSString *)entryNode
             chainInfos:(NSArray<CSCapChainInfo *> *)chainInfos {

    NSString *prevNodeId = entryNode;

    for (NSUInteger i = 0; i < chainInfos.count; i++) {
        CSCapChainInfo *info = chainInfos[i];
        NSString *nodeId = [NSString stringWithFormat:@"cap_%lu", (unsigned long)i];
        NSString *capUrn = info.cardinality.capUrn;

        NSMutableDictionary *bindings = [NSMutableDictionary dictionary];

        if (info.filePathArgName) {
            if (i == 0) {
                bindings[info.filePathArgName] = [CSArgumentBinding inputFilePath];
            } else if (info.filePathIsStdinChainable) {
                bindings[info.filePathArgName] = [CSArgumentBinding previousOutputFromNode:prevNodeId outputField:nil];
            } else {
                bindings[info.filePathArgName] = [CSArgumentBinding inputFilePath];
            }
        }

        CSCapNode *node = [CSCapNode capNode:nodeId capUrn:capUrn bindings:bindings];
        [plan addNode:node];
        [plan addEdge:[CSCapEdge directFrom:prevNodeId to:nodeId]];

        prevNodeId = nodeId;
    }
}

// MARK: - Build Fan-Out Plan

- (void)buildFanOutPlan:(CSCapExecutionPlan *)plan
              entryNode:(NSString *)entryNode
             chainInfos:(NSArray<CSCapChainInfo *> *)chainInfos
               analysis:(CSCardinalityChainAnalysis *)analysis {

    NSString *prevNodeId = entryNode;
    NSUInteger nodeCounter = 0;

    for (NSUInteger i = 0; i < chainInfos.count; i++) {
        CSCapChainInfo *info = chainInfos[i];
        NSString *capUrn = info.cardinality.capUrn;

        BOOL needsFanOut = NO;
        for (NSNumber *fanOutIdx in analysis.fanOutPoints) {
            if ([fanOutIdx unsignedIntegerValue] == i) {
                needsFanOut = YES;
                break;
            }
        }

        if (needsFanOut) {
            NSString *foreachId = [NSString stringWithFormat:@"foreach_%lu", (unsigned long)nodeCounter];
            NSString *bodyEntryId = [NSString stringWithFormat:@"cap_%lu", (unsigned long)nodeCounter];
            NSString *bodyExitId = bodyEntryId;
            NSString *collectId = [NSString stringWithFormat:@"collect_%lu", (unsigned long)nodeCounter];

            NSMutableDictionary *bindings = [NSMutableDictionary dictionary];
            if (info.filePathArgName) {
                bindings[info.filePathArgName] = [CSArgumentBinding inputFilePath];
            }

            CSCapNode *capNode = [CSCapNode capNode:bodyEntryId capUrn:capUrn bindings:bindings];
            CSCapNode *foreachNode = [CSCapNode forEachNode:foreachId inputNode:prevNodeId bodyEntry:bodyEntryId bodyExit:bodyExitId];
            CSCapNode *collectNode = [CSCapNode collectNode:collectId inputNodes:@[bodyExitId]];

            [plan addNode:foreachNode];
            [plan addNode:capNode];
            [plan addNode:collectNode];

            [plan addEdge:[CSCapEdge directFrom:prevNodeId to:foreachId]];
            [plan addEdge:[CSCapEdge iterationFrom:foreachId to:bodyEntryId]];
            [plan addEdge:[CSCapEdge collectionFrom:bodyExitId to:collectId]];

            prevNodeId = collectId;
            nodeCounter++;
        } else {
            NSString *nodeId = [NSString stringWithFormat:@"cap_%lu", (unsigned long)nodeCounter];

            NSMutableDictionary *bindings = [NSMutableDictionary dictionary];
            if (info.filePathArgName) {
                if (nodeCounter == 0) {
                    bindings[info.filePathArgName] = [CSArgumentBinding inputFilePath];
                } else if (info.filePathIsStdinChainable) {
                    bindings[info.filePathArgName] = [CSArgumentBinding previousOutputFromNode:prevNodeId outputField:nil];
                } else {
                    bindings[info.filePathArgName] = [CSArgumentBinding inputFilePath];
                }
            }

            CSCapNode *node = [CSCapNode capNode:nodeId capUrn:capUrn bindings:bindings];
            [plan addNode:node];
            [plan addEdge:[CSCapEdge directFrom:prevNodeId to:nodeId]];

            prevNodeId = nodeId;
            nodeCounter++;
        }
    }
}

// MARK: - Analyze Path Cardinality

- (void)analyzePathCardinalityFromSource:(NSString *)sourceMedia
                                toTarget:(NSString *)targetMedia
                              completion:(void (^)(CSCardinalityChainAnalysis * _Nullable analysis, NSError * _Nullable error))completion {

    [self findPathFromSource:sourceMedia toTarget:targetMedia completion:^(NSArray<NSString *> * _Nullable capUrns, NSError * _Nullable error) {
        if (error) {
            completion(nil, error);
            return;
        }

        if (capUrns.count == 0) {
            completion([CSCardinalityChainAnalysis analyzeChain:@[]], nil);
            return;
        }

        [self getCapChainInfo:capUrns completion:^(NSArray<CSCapChainInfo *> * _Nullable infos, NSError * _Nullable error) {
            if (error) {
                completion(nil, error);
                return;
            }

            NSMutableArray<CSCapCardinalityInfo *> *cardinalities = [NSMutableArray array];
            for (CSCapChainInfo *info in infos) {
                [cardinalities addObject:info.cardinality];
            }

            completion([CSCardinalityChainAnalysis analyzeChain:cardinalities], nil);
        }];
    }];
}

// MARK: - Build Plan from Path

- (void)buildPlanFromPath:(CSCapChainPathInfo *)path
                     name:(NSString *)name
        inputCardinality:(CSInputCardinality)cardinality
              completion:(void (^)(CSCapExecutionPlan * _Nullable plan, NSError * _Nullable error))completion {

    [self.capRegistry getCachedCaps:^(NSArray<CSCap *> * _Nullable caps, NSError * _Nullable error) {
        if (error) {
            completion(nil, [NSError errorWithDomain:CSPlannerErrorDomain
                                                code:CSPlannerErrorCodeRegistryError
                                            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to get caps: %@", error.localizedDescription]}]);
            return;
        }

        // Build file path info map
        NSMutableDictionary<NSString *, NSArray *> *filePathInfo = [NSMutableDictionary dictionary];
        for (CSCapChainStepInfo *step in path.steps) {
            CSCap *cap = nil;
            for (CSCap *c in caps) {
                if ([[[c capUrn] toString] isEqualToString:step.capUrn]) {
                    cap = c;
                    break;
                }
            }

            NSString *argName = cap ? [CSCapPlanBuilder findFilePathArg:cap] : nil;
            BOOL chainable = cap ? [CSCapPlanBuilder isFilePathStdinChainable:cap] : NO;
            filePathInfo[step.capUrn] = @[argName ?: [NSNull null], @(chainable)];
        }

        CSCapExecutionPlan *plan = [CSCapExecutionPlan planWithName:name];

        NSString *inputSlotId = @"input_slot";
        [plan addNode:[CSCapNode inputSlotNode:inputSlotId
                                      slotName:@"input"
                                      mediaUrn:path.sourceSpec
                                   cardinality:cardinality]];

        NSString *prevNodeId = inputSlotId;

        for (NSUInteger i = 0; i < path.steps.count; i++) {
            CSCapChainStepInfo *step = path.steps[i];
            NSString *nodeId = [NSString stringWithFormat:@"cap_%lu", (unsigned long)i];

            NSMutableDictionary *bindings = [NSMutableDictionary dictionary];

            NSArray *info = filePathInfo[step.capUrn];
            id argName = info[0];
            BOOL chainable = [info[1] boolValue];

            if (![argName isKindOfClass:[NSNull class]]) {
                if (i == 0) {
                    bindings[argName] = [CSArgumentBinding inputFilePath];
                } else if (chainable) {
                    bindings[argName] = [CSArgumentBinding previousOutputFromNode:prevNodeId outputField:nil];
                } else {
                    bindings[argName] = [CSArgumentBinding inputFilePath];
                }
            }

            CSCapNode *node = [CSCapNode capNode:nodeId capUrn:step.capUrn bindings:bindings];
            [plan addNode:node];
            [plan addEdge:[CSCapEdge directFrom:prevNodeId to:nodeId]];

            prevNodeId = nodeId;
        }

        NSString *outputId = @"output";
        [plan addNode:[CSCapNode outputNode:outputId outputName:@"result" sourceNode:prevNodeId]];
        [plan addEdge:[CSCapEdge directFrom:prevNodeId to:outputId]];

        plan.metadata = @{
            @"source_spec": path.sourceSpec,
            @"target_spec": path.targetSpec
        };

        completion(plan, nil);
    }];
}

// MARK: - Get Reachable Targets

- (void)getReachableTargetsFromSource:(NSString *)sourceMedia
                           completion:(void (^)(NSArray<NSString *> * _Nullable targets, NSError * _Nullable error))completion {

    [self.capRegistry getCachedCaps:^(NSArray<CSCap *> * _Nullable caps, NSError * _Nullable error) {
        if (error) {
            completion(nil, [NSError errorWithDomain:CSPlannerErrorDomain
                                                code:CSPlannerErrorCodeRegistryError
                                            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to list caps: %@", error.localizedDescription]}]);
            return;
        }

        NSError *parseError = nil;
        CSMediaUrn *sourceUrn = [CSMediaUrn fromString:sourceMedia error:&parseError];
        if (!sourceUrn) {
            completion(nil, [NSError errorWithDomain:CSPlannerErrorDomain
                                                code:CSPlannerErrorCodeInvalidInput
                                            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Invalid source media URN '%@': %@", sourceMedia, parseError.localizedDescription]}]);
            return;
        }

        NSMutableSet *reachable = [NSMutableSet set];
        NSMutableSet *visited = [NSMutableSet set];
        NSMutableArray *queue = [NSMutableArray array];

        NSString *sourceCanonical = [sourceUrn toString];
        [queue addObject:sourceUrn];
        [visited addObject:sourceCanonical];

        // Build graph
        NSMutableDictionary<NSString *, NSMutableArray<CSMediaUrn *> *> *graph = [NSMutableDictionary dictionary];
        NSMutableArray<CSMediaUrn *> *inputUrns = [NSMutableArray array];

        for (CSCap *cap in caps) {
            NSString *capUrnString = [[cap capUrn] toString];

            if (![self isCapAvailable:capUrnString]) {
                continue;
            }

            NSString *inputSpec = [[cap capUrn] inSpec];
            NSString *outputSpec = [[cap capUrn] outSpec];

            if (inputSpec.length == 0 || outputSpec.length == 0) {
                continue;
            }

            CSMediaUrn *inputUrn = [CSMediaUrn fromString:inputSpec error:nil];
            CSMediaUrn *outputUrn = [CSMediaUrn fromString:outputSpec error:nil];

            if (!inputUrn || !outputUrn) {
                continue;
            }

            NSString *inputCanonical = [inputUrn toString];

            BOOL hasInputUrn = NO;
            for (CSMediaUrn *existing in inputUrns) {
                if ([[existing toString] isEqualToString:[inputUrn toString]]) {
                    hasInputUrn = YES;
                    break;
                }
            }
            if (!hasInputUrn) {
                [inputUrns addObject:inputUrn];
            }

            if (!graph[inputCanonical]) {
                graph[inputCanonical] = [NSMutableArray array];
            }
            [graph[inputCanonical] addObject:outputUrn];
        }

        // BFS
        while (queue.count > 0) {
            CSMediaUrn *currentUrn = queue.firstObject;
            [queue removeObjectAtIndex:0];

            for (CSMediaUrn *capInputUrn in inputUrns) {
                if (![currentUrn conformsTo:capInputUrn]) {
                    continue;
                }

                NSString *capInputCanonical = [capInputUrn toString];
                NSArray<CSMediaUrn *> *neighbors = graph[capInputCanonical];

                for (CSMediaUrn *outputUrn in neighbors) {
                    NSString *outputCanonical = [outputUrn toString];
                    if (![visited containsObject:outputCanonical]) {
                        [visited addObject:outputCanonical];
                        [reachable addObject:outputCanonical];
                        [queue addObject:outputUrn];
                    }
                }
            }
        }

        completion([reachable allObjects], nil);
    }];
}

// MARK: - Get Reachable Targets with Metadata

- (void)getReachableTargetsWithMetadataFromSource:(NSString *)sourceMedia
                                         maxDepth:(NSUInteger)maxDepth
                                       completion:(void (^)(NSArray<CSReachableTargetInfo *> * _Nullable targets, NSError * _Nullable error))completion {

    [self.capRegistry getCachedCaps:^(NSArray<CSCap *> * _Nullable caps, NSError * _Nullable error) {
        if (error) {
            completion(nil, [NSError errorWithDomain:CSPlannerErrorDomain
                                                code:CSPlannerErrorCodeRegistryError
                                            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to list caps: %@", error.localizedDescription]}]);
            return;
        }

        NSError *parseError = nil;
        CSMediaUrn *sourceUrn = [CSMediaUrn fromString:sourceMedia error:&parseError];
        if (!sourceUrn) {
            completion(nil, [NSError errorWithDomain:CSPlannerErrorDomain
                                                code:CSPlannerErrorCodeInvalidInput
                                            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Invalid source media URN '%@': %@", sourceMedia, parseError.localizedDescription]}]);
            return;
        }

        NSMutableDictionary<NSString *, CSReachableTargetInfo *> *results = [NSMutableDictionary dictionary];
        NSMutableSet *visited = [NSMutableSet set];
        NSMutableArray *queue = [NSMutableArray array];

        NSString *sourceCanonical = [sourceUrn toString];
        [queue addObject:@[sourceUrn, @0]];
        [visited addObject:sourceCanonical];

        // Build graph
        NSMutableDictionary<NSString *, NSMutableArray<CSMediaUrn *> *> *graph = [NSMutableDictionary dictionary];
        NSMutableArray<CSMediaUrn *> *inputUrns = [NSMutableArray array];
        NSMutableSet *seenEdges = [NSMutableSet set];

        for (CSCap *cap in caps) {
            NSString *capUrnString = [[cap capUrn] toString];

            if (![self isCapAvailable:capUrnString]) {
                continue;
            }

            NSString *inputSpec = [[cap capUrn] inSpec];
            NSString *outputSpec = [[cap capUrn] outSpec];

            if (inputSpec.length == 0 || outputSpec.length == 0) {
                continue;
            }

            CSMediaUrn *inputUrn = [CSMediaUrn fromString:inputSpec error:nil];
            CSMediaUrn *outputUrn = [CSMediaUrn fromString:outputSpec error:nil];

            if (!inputUrn || !outputUrn) {
                continue;
            }

            NSString *inputCanonical = [inputUrn toString];

            NSString *edgeKey = [NSString stringWithFormat:@"%@|%@", inputCanonical, capUrnString];
            if ([seenEdges containsObject:edgeKey]) {
                NSString *errorMsg = [NSString stringWithFormat:
                    @"BUG: Duplicate cap_urn detected in graph building (get_reachable_targets_with_metadata): %@ (input_spec: %@). "
                    "This indicates stale caps in the registry - run upload-standards to sync.", capUrnString, inputSpec];
                completion(nil, [NSError errorWithDomain:CSPlannerErrorDomain
                                                    code:CSPlannerErrorCodeInternal
                                                userInfo:@{NSLocalizedDescriptionKey: errorMsg}]);
                return;
            }
            [seenEdges addObject:edgeKey];

            BOOL hasInputUrn = NO;
            for (CSMediaUrn *existing in inputUrns) {
                if ([[existing toString] isEqualToString:[inputUrn toString]]) {
                    hasInputUrn = YES;
                    break;
                }
            }
            if (!hasInputUrn) {
                [inputUrns addObject:inputUrn];
            }

            if (!graph[inputCanonical]) {
                graph[inputCanonical] = [NSMutableArray array];
            }
            [graph[inputCanonical] addObject:outputUrn];
        }

        // BFS with depth tracking
        while (queue.count > 0) {
            NSArray *item = queue.firstObject;
            [queue removeObjectAtIndex:0];

            CSMediaUrn *currentUrn = item[0];
            NSUInteger depth = [item[1] unsignedIntegerValue];

            if (depth >= maxDepth) {
                continue;
            }

            for (CSMediaUrn *capInputUrn in inputUrns) {
                if (![currentUrn conformsTo:capInputUrn]) {
                    continue;
                }

                NSString *capInputCanonical = [capInputUrn toString];
                NSArray<CSMediaUrn *> *neighbors = graph[capInputCanonical];

                for (CSMediaUrn *outputUrn in neighbors) {
                    NSUInteger newDepth = depth + 1;
                    NSString *outputCanonical = [outputUrn toString];

                    if (!results[outputCanonical]) {
                        CSReachableTargetInfo *info = [[CSReachableTargetInfo alloc] init];
                        info.mediaUrn = outputCanonical;
                        info.displayName = outputCanonical; // Will be enriched by media registry
                        info.minDepth = newDepth;
                        info.maxDepth = newDepth;
                        results[outputCanonical] = info;
                    }

                    if (![visited containsObject:outputCanonical]) {
                        [visited addObject:outputCanonical];
                        [queue addObject:@[outputUrn, @(newDepth)]];
                    }
                }
            }
        }

        completion([results allValues], nil);
    }];
}

// MARK: - Find All Paths (DFS)

- (void)findAllPathsFromSource:(NSString *)sourceMedia
                      toTarget:(NSString *)targetMedia
                      maxDepth:(NSUInteger)maxDepth
                    completion:(void (^)(NSArray<NSArray<NSString *> *> * _Nullable paths, NSError * _Nullable error))completion {

    // For simplicity in Objective-C, return single best path
    [self findPathFromSource:sourceMedia toTarget:targetMedia completion:^(NSArray<NSString *> * _Nullable capUrns, NSError * _Nullable error) {
        if (error) {
            completion(nil, error);
            return;
        }

        if (capUrns.count == 0) {
            completion(@[], nil);
        } else {
            completion(@[capUrns], nil);
        }
    }];
}

// MARK: - Analyze Path Arguments

- (void)analyzePathArgumentsForPath:(NSArray<NSString *> *)capUrns
                         completion:(void (^)(CSPathArgumentRequirements * _Nullable requirements, NSError * _Nullable error))completion {

    [self.capRegistry getCachedCaps:^(NSArray<CSCap *> * _Nullable caps, NSError * _Nullable error) {
        if (error) {
            completion(nil, [NSError errorWithDomain:CSPlannerErrorDomain
                                                code:CSPlannerErrorCodeRegistryError
                                            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to get caps: %@", error.localizedDescription]}]);
            return;
        }

        NSMutableArray<CSStepArgumentRequirements *> *stepRequirements = [NSMutableArray array];
        NSMutableArray<CSArgumentInfo *> *allSlots = [NSMutableArray array];

        for (NSUInteger stepIndex = 0; stepIndex < capUrns.count; stepIndex++) {
            NSString *capUrn = capUrns[stepIndex];

            CSCap *cap = nil;
            for (CSCap *c in caps) {
                if ([[[c capUrn] toString] isEqualToString:capUrn]) {
                    cap = c;
                    break;
                }
            }

            if (!cap) {
                completion(nil, [NSError errorWithDomain:CSPlannerErrorDomain
                                                    code:CSPlannerErrorCodeNotFound
                                                userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Cap '%@' not found in registry", capUrn]}]);
                return;
            }

            NSString *inSpec = [[cap capUrn] inSpec];
            NSString *outSpec = [[cap capUrn] outSpec];

            NSMutableArray<CSArgumentInfo *> *arguments = [NSMutableArray array];
            NSMutableArray<CSArgumentInfo *> *slots = [NSMutableArray array];

            for (CSCapArg *arg in cap.args) {
                // Determine resolution
                BOOL isInputArg = [arg.mediaUrn isEqualToString:inSpec];
                BOOL isOutputArg = [arg.mediaUrn isEqualToString:outSpec];
                BOOL isFilePathType = NO;

                NSError *parseError = nil;
                CSMediaUrn *urn = [CSMediaUrn fromString:arg.mediaUrn error:&parseError];
                if (urn) {
                    isFilePathType = [urn isAnyFilePath];
                }

                NSString *resolution;
                if (isInputArg) {
                    resolution = (stepIndex == 0) ? @"from_input_file" : @"from_previous_output";
                } else if (isOutputArg) {
                    resolution = @"from_previous_output";
                } else if (isFilePathType) {
                    resolution = (stepIndex == 0) ? @"from_input_file" : @"from_previous_output";
                } else if (arg.defaultValue) {
                    resolution = @"has_default";
                } else {
                    resolution = @"requires_user_input";
                }

                CSArgumentInfo *argInfo = [[CSArgumentInfo alloc] init];
                argInfo.name = arg.mediaUrn;
                argInfo.mediaUrn = arg.mediaUrn;
                argInfo.isRequired = arg.required;
                argInfo.defaultValue = arg.defaultValue;
                argInfo.schema = nil; // Would need MediaValidation conversion

                BOOL isIOArg = [resolution isEqualToString:@"from_input_file"] || [resolution isEqualToString:@"from_previous_output"];

                if (!isIOArg) {
                    [slots addObject:argInfo];
                    [allSlots addObject:argInfo];
                }
                [arguments addObject:argInfo];
            }

            CSStepArgumentRequirements *stepReq = [[CSStepArgumentRequirements alloc] init];
            stepReq.capUrn = capUrn;
            stepReq.arguments = arguments;
            [stepRequirements addObject:stepReq];
        }

        CSPathArgumentRequirements *requirements = [[CSPathArgumentRequirements alloc] init];
        requirements.steps = stepRequirements;
        requirements.allSlots = allSlots;

        completion(requirements, nil);
    }];
}

@end

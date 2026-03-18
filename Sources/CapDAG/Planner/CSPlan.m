//
//  CSPlan.m
//  CapDAG
//
//  Cap Execution Plan structures
//  Mirrors Rust: src/planner/plan.rs
//

#import "CSPlan.h"
#import "CSArgumentBinding.h"
#import "CSCardinality.h"

// MARK: - MachinePlanEdge

@implementation CSMachinePlanEdge

+ (instancetype)directFrom:(NSString *)from to:(NSString *)to {
    CSMachinePlanEdge *edge = [[CSMachinePlanEdge alloc] init];
    edge.fromNode = from;
    edge.toNode = to;
    edge.edgeType = CSEdgeTypeDirect;
    return edge;
}

+ (instancetype)iterationFrom:(NSString *)from to:(NSString *)to {
    CSMachinePlanEdge *edge = [[CSMachinePlanEdge alloc] init];
    edge.fromNode = from;
    edge.toNode = to;
    edge.edgeType = CSEdgeTypeIteration;
    return edge;
}

+ (instancetype)collectionFrom:(NSString *)from to:(NSString *)to {
    CSMachinePlanEdge *edge = [[CSMachinePlanEdge alloc] init];
    edge.fromNode = from;
    edge.toNode = to;
    edge.edgeType = CSEdgeTypeCollection;
    return edge;
}

+ (instancetype)jsonFieldFrom:(NSString *)from to:(NSString *)to field:(NSString *)field {
    CSMachinePlanEdge *edge = [[CSMachinePlanEdge alloc] init];
    edge.fromNode = from;
    edge.toNode = to;
    edge.edgeType = CSEdgeTypeJsonField;
    edge.jsonField = field;
    return edge;
}

+ (instancetype)jsonPathFrom:(NSString *)from to:(NSString *)to path:(NSString *)path {
    CSMachinePlanEdge *edge = [[CSMachinePlanEdge alloc] init];
    edge.fromNode = from;
    edge.toNode = to;
    edge.edgeType = CSEdgeTypeJsonPath;
    edge.jsonPath = path;
    return edge;
}

@end

// MARK: - MachineNode

@implementation CSMachineNode

+ (instancetype)capNode:(NSString *)nodeId capUrn:(NSString *)capUrn {
    return [self capNode:nodeId capUrn:capUrn bindings:@{} preferredCap:nil];
}

+ (instancetype)capNode:(NSString *)nodeId capUrn:(NSString *)capUrn bindings:(NSDictionary<NSString *, CSArgumentBinding *> *)bindings {
    return [self capNode:nodeId capUrn:capUrn bindings:bindings preferredCap:nil];
}

+ (instancetype)capNode:(NSString *)nodeId capUrn:(NSString *)capUrn bindings:(NSDictionary<NSString *, CSArgumentBinding *> *)bindings preferredCap:(nullable NSString *)preferredCap {
    CSMachineNode *node = [[CSMachineNode alloc] init];
    node.nodeId = nodeId;
    node.capUrn = capUrn;
    node.argBindings = bindings;
    node.preferredCap = preferredCap;
    return node;
}

+ (instancetype)forEachNode:(NSString *)nodeId inputNode:(NSString *)inputNode bodyEntry:(NSString *)bodyEntry bodyExit:(NSString *)bodyExit {
    CSMachineNode *node = [[CSMachineNode alloc] init];
    node.nodeId = nodeId;
    node.inputNode = inputNode;
    node.bodyEntry = bodyEntry;
    node.bodyExit = bodyExit;
    node.nodeDescription = @"Fan-out: process each item in vector";
    return node;
}

+ (instancetype)collectNode:(NSString *)nodeId inputNodes:(NSArray<CSNodeId> *)inputNodes {
    CSMachineNode *node = [[CSMachineNode alloc] init];
    node.nodeId = nodeId;
    node.inputNodes = inputNodes;
    node.nodeDescription = @"Fan-in: collect results into vector";
    return node;
}

+ (instancetype)inputSlotNode:(NSString *)nodeId slotName:(NSString *)slotName mediaUrn:(NSString *)mediaUrn cardinality:(CSInputCardinality)cardinality {
    CSMachineNode *node = [[CSMachineNode alloc] init];
    node.nodeId = nodeId;
    node.slotName = slotName;
    node.expectedMediaUrn = mediaUrn;
    node.cardinality = cardinality;
    node.nodeDescription = [NSString stringWithFormat:@"Input: %@", slotName];
    return node;
}

+ (instancetype)outputNode:(NSString *)nodeId outputName:(NSString *)outputName sourceNode:(NSString *)sourceNode {
    CSMachineNode *node = [[CSMachineNode alloc] init];
    node.nodeId = nodeId;
    node.outputName = outputName;
    node.sourceNode = sourceNode;
    node.nodeDescription = [NSString stringWithFormat:@"Output: %@", outputName];
    return node;
}

+ (instancetype)wrapInListNode:(NSString *)nodeId
                  itemMediaUrn:(NSString *)itemMediaUrn
                  listMediaUrn:(NSString *)listMediaUrn {
    CSMachineNode *node = [[CSMachineNode alloc] init];
    node.nodeId = nodeId;
    node.wrapItemMediaUrn = itemMediaUrn;
    node.wrapListMediaUrn = listMediaUrn;
    node.nodeDescription = @"WrapInList: wrap scalar in list-of-one";
    return node;
}

- (BOOL)isCap {
    return self.capUrn != nil;
}

- (BOOL)isFanOut {
    return self.bodyEntry != nil && self.bodyExit != nil;
}

- (BOOL)isFanIn {
    return self.inputNodes != nil && self.inputNodes.count > 0;
}

- (BOOL)isWrapInList {
    return self.wrapItemMediaUrn != nil && self.wrapListMediaUrn != nil;
}

@end

// MARK: - MachinePlan

@implementation CSMachinePlan

+ (instancetype)planWithName:(NSString *)name {
    CSMachinePlan *plan = [[CSMachinePlan alloc] init];
    plan.name = name;
    plan.nodes = [NSMutableDictionary dictionary];
    plan.edges = [NSMutableArray array];
    plan.entryNodes = [NSMutableArray array];
    plan.outputNodes = [NSMutableArray array];
    return plan;
}

- (void)addNode:(CSMachineNode *)node {
    NSString *nodeId = node.nodeId;

    // Track entry/output nodes
    if (node.slotName) {
        // InputSlot node
        [self.entryNodes addObject:nodeId];
    } else if (node.outputName) {
        // Output node
        [self.outputNodes addObject:nodeId];
    }

    self.nodes[nodeId] = node;
}

- (void)addEdge:(CSMachinePlanEdge *)edge {
    [self.edges addObject:edge];
}

- (nullable CSMachineNode *)getNode:(NSString *)nodeId {
    return self.nodes[nodeId];
}

- (NSError * _Nullable)validate {
    // Check all edge references exist
    for (CSMachinePlanEdge *edge in self.edges) {
        if (!self.nodes[edge.fromNode]) {
            return [NSError errorWithDomain:@"CSPlannerError"
                                       code:1
                                   userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:
                                       @"Edge from_node '%@' not found in plan", edge.fromNode]}];
        }
        if (!self.nodes[edge.toNode]) {
            return [NSError errorWithDomain:@"CSPlannerError"
                                       code:1
                                   userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:
                                       @"Edge to_node '%@' not found in plan", edge.toNode]}];
        }
    }

    // Check entry nodes exist
    for (NSString *entry in self.entryNodes) {
        if (!self.nodes[entry]) {
            return [NSError errorWithDomain:@"CSPlannerError"
                                       code:1
                                   userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:
                                       @"Entry node '%@' not found in plan", entry]}];
        }
    }

    // Check output nodes exist
    for (NSString *output in self.outputNodes) {
        if (!self.nodes[output]) {
            return [NSError errorWithDomain:@"CSPlannerError"
                                       code:1
                                   userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:
                                       @"Output node '%@' not found in plan", output]}];
        }
    }

    return nil;
}

- (nullable NSArray<CSMachineNode *> *)topologicalOrder:(NSError **)error {
    NSMutableDictionary<NSString *, NSNumber *> *inDegree = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *adj = [NSMutableDictionary dictionary];

    // Initialize
    for (NSString *nodeId in self.nodes) {
        inDegree[nodeId] = @0;
        adj[nodeId] = [NSMutableArray array];
    }

    // Build adjacency list and count in-degrees
    for (CSMachinePlanEdge *edge in self.edges) {
        inDegree[edge.toNode] = @([inDegree[edge.toNode] integerValue] + 1);
        [adj[edge.fromNode] addObject:edge.toNode];
    }

    // Queue nodes with in-degree 0
    NSMutableArray<NSString *> *queue = [NSMutableArray array];
    for (NSString *nodeId in inDegree) {
        if ([inDegree[nodeId] integerValue] == 0) {
            [queue addObject:nodeId];
        }
    }

    NSMutableArray<CSMachineNode *> *result = [NSMutableArray array];

    while (queue.count > 0) {
        NSString *nodeId = queue.firstObject;
        [queue removeObjectAtIndex:0];

        CSMachineNode *node = self.nodes[nodeId];
        if (node) {
            [result addObject:node];
        }

        NSArray<NSString *> *neighbors = adj[nodeId];
        for (NSString *neighbor in neighbors) {
            NSInteger degree = [inDegree[neighbor] integerValue] - 1;
            inDegree[neighbor] = @(degree);
            if (degree == 0) {
                [queue addObject:neighbor];
            }
        }
    }

    if (result.count != self.nodes.count) {
        if (error) {
            *error = [NSError errorWithDomain:@"CSPlannerError"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Cycle detected in execution plan"}];
        }
        return nil;
    }

    return result;
}

+ (instancetype)singleCapPlan:(NSString *)capUrn inputMedia:(NSString *)inputMedia outputMedia:(NSString *)outputMedia filePathArgName:(NSString *)filePathArgName {
    CSMachinePlan *plan = [self planWithName:[NSString stringWithFormat:@"Single cap: %@", capUrn]];

    // Add input slot
    NSString *inputId = @"input_slot";
    [plan addNode:[CSMachineNode inputSlotNode:inputId
                                  slotName:@"input"
                                  mediaUrn:inputMedia
                               cardinality:CSInputCardinalitySingle]];

    // Add cap node
    NSString *capId = @"cap_0";
    CSArgumentBinding *filePathBinding = [CSArgumentBinding inputFilePath];
    NSDictionary *bindings = @{filePathArgName: filePathBinding};
    [plan addNode:[CSMachineNode capNode:capId capUrn:capUrn bindings:bindings]];
    [plan addEdge:[CSMachinePlanEdge directFrom:inputId to:capId]];

    // Add output node
    NSString *outputId = @"output";
    [plan addNode:[CSMachineNode outputNode:outputId outputName:@"result" sourceNode:capId]];
    [plan addEdge:[CSMachinePlanEdge directFrom:capId to:outputId]];

    return plan;
}

+ (instancetype)linearChainPlan:(NSArray<NSString *> *)capUrns inputMedia:(NSString *)inputMedia outputMedia:(NSString *)outputMedia filePathArgNames:(NSArray<NSString *> *)filePathArgNames {
    CSMachinePlan *plan = [self planWithName:@"Linear cap chain"];

    if (capUrns.count == 0) {
        return plan;
    }

    // Add input slot
    NSString *inputId = @"input_slot";
    [plan addNode:[CSMachineNode inputSlotNode:inputId
                                  slotName:@"input"
                                  mediaUrn:inputMedia
                               cardinality:CSInputCardinalitySingle]];

    NSString *prevId = inputId;

    // Add cap nodes
    for (NSUInteger i = 0; i < capUrns.count; i++) {
        NSString *urn = capUrns[i];
        NSString *capId = [NSString stringWithFormat:@"cap_%lu", (unsigned long)i];

        NSDictionary *bindings = @{};
        if (i < filePathArgNames.count) {
            NSString *argName = filePathArgNames[i];
            CSArgumentBinding *filePathBinding = [CSArgumentBinding inputFilePath];
            bindings = @{argName: filePathBinding};
        }

        [plan addNode:[CSMachineNode capNode:capId capUrn:urn bindings:bindings]];
        [plan addEdge:[CSMachinePlanEdge directFrom:prevId to:capId]];
        prevId = capId;
    }

    // Add output node
    NSString *outputId = @"output";
    [plan addNode:[CSMachineNode outputNode:outputId outputName:@"result" sourceNode:prevId]];
    [plan addEdge:[CSMachinePlanEdge directFrom:prevId to:outputId]];

    return plan;
}

// MARK: - Plan Decomposition

- (BOOL)hasForeachOrCollect {
    for (NSString *nodeId in self.nodes) {
        CSMachineNode *node = self.nodes[nodeId];
        if ([node isFanOut] || [node isFanIn]) {
            return YES;
        }
    }
    return NO;
}

- (nullable NSString *)findFirstForeach {
    NSError *error = nil;
    NSArray<CSMachineNode *> *topo = [self topologicalOrder:&error];
    if (!topo) return nil;

    for (CSMachineNode *node in topo) {
        if ([node isFanOut]) {
            return node.nodeId;
        }
    }
    return nil;
}

- (nullable CSMachinePlan *)extractPrefixTo:(NSString *)targetNodeId
                                           error:(NSError **)error {
    if (!self.nodes[targetNodeId]) {
        if (error) {
            *error = [NSError errorWithDomain:@"CSPlannerError" code:1
                                     userInfo:@{NSLocalizedDescriptionKey:
                [NSString stringWithFormat:@"Target node '%@' not found in plan", targetNodeId]}];
        }
        return nil;
    }

    // Build reverse adjacency: toNode -> [fromNode]
    NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *reverseAdj = [NSMutableDictionary dictionary];
    for (CSMachinePlanEdge *edge in self.edges) {
        if (!reverseAdj[edge.toNode]) {
            reverseAdj[edge.toNode] = [NSMutableArray array];
        }
        [reverseAdj[edge.toNode] addObject:edge.fromNode];
    }

    // BFS backward from target to find all ancestors
    NSMutableSet<NSString *> *ancestors = [NSMutableSet setWithObject:targetNodeId];
    NSMutableArray<NSString *> *queue = [NSMutableArray arrayWithObject:targetNodeId];

    while (queue.count > 0) {
        NSString *nodeId = queue.firstObject;
        [queue removeObjectAtIndex:0];

        NSArray<NSString *> *parents = reverseAdj[nodeId];
        for (NSString *parent in parents) {
            if (![ancestors containsObject:parent]) {
                [ancestors addObject:parent];
                [queue addObject:parent];
            }
        }
    }

    // Build sub-plan with ancestor nodes (skip original Output nodes)
    CSMachinePlan *subPlan = [CSMachinePlan planWithName:
        [NSString stringWithFormat:@"%@ [prefix to %@]", self.name, targetNodeId]];

    for (NSString *nodeId in ancestors) {
        CSMachineNode *node = self.nodes[nodeId];
        if (!node) continue;
        if (node.outputName) continue; // skip Output nodes
        [subPlan addNode:node];
    }

    // Add edges where both endpoints are in ancestors and neither is an Output
    for (CSMachinePlanEdge *edge in self.edges) {
        if ([ancestors containsObject:edge.fromNode] && [ancestors containsObject:edge.toNode]) {
            CSMachineNode *fromNode = self.nodes[edge.fromNode];
            CSMachineNode *toNode = self.nodes[edge.toNode];
            if (fromNode.outputName || toNode.outputName) continue;
            [subPlan addEdge:edge];
        }
    }

    // Add synthetic Output connected to target
    NSString *outputId = [NSString stringWithFormat:@"%@_prefix_output", targetNodeId];
    [subPlan addNode:[CSMachineNode outputNode:outputId outputName:@"prefix_result" sourceNode:targetNodeId]];
    [subPlan addEdge:[CSMachinePlanEdge directFrom:targetNodeId to:outputId]];

    NSError *validateError = [subPlan validate];
    if (validateError) {
        if (error) *error = validateError;
        return nil;
    }
    return subPlan;
}

- (nullable CSMachinePlan *)extractForeachBody:(NSString *)foreachNodeId
                                       itemMediaUrn:(NSString *)itemMediaUrn
                                              error:(NSError **)error {
    CSMachineNode *foreachNode = self.nodes[foreachNodeId];
    if (!foreachNode) {
        if (error) {
            *error = [NSError errorWithDomain:@"CSPlannerError" code:1
                                     userInfo:@{NSLocalizedDescriptionKey:
                [NSString stringWithFormat:@"ForEach node '%@' not found", foreachNodeId]}];
        }
        return nil;
    }

    if (![foreachNode isFanOut]) {
        if (error) {
            *error = [NSError errorWithDomain:@"CSPlannerError" code:1
                                     userInfo:@{NSLocalizedDescriptionKey:
                [NSString stringWithFormat:@"Node '%@' is not a ForEach node", foreachNodeId]}];
        }
        return nil;
    }

    NSString *bodyEntry = foreachNode.bodyEntry;
    NSString *bodyExit = foreachNode.bodyExit;

    // Build forward adjacency
    NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *forwardAdj = [NSMutableDictionary dictionary];
    for (CSMachinePlanEdge *edge in self.edges) {
        if (!forwardAdj[edge.fromNode]) {
            forwardAdj[edge.fromNode] = [NSMutableArray array];
        }
        [forwardAdj[edge.fromNode] addObject:edge.toNode];
    }

    // BFS forward from bodyEntry to find body nodes
    NSMutableSet<NSString *> *bodyNodes = [NSMutableSet setWithObject:bodyEntry];
    NSMutableArray<NSString *> *queue = [NSMutableArray arrayWithObject:bodyEntry];

    while (queue.count > 0) {
        NSString *nodeId = queue.firstObject;
        [queue removeObjectAtIndex:0];

        // Don't traverse past body_exit (unless it IS body_entry)
        if ([nodeId isEqualToString:bodyExit] && ![nodeId isEqualToString:bodyEntry]) {
            continue;
        }

        NSArray<NSString *> *children = forwardAdj[nodeId];
        for (NSString *child in children) {
            CSMachineNode *childNode = self.nodes[child];
            if (!childNode) continue;

            // Don't include Output or Collect nodes from original plan
            if (childNode.outputName || [childNode isFanIn]) {
                // But include body_exit if it matches
                if ([child isEqualToString:bodyExit]) {
                    [bodyNodes addObject:child];
                }
                continue;
            }

            if (![bodyNodes containsObject:child]) {
                [bodyNodes addObject:child];
                [queue addObject:child];
            }
        }
    }

    // Ensure body_exit is included
    [bodyNodes addObject:bodyExit];

    // Build body sub-plan
    CSMachinePlan *bodyPlan = [CSMachinePlan planWithName:
        [NSString stringWithFormat:@"%@ [foreach body %@]", self.name, foreachNodeId]];

    // Add synthetic InputSlot for per-item input
    NSString *inputId = [NSString stringWithFormat:@"%@_body_input", foreachNodeId];
    [bodyPlan addNode:[CSMachineNode inputSlotNode:inputId
                                     slotName:@"item_input"
                                     mediaUrn:itemMediaUrn
                                  cardinality:CSInputCardinalitySingle]];

    // Add body nodes
    for (NSString *nodeId in bodyNodes) {
        CSMachineNode *node = self.nodes[nodeId];
        if (node) {
            [bodyPlan addNode:node];
        }
    }

    // Add edge from synthetic input to body_entry
    [bodyPlan addEdge:[CSMachinePlanEdge directFrom:inputId to:bodyEntry]];

    // Add edges where both endpoints are body nodes (skip Iteration/Collection edges)
    for (CSMachinePlanEdge *edge in self.edges) {
        if ([bodyNodes containsObject:edge.fromNode] && [bodyNodes containsObject:edge.toNode]) {
            if (edge.edgeType == CSEdgeTypeIteration || edge.edgeType == CSEdgeTypeCollection) {
                continue;
            }
            [bodyPlan addEdge:edge];
        }
    }

    // Add synthetic Output connected to body_exit
    NSString *outputId = [NSString stringWithFormat:@"%@_body_output", foreachNodeId];
    [bodyPlan addNode:[CSMachineNode outputNode:outputId outputName:@"item_result" sourceNode:bodyExit]];
    [bodyPlan addEdge:[CSMachinePlanEdge directFrom:bodyExit to:outputId]];

    NSError *validateError = [bodyPlan validate];
    if (validateError) {
        if (error) *error = validateError;
        return nil;
    }
    return bodyPlan;
}

- (nullable CSMachinePlan *)extractSuffixFrom:(NSString *)sourceNodeId
                                    sourceMediaUrn:(NSString *)sourceMediaUrn
                                             error:(NSError **)error {
    if (!self.nodes[sourceNodeId]) {
        if (error) {
            *error = [NSError errorWithDomain:@"CSPlannerError" code:1
                                     userInfo:@{NSLocalizedDescriptionKey:
                [NSString stringWithFormat:@"Source node '%@' not found in plan", sourceNodeId]}];
        }
        return nil;
    }

    // Build forward adjacency
    NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *forwardAdj = [NSMutableDictionary dictionary];
    for (CSMachinePlanEdge *edge in self.edges) {
        if (!forwardAdj[edge.fromNode]) {
            forwardAdj[edge.fromNode] = [NSMutableArray array];
        }
        [forwardAdj[edge.fromNode] addObject:edge.toNode];
    }

    // BFS forward from source to find all descendants
    NSMutableSet<NSString *> *descendants = [NSMutableSet setWithObject:sourceNodeId];
    NSMutableArray<NSString *> *queue = [NSMutableArray arrayWithObject:sourceNodeId];

    while (queue.count > 0) {
        NSString *nodeId = queue.firstObject;
        [queue removeObjectAtIndex:0];

        NSArray<NSString *> *children = forwardAdj[nodeId];
        for (NSString *child in children) {
            if (![descendants containsObject:child]) {
                [descendants addObject:child];
                [queue addObject:child];
            }
        }
    }

    CSMachinePlan *subPlan = [CSMachinePlan planWithName:
        [NSString stringWithFormat:@"%@ [suffix from %@]", self.name, sourceNodeId]];

    // Add synthetic InputSlot
    NSString *inputId = [NSString stringWithFormat:@"%@_suffix_input", sourceNodeId];
    [subPlan addNode:[CSMachineNode inputSlotNode:inputId
                                    slotName:@"collected_input"
                                    mediaUrn:sourceMediaUrn
                                 cardinality:CSInputCardinalitySingle]];

    // Add descendant nodes (skip source — replaced by InputSlot; skip original InputSlots)
    for (NSString *nodeId in descendants) {
        if ([nodeId isEqualToString:sourceNodeId]) continue;
        CSMachineNode *node = self.nodes[nodeId];
        if (!node) continue;
        if (node.slotName) continue; // skip original InputSlot nodes
        [subPlan addNode:node];
    }

    // Rewire edges: source -> child becomes inputSlot -> child
    for (CSMachinePlanEdge *edge in self.edges) {
        if ([edge.fromNode isEqualToString:sourceNodeId] && [descendants containsObject:edge.toNode]) {
            [subPlan addEdge:[CSMachinePlanEdge directFrom:inputId to:edge.toNode]];
        } else if ([descendants containsObject:edge.fromNode]
                   && [descendants containsObject:edge.toNode]
                   && ![edge.fromNode isEqualToString:sourceNodeId]) {
            [subPlan addEdge:edge];
        }
    }

    NSError *validateError = [subPlan validate];
    if (validateError) {
        if (error) *error = validateError;
        return nil;
    }
    return subPlan;
}

@end

// MARK: - NodeExecutionResult

@implementation CSNodeExecutionResult
@end

// MARK: - MachineResult

@implementation CSMachineResult
@end

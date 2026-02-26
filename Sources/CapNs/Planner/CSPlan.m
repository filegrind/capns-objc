//
//  CSPlan.m
//  CapNs
//
//  Cap Execution Plan structures
//  Mirrors Rust: src/planner/plan.rs
//

#import "CSPlan.h"
#import "CSArgumentBinding.h"
#import "CSCardinality.h"

// MARK: - CapEdge

@implementation CSCapEdge

+ (instancetype)directFrom:(NSString *)from to:(NSString *)to {
    CSCapEdge *edge = [[CSCapEdge alloc] init];
    edge.fromNode = from;
    edge.toNode = to;
    edge.edgeType = CSEdgeTypeDirect;
    return edge;
}

+ (instancetype)iterationFrom:(NSString *)from to:(NSString *)to {
    CSCapEdge *edge = [[CSCapEdge alloc] init];
    edge.fromNode = from;
    edge.toNode = to;
    edge.edgeType = CSEdgeTypeIteration;
    return edge;
}

+ (instancetype)collectionFrom:(NSString *)from to:(NSString *)to {
    CSCapEdge *edge = [[CSCapEdge alloc] init];
    edge.fromNode = from;
    edge.toNode = to;
    edge.edgeType = CSEdgeTypeCollection;
    return edge;
}

+ (instancetype)jsonFieldFrom:(NSString *)from to:(NSString *)to field:(NSString *)field {
    CSCapEdge *edge = [[CSCapEdge alloc] init];
    edge.fromNode = from;
    edge.toNode = to;
    edge.edgeType = CSEdgeTypeJsonField;
    edge.jsonField = field;
    return edge;
}

+ (instancetype)jsonPathFrom:(NSString *)from to:(NSString *)to path:(NSString *)path {
    CSCapEdge *edge = [[CSCapEdge alloc] init];
    edge.fromNode = from;
    edge.toNode = to;
    edge.edgeType = CSEdgeTypeJsonPath;
    edge.jsonPath = path;
    return edge;
}

@end

// MARK: - CapNode

@implementation CSCapNode

+ (instancetype)capNode:(NSString *)nodeId capUrn:(NSString *)capUrn {
    return [self capNode:nodeId capUrn:capUrn bindings:@{} preferredCap:nil];
}

+ (instancetype)capNode:(NSString *)nodeId capUrn:(NSString *)capUrn bindings:(NSDictionary<NSString *, CSArgumentBinding *> *)bindings {
    return [self capNode:nodeId capUrn:capUrn bindings:bindings preferredCap:nil];
}

+ (instancetype)capNode:(NSString *)nodeId capUrn:(NSString *)capUrn bindings:(NSDictionary<NSString *, CSArgumentBinding *> *)bindings preferredCap:(nullable NSString *)preferredCap {
    CSCapNode *node = [[CSCapNode alloc] init];
    node.nodeId = nodeId;
    node.capUrn = capUrn;
    node.argBindings = bindings;
    node.preferredCap = preferredCap;
    return node;
}

+ (instancetype)forEachNode:(NSString *)nodeId inputNode:(NSString *)inputNode bodyEntry:(NSString *)bodyEntry bodyExit:(NSString *)bodyExit {
    CSCapNode *node = [[CSCapNode alloc] init];
    node.nodeId = nodeId;
    node.inputNode = inputNode;
    node.bodyEntry = bodyEntry;
    node.bodyExit = bodyExit;
    node.nodeDescription = @"Fan-out: process each item in vector";
    return node;
}

+ (instancetype)collectNode:(NSString *)nodeId inputNodes:(NSArray<CSNodeId> *)inputNodes {
    CSCapNode *node = [[CSCapNode alloc] init];
    node.nodeId = nodeId;
    node.inputNodes = inputNodes;
    node.nodeDescription = @"Fan-in: collect results into vector";
    return node;
}

+ (instancetype)inputSlotNode:(NSString *)nodeId slotName:(NSString *)slotName mediaUrn:(NSString *)mediaUrn cardinality:(CSInputCardinality)cardinality {
    CSCapNode *node = [[CSCapNode alloc] init];
    node.nodeId = nodeId;
    node.slotName = slotName;
    node.expectedMediaUrn = mediaUrn;
    node.cardinality = cardinality;
    node.nodeDescription = [NSString stringWithFormat:@"Input: %@", slotName];
    return node;
}

+ (instancetype)outputNode:(NSString *)nodeId outputName:(NSString *)outputName sourceNode:(NSString *)sourceNode {
    CSCapNode *node = [[CSCapNode alloc] init];
    node.nodeId = nodeId;
    node.outputName = outputName;
    node.sourceNode = sourceNode;
    node.nodeDescription = [NSString stringWithFormat:@"Output: %@", outputName];
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

@end

// MARK: - CapExecutionPlan

@implementation CSCapExecutionPlan

+ (instancetype)planWithName:(NSString *)name {
    CSCapExecutionPlan *plan = [[CSCapExecutionPlan alloc] init];
    plan.name = name;
    plan.nodes = [NSMutableDictionary dictionary];
    plan.edges = [NSMutableArray array];
    plan.entryNodes = [NSMutableArray array];
    plan.outputNodes = [NSMutableArray array];
    return plan;
}

- (void)addNode:(CSCapNode *)node {
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

- (void)addEdge:(CSCapEdge *)edge {
    [self.edges addObject:edge];
}

- (nullable CSCapNode *)getNode:(NSString *)nodeId {
    return self.nodes[nodeId];
}

- (NSError * _Nullable)validate {
    // Check all edge references exist
    for (CSCapEdge *edge in self.edges) {
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

- (nullable NSArray<CSCapNode *> *)topologicalOrder:(NSError **)error {
    NSMutableDictionary<NSString *, NSNumber *> *inDegree = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *adj = [NSMutableDictionary dictionary];

    // Initialize
    for (NSString *nodeId in self.nodes) {
        inDegree[nodeId] = @0;
        adj[nodeId] = [NSMutableArray array];
    }

    // Build adjacency list and count in-degrees
    for (CSCapEdge *edge in self.edges) {
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

    NSMutableArray<CSCapNode *> *result = [NSMutableArray array];

    while (queue.count > 0) {
        NSString *nodeId = queue.firstObject;
        [queue removeObjectAtIndex:0];

        CSCapNode *node = self.nodes[nodeId];
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
    CSCapExecutionPlan *plan = [self planWithName:[NSString stringWithFormat:@"Single cap: %@", capUrn]];

    // Add input slot
    NSString *inputId = @"input_slot";
    [plan addNode:[CSCapNode inputSlotNode:inputId
                                  slotName:@"input"
                                  mediaUrn:inputMedia
                               cardinality:CSInputCardinalitySingle]];

    // Add cap node
    NSString *capId = @"cap_0";
    CSArgumentBinding *filePathBinding = [CSArgumentBinding inputFilePath];
    NSDictionary *bindings = @{filePathArgName: filePathBinding};
    [plan addNode:[CSCapNode capNode:capId capUrn:capUrn bindings:bindings]];
    [plan addEdge:[CSCapEdge directFrom:inputId to:capId]];

    // Add output node
    NSString *outputId = @"output";
    [plan addNode:[CSCapNode outputNode:outputId outputName:@"result" sourceNode:capId]];
    [plan addEdge:[CSCapEdge directFrom:capId to:outputId]];

    return plan;
}

+ (instancetype)linearChainPlan:(NSArray<NSString *> *)capUrns inputMedia:(NSString *)inputMedia outputMedia:(NSString *)outputMedia filePathArgNames:(NSArray<NSString *> *)filePathArgNames {
    CSCapExecutionPlan *plan = [self planWithName:@"Linear cap chain"];

    if (capUrns.count == 0) {
        return plan;
    }

    // Add input slot
    NSString *inputId = @"input_slot";
    [plan addNode:[CSCapNode inputSlotNode:inputId
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

        [plan addNode:[CSCapNode capNode:capId capUrn:urn bindings:bindings]];
        [plan addEdge:[CSCapEdge directFrom:prevId to:capId]];
        prevId = capId;
    }

    // Add output node
    NSString *outputId = @"output";
    [plan addNode:[CSCapNode outputNode:outputId outputName:@"result" sourceNode:prevId]];
    [plan addEdge:[CSCapEdge directFrom:prevId to:outputId]];

    return plan;
}

@end

// MARK: - NodeExecutionResult

@implementation CSNodeExecutionResult
@end

// MARK: - CapChainExecutionResult

@implementation CSCapChainExecutionResult
@end

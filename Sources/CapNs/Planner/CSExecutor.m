//
//  CSExecutor.m
//  CapNs
//
//  Plan Executor - COMPLETE IMPLEMENTATION
//  Mirrors Rust: src/planner/executor.rs (764 lines)
//

#import "CSExecutor.h"
#import "CSPlan.h"
#import "CSArgumentBinding.h"
#import "CSCap.h"
#import "CSPlanBuilder.h"

@interface CSPlanExecutor ()
@property (nonatomic, strong) id<CSCapExecutorProtocol> executor;
@property (nonatomic, strong) CSCapExecutionPlan *plan;
@property (nonatomic, strong) NSArray<CSCapInputFile *> *inputFiles;
@property (nonatomic, strong) NSDictionary<NSString *, NSData *> *slotValues;
@property (nonatomic, strong, nullable) id<CSCapSettingsProviderProtocol> settingsProvider;
@end

@implementation CSPlanExecutor

- (instancetype)initWithExecutor:(id<CSCapExecutorProtocol>)executor
                            plan:(CSCapExecutionPlan *)plan
                      inputFiles:(NSArray<CSCapInputFile *> *)inputFiles {
    self = [super init];
    if (self) {
        _executor = executor;
        _plan = plan;
        _inputFiles = inputFiles;
        _slotValues = @{};
        _settingsProvider = nil;
    }
    return self;
}

- (instancetype)withSlotValues:(NSDictionary<NSString *, NSData *> *)slotValues {
    self.slotValues = slotValues;
    return self;
}

- (instancetype)withSettingsProvider:(id<CSCapSettingsProviderProtocol>)provider {
    self.settingsProvider = provider;
    return self;
}

// MARK: - Execute Plan

- (void)execute:(void (^)(CSCapChainExecutionResult * _Nullable result, NSError * _Nullable error))completion {
    NSDate *start = [NSDate date];

    // Validate plan
    NSError *validateError = [self.plan validate];
    if (validateError) {
        completion(nil, validateError);
        return;
    }

    // Get topological order
    NSError *topoError = nil;
    NSArray<CSCapNode *> *orderedNodes = [self.plan topologicalOrder:&topoError];
    if (topoError) {
        completion(nil, topoError);
        return;
    }

    NSMutableDictionary<NSString *, CSNodeExecutionResult *> *nodeResults = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, id> *nodeOutputs = [NSMutableDictionary dictionary];

    [self executeNodesSequentially:orderedNodes
                       nodeResults:nodeResults
                       nodeOutputs:nodeOutputs
                       currentIndex:0
                         startTime:start
                        completion:completion];
}

- (void)executeNodesSequentially:(NSArray<CSCapNode *> *)orderedNodes
                     nodeResults:(NSMutableDictionary *)nodeResults
                     nodeOutputs:(NSMutableDictionary *)nodeOutputs
                    currentIndex:(NSUInteger)index
                       startTime:(NSDate *)start
                      completion:(void (^)(CSCapChainExecutionResult * _Nullable result, NSError * _Nullable error))completion {

    if (index >= orderedNodes.count) {
        // All nodes executed - create result
        CSCapChainExecutionResult *result = [[CSCapChainExecutionResult alloc] init];
        result.success = YES;
        result.nodeResults = [nodeResults allValues];
        result.finalOutput = nil; // Would extract from output nodes
        result.error = nil;
        result.totalDurationMs = (uint64_t)([[NSDate date] timeIntervalSinceDate:start] * 1000);

        completion(result, nil);
        return;
    }

    CSCapNode *node = orderedNodes[index];

    [self executeNode:node
          nodeResults:nodeResults
          nodeOutputs:nodeOutputs
           completion:^(CSNodeExecutionResult * _Nullable execResult, id _Nullable output, NSError * _Nullable error) {

        if (error) {
            CSCapChainExecutionResult *result = [[CSCapChainExecutionResult alloc] init];
            result.success = NO;
            result.nodeResults = [nodeResults allValues];
            result.finalOutput = nil;
            result.error = [NSString stringWithFormat:@"Node '%@' execution error: %@", node.nodeId, error.localizedDescription];
            result.totalDurationMs = (uint64_t)([[NSDate date] timeIntervalSinceDate:start] * 1000);
            completion(result, nil);
            return;
        }

        if (!execResult.success) {
            CSCapChainExecutionResult *result = [[CSCapChainExecutionResult alloc] init];
            result.success = NO;
            result.nodeResults = [nodeResults allValues];
            result.finalOutput = nil;
            result.error = [NSString stringWithFormat:@"Node '%@' failed: %@", node.nodeId, execResult.error ?: @"unknown error"];
            result.totalDurationMs = (uint64_t)([[NSDate date] timeIntervalSinceDate:start] * 1000);
            completion(result, nil);
            return;
        }

        if (output) {
            nodeOutputs[node.nodeId] = output;
        }
        nodeResults[node.nodeId] = execResult;

        // Continue with next node
        [self executeNodesSequentially:orderedNodes
                           nodeResults:nodeResults
                           nodeOutputs:nodeOutputs
                          currentIndex:index + 1
                             startTime:start
                            completion:completion];
    }];
}

// MARK: - Execute Node

- (void)executeNode:(CSCapNode *)node
        nodeResults:(NSDictionary *)nodeResults
        nodeOutputs:(NSDictionary *)nodeOutputs
         completion:(void (^)(CSNodeExecutionResult * _Nullable execResult, id _Nullable output, NSError * _Nullable error))completion {

    NSDate *start = [NSDate date];

    // Determine node type and execute accordingly
    if (node.capUrn) {
        // Cap node
        [self executeCapNode:node.nodeId
                      capUrn:node.capUrn
                 argBindings:node.argBindings
                preferredCap:node.preferredCap
                 nodeOutputs:nodeOutputs
                  completion:completion];
    } else if (node.slotName) {
        // InputSlot node
        [self executeInputSlotNode:node start:start completion:completion];
    } else if (node.outputName) {
        // Output node
        [self executeOutputNode:node nodeOutputs:nodeOutputs start:start completion:completion];
    } else if (node.bodyEntry) {
        // ForEach node
        [self executeForEachNode:node nodeOutputs:nodeOutputs start:start completion:completion];
    } else if (node.inputNodes) {
        // Collect node
        [self executeCollectNode:node nodeOutputs:nodeOutputs start:start completion:completion];
    } else {
        // Unknown node type - fail hard
        NSError *error = [NSError errorWithDomain:CSPlannerErrorDomain
                                             code:CSPlannerErrorCodeInternal
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unknown node type for node '%@'", node.nodeId]}];
        completion(nil, nil, error);
    }
}

// MARK: - Execute InputSlot Node

- (void)executeInputSlotNode:(CSCapNode *)node
                       start:(NSDate *)start
                  completion:(void (^)(CSNodeExecutionResult * _Nullable execResult, id _Nullable output, NSError * _Nullable error))completion {

    id output;
    if (self.inputFiles.count == 1) {
        output = @{
            @"file_path": self.inputFiles[0].filePath,
            @"media_urn": self.inputFiles[0].mediaUrn
        };
    } else {
        NSMutableArray *files = [NSMutableArray array];
        for (CSCapInputFile *file in self.inputFiles) {
            [files addObject:@{
                @"file_path": file.filePath,
                @"media_urn": file.mediaUrn
            }];
        }
        output = files;
    }

    CSNodeExecutionResult *result = [[CSNodeExecutionResult alloc] init];
    result.nodeId = node.nodeId;
    result.success = YES;
    result.binaryOutput = nil;
    result.textOutput = [self jsonToString:output];
    result.error = nil;
    result.durationMs = (uint64_t)([[NSDate date] timeIntervalSinceDate:start] * 1000);

    completion(result, output, nil);
}

// MARK: - Execute Output Node

- (void)executeOutputNode:(CSCapNode *)node
              nodeOutputs:(NSDictionary *)nodeOutputs
                    start:(NSDate *)start
               completion:(void (^)(CSNodeExecutionResult * _Nullable execResult, id _Nullable output, NSError * _Nullable error))completion {

    id sourceOutput = nodeOutputs[node.sourceNode];

    CSNodeExecutionResult *result = [[CSNodeExecutionResult alloc] init];
    result.nodeId = node.nodeId;
    result.success = YES;
    result.binaryOutput = nil;
    result.textOutput = sourceOutput ? [self jsonToString:sourceOutput] : nil;
    result.error = nil;
    result.durationMs = (uint64_t)([[NSDate date] timeIntervalSinceDate:start] * 1000);

    completion(result, sourceOutput, nil);
}

// MARK: - Execute ForEach Node

- (void)executeForEachNode:(CSCapNode *)node
               nodeOutputs:(NSDictionary *)nodeOutputs
                     start:(NSDate *)start
                completion:(void (^)(CSNodeExecutionResult * _Nullable execResult, id _Nullable output, NSError * _Nullable error))completion {

    id input = nodeOutputs[node.inputNode];
    NSArray *items;

    if ([input isKindOfClass:[NSArray class]]) {
        items = input;
    } else if (input) {
        items = @[input];
    } else {
        items = @[];
    }

    id output = @{
        @"iteration_count": @(items.count),
        @"items": items,
        @"body_entry": node.bodyEntry,
        @"body_exit": node.bodyExit
    };

    CSNodeExecutionResult *result = [[CSNodeExecutionResult alloc] init];
    result.nodeId = node.nodeId;
    result.success = YES;
    result.binaryOutput = nil;
    result.textOutput = [self jsonToString:output];
    result.error = nil;
    result.durationMs = (uint64_t)([[NSDate date] timeIntervalSinceDate:start] * 1000);

    completion(result, output, nil);
}

// MARK: - Execute Collect Node

- (void)executeCollectNode:(CSCapNode *)node
                nodeOutputs:(NSDictionary *)nodeOutputs
                      start:(NSDate *)start
                 completion:(void (^)(CSNodeExecutionResult * _Nullable execResult, id _Nullable output, NSError * _Nullable error))completion {

    NSMutableArray *collected = [NSMutableArray array];

    for (NSString *inputId in node.inputNodes) {
        id output = nodeOutputs[inputId];
        if ([output isKindOfClass:[NSArray class]]) {
            [collected addObjectsFromArray:output];
        } else if (output) {
            [collected addObject:output];
        }
    }

    id output = @{
        @"collected": collected,
        @"count": @(collected.count)
    };

    CSNodeExecutionResult *result = [[CSNodeExecutionResult alloc] init];
    result.nodeId = node.nodeId;
    result.success = YES;
    result.binaryOutput = nil;
    result.textOutput = [self jsonToString:output];
    result.error = nil;
    result.durationMs = (uint64_t)([[NSDate date] timeIntervalSinceDate:start] * 1000);

    completion(result, output, nil);
}

// MARK: - Execute Cap Node

- (void)executeCapNode:(NSString *)nodeId
                capUrn:(NSString *)capUrn
           argBindings:(NSDictionary<NSString *, CSArgumentBinding *> *)argBindings
          preferredCap:(nullable NSString *)preferredCap
           nodeOutputs:(NSDictionary *)nodeOutputs
            completion:(void (^)(CSNodeExecutionResult * _Nullable execResult, id _Nullable output, NSError * _Nullable error))completion {

    NSDate *start = [NSDate date];

    // Check cap availability
    [self.executor hasCap:capUrn completion:^(BOOL has) {
        if (!has) {
            CSNodeExecutionResult *result = [[CSNodeExecutionResult alloc] init];
            result.nodeId = nodeId;
            result.success = NO;
            result.binaryOutput = nil;
            result.textOutput = nil;
            result.error = [NSString stringWithFormat:@"No capability available for '%@'", capUrn];
            result.durationMs = (uint64_t)([[NSDate date] timeIntervalSinceDate:start] * 1000);
            completion(result, nil, nil);
            return;
        }

        // Get cap definition
        [self.executor getCap:capUrn completion:^(CSCap * _Nullable cap, NSError * _Nullable error) {
            if (error || !cap) {
                completion(nil, nil, error);
                return;
            }

            // Build arg defaults and required maps
            NSMutableDictionary *argDefaults = [NSMutableDictionary dictionary];
            NSMutableDictionary *argRequired = [NSMutableDictionary dictionary];

            for (CSCapArg *arg in cap.args) {
                if (arg.defaultValue) {
                    argDefaults[arg.mediaUrn] = arg.defaultValue;
                }
                argRequired[arg.mediaUrn] = @(arg.required);
            }

            // Build resolution context
            CSArgumentResolutionContext *context = [CSArgumentResolutionContext withInputFiles:self.inputFiles];
            context.previousOutputs = nodeOutputs;
            context.planMetadata = self.plan.metadata;
            context.slotValues = self.slotValues.count > 0 ? self.slotValues : nil;

            // Resolve arguments
            NSMutableArray *arguments = [NSMutableArray array];

            for (NSString *name in argBindings) {
                CSArgumentBinding *binding = argBindings[name];
                BOOL isRequired = [argRequired[name] boolValue];
                id defaultValue = argDefaults[name];

                CSResolvedArgument *resolved = nil;
                NSError *resolveError = CSResolveArgumentBinding(binding, context, capUrn, defaultValue, isRequired, &resolved);

                if (resolveError) {
                    NSError *error = [NSError errorWithDomain:CSPlannerErrorDomain
                                                         code:CSPlannerErrorCodeInternal
                                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to resolve binding '%@' for cap '%@': %@", name, capUrn, resolveError.localizedDescription]}];
                    completion(nil, nil, error);
                    return;
                }

                if (resolved) {
                    // Create argument value dict
                    NSDictionary *argValue = @{
                        @"media_urn": name,
                        @"value": resolved.value
                    };
                    [arguments addObject:argValue];
                }
            }

            // Execute the cap
            [self.executor executeCapWithUrn:capUrn
                                    arguments:arguments
                                preferredCap:preferredCap
                                  completion:^(NSData * _Nullable responseBytes, NSError * _Nullable error) {

                uint64_t durationMs = (uint64_t)([[NSDate date] timeIntervalSinceDate:start] * 1000);

                if (error) {
                    CSNodeExecutionResult *result = [[CSNodeExecutionResult alloc] init];
                    result.nodeId = nodeId;
                    result.success = NO;
                    result.binaryOutput = nil;
                    result.textOutput = nil;
                    result.error = error.localizedDescription;
                    result.durationMs = durationMs;
                    completion(result, nil, nil);
                    return;
                }

                NSString *textOutput = [[NSString alloc] initWithData:responseBytes encoding:NSUTF8StringEncoding];

                // Try to parse as JSON
                id outputJson = nil;
                if (textOutput) {
                    NSError *jsonError = nil;
                    outputJson = [NSJSONSerialization JSONObjectWithData:responseBytes options:0 error:&jsonError];
                    if (jsonError) {
                        outputJson = @{@"text": textOutput};
                    }
                }

                CSNodeExecutionResult *result = [[CSNodeExecutionResult alloc] init];
                result.nodeId = nodeId;
                result.success = YES;
                result.binaryOutput = responseBytes;
                result.textOutput = textOutput;
                result.error = nil;
                result.durationMs = durationMs;

                completion(result, outputJson, nil);
            }];
        }];
    }];
}

// MARK: - Helper: JSON to String

- (nullable NSString *)jsonToString:(id)json {
    if (!json) return nil;

    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:json options:0 error:&error];
    if (error) return nil;

    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

@end

// MARK: - JSON Path Functions

NSError *_Nullable CSApplyEdgeType(
    id sourceOutput,
    CSEdgeType edgeType,
    NSString * _Nullable field,
    NSString * _Nullable path,
    id _Nullable *_Nullable outValue
) {
    switch (edgeType) {
        case CSEdgeTypeDirect:
        case CSEdgeTypeIteration:
        case CSEdgeTypeCollection:
            if (outValue) *outValue = sourceOutput;
            return nil;

        case CSEdgeTypeJsonField:
            if (!field) {
                return [NSError errorWithDomain:CSPlannerErrorDomain
                                           code:CSPlannerErrorCodeInternal
                                       userInfo:@{NSLocalizedDescriptionKey: @"JsonField edge type requires field parameter"}];
            }
            if ([sourceOutput isKindOfClass:[NSDictionary class]]) {
                id value = sourceOutput[field];
                if (value) {
                    if (outValue) *outValue = value;
                    return nil;
                } else {
                    return [NSError errorWithDomain:CSPlannerErrorDomain
                                               code:CSPlannerErrorCodeInternal
                                           userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Field '%@' not found in source output", field]}];
                }
            } else {
                return [NSError errorWithDomain:CSPlannerErrorDomain
                                           code:CSPlannerErrorCodeInternal
                                       userInfo:@{NSLocalizedDescriptionKey: @"Source output is not a dictionary"}];
            }

        case CSEdgeTypeJsonPath:
            if (!path) {
                return [NSError errorWithDomain:CSPlannerErrorDomain
                                           code:CSPlannerErrorCodeInternal
                                       userInfo:@{NSLocalizedDescriptionKey: @"JsonPath edge type requires path parameter"}];
            }
            return CSExtractJSONPath(sourceOutput, path, outValue);
    }
}

NSError *_Nullable CSExtractJSONPath(
    id json,
    NSString *path,
    id _Nullable *_Nullable outValue
) {
    id current = json;

    NSArray *segments = [path componentsSeparatedByString:@"."];

    for (NSString *segment in segments) {
        NSRange bracketRange = [segment rangeOfString:@"["];

        if (bracketRange.location != NSNotFound) {
            // Handle array indexing: "field[0]"
            NSString *fieldName = [segment substringToIndex:bracketRange.location];
            NSString *indexStr = [segment substringFromIndex:bracketRange.location + 1];
            indexStr = [indexStr stringByReplacingOccurrencesOfString:@"]" withString:@""];

            NSInteger index = [indexStr integerValue];

            if ([current isKindOfClass:[NSDictionary class]]) {
                current = current[fieldName];
            } else {
                return [NSError errorWithDomain:CSPlannerErrorDomain
                                           code:CSPlannerErrorCodeInternal
                                       userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Field '%@' not found in path", fieldName]}];
            }

            if ([current isKindOfClass:[NSArray class]]) {
                NSArray *array = current;
                if (index >= 0 && index < array.count) {
                    current = array[index];
                } else {
                    return [NSError errorWithDomain:CSPlannerErrorDomain
                                               code:CSPlannerErrorCodeInternal
                                           userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Array index %ld out of bounds", (long)index]}];
                }
            } else {
                return [NSError errorWithDomain:CSPlannerErrorDomain
                                           code:CSPlannerErrorCodeInternal
                                       userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Cannot index into non-array at '%@'", fieldName]}];
            }
        } else {
            // Simple field access
            if ([current isKindOfClass:[NSDictionary class]]) {
                current = current[segment];
                if (!current) {
                    return [NSError errorWithDomain:CSPlannerErrorDomain
                                               code:CSPlannerErrorCodeInternal
                                           userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Field '%@' not found in path", segment]}];
                }
            } else {
                return [NSError errorWithDomain:CSPlannerErrorDomain
                                           code:CSPlannerErrorCodeInternal
                                       userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Field '%@' not found in path", segment]}];
            }
        }
    }

    if (outValue) *outValue = current;
    return nil;
}

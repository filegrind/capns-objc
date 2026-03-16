//
//  CSPlanDecompositionTests.m
//  CapDAGTests
//
//  Tests for plan decomposition (WrapInList, extract prefix/body/suffix).
//  Mirrors Rust plan.rs tests TEST934-TEST764.
//

#import <XCTest/XCTest.h>
#import "CapDAG.h"

@interface CSPlanDecompositionTests : XCTestCase
@end

// Helper: build plan with ForEach closed by Collect
// Topology: input_slot → cap_0 → foreach_0 --iteration--> body_cap_0 → body_cap_1 --collection--> collect_0 → cap_post → output
static CSCapExecutionPlan *buildForeachPlanWithCollect(void) {
    CSCapExecutionPlan *plan = [CSCapExecutionPlan planWithName:@"ForEach test plan"];

    [plan addNode:[CSCapNode inputSlotNode:@"input_slot" slotName:@"input" mediaUrn:@"media:pdf" cardinality:CSInputCardinalitySingle]];
    [plan addNode:[CSCapNode capNode:@"cap_0" capUrn:@"cap:in=media:pdf;out=media:pdf-page;list"]];
    [plan addNode:[CSCapNode forEachNode:@"foreach_0" inputNode:@"cap_0" bodyEntry:@"body_cap_0" bodyExit:@"body_cap_1"]];
    [plan addNode:[CSCapNode capNode:@"body_cap_0" capUrn:@"cap:in=media:pdf-page;out=media:text;textable"]];
    [plan addNode:[CSCapNode capNode:@"body_cap_1" capUrn:@"cap:in=media:text;textable;out=media:bool;decision;textable"]];
    [plan addNode:[CSCapNode collectNode:@"collect_0" inputNodes:@[@"body_cap_1"]]];
    [plan addNode:[CSCapNode capNode:@"cap_post" capUrn:@"cap:in=media:bool;decision;list;textable;out=media:json;textable"]];
    [plan addNode:[CSCapNode outputNode:@"output" outputName:@"result" sourceNode:@"cap_post"]];

    [plan addEdge:[CSCapEdge directFrom:@"input_slot" to:@"cap_0"]];
    [plan addEdge:[CSCapEdge directFrom:@"cap_0" to:@"foreach_0"]];
    [plan addEdge:[CSCapEdge iterationFrom:@"foreach_0" to:@"body_cap_0"]];
    [plan addEdge:[CSCapEdge directFrom:@"body_cap_0" to:@"body_cap_1"]];
    [plan addEdge:[CSCapEdge collectionFrom:@"body_cap_1" to:@"collect_0"]];
    [plan addEdge:[CSCapEdge directFrom:@"collect_0" to:@"cap_post"]];
    [plan addEdge:[CSCapEdge directFrom:@"cap_post" to:@"output"]];

    return plan;
}

// Helper: build plan with unclosed ForEach (no Collect)
// Topology: input_slot → cap_0 → foreach_0 --iteration--> body_cap_0 → output
static CSCapExecutionPlan *buildForeachPlanUnclosed(void) {
    CSCapExecutionPlan *plan = [CSCapExecutionPlan planWithName:@"Unclosed ForEach test plan"];

    [plan addNode:[CSCapNode inputSlotNode:@"input_slot" slotName:@"input" mediaUrn:@"media:pdf" cardinality:CSInputCardinalitySingle]];
    [plan addNode:[CSCapNode capNode:@"cap_0" capUrn:@"cap:in=media:pdf;out=media:pdf-page;list"]];
    [plan addNode:[CSCapNode forEachNode:@"foreach_0" inputNode:@"cap_0" bodyEntry:@"body_cap_0" bodyExit:@"body_cap_0"]];
    [plan addNode:[CSCapNode capNode:@"body_cap_0" capUrn:@"cap:in=media:pdf-page;out=media:bool;decision;textable"]];
    [plan addNode:[CSCapNode outputNode:@"output" outputName:@"result" sourceNode:@"body_cap_0"]];

    [plan addEdge:[CSCapEdge directFrom:@"input_slot" to:@"cap_0"]];
    [plan addEdge:[CSCapEdge directFrom:@"cap_0" to:@"foreach_0"]];
    [plan addEdge:[CSCapEdge iterationFrom:@"foreach_0" to:@"body_cap_0"]];
    [plan addEdge:[CSCapEdge directFrom:@"body_cap_0" to:@"output"]];

    return plan;
}

@implementation CSPlanDecompositionTests

// MARK: - WrapInList Node Tests

- (void)testWrapInListNodeFactory {
    CSCapNode *node = [CSCapNode wrapInListNode:@"wrap_0" itemMediaUrn:@"media:text" listMediaUrn:@"media:list;text"];

    XCTAssertEqualObjects(node.nodeId, @"wrap_0");
    XCTAssertEqualObjects(node.wrapItemMediaUrn, @"media:text");
    XCTAssertEqualObjects(node.wrapListMediaUrn, @"media:list;text");
    XCTAssertTrue([node isWrapInList]);
    XCTAssertFalse([node isCap]);
    XCTAssertFalse([node isFanOut]);
    XCTAssertFalse([node isFanIn]);
}

- (void)testWrapInListIsNotWrapInListForOtherTypes {
    CSCapNode *cap = [CSCapNode capNode:@"cap_0" capUrn:@"cap:test"];
    XCTAssertFalse([cap isWrapInList]);

    CSCapNode *forEach = [CSCapNode forEachNode:@"fe" inputNode:@"in" bodyEntry:@"b1" bodyExit:@"b2"];
    XCTAssertFalse([forEach isWrapInList]);
}

// MARK: - TEST934: findFirstForeach detects ForEach
- (void)test934FindFirstForeach {
    CSCapExecutionPlan *plan = buildForeachPlanWithCollect();
    NSString *foreachId = [plan findFirstForeach];
    XCTAssertEqualObjects(foreachId, @"foreach_0");
}

// TEST935: findFirstForeach returns nil for linear plans
- (void)test935FindFirstForeachLinear {
    CSCapExecutionPlan *plan = [CSCapExecutionPlan linearChainPlan:@[@"cap:a", @"cap:b"]
                                                       inputMedia:@"media:pdf"
                                                      outputMedia:@"media:png"
                                                  filePathArgNames:@[@"input_a", @"input_b"]];
    XCTAssertNil([plan findFirstForeach]);
}

// TEST936: hasForeachOrCollect
- (void)test936HasForeachOrCollect {
    CSCapExecutionPlan *foreachPlan = buildForeachPlanWithCollect();
    XCTAssertTrue([foreachPlan hasForeachOrCollect]);

    CSCapExecutionPlan *linearPlan = [CSCapExecutionPlan linearChainPlan:@[@"cap:a"]
                                                             inputMedia:@"media:pdf"
                                                            outputMedia:@"media:png"
                                                        filePathArgNames:@[@"input_a"]];
    XCTAssertFalse([linearPlan hasForeachOrCollect]);
}

// TEST937: extractPrefixTo extracts input_slot → cap_0 as standalone plan
- (void)test937ExtractPrefixTo {
    CSCapExecutionPlan *plan = buildForeachPlanWithCollect();

    NSError *error = nil;
    CSCapExecutionPlan *prefix = [plan extractPrefixTo:@"cap_0" error:&error];
    XCTAssertNotNil(prefix, @"extractPrefixTo should succeed: %@", error);

    // Should have: input_slot, cap_0, synthetic output
    XCTAssertEqual(prefix.nodes.count, 3u);
    XCTAssertNotNil([prefix getNode:@"input_slot"]);
    XCTAssertNotNil([prefix getNode:@"cap_0"]);
    XCTAssertNotNil([prefix getNode:@"cap_0_prefix_output"]);
    XCTAssertEqual(prefix.entryNodes.count, 1u);
    XCTAssertEqual(prefix.outputNodes.count, 1u);
    XCTAssertNil([prefix validate]);

    // Topological order works (no cycles)
    NSArray *order = [prefix topologicalOrder:&error];
    XCTAssertNotNil(order);
    XCTAssertEqual(order.count, 3u);
}

// TEST754: extractPrefixTo with nonexistent node returns error
- (void)test754ExtractPrefixNonexistent {
    CSCapExecutionPlan *plan = buildForeachPlanWithCollect();
    NSError *error = nil;
    CSCapExecutionPlan *result = [plan extractPrefixTo:@"nonexistent" error:&error];
    XCTAssertNil(result);
    XCTAssertNotNil(error);
}

// TEST755: extractForeachBody extracts body with synthetic I/O
- (void)test755ExtractForeachBody {
    CSCapExecutionPlan *plan = buildForeachPlanWithCollect();

    NSError *error = nil;
    CSCapExecutionPlan *body = [plan extractForeachBody:@"foreach_0" itemMediaUrn:@"media:pdf-page" error:&error];
    XCTAssertNotNil(body, @"extractForeachBody should succeed: %@", error);

    // Should have: synthetic input, body_cap_0, body_cap_1, synthetic output
    XCTAssertEqual(body.nodes.count, 4u);
    XCTAssertNotNil([body getNode:@"foreach_0_body_input"]);
    XCTAssertNotNil([body getNode:@"body_cap_0"]);
    XCTAssertNotNil([body getNode:@"body_cap_1"]);
    XCTAssertNotNil([body getNode:@"foreach_0_body_output"]);
    XCTAssertEqual(body.entryNodes.count, 1u);
    XCTAssertEqual(body.outputNodes.count, 1u);
    XCTAssertNil([body validate]);

    // Should NOT contain ForEach or Collect
    XCTAssertFalse([body hasForeachOrCollect]);

    // Verify synthetic InputSlot has item media URN
    CSCapNode *inputNode = [body getNode:@"foreach_0_body_input"];
    XCTAssertEqualObjects(inputNode.expectedMediaUrn, @"media:pdf-page");
    XCTAssertEqual(inputNode.cardinality, CSInputCardinalitySingle);

    // Topological order
    NSArray *order = [body topologicalOrder:&error];
    XCTAssertNotNil(order);
    XCTAssertEqual(order.count, 4u);
}

// TEST756: extractForeachBody for unclosed ForEach (single body cap)
- (void)test756ExtractForeachBodyUnclosed {
    CSCapExecutionPlan *plan = buildForeachPlanUnclosed();

    NSError *error = nil;
    CSCapExecutionPlan *body = [plan extractForeachBody:@"foreach_0" itemMediaUrn:@"media:pdf-page" error:&error];
    XCTAssertNotNil(body, @"should succeed: %@", error);

    // Should have: synthetic input, body_cap_0, synthetic output
    XCTAssertEqual(body.nodes.count, 3u);
    XCTAssertNotNil([body getNode:@"foreach_0_body_input"]);
    XCTAssertNotNil([body getNode:@"body_cap_0"]);
    XCTAssertNotNil([body getNode:@"foreach_0_body_output"]);
    XCTAssertNil([body validate]);
    XCTAssertFalse([body hasForeachOrCollect]);
}

// TEST757: extractForeachBody fails for non-ForEach node
- (void)test757ExtractForeachBodyWrongType {
    CSCapExecutionPlan *plan = buildForeachPlanWithCollect();
    NSError *error = nil;
    CSCapExecutionPlan *result = [plan extractForeachBody:@"cap_0" itemMediaUrn:@"media:pdf-page" error:&error];
    XCTAssertNil(result);
    XCTAssertNotNil(error);
    XCTAssertTrue([error.localizedDescription containsString:@"not a ForEach"],
                  @"Error should mention 'not a ForEach': %@", error.localizedDescription);
}

// TEST758: extractSuffixFrom extracts collect → cap_post → output
- (void)test758ExtractSuffixFrom {
    CSCapExecutionPlan *plan = buildForeachPlanWithCollect();

    NSError *error = nil;
    CSCapExecutionPlan *suffix = [plan extractSuffixFrom:@"collect_0" sourceMediaUrn:@"media:bool;decision;list;textable" error:&error];
    XCTAssertNotNil(suffix, @"should succeed: %@", error);

    // Should have: synthetic input, cap_post, output
    XCTAssertEqual(suffix.nodes.count, 3u);
    XCTAssertNotNil([suffix getNode:@"collect_0_suffix_input"]);
    XCTAssertNotNil([suffix getNode:@"cap_post"]);
    XCTAssertNotNil([suffix getNode:@"output"]);
    XCTAssertEqual(suffix.entryNodes.count, 1u);
    XCTAssertEqual(suffix.outputNodes.count, 1u);
    XCTAssertNil([suffix validate]);

    // Should not contain ForEach/Collect
    XCTAssertFalse([suffix hasForeachOrCollect]);
}

// TEST759: extractSuffixFrom fails for nonexistent node
- (void)test759ExtractSuffixNonexistent {
    CSCapExecutionPlan *plan = buildForeachPlanWithCollect();
    NSError *error = nil;
    CSCapExecutionPlan *result = [plan extractSuffixFrom:@"nonexistent" sourceMediaUrn:@"media:whatever" error:&error];
    XCTAssertNil(result);
    XCTAssertNotNil(error);
}

// TEST760: Full decomposition covers all cap nodes
- (void)test760DecompositionCoversAllCaps {
    CSCapExecutionPlan *plan = buildForeachPlanWithCollect();

    // Get all original cap node IDs
    NSMutableSet *originalCaps = [NSMutableSet set];
    for (NSString *nodeId in plan.nodes) {
        CSCapNode *node = plan.nodes[nodeId];
        if ([node isCap]) {
            [originalCaps addObject:nodeId];
        }
    }
    XCTAssertEqual(originalCaps.count, 4u); // cap_0, body_cap_0, body_cap_1, cap_post

    NSError *error = nil;
    CSCapExecutionPlan *prefix = [plan extractPrefixTo:@"cap_0" error:&error];
    CSCapExecutionPlan *body = [plan extractForeachBody:@"foreach_0" itemMediaUrn:@"media:pdf-page" error:&error];
    CSCapExecutionPlan *suffix = [plan extractSuffixFrom:@"collect_0" sourceMediaUrn:@"media:bool;decision;list;textable" error:&error];

    XCTAssertNotNil(prefix);
    XCTAssertNotNil(body);
    XCTAssertNotNil(suffix);

    // Collect cap nodes from each sub-plan
    NSMutableSet *allCaps = [NSMutableSet set];
    for (NSString *nodeId in prefix.nodes) {
        if ([prefix.nodes[nodeId] isCap]) [allCaps addObject:nodeId];
    }
    for (NSString *nodeId in body.nodes) {
        if ([body.nodes[nodeId] isCap]) [allCaps addObject:nodeId];
    }
    for (NSString *nodeId in suffix.nodes) {
        if ([suffix.nodes[nodeId] isCap]) [allCaps addObject:nodeId];
    }

    XCTAssertEqualObjects(allCaps, originalCaps,
                          @"Decomposition should cover all cap nodes");
}

// TEST761: Prefix is valid DAG
- (void)test761PrefixIsDag {
    CSCapExecutionPlan *plan = buildForeachPlanWithCollect();
    NSError *error = nil;
    CSCapExecutionPlan *prefix = [plan extractPrefixTo:@"cap_0" error:&error];
    XCTAssertNotNil(prefix);
    XCTAssertNotNil([prefix topologicalOrder:&error]);
}

// TEST762: Body is valid DAG
- (void)test762BodyIsDag {
    CSCapExecutionPlan *plan = buildForeachPlanWithCollect();
    NSError *error = nil;
    CSCapExecutionPlan *body = [plan extractForeachBody:@"foreach_0" itemMediaUrn:@"media:pdf-page" error:&error];
    XCTAssertNotNil(body);
    XCTAssertNotNil([body topologicalOrder:&error]);
}

// TEST763: Suffix is valid DAG
- (void)test763SuffixIsDag {
    CSCapExecutionPlan *plan = buildForeachPlanWithCollect();
    NSError *error = nil;
    CSCapExecutionPlan *suffix = [plan extractSuffixFrom:@"collect_0" sourceMediaUrn:@"media:bool;decision;list;textable" error:&error];
    XCTAssertNotNil(suffix);
    XCTAssertNotNil([suffix topologicalOrder:&error]);
}

// TEST764: extractPrefixTo with InputSlot as target (trivial prefix)
- (void)test764PrefixToInputSlot {
    CSCapExecutionPlan *plan = buildForeachPlanWithCollect();
    NSError *error = nil;
    CSCapExecutionPlan *prefix = [plan extractPrefixTo:@"input_slot" error:&error];
    XCTAssertNotNil(prefix, @"should succeed: %@", error);

    // Should have: input_slot + synthetic output
    XCTAssertEqual(prefix.nodes.count, 2u);
    XCTAssertNil([prefix validate]);
}

@end

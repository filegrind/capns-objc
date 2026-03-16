//
//  CSCapMatrixTests.m
//  Tests for CSCapMatrix
//

#import <XCTest/XCTest.h>
#import "CapDAG.h"

// Mock CapSet for testing
@interface MockCapSet : NSObject <CSCapSet>
@property (nonatomic, strong) NSString *name;
@end

@implementation MockCapSet

- (instancetype)initWithName:(NSString *)name {
    self = [super init];
    if (self) {
        _name = name;
    }
    return self;
}

- (void)executeCap:(NSString *)cap
    positionalArgs:(NSArray *)positionalArgs
         namedArgs:(NSArray *)namedArgs
       stdinSource:(CSStdinSource * _Nullable)stdinSource
        completion:(void (^)(CSResponseWrapper * _Nullable response, NSError * _Nullable error))completion {

    CSResponseWrapper *response = [CSResponseWrapper textResponseWithData:
        [[NSString stringWithFormat:@"Mock response from %@", self.name] dataUsingEncoding:NSUTF8StringEncoding]];
    completion(response, nil);
}

@end

@interface CSCapMatrixTests : XCTestCase
@property (nonatomic, strong) CSCapMatrix *registry;
@end

@implementation CSCapMatrixTests

- (void)setUp {
    [super setUp];
    self.registry = [CSCapMatrix registry];
}

- (void)tearDown {
    self.registry = nil;
    [super tearDown];
}

- (void)testRegisterAndFindCapSet {
    MockCapSet *host = [[MockCapSet alloc] initWithName:@"test-host"];

    NSError *error = nil;
    CSCapUrn *capUrn = [CSCapUrn fromString:@"cap:in=media:void;op=test;out=\"media:record;textable\";basic" error:&error];
    XCTAssertNotNil(capUrn, @"Failed to create CapUrn: %@", error.localizedDescription);
    XCTAssertNil(error, @"Should not have error creating CapUrn");

    CSCap *cap = [CSCap capWithUrn:capUrn
                             title:@"Test"
                           command:@"test"
                       description:@"Test capability"
                          metadata:@{}
                        mediaSpecs:@[]
                         args:@[]
                            output:nil
                      metadataJSON:nil];

    NSError *registerError = nil;
    BOOL success = [self.registry registerCapSet:@"test-host"
                                             host:host
                                     capabilities:@[cap]
                                            error:&registerError];

    XCTAssertTrue(success, @"Failed to register cap host");
    XCTAssertNil(registerError, @"Registration should not produce error");

    // Test exact match
    NSError *findError = nil;
    NSArray<id<CSCapSet>> *sets = [self.registry findCapSets:@"cap:in=media:void;op=test;out=\"media:record;textable\";basic" error:&findError];
    XCTAssertNotNil(sets, @"Should find sets for exact match");
    XCTAssertNil(findError, @"Should not have error for exact match");
    XCTAssertEqual(sets.count, 1, @"Should find exactly one host");

    // Test subset match (request has more specific requirements)
    sets = [self.registry findCapSets:@"cap:in=media:void;model=gpt-4;op=test;out=\"media:record;textable\";basic" error:&findError];
    XCTAssertNotNil(sets, @"Should find sets for subset match");
    XCTAssertNil(findError, @"Should not have error for subset match");
    XCTAssertEqual(sets.count, 1, @"Should find exactly one host for subset match");

    // Test no match
    sets = [self.registry findCapSets:@"cap:in=media:void;op=different;out=\"media:record;textable\"" error:&findError];
    XCTAssertNil(sets, @"Should not find sets for non-matching capability");
    XCTAssertNotNil(findError, @"Should have error for non-matching capability");
    XCTAssertEqual(findError.code, CSCapMatrixErrorTypeNoSetsFound, @"Should be NoSetsFound error");
}

- (void)testBestCapSetSelection {
    // Register general host
    MockCapSet *generalHost = [[MockCapSet alloc] initWithName:@"general"];
    CSCapUrn *generalCapUrn = [CSCapUrn fromString:@"cap:in=media:void;op=generate;out=\"media:record;textable\"" error:nil];
    CSCap *generalCap = [CSCap capWithUrn:generalCapUrn
                                   title:@"Generate"
                                 command:@"generate"
                             description:@"General generation"
                                metadata:@{}
                              mediaSpecs:@[]
                               args:@[]
                                  output:nil
                            metadataJSON:nil];

    // Register specific host
    MockCapSet *specificHost = [[MockCapSet alloc] initWithName:@"specific"];
    CSCapUrn *specificCapUrn = [CSCapUrn fromString:@"cap:in=media:void;model=gpt-4;op=generate;out=\"media:record;textable\";text" error:nil];
    CSCap *specificCap = [CSCap capWithUrn:specificCapUrn
                                    title:@"Generate"
                                  command:@"generate"
                              description:@"Specific text generation"
                                 metadata:@{}
                               mediaSpecs:@[]
                                args:@[]
                                   output:nil
                             metadataJSON:nil];

    [self.registry registerCapSet:@"general" host:generalHost capabilities:@[generalCap] error:nil];
    [self.registry registerCapSet:@"specific" host:specificHost capabilities:@[specificCap] error:nil];

    // Request should match the more specific host (using valid URN characters)
    NSError *error = nil;
    CSCap *capDefinition = nil;
    id<CSCapSet> bestHost = [self.registry findBestCapSet:@"cap:in=media:void;model=gpt-4;op=generate;out=\"media:record;textable\";temperature=low;text" error:&error capDefinition:&capDefinition];
    XCTAssertNotNil(bestHost, @"Should find a best host");
    XCTAssertNil(error, @"Should not have error finding best host");
    XCTAssertNotNil(capDefinition, @"Should return cap definition");

    // Both sets should match
    NSArray<id<CSCapSet>> *allHosts = [self.registry findCapSets:@"cap:in=media:void;model=gpt-4;op=generate;out=\"media:record;textable\";temperature=low;text" error:&error];
    XCTAssertNotNil(allHosts, @"Should find all matching sets");
    XCTAssertEqual(allHosts.count, 2, @"Should find both sets");
}

- (void)testInvalidUrnHandling {
    NSError *error = nil;
    NSArray<id<CSCapSet>> *sets = [self.registry findCapSets:@"invalid-urn" error:&error];

    XCTAssertNil(sets, @"Should not find sets for invalid URN");
    XCTAssertNotNil(error, @"Should have error for invalid URN");
    XCTAssertEqual(error.code, CSCapMatrixErrorTypeInvalidUrn, @"Should be InvalidUrn error");
}

- (void)testCanHandle {
    // Empty registry
    BOOL canHandle = [self.registry acceptsRequest:@"cap:in=media:void;op=test;out=\"media:record;textable\""];
    XCTAssertFalse(canHandle, @"Empty registry should not handle any capability");

    // After registration
    MockCapSet *host = [[MockCapSet alloc] initWithName:@"test"];
    CSCapUrn *capUrn = [CSCapUrn fromString:@"cap:in=media:void;op=test;out=\"media:record;textable\"" error:nil];
    CSCap *cap = [CSCap capWithUrn:capUrn
                             title:@"Test"
                           command:@"test"
                       description:@"Test"
                          metadata:@{}
                        mediaSpecs:@[]
                         args:@[]
                            output:nil
                      metadataJSON:nil];

    [self.registry registerCapSet:@"test" host:host capabilities:@[cap] error:nil];

    canHandle = [self.registry acceptsRequest:@"cap:in=media:void;op=test;out=\"media:record;textable\""];
    XCTAssertTrue(canHandle, @"Registry should handle registered capability");

    canHandle = [self.registry acceptsRequest:@"cap:extra=param;in=media:void;op=test;out=\"media:record;textable\""];
    XCTAssertTrue(canHandle, @"Registry should handle capability with extra parameters");

    canHandle = [self.registry acceptsRequest:@"cap:in=media:void;op=different;out=\"media:record;textable\""];
    XCTAssertFalse(canHandle, @"Registry should not handle unregistered capability");
}

- (void)testUnregisterCapSet {
    MockCapSet *host = [[MockCapSet alloc] initWithName:@"test"];
    CSCapUrn *capUrn = [CSCapUrn fromString:@"cap:in=media:void;op=test;out=\"media:record;textable\"" error:nil];
    CSCap *cap = [CSCap capWithUrn:capUrn
                             title:@"Test"
                           command:@"test"
                       description:@"Test"
                          metadata:@{}
                        mediaSpecs:@[]
                         args:@[]
                            output:nil
                      metadataJSON:nil];

    [self.registry registerCapSet:@"test" host:host capabilities:@[cap] error:nil];

    // Verify it's registered
    XCTAssertTrue([self.registry acceptsRequest:@"cap:in=media:void;op=test;out=\"media:record;textable\""], @"Should handle capability before unregistering");

    // Unregister
    BOOL success = [self.registry unregisterCapSet:@"test"];
    XCTAssertTrue(success, @"Should successfully unregister existing host");

    // Verify it's gone
    XCTAssertFalse([self.registry acceptsRequest:@"cap:in=media:void;op=test;out=\"media:record;textable\""], @"Should not handle capability after unregistering");

    // Try to unregister non-existent host
    success = [self.registry unregisterCapSet:@"nonexistent"];
    XCTAssertFalse(success, @"Should return false when unregistering non-existent host");
}

// Helper to create a test cap with given URN and title
static CSCap *makeCap(NSString *urnString, NSString *title) {
    CSCapUrn *urn = [CSCapUrn fromString:urnString error:nil];
    return [CSCap capWithUrn:urn
                       title:title
                     command:@"test"
                 description:title
                    metadata:@{}
                  mediaSpecs:@[]
                       args:@[]
                      output:nil
                metadataJSON:nil];
}

static NSString* testMatrixUrn(NSString *tags) {
    if (tags == nil || tags.length == 0) {
        return @"cap:in=\"media:void\";out=\"media:record;textable\"";
    }
    return [NSString stringWithFormat:@"cap:in=\"media:void\";out=\"media:record;textable\";%@", tags];
}

// TEST569: unregisterCapSet
- (void)testUnregisterCapSet569 {
    MockCapSet *host = [[MockCapSet alloc] initWithName:@"test"];
    CSCap *cap = makeCap(testMatrixUrn(@"op=test"), @"Test");
    [self.registry registerCapSet:@"test" host:host capabilities:@[cap] error:nil];
    XCTAssertTrue([self.registry acceptsRequest:testMatrixUrn(@"op=test")]);
    BOOL success = [self.registry unregisterCapSet:@"test"];
    XCTAssertTrue(success);
    XCTAssertFalse([self.registry acceptsRequest:testMatrixUrn(@"op=test")]);
    XCTAssertFalse([self.registry unregisterCapSet:@"nonexistent"]);
}

// TEST570: clear
- (void)testClear570 {
    MockCapSet *host = [[MockCapSet alloc] initWithName:@"test"];
    CSCap *cap = makeCap(testMatrixUrn(@"op=test"), @"Test");
    [self.registry registerCapSet:@"test" host:host capabilities:@[cap] error:nil];
    XCTAssertTrue([self.registry acceptsRequest:testMatrixUrn(@"op=test")]);
    [self.registry clear];
    XCTAssertFalse([self.registry acceptsRequest:testMatrixUrn(@"op=test")]);
    XCTAssertEqual([self.registry getHostNames].count, 0);
}

// TEST571: getAllCapabilities returns caps from all hosts
- (void)test571_get_all_capabilities {
    MockCapSet *host1 = [[MockCapSet alloc] initWithName:@"h1"];
    MockCapSet *host2 = [[MockCapSet alloc] initWithName:@"h2"];
    CSCap *capA = makeCap(testMatrixUrn(@"op=a"), @"Cap A");
    CSCap *capB = makeCap(testMatrixUrn(@"op=b"), @"Cap B");
    CSCap *capC = makeCap(testMatrixUrn(@"op=c"), @"Cap C");
    [self.registry registerCapSet:@"h1" host:host1 capabilities:@[capA, capB] error:nil];
    [self.registry registerCapSet:@"h2" host:host2 capabilities:@[capC] error:nil];
    NSArray *all = [self.registry getAllCapabilities];
    XCTAssertEqual(all.count, 3);
}

// TEST127: CapGraph basic construction
- (void)test127_cap_graph_basic_construction {
    CSCapGraph *graph = [CSCapGraph graph];
    CSCap *cap = makeCap(@"cap:in=\"media:\";op=extract_text;out=\"media:textable\"", @"Text Extractor");
    [graph addCap:cap registryName:@"test_registry"];
    XCTAssertGreaterThanOrEqual([graph getNodes].count, 2, @"Should have at least 2 nodes");
    XCTAssertGreaterThanOrEqual([graph getEdges].count, 1, @"Should have at least 1 edge");
    XCTAssertTrue([graph hasDirectEdge:@"media:" toSpec:@"media:textable"]);
}

// TEST128: CapGraph outgoing/incoming edges
- (void)test128_cap_graph_outgoing_incoming {
    CSCapGraph *graph = [CSCapGraph graph];
    CSCap *cap1 = makeCap(@"cap:in=\"media:binary\";op=extract_text;out=\"media:textable\"", @"Text Extractor");
    CSCap *cap2 = makeCap(@"cap:in=\"media:binary\";op=parse_json;out=\"media:record;textable\"", @"JSON Parser");
    [graph addCap:cap1 registryName:@"r1"];
    [graph addCap:cap2 registryName:@"r2"];

    NSArray *outgoing = [graph getOutgoing:@"media:binary"];
    XCTAssertEqual(outgoing.count, 2);

    NSArray *incomingStr = [graph getIncoming:@"media:textable"];
    XCTAssertEqual(incomingStr.count, 1);

    NSArray *incomingObj = [graph getIncoming:@"media:record;textable"];
    XCTAssertEqual(incomingObj.count, 1);
}

// TEST129: CapGraph can_convert (direct, indirect, no-path)
- (void)test129_cap_graph_can_convert {
    CSCapGraph *graph = [CSCapGraph graph];
    CSCap *cap1 = makeCap(@"cap:in=\"media:binary\";op=extract;out=\"media:textable\"", @"Binary to Str");
    CSCap *cap2 = makeCap(@"cap:in=\"media:textable\";op=parse;out=\"media:record;textable\"", @"Str to Obj");
    [graph addCap:cap1 registryName:@"r"];
    [graph addCap:cap2 registryName:@"r"];

    XCTAssertTrue([graph canConvert:@"media:binary" toSpec:@"media:textable"]);
    XCTAssertTrue([graph canConvert:@"media:textable" toSpec:@"media:record;textable"]);
    XCTAssertTrue([graph canConvert:@"media:binary" toSpec:@"media:record;textable"]); // indirect
    XCTAssertTrue([graph canConvert:@"media:binary" toSpec:@"media:binary"]); // same
    XCTAssertFalse([graph canConvert:@"media:record;textable" toSpec:@"media:binary"]); // no path
}

// TEST130: CapGraph find_path (shortest path)
- (void)test130_cap_graph_find_path {
    CSCapGraph *graph = [CSCapGraph graph];
    CSCap *cap1 = makeCap(@"cap:in=\"media:binary\";op=extract;out=\"media:string\"", @"Binary to Str");
    CSCap *cap2 = makeCap(@"cap:in=\"media:string\";op=parse;out=\"media:object\"", @"Str to Obj");
    [graph addCap:cap1 registryName:@"r"];
    [graph addCap:cap2 registryName:@"r"];

    NSArray<CSCapGraphEdge *> *path = [graph findPath:@"media:binary" toSpec:@"media:object"];
    XCTAssertNotNil(path);
    XCTAssertEqual(path.count, 2);
    XCTAssertEqualObjects(path[0].fromSpec, @"media:binary");
    XCTAssertEqualObjects(path[0].toSpec, @"media:string");
    XCTAssertEqualObjects(path[1].fromSpec, @"media:string");
    XCTAssertEqualObjects(path[1].toSpec, @"media:object");

    NSArray<CSCapGraphEdge *> *direct = [graph findPath:@"media:binary" toSpec:@"media:string"];
    XCTAssertEqual(direct.count, 1);

    NSArray<CSCapGraphEdge *> *noPath = [graph findPath:@"media:object" toSpec:@"media:binary"];
    XCTAssertNil(noPath);

    NSArray<CSCapGraphEdge *> *same = [graph findPath:@"media:binary" toSpec:@"media:binary"];
    XCTAssertNotNil(same);
    XCTAssertEqual(same.count, 0);
}

// TEST131: CapGraph find_all_paths sorted by length
- (void)test131_cap_graph_find_all_paths {
    CSCapGraph *graph = [CSCapGraph graph];
    CSCap *cap1 = makeCap(@"cap:in=\"media:binary\";op=step1;out=\"media:string\"", @"A to B");
    CSCap *cap2 = makeCap(@"cap:in=\"media:string\";op=step2;out=\"media:object\"", @"B to C");
    CSCap *cap3 = makeCap(@"cap:in=\"media:binary\";op=direct;out=\"media:object\"", @"A to C Direct");
    [graph addCap:cap1 registryName:@"r"];
    [graph addCap:cap2 registryName:@"r"];
    [graph addCap:cap3 registryName:@"r"];

    NSArray<NSArray<CSCapGraphEdge *> *> *allPaths = [graph findAllPaths:@"media:binary" toSpec:@"media:object" maxDepth:5];
    XCTAssertEqual(allPaths.count, 2);
    XCTAssertEqual(allPaths[0].count, 1); // Direct path
    XCTAssertEqual(allPaths[1].count, 2); // Through intermediate
}

// TEST132: CapGraph get_direct_edges sorted by specificity
- (void)test132_cap_graph_get_direct_edges_sorted {
    CSCapGraph *graph = [CSCapGraph graph];
    CSCap *cap1 = makeCap(@"cap:in=\"media:binary\";op=generic;out=\"media:string\"", @"Generic");
    CSCap *cap2 = makeCap(@"cap:ext=pdf;in=\"media:binary\";op=specific;out=\"media:string\"", @"Specific PDF");
    [graph addCap:cap1 registryName:@"r"];
    [graph addCap:cap2 registryName:@"r"];

    NSArray<CSCapGraphEdge *> *edges = [graph getDirectEdges:@"media:binary" toSpec:@"media:string"];
    XCTAssertEqual(edges.count, 2);
    XCTAssertEqualObjects(edges[0].cap.title, @"Specific PDF"); // Higher specificity
    XCTAssertEqualObjects(edges[1].cap.title, @"Generic"); // Lower specificity
}

// TEST134: CapGraph stats
- (void)test134_cap_graph_stats {
    CSCapGraph *graph = [CSCapGraph graph];
    CSCap *cap1 = makeCap(@"cap:in=\"media:binary\";op=a;out=\"media:string\"", @"Cap 1");
    CSCap *cap2 = makeCap(@"cap:in=\"media:string\";op=b;out=\"media:object\"", @"Cap 2");
    [graph addCap:cap1 registryName:@"r"];
    [graph addCap:cap2 registryName:@"r"];

    CSCapGraphStats *stats = [graph stats];
    XCTAssertEqual(stats.nodeCount, 3);
    XCTAssertEqual(stats.edgeCount, 2);
    XCTAssertEqual(stats.inputSpecCount, 2);
    XCTAssertEqual(stats.outputSpecCount, 2);
}

// TEST976: CapGraph find_best_path (highest specificity over shortest)
- (void)test976_cap_graph_find_best_path {
    CSCapGraph *graph = [CSCapGraph graph];
    CSCap *capDirect = makeCap(@"cap:in=\"media:binary\";op=direct;out=\"media:object\"", @"Direct Low Spec");
    CSCap *capHop1 = makeCap(@"cap:ext=pdf;in=\"media:binary\";op=extract;out=\"media:string\"", @"Hop1 High Spec");
    CSCap *capHop2 = makeCap(@"cap:ext=json;in=\"media:string\";op=parse;out=\"media:object\"", @"Hop2 High Spec");
    [graph addCap:capDirect registryName:@"r1"];
    [graph addCap:capHop1 registryName:@"r2"];
    [graph addCap:capHop2 registryName:@"r2"];

    NSArray<CSCapGraphEdge *> *shortest = [graph findPath:@"media:binary" toSpec:@"media:object"];
    XCTAssertEqual(shortest.count, 1);

    NSArray<CSCapGraphEdge *> *best = [graph findBestPath:@"media:binary" toSpec:@"media:object" maxDepth:5];
    NSInteger totalSpec = 0;
    for (CSCapGraphEdge *e in best) totalSpec += e.specificity;
    XCTAssertGreaterThan(totalSpec, shortest[0].specificity);
    XCTAssertEqual(best.count, 2);
}

// TEST577: CapGraph input/output specs
- (void)test577_cap_graph_input_output_specs {
    CSCapGraph *graph = [CSCapGraph graph];
    CSCap *cap = makeCap(@"cap:in=\"media:binary\";op=x;out=\"media:string\"", @"X");
    [graph addCap:cap registryName:@"r"];

    NSArray<NSString *> *inputs = [graph getInputSpecs];
    XCTAssertTrue([inputs containsObject:@"media:binary"]);

    NSArray<NSString *> *outputs = [graph getOutputSpecs];
    XCTAssertTrue([outputs containsObject:@"media:string"]);

    XCTAssertFalse([outputs containsObject:@"media:binary"]);
    XCTAssertFalse([inputs containsObject:@"media:string"]);
}

// TEST124: CapBlock no match returns error
- (void)test124_cap_block_no_match {
    CSCapBlock *block = [CSCapBlock cube];
    CSCapMatrix *emptyReg = [CSCapMatrix registry];
    [block addRegistry:@"empty" registry:emptyReg];

    NSError *error = nil;
    CSBestCapSetMatch *result = [block findBestCapSet:testMatrixUrn(@"op=nonexistent") error:&error];
    XCTAssertNil(result);
    XCTAssertNotNil(error);
}

// TEST574: CapBlock remove_registry
- (void)test574_cap_block_remove_registry {
    CSCapMatrix *reg = [CSCapMatrix registry];
    MockCapSet *host = [[MockCapSet alloc] initWithName:@"h1"];
    [reg registerCapSet:@"h1" host:host capabilities:@[makeCap(testMatrixUrn(@"op=a"), @"A")] error:nil];

    CSCapBlock *block = [CSCapBlock cube];
    [block addRegistry:@"r1" registry:reg];
    XCTAssertTrue([block acceptsRequest:testMatrixUrn(@"op=a")]);

    CSCapMatrix *removed = [block removeRegistry:@"r1"];
    XCTAssertNotNil(removed);
    XCTAssertFalse([block acceptsRequest:testMatrixUrn(@"op=a")]);
    XCTAssertNil([block removeRegistry:@"nonexistent"]);
}

// TEST575: CapBlock get_registry
- (void)test575_cap_block_get_registry {
    CSCapMatrix *reg = [CSCapMatrix registry];
    CSCapBlock *block = [CSCapBlock cube];
    [block addRegistry:@"r1" registry:reg];
    XCTAssertNotNil([block getRegistry:@"r1"]);
    XCTAssertNil([block getRegistry:@"nonexistent"]);
}

// TEST576: CapBlock get_registry_names in insertion order
- (void)test576_cap_block_get_registry_names {
    CSCapBlock *block = [CSCapBlock cube];
    [block addRegistry:@"alpha" registry:[CSCapMatrix registry]];
    [block addRegistry:@"beta" registry:[CSCapMatrix registry]];
    NSArray *names = [block getRegistryNames];
    XCTAssertEqual(names.count, 2);
    XCTAssertEqualObjects(names[0], @"alpha");
    XCTAssertEqualObjects(names[1], @"beta");
}

- (void)testClear {
    MockCapSet *host = [[MockCapSet alloc] initWithName:@"test"];
    CSCapUrn *capUrn = [CSCapUrn fromString:@"cap:in=media:void;op=test;out=\"media:record;textable\"" error:nil];
    CSCap *cap = [CSCap capWithUrn:capUrn
                             title:@"Test"
                           command:@"test"
                       description:@"Test"
                          metadata:@{}
                        mediaSpecs:@[]
                         args:@[]
                            output:nil
                      metadataJSON:nil];

    [self.registry registerCapSet:@"test" host:host capabilities:@[cap] error:nil];

    // Verify it's registered
    XCTAssertTrue([self.registry acceptsRequest:@"cap:in=media:void;op=test;out=\"media:record;textable\""], @"Should handle capability before clearing");
    XCTAssertEqual([self.registry getHostNames].count, 1, @"Should have one host before clearing");

    // Clear
    [self.registry clear];

    // Verify everything is gone
    XCTAssertFalse([self.registry acceptsRequest:@"cap:in=media:void;op=test;out=\"media:record;textable\""], @"Should not handle any capabilities after clearing");
    XCTAssertEqual([self.registry getHostNames].count, 0, @"Should have no sets after clearing");
}

@end

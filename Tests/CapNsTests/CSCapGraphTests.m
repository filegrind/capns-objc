//
//  CSCapGraphTests.m
//  Tests for CSCapGraph
//

#import <XCTest/XCTest.h>
#import "CapNs.h"

// Mock CapSet for testing (reuse pattern from CSCapMatrixTests)
@interface MockCapSetForGraph : NSObject <CSCapSet>
@property (nonatomic, strong) NSString *name;
@end

@implementation MockCapSetForGraph

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
         stdinData:(NSData * _Nullable)stdinData
        completion:(void (^)(CSResponseWrapper * _Nullable response, NSError * _Nullable error))completion {

    CSResponseWrapper *response = [CSResponseWrapper textResponseWithData:
        [[NSString stringWithFormat:@"Mock response from %@", self.name] dataUsingEncoding:NSUTF8StringEncoding]];
    completion(response, nil);
}

@end

@interface CSCapGraphTests : XCTestCase
@end

@implementation CSCapGraphTests

// Helper to create a Cap for graph testing with specific in/out specs
- (CSCap *)makeGraphCapWithInSpec:(NSString *)inSpec outSpec:(NSString *)outSpec title:(NSString *)title {
    NSString *urnString = [NSString stringWithFormat:@"cap:in=\"%@\";op=convert;out=\"%@\"", inSpec, outSpec];
    CSCapUrn *capUrn = [CSCapUrn fromString:urnString error:nil];
    return [CSCap capWithUrn:capUrn
                       title:title
                     command:@"convert"
                 description:title
                    metadata:@{}
                  mediaSpecs:@{}
                   arguments:[CSCapArguments arguments]
                      output:nil
                acceptsStdin:NO
                metadataJSON:nil];
}

- (void)testCapGraphBasicConstruction {
    CSCapMatrix *registry = [CSCapMatrix registry];

    MockCapSetForGraph *host = [[MockCapSetForGraph alloc] initWithName:@"converter"];

    // Add caps that form a graph:
    // binary -> str -> obj
    CSCap *cap1 = [self makeGraphCapWithInSpec:@"media:type=binary;v=1" outSpec:@"media:type=string;v=1" title:@"Binary to String"];
    CSCap *cap2 = [self makeGraphCapWithInSpec:@"media:type=string;v=1" outSpec:@"media:type=object;v=1" title:@"String to Object"];

    [registry registerCapSet:@"converter" host:host capabilities:@[cap1, cap2] error:nil];

    CSCapCube *cube = [CSCapCube cube];
    [cube addRegistry:@"converters" registry:registry];

    CSCapGraph *graph = [cube graph];

    // Check nodes
    NSSet<NSString *> *nodes = [graph getNodes];
    XCTAssertEqual(nodes.count, 3, @"Expected 3 nodes");

    // Check edges
    NSArray<CSCapGraphEdge *> *edges = [graph getEdges];
    XCTAssertEqual(edges.count, 2, @"Expected 2 edges");

    // Check stats
    CSCapGraphStats *stats = [graph stats];
    XCTAssertEqual(stats.nodeCount, 3, @"Expected 3 nodes in stats");
    XCTAssertEqual(stats.edgeCount, 2, @"Expected 2 edges in stats");
}

- (void)testCapGraphOutgoingIncoming {
    CSCapMatrix *registry = [CSCapMatrix registry];

    MockCapSetForGraph *host = [[MockCapSetForGraph alloc] initWithName:@"converter"];

    // binary -> str, binary -> obj
    CSCap *cap1 = [self makeGraphCapWithInSpec:@"media:type=binary;v=1" outSpec:@"media:type=string;v=1" title:@"Binary to String"];
    CSCap *cap2 = [self makeGraphCapWithInSpec:@"media:type=binary;v=1" outSpec:@"media:type=object;v=1" title:@"Binary to Object"];

    [registry registerCapSet:@"converter" host:host capabilities:@[cap1, cap2] error:nil];

    CSCapCube *cube = [CSCapCube cube];
    [cube addRegistry:@"converters" registry:registry];

    CSCapGraph *graph = [cube graph];

    // binary has 2 outgoing edges
    NSArray<CSCapGraphEdge *> *outgoing = [graph getOutgoing:@"media:type=binary;v=1"];
    XCTAssertEqual(outgoing.count, 2, @"Expected 2 outgoing edges from binary");

    // str has 1 incoming edge
    NSArray<CSCapGraphEdge *> *incoming = [graph getIncoming:@"media:type=string;v=1"];
    XCTAssertEqual(incoming.count, 1, @"Expected 1 incoming edge to str");

    // obj has 1 incoming edge
    incoming = [graph getIncoming:@"media:type=object;v=1"];
    XCTAssertEqual(incoming.count, 1, @"Expected 1 incoming edge to obj");
}

- (void)testCapGraphCanConvert {
    CSCapMatrix *registry = [CSCapMatrix registry];

    MockCapSetForGraph *host = [[MockCapSetForGraph alloc] initWithName:@"converter"];

    // binary -> str -> obj
    CSCap *cap1 = [self makeGraphCapWithInSpec:@"media:type=binary;v=1" outSpec:@"media:type=string;v=1" title:@"Binary to String"];
    CSCap *cap2 = [self makeGraphCapWithInSpec:@"media:type=string;v=1" outSpec:@"media:type=object;v=1" title:@"String to Object"];

    [registry registerCapSet:@"converter" host:host capabilities:@[cap1, cap2] error:nil];

    CSCapCube *cube = [CSCapCube cube];
    [cube addRegistry:@"converters" registry:registry];

    CSCapGraph *graph = [cube graph];

    // Direct conversions
    XCTAssertTrue([graph canConvert:@"media:type=binary;v=1" toSpec:@"media:type=string;v=1"], @"Should convert binary to str");
    XCTAssertTrue([graph canConvert:@"media:type=string;v=1" toSpec:@"media:type=object;v=1"], @"Should convert str to obj");

    // Transitive conversion
    XCTAssertTrue([graph canConvert:@"media:type=binary;v=1" toSpec:@"media:type=object;v=1"], @"Should convert binary to obj transitively");

    // Same spec
    XCTAssertTrue([graph canConvert:@"media:type=binary;v=1" toSpec:@"media:type=binary;v=1"], @"Should convert same spec");

    // Impossible conversions
    XCTAssertFalse([graph canConvert:@"media:type=object;v=1" toSpec:@"media:type=binary;v=1"], @"Should not convert obj to binary");
    XCTAssertFalse([graph canConvert:@"std:nonexistent.v1" toSpec:@"media:type=string;v=1"], @"Should not convert nonexistent");
}

- (void)testCapGraphFindPath {
    CSCapMatrix *registry = [CSCapMatrix registry];

    MockCapSetForGraph *host = [[MockCapSetForGraph alloc] initWithName:@"converter"];

    // binary -> str -> obj
    CSCap *cap1 = [self makeGraphCapWithInSpec:@"media:type=binary;v=1" outSpec:@"media:type=string;v=1" title:@"Binary to String"];
    CSCap *cap2 = [self makeGraphCapWithInSpec:@"media:type=string;v=1" outSpec:@"media:type=object;v=1" title:@"String to Object"];

    [registry registerCapSet:@"converter" host:host capabilities:@[cap1, cap2] error:nil];

    CSCapCube *cube = [CSCapCube cube];
    [cube addRegistry:@"converters" registry:registry];

    CSCapGraph *graph = [cube graph];

    // Direct path
    NSArray<CSCapGraphEdge *> *path = [graph findPath:@"media:type=binary;v=1" toSpec:@"media:type=string;v=1"];
    XCTAssertNotNil(path, @"Should find path from binary to str");
    XCTAssertEqual(path.count, 1, @"Expected path length 1");

    // Transitive path
    path = [graph findPath:@"media:type=binary;v=1" toSpec:@"media:type=object;v=1"];
    XCTAssertNotNil(path, @"Should find path from binary to obj");
    XCTAssertEqual(path.count, 2, @"Expected path length 2");
    XCTAssertEqualObjects(path[0].cap.title, @"Binary to String", @"First edge");
    XCTAssertEqualObjects(path[1].cap.title, @"String to Object", @"Second edge");

    // No path
    path = [graph findPath:@"media:type=object;v=1" toSpec:@"media:type=binary;v=1"];
    XCTAssertNil(path, @"Should not find impossible path");

    // Same spec
    path = [graph findPath:@"media:type=binary;v=1" toSpec:@"media:type=binary;v=1"];
    XCTAssertNotNil(path, @"Should return empty path for same spec");
    XCTAssertEqual(path.count, 0, @"Expected empty path for same spec");
}

- (void)testCapGraphFindAllPaths {
    CSCapMatrix *registry = [CSCapMatrix registry];

    MockCapSetForGraph *host = [[MockCapSetForGraph alloc] initWithName:@"converter"];

    // Create a graph with multiple paths:
    // binary -> str -> obj
    // binary -> obj (direct)
    CSCap *cap1 = [self makeGraphCapWithInSpec:@"media:type=binary;v=1" outSpec:@"media:type=string;v=1" title:@"Binary to String"];
    CSCap *cap2 = [self makeGraphCapWithInSpec:@"media:type=string;v=1" outSpec:@"media:type=object;v=1" title:@"String to Object"];
    CSCap *cap3 = [self makeGraphCapWithInSpec:@"media:type=binary;v=1" outSpec:@"media:type=object;v=1" title:@"Binary to Object (direct)"];

    [registry registerCapSet:@"converter" host:host capabilities:@[cap1, cap2, cap3] error:nil];

    CSCapCube *cube = [CSCapCube cube];
    [cube addRegistry:@"converters" registry:registry];

    CSCapGraph *graph = [cube graph];

    // Find all paths from binary to obj
    NSArray<NSArray<CSCapGraphEdge *> *> *paths = [graph findAllPaths:@"media:type=binary;v=1" toSpec:@"media:type=object;v=1" maxDepth:3];

    XCTAssertEqual(paths.count, 2, @"Expected 2 paths");

    // Paths should be sorted by length (shortest first)
    XCTAssertEqual(paths[0].count, 1, @"First path should have length 1 (direct)");
    XCTAssertEqual(paths[1].count, 2, @"Second path should have length 2 (via str)");
}

- (void)testCapGraphGetDirectEdges {
    CSCapMatrix *registry1 = [CSCapMatrix registry];
    CSCapMatrix *registry2 = [CSCapMatrix registry];

    MockCapSetForGraph *host1 = [[MockCapSetForGraph alloc] initWithName:@"converter1"];
    MockCapSetForGraph *host2 = [[MockCapSetForGraph alloc] initWithName:@"converter2"];

    // Two converters: binary -> str with different specificities
    CSCap *cap1 = [self makeGraphCapWithInSpec:@"media:type=binary;v=1" outSpec:@"media:type=string;v=1" title:@"Generic Binary to String"];

    // More specific converter (with extra tag for higher specificity)
    CSCapUrn *capUrn2 = [CSCapUrn fromString:@"cap:ext=pdf;in=\"media:type=binary;v=1\";op=convert;out=\"media:type=string;v=1\"" error:nil];
    CSCap *cap2 = [CSCap capWithUrn:capUrn2
                             title:@"PDF Binary to String"
                           command:@"convert"
                       description:@"PDF Binary to String"
                          metadata:@{}
                        mediaSpecs:@{}
                         arguments:[CSCapArguments arguments]
                            output:nil
                      acceptsStdin:NO
                      metadataJSON:nil];

    [registry1 registerCapSet:@"converter1" host:host1 capabilities:@[cap1] error:nil];
    [registry2 registerCapSet:@"converter2" host:host2 capabilities:@[cap2] error:nil];

    CSCapCube *cube = [CSCapCube cube];
    [cube addRegistry:@"reg1" registry:registry1];
    [cube addRegistry:@"reg2" registry:registry2];

    CSCapGraph *graph = [cube graph];

    // Get direct edges (should be sorted by specificity)
    NSArray<CSCapGraphEdge *> *edges = [graph getDirectEdges:@"media:type=binary;v=1" toSpec:@"media:type=string;v=1"];

    XCTAssertEqual(edges.count, 2, @"Expected 2 direct edges");

    // First should be more specific (PDF converter)
    XCTAssertEqualObjects(edges[0].cap.title, @"PDF Binary to String", @"First edge should be more specific");
    XCTAssertGreaterThan(edges[0].specificity, edges[1].specificity, @"First edge should have higher specificity");
}

- (void)testCapGraphStats {
    CSCapMatrix *registry = [CSCapMatrix registry];

    MockCapSetForGraph *host = [[MockCapSetForGraph alloc] initWithName:@"converter"];

    // binary -> str -> obj
    //         \-> json
    CSCap *cap1 = [self makeGraphCapWithInSpec:@"media:type=binary;v=1" outSpec:@"media:type=string;v=1" title:@"Binary to String"];
    CSCap *cap2 = [self makeGraphCapWithInSpec:@"media:type=string;v=1" outSpec:@"media:type=object;v=1" title:@"String to Object"];
    CSCap *cap3 = [self makeGraphCapWithInSpec:@"media:type=binary;v=1" outSpec:@"media:type=json;v=1" title:@"Binary to JSON"];

    [registry registerCapSet:@"converter" host:host capabilities:@[cap1, cap2, cap3] error:nil];

    CSCapCube *cube = [CSCapCube cube];
    [cube addRegistry:@"converters" registry:registry];

    CSCapGraph *graph = [cube graph];
    CSCapGraphStats *stats = [graph stats];

    // 4 unique nodes: binary, str, obj, json
    XCTAssertEqual(stats.nodeCount, 4, @"Expected 4 nodes");

    // 3 edges
    XCTAssertEqual(stats.edgeCount, 3, @"Expected 3 edges");

    // 2 input specs (binary, str)
    XCTAssertEqual(stats.inputSpecCount, 2, @"Expected 2 input specs");

    // 3 output specs (str, obj, json)
    XCTAssertEqual(stats.outputSpecCount, 3, @"Expected 3 output specs");
}

- (void)testCapGraphWithCapCube {
    // Integration test: build graph from CapCube
    CSCapMatrix *providerRegistry = [CSCapMatrix registry];
    CSCapMatrix *pluginRegistry = [CSCapMatrix registry];

    MockCapSetForGraph *providerHost = [[MockCapSetForGraph alloc] initWithName:@"provider"];
    MockCapSetForGraph *pluginHost = [[MockCapSetForGraph alloc] initWithName:@"plugin"];

    // Provider: binary -> str
    CSCap *providerCap = [self makeGraphCapWithInSpec:@"media:type=binary;v=1" outSpec:@"media:type=string;v=1" title:@"Provider Binary to String"];
    [providerRegistry registerCapSet:@"provider" host:providerHost capabilities:@[providerCap] error:nil];

    // Plugin: str -> obj
    CSCap *pluginCap = [self makeGraphCapWithInSpec:@"media:type=string;v=1" outSpec:@"media:type=object;v=1" title:@"Plugin String to Object"];
    [pluginRegistry registerCapSet:@"plugin" host:pluginHost capabilities:@[pluginCap] error:nil];

    CSCapCube *cube = [CSCapCube cube];
    [cube addRegistry:@"providers" registry:providerRegistry];
    [cube addRegistry:@"plugins" registry:pluginRegistry];

    CSCapGraph *graph = [cube graph];

    // Should be able to convert binary -> obj through both registries
    XCTAssertTrue([graph canConvert:@"media:type=binary;v=1" toSpec:@"media:type=object;v=1"], @"Should convert across registries");

    NSArray<CSCapGraphEdge *> *path = [graph findPath:@"media:type=binary;v=1" toSpec:@"media:type=object;v=1"];
    XCTAssertNotNil(path, @"Should find path");
    XCTAssertEqual(path.count, 2, @"Expected path length 2");

    // Verify edges come from different registries
    XCTAssertEqualObjects(path[0].registryName, @"providers", @"First edge from providers");
    XCTAssertEqualObjects(path[1].registryName, @"plugins", @"Second edge from plugins");
}

@end

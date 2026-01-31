//
//  CSCapCubeTests.m
//  Tests for CSCapCube
//

#import <XCTest/XCTest.h>
#import "CapNs.h"

// Mock CapSet for testing (reuse pattern from CSCapMatrixTests)
@interface MockCapSetForCube : NSObject <CSCapSet>
@property (nonatomic, strong) NSString *name;
@end

@implementation MockCapSetForCube

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

@interface CSCapCubeTests : XCTestCase
@end

@implementation CSCapCubeTests

// Helper to create a Cap for testing
- (CSCap *)makeCapWithUrn:(NSString *)urnString title:(NSString *)title {
    CSCapUrn *capUrn = [CSCapUrn fromString:urnString error:nil];
    return [CSCap capWithUrn:capUrn
                       title:title
                     command:@"test"
                 description:title
                    metadata:@{}
                  mediaSpecs:@[]
                        args:@[]
                      output:nil
                metadataJSON:nil];
}

// Helper for test URNs - media URNs with form=map must be quoted
- (NSString *)testUrnWithTags:(NSString *)tags {
    if (tags.length == 0) {
        return @"cap:in=\"media:void\";out=\"media:form=map;textable\"";
    }
    return [NSString stringWithFormat:@"cap:in=\"media:void\";out=\"media:form=map;textable\";%@", tags];
}

- (void)testCapCubeMoreSpecificWins {
    // This is the key test: provider has less specific cap, plugin has more specific
    // The more specific one should win regardless of registry order

    CSCapMatrix *providerRegistry = [CSCapMatrix registry];
    CSCapMatrix *pluginRegistry = [CSCapMatrix registry];

    // Provider: less specific cap (no ext tag)
    MockCapSetForCube *providerHost = [[MockCapSetForCube alloc] initWithName:@"provider"];
    CSCap *providerCap = [self makeCapWithUrn:@"cap:in=media:bytes;op=generate_thumbnail;out=media:binary"
                                       title:@"Provider Thumbnail Generator (generic)"];
    [providerRegistry registerCapSet:@"provider" host:providerHost capabilities:@[providerCap] error:nil];

    // Plugin: more specific cap (has ext=pdf)
    MockCapSetForCube *pluginHost = [[MockCapSetForCube alloc] initWithName:@"plugin"];
    CSCap *pluginCap = [self makeCapWithUrn:@"cap:ext=pdf;in=media:bytes;op=generate_thumbnail;out=media:binary"
                                     title:@"Plugin PDF Thumbnail Generator (specific)"];
    [pluginRegistry registerCapSet:@"plugin" host:pluginHost capabilities:@[pluginCap] error:nil];

    // Create composite with provider first (normally would have priority on ties)
    CSCapCube *composite = [CSCapCube cube];
    [composite addRegistry:@"providers" registry:providerRegistry];
    [composite addRegistry:@"plugins" registry:pluginRegistry];

    // Request for PDF thumbnails - plugin's more specific cap should win
    NSString *request = @"cap:ext=pdf;in=media:bytes;op=generate_thumbnail;out=media:binary";
    NSError *error = nil;
    CSBestCapSetMatch *best = [composite findBestCapSet:request error:&error];

    XCTAssertNotNil(best, @"Should find best cap set");
    XCTAssertNil(error, @"Should not have error");

    // Plugin registry has specificity 4 (in, op, out, ext)
    // Provider registry has specificity 3 (in, op, out)
    // Plugin should win even though providers were added first
    XCTAssertEqualObjects(best.registryName, @"plugins", @"More specific plugin should win over less specific provider");
    XCTAssertEqual(best.specificity, 4, @"Plugin cap has 4 specific tags");
    XCTAssertEqualObjects(best.cap.title, @"Plugin PDF Thumbnail Generator (specific)", @"Should get plugin cap");
}

- (void)testCapCubeTieGoesToFirst {
    // When specificity is equal, first registry wins

    CSCapMatrix *registry1 = [CSCapMatrix registry];
    CSCapMatrix *registry2 = [CSCapMatrix registry];

    // Both have same specificity
    MockCapSetForCube *host1 = [[MockCapSetForCube alloc] initWithName:@"host1"];
    CSCap *cap1 = [self makeCapWithUrn:[self testUrnWithTags:@"ext=pdf;op=generate"]
                                 title:@"Registry 1 Cap"];
    [registry1 registerCapSet:@"host1" host:host1 capabilities:@[cap1] error:nil];

    MockCapSetForCube *host2 = [[MockCapSetForCube alloc] initWithName:@"host2"];
    CSCap *cap2 = [self makeCapWithUrn:[self testUrnWithTags:@"ext=pdf;op=generate"]
                                 title:@"Registry 2 Cap"];
    [registry2 registerCapSet:@"host2" host:host2 capabilities:@[cap2] error:nil];

    CSCapCube *composite = [CSCapCube cube];
    [composite addRegistry:@"first" registry:registry1];
    [composite addRegistry:@"second" registry:registry2];

    NSError *error = nil;
    CSBestCapSetMatch *best = [composite findBestCapSet:[self testUrnWithTags:@"ext=pdf;op=generate"] error:&error];

    XCTAssertNotNil(best, @"Should find best cap set");
    XCTAssertNil(error, @"Should not have error");

    // Both have same specificity, first registry should win
    XCTAssertEqualObjects(best.registryName, @"first", @"On tie, first registry should win");
    XCTAssertEqualObjects(best.cap.title, @"Registry 1 Cap", @"Should get first registry's cap");
}

- (void)testCapCubePollsAll {
    // Test that all registries are polled

    CSCapMatrix *registry1 = [CSCapMatrix registry];
    CSCapMatrix *registry2 = [CSCapMatrix registry];
    CSCapMatrix *registry3 = [CSCapMatrix registry];

    // Registry 1: doesn't match
    MockCapSetForCube *host1 = [[MockCapSetForCube alloc] initWithName:@"host1"];
    CSCap *cap1 = [self makeCapWithUrn:[self testUrnWithTags:@"op=different"]
                                 title:@"Registry 1"];
    [registry1 registerCapSet:@"host1" host:host1 capabilities:@[cap1] error:nil];

    // Registry 2: matches but less specific
    MockCapSetForCube *host2 = [[MockCapSetForCube alloc] initWithName:@"host2"];
    CSCap *cap2 = [self makeCapWithUrn:[self testUrnWithTags:@"op=generate"]
                                 title:@"Registry 2"];
    [registry2 registerCapSet:@"host2" host:host2 capabilities:@[cap2] error:nil];

    // Registry 3: matches and most specific
    MockCapSetForCube *host3 = [[MockCapSetForCube alloc] initWithName:@"host3"];
    CSCap *cap3 = [self makeCapWithUrn:[self testUrnWithTags:@"ext=pdf;format=thumbnail;op=generate"]
                                 title:@"Registry 3"];
    [registry3 registerCapSet:@"host3" host:host3 capabilities:@[cap3] error:nil];

    CSCapCube *composite = [CSCapCube cube];
    [composite addRegistry:@"r1" registry:registry1];
    [composite addRegistry:@"r2" registry:registry2];
    [composite addRegistry:@"r3" registry:registry3];

    NSError *error = nil;
    CSBestCapSetMatch *best = [composite findBestCapSet:[self testUrnWithTags:@"ext=pdf;format=thumbnail;op=generate"] error:&error];

    XCTAssertNotNil(best, @"Should find best cap set");
    XCTAssertNil(error, @"Should not have error");

    // Registry 3 has more specific tags
    XCTAssertEqualObjects(best.registryName, @"r3", @"Most specific registry should win");
}

- (void)testCapCubeNoMatch {
    CSCapMatrix *registry = [CSCapMatrix registry];

    CSCapCube *composite = [CSCapCube cube];
    [composite addRegistry:@"empty" registry:registry];

    NSError *error = nil;
    CSBestCapSetMatch *best = [composite findBestCapSet:[self testUrnWithTags:@"op=nonexistent"] error:&error];

    XCTAssertNil(best, @"Should not find match for nonexistent capability");
    XCTAssertNotNil(error, @"Should have error");
    XCTAssertEqual(error.code, CSCapMatrixErrorTypeNoSetsFound, @"Should be NoSetsFound error");
}

- (void)testCapCubeFallbackScenario {
    // Test the exact scenario from the user's issue:
    // Provider: generic fallback (can handle any file type)
    // Plugin:   PDF-specific handler
    // Request:  PDF thumbnail
    // Expected: Plugin wins (more specific)

    CSCapMatrix *providerRegistry = [CSCapMatrix registry];
    CSCapMatrix *pluginRegistry = [CSCapMatrix registry];

    // Provider with generic fallback (can handle any file type)
    MockCapSetForCube *providerHost = [[MockCapSetForCube alloc] initWithName:@"provider_fallback"];
    CSCap *providerCap = [self makeCapWithUrn:@"cap:in=media:bytes;op=generate_thumbnail;out=media:binary"
                                       title:@"Generic Thumbnail Provider"];
    [providerRegistry registerCapSet:@"provider_fallback" host:providerHost capabilities:@[providerCap] error:nil];

    // Plugin with PDF-specific handler
    MockCapSetForCube *pluginHost = [[MockCapSetForCube alloc] initWithName:@"pdf_plugin"];
    CSCap *pluginCap = [self makeCapWithUrn:@"cap:ext=pdf;in=media:bytes;op=generate_thumbnail;out=media:binary"
                                     title:@"PDF Thumbnail Plugin"];
    [pluginRegistry registerCapSet:@"pdf_plugin" host:pluginHost capabilities:@[pluginCap] error:nil];

    // Providers first (would win on tie)
    CSCapCube *composite = [CSCapCube cube];
    [composite addRegistry:@"providers" registry:providerRegistry];
    [composite addRegistry:@"plugins" registry:pluginRegistry];

    // Request for PDF thumbnail
    NSString *request = @"cap:ext=pdf;in=media:bytes;op=generate_thumbnail;out=media:binary";
    NSError *error = nil;
    CSBestCapSetMatch *best = [composite findBestCapSet:request error:&error];

    XCTAssertNotNil(best, @"Should find best cap set");
    XCTAssertNil(error, @"Should not have error");

    // Plugin (specificity 4) should beat provider (specificity 3)
    XCTAssertEqualObjects(best.registryName, @"plugins", @"Plugin should win");
    XCTAssertEqualObjects(best.cap.title, @"PDF Thumbnail Plugin", @"Should get plugin cap");
    XCTAssertEqual(best.specificity, 4, @"Plugin has specificity 4");

    // Also test that for a different file type, provider wins
    NSString *requestWav = @"cap:ext=wav;in=media:bytes;op=generate_thumbnail;out=media:binary";
    CSBestCapSetMatch *bestWav = [composite findBestCapSet:requestWav error:&error];

    XCTAssertNotNil(bestWav, @"Should find best cap set for wav");
    XCTAssertNil(error, @"Should not have error for wav");

    // Only provider matches (plugin doesn't match ext=wav)
    XCTAssertEqualObjects(bestWav.registryName, @"providers", @"Provider should win for wav");
    XCTAssertEqualObjects(bestWav.cap.title, @"Generic Thumbnail Provider", @"Should get provider cap");
}

- (void)testCapCubeCanMethod {
    // Test the can() method that returns a CSCapCaller

    CSCapMatrix *providerRegistry = [CSCapMatrix registry];

    MockCapSetForCube *providerHost = [[MockCapSetForCube alloc] initWithName:@"test_provider"];
    CSCap *providerCap = [self makeCapWithUrn:[self testUrnWithTags:@"ext=pdf;op=generate"]
                                       title:@"Test Provider"];
    [providerRegistry registerCapSet:@"test_provider" host:providerHost capabilities:@[providerCap] error:nil];

    CSCapCube *composite = [CSCapCube cube];
    [composite addRegistry:@"providers" registry:providerRegistry];

    // Test can() returns a CSCapCaller
    NSError *error = nil;
    CSCapCaller *caller = [composite can:[self testUrnWithTags:@"ext=pdf;op=generate"] error:&error];

    XCTAssertNotNil(caller, @"Should return CSCapCaller");
    XCTAssertNil(error, @"Should not have error");

    // Verify we got the right cap via CanHandle checks
    XCTAssertTrue([composite canHandle:[self testUrnWithTags:@"ext=pdf;op=generate"]], @"Should handle matching cap");
    XCTAssertFalse([composite canHandle:[self testUrnWithTags:@"op=nonexistent"]], @"Should not handle non-matching cap");
}

- (void)testCapCubeRegistryManagement {
    CSCapCube *composite = [CSCapCube cube];

    CSCapMatrix *registry1 = [CSCapMatrix registry];
    CSCapMatrix *registry2 = [CSCapMatrix registry];

    // Test AddRegistry
    [composite addRegistry:@"r1" registry:registry1];
    [composite addRegistry:@"r2" registry:registry2];

    NSArray<NSString *> *names = [composite getRegistryNames];
    XCTAssertEqual(names.count, 2, @"Should have 2 registries");

    // Test GetRegistry
    CSCapMatrix *got = [composite getRegistry:@"r1"];
    XCTAssertEqual(got, registry1, @"Should get correct registry");

    // Test RemoveRegistry
    CSCapMatrix *removed = [composite removeRegistry:@"r1"];
    XCTAssertEqual(removed, registry1, @"Should return removed registry");

    names = [composite getRegistryNames];
    XCTAssertEqual(names.count, 1, @"Should have 1 registry after removal");

    // Test GetRegistry for non-existent
    got = [composite getRegistry:@"nonexistent"];
    XCTAssertNil(got, @"Should return nil for non-existent registry");
}

@end

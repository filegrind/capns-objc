//
//  CSCapMatrixTests.m
//  Tests for CSCapMatrix
//

#import <XCTest/XCTest.h>
#import "CapNs.h"

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
    CSCapUrn *capUrn = [CSCapUrn fromString:@"cap:in=media:void;op=test;out=\"media:form=map;textable\";basic" error:&error];
    XCTAssertNotNil(capUrn, @"Failed to create CapUrn: %@", error.localizedDescription);
    XCTAssertNil(error, @"Should not have error creating CapUrn");

    CSCap *cap = [CSCap capWithUrn:capUrn
                             title:@"Test"
                           command:@"test"
                       description:@"Test capability"
                          metadata:@{}
                        mediaSpecs:@{}
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
    NSArray<id<CSCapSet>> *sets = [self.registry findCapSets:@"cap:in=media:void;op=test;out=\"media:form=map;textable\";basic" error:&findError];
    XCTAssertNotNil(sets, @"Should find sets for exact match");
    XCTAssertNil(findError, @"Should not have error for exact match");
    XCTAssertEqual(sets.count, 1, @"Should find exactly one host");

    // Test subset match (request has more specific requirements)
    sets = [self.registry findCapSets:@"cap:in=media:void;model=gpt-4;op=test;out=\"media:form=map;textable\";basic" error:&findError];
    XCTAssertNotNil(sets, @"Should find sets for subset match");
    XCTAssertNil(findError, @"Should not have error for subset match");
    XCTAssertEqual(sets.count, 1, @"Should find exactly one host for subset match");

    // Test no match
    sets = [self.registry findCapSets:@"cap:in=media:void;op=different;out=\"media:form=map;textable\"" error:&findError];
    XCTAssertNil(sets, @"Should not find sets for non-matching capability");
    XCTAssertNotNil(findError, @"Should have error for non-matching capability");
    XCTAssertEqual(findError.code, CSCapMatrixErrorTypeNoSetsFound, @"Should be NoSetsFound error");
}

- (void)testBestCapSetSelection {
    // Register general host
    MockCapSet *generalHost = [[MockCapSet alloc] initWithName:@"general"];
    CSCapUrn *generalCapUrn = [CSCapUrn fromString:@"cap:in=media:void;op=generate;out=\"media:form=map;textable\"" error:nil];
    CSCap *generalCap = [CSCap capWithUrn:generalCapUrn
                                   title:@"Generate"
                                 command:@"generate"
                             description:@"General generation"
                                metadata:@{}
                              mediaSpecs:@{}
                               args:@[]
                                  output:nil
                            metadataJSON:nil];

    // Register specific host
    MockCapSet *specificHost = [[MockCapSet alloc] initWithName:@"specific"];
    CSCapUrn *specificCapUrn = [CSCapUrn fromString:@"cap:in=media:void;model=gpt-4;op=generate;out=\"media:form=map;textable\";text" error:nil];
    CSCap *specificCap = [CSCap capWithUrn:specificCapUrn
                                    title:@"Generate"
                                  command:@"generate"
                              description:@"Specific text generation"
                                 metadata:@{}
                               mediaSpecs:@{}
                                args:@[]
                                   output:nil
                             metadataJSON:nil];

    [self.registry registerCapSet:@"general" host:generalHost capabilities:@[generalCap] error:nil];
    [self.registry registerCapSet:@"specific" host:specificHost capabilities:@[specificCap] error:nil];

    // Request should match the more specific host (using valid URN characters)
    NSError *error = nil;
    CSCap *capDefinition = nil;
    id<CSCapSet> bestHost = [self.registry findBestCapSet:@"cap:in=media:void;model=gpt-4;op=generate;out=\"media:form=map;textable\";temperature=low;text" error:&error capDefinition:&capDefinition];
    XCTAssertNotNil(bestHost, @"Should find a best host");
    XCTAssertNil(error, @"Should not have error finding best host");
    XCTAssertNotNil(capDefinition, @"Should return cap definition");

    // Both sets should match
    NSArray<id<CSCapSet>> *allHosts = [self.registry findCapSets:@"cap:in=media:void;model=gpt-4;op=generate;out=\"media:form=map;textable\";temperature=low;text" error:&error];
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
    BOOL canHandle = [self.registry canHandle:@"cap:in=media:void;op=test;out=\"media:form=map;textable\""];
    XCTAssertFalse(canHandle, @"Empty registry should not handle any capability");

    // After registration
    MockCapSet *host = [[MockCapSet alloc] initWithName:@"test"];
    CSCapUrn *capUrn = [CSCapUrn fromString:@"cap:in=media:void;op=test;out=\"media:form=map;textable\"" error:nil];
    CSCap *cap = [CSCap capWithUrn:capUrn
                             title:@"Test"
                           command:@"test"
                       description:@"Test"
                          metadata:@{}
                        mediaSpecs:@{}
                         args:@[]
                            output:nil
                      metadataJSON:nil];

    [self.registry registerCapSet:@"test" host:host capabilities:@[cap] error:nil];

    canHandle = [self.registry canHandle:@"cap:in=media:void;op=test;out=\"media:form=map;textable\""];
    XCTAssertTrue(canHandle, @"Registry should handle registered capability");

    canHandle = [self.registry canHandle:@"cap:extra=param;in=media:void;op=test;out=\"media:form=map;textable\""];
    XCTAssertTrue(canHandle, @"Registry should handle capability with extra parameters");

    canHandle = [self.registry canHandle:@"cap:in=media:void;op=different;out=\"media:form=map;textable\""];
    XCTAssertFalse(canHandle, @"Registry should not handle unregistered capability");
}

- (void)testUnregisterCapSet {
    MockCapSet *host = [[MockCapSet alloc] initWithName:@"test"];
    CSCapUrn *capUrn = [CSCapUrn fromString:@"cap:in=media:void;op=test;out=\"media:form=map;textable\"" error:nil];
    CSCap *cap = [CSCap capWithUrn:capUrn
                             title:@"Test"
                           command:@"test"
                       description:@"Test"
                          metadata:@{}
                        mediaSpecs:@{}
                         args:@[]
                            output:nil
                      metadataJSON:nil];

    [self.registry registerCapSet:@"test" host:host capabilities:@[cap] error:nil];

    // Verify it's registered
    XCTAssertTrue([self.registry canHandle:@"cap:in=media:void;op=test;out=\"media:form=map;textable\""], @"Should handle capability before unregistering");

    // Unregister
    BOOL success = [self.registry unregisterCapSet:@"test"];
    XCTAssertTrue(success, @"Should successfully unregister existing host");

    // Verify it's gone
    XCTAssertFalse([self.registry canHandle:@"cap:in=media:void;op=test;out=\"media:form=map;textable\""], @"Should not handle capability after unregistering");

    // Try to unregister non-existent host
    success = [self.registry unregisterCapSet:@"nonexistent"];
    XCTAssertFalse(success, @"Should return false when unregistering non-existent host");
}

- (void)testClear {
    MockCapSet *host = [[MockCapSet alloc] initWithName:@"test"];
    CSCapUrn *capUrn = [CSCapUrn fromString:@"cap:in=media:void;op=test;out=\"media:form=map;textable\"" error:nil];
    CSCap *cap = [CSCap capWithUrn:capUrn
                             title:@"Test"
                           command:@"test"
                       description:@"Test"
                          metadata:@{}
                        mediaSpecs:@{}
                         args:@[]
                            output:nil
                      metadataJSON:nil];

    [self.registry registerCapSet:@"test" host:host capabilities:@[cap] error:nil];

    // Verify it's registered
    XCTAssertTrue([self.registry canHandle:@"cap:in=media:void;op=test;out=\"media:form=map;textable\""], @"Should handle capability before clearing");
    XCTAssertEqual([self.registry getHostNames].count, 1, @"Should have one host before clearing");

    // Clear
    [self.registry clear];

    // Verify everything is gone
    XCTAssertFalse([self.registry canHandle:@"cap:in=media:void;op=test;out=\"media:form=map;textable\""], @"Should not handle any capabilities after clearing");
    XCTAssertEqual([self.registry getHostNames].count, 0, @"Should have no sets after clearing");
}

@end

//
//  CSCapHostRegistryTests.m
//  Tests for CSCapHostRegistry
//

#import <XCTest/XCTest.h>
#import "../../Sources/CapNs/include/CSCapHostRegistry.h"
#import "../../Sources/CapNs/include/CSCapUrn.h"
#import "../../Sources/CapNs/include/CSCap.h"
#import "../../Sources/CapNs/include/CSResponseWrapper.h"

// Mock CapHost for testing
@interface MockCapHost : NSObject <CSCapHost>
@property (nonatomic, strong) NSString *name;
@end

@implementation MockCapHost

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

@interface CSCapHostRegistryTests : XCTestCase
@property (nonatomic, strong) CSCapHostRegistry *registry;
@end

@implementation CSCapHostRegistryTests

- (void)setUp {
    [super setUp];
    self.registry = [CSCapHostRegistry registry];
}

- (void)tearDown {
    self.registry = nil;
    [super tearDown];
}

- (void)testRegisterAndFindCapHost {
    MockCapHost *host = [[MockCapHost alloc] initWithName:@"test-host"];
    
    NSError *error = nil;
    CSCapUrn *capUrn = [CSCapUrn fromString:@"cap:action=test;type=basic" error:&error];
    XCTAssertNotNil(capUrn, @"Failed to create CapUrn: %@", error.localizedDescription);
    XCTAssertNil(error, @"Should not have error creating CapUrn");
    
    CSCap *cap = [CSCap capWithUrn:capUrn 
                            command:@"test"
                        description:@"Test capability"
                           metadata:@{}
                          arguments:[[CSCapArguments alloc] init]
                             output:nil
                       acceptsStdin:NO];
    
    NSError *registerError = nil;
    BOOL success = [self.registry registerCapHost:@"test-host" 
                                             host:host 
                                     capabilities:@[cap] 
                                            error:&registerError];
    
    XCTAssertTrue(success, @"Failed to register cap host");
    XCTAssertNil(registerError, @"Registration should not produce error");
    
    // Test exact match
    NSError *findError = nil;
    NSArray<id<CSCapHost>> *hosts = [self.registry findCapHosts:@"cap:action=test;type=basic" error:&findError];
    XCTAssertNotNil(hosts, @"Should find hosts for exact match");
    XCTAssertNil(findError, @"Should not have error for exact match");
    XCTAssertEqual(hosts.count, 1, @"Should find exactly one host");
    
    // Test subset match (request has more specific requirements)
    hosts = [self.registry findCapHosts:@"cap:action=test;type=basic;model=gpt-4" error:&findError];
    XCTAssertNotNil(hosts, @"Should find hosts for subset match");
    XCTAssertNil(findError, @"Should not have error for subset match");
    XCTAssertEqual(hosts.count, 1, @"Should find exactly one host for subset match");
    
    // Test no match
    hosts = [self.registry findCapHosts:@"cap:action=different" error:&findError];
    XCTAssertNil(hosts, @"Should not find hosts for non-matching capability");
    XCTAssertNotNil(findError, @"Should have error for non-matching capability");
    XCTAssertEqual(findError.code, CSCapHostRegistryErrorTypeNoHostsFound, @"Should be NoHostsFound error");
}

- (void)testBestCapHostSelection {
    // Register general host
    MockCapHost *generalHost = [[MockCapHost alloc] initWithName:@"general"];
    CSCapUrn *generalCapUrn = [CSCapUrn fromString:@"cap:action=generate" error:nil];
    CSCap *generalCap = [CSCap capWithUrn:generalCapUrn 
                                   command:@"generate"
                               description:@"General generation"
                                  metadata:@{}
                                 arguments:[[CSCapArguments alloc] init]
                                    output:nil
                              acceptsStdin:NO];
    
    // Register specific host
    MockCapHost *specificHost = [[MockCapHost alloc] initWithName:@"specific"];
    CSCapUrn *specificCapUrn = [CSCapUrn fromString:@"cap:action=generate;type=text;model=gpt-4" error:nil];
    CSCap *specificCap = [CSCap capWithUrn:specificCapUrn 
                                    command:@"generate"
                                description:@"Specific text generation"
                                   metadata:@{}
                                  arguments:[[CSCapArguments alloc] init]
                                     output:nil
                               acceptsStdin:NO];
    
    [self.registry registerCapHost:@"general" host:generalHost capabilities:@[generalCap] error:nil];
    [self.registry registerCapHost:@"specific" host:specificHost capabilities:@[specificCap] error:nil];
    
    // Request should match the more specific host (using valid URN characters)
    NSError *error = nil;
    id<CSCapHost> bestHost = [self.registry findBestCapHost:@"cap:action=generate;type=text;model=gpt-4;temperature=low" error:&error];
    XCTAssertNotNil(bestHost, @"Should find a best host");
    XCTAssertNil(error, @"Should not have error finding best host");
    
    // Both hosts should match
    NSArray<id<CSCapHost>> *allHosts = [self.registry findCapHosts:@"cap:action=generate;type=text;model=gpt-4;temperature=low" error:&error];
    XCTAssertNotNil(allHosts, @"Should find all matching hosts");
    XCTAssertEqual(allHosts.count, 2, @"Should find both hosts");
}

- (void)testInvalidUrnHandling {
    NSError *error = nil;
    NSArray<id<CSCapHost>> *hosts = [self.registry findCapHosts:@"invalid-urn" error:&error];
    
    XCTAssertNil(hosts, @"Should not find hosts for invalid URN");
    XCTAssertNotNil(error, @"Should have error for invalid URN");
    XCTAssertEqual(error.code, CSCapHostRegistryErrorTypeInvalidUrn, @"Should be InvalidUrn error");
}

- (void)testCanHandle {
    // Empty registry
    BOOL canHandle = [self.registry canHandle:@"cap:action=test"];
    XCTAssertFalse(canHandle, @"Empty registry should not handle any capability");
    
    // After registration
    MockCapHost *host = [[MockCapHost alloc] initWithName:@"test"];
    CSCapUrn *capUrn = [CSCapUrn fromString:@"cap:action=test" error:nil];
    CSCap *cap = [CSCap capWithUrn:capUrn 
                           command:@"test"
                       description:@"Test"
                          metadata:@{}
                         arguments:[[CSCapArguments alloc] init]
                            output:nil
                      acceptsStdin:NO];
    
    [self.registry registerCapHost:@"test" host:host capabilities:@[cap] error:nil];
    
    canHandle = [self.registry canHandle:@"cap:action=test"];
    XCTAssertTrue(canHandle, @"Registry should handle registered capability");
    
    canHandle = [self.registry canHandle:@"cap:action=test;extra=param"];
    XCTAssertTrue(canHandle, @"Registry should handle capability with extra parameters");
    
    canHandle = [self.registry canHandle:@"cap:action=different"];
    XCTAssertFalse(canHandle, @"Registry should not handle unregistered capability");
}

- (void)testUnregisterCapHost {
    MockCapHost *host = [[MockCapHost alloc] initWithName:@"test"];
    CSCapUrn *capUrn = [CSCapUrn fromString:@"cap:action=test" error:nil];
    CSCap *cap = [CSCap capWithUrn:capUrn 
                           command:@"test"
                       description:@"Test"
                          metadata:@{}
                         arguments:[[CSCapArguments alloc] init]
                            output:nil
                      acceptsStdin:NO];
    
    [self.registry registerCapHost:@"test" host:host capabilities:@[cap] error:nil];
    
    // Verify it's registered
    XCTAssertTrue([self.registry canHandle:@"cap:action=test"], @"Should handle capability before unregistering");
    
    // Unregister
    BOOL success = [self.registry unregisterCapHost:@"test"];
    XCTAssertTrue(success, @"Should successfully unregister existing host");
    
    // Verify it's gone
    XCTAssertFalse([self.registry canHandle:@"cap:action=test"], @"Should not handle capability after unregistering");
    
    // Try to unregister non-existent host
    success = [self.registry unregisterCapHost:@"nonexistent"];
    XCTAssertFalse(success, @"Should return false when unregistering non-existent host");
}

- (void)testClear {
    MockCapHost *host = [[MockCapHost alloc] initWithName:@"test"];
    CSCapUrn *capUrn = [CSCapUrn fromString:@"cap:action=test" error:nil];
    CSCap *cap = [CSCap capWithUrn:capUrn 
                           command:@"test"
                       description:@"Test"
                          metadata:@{}
                         arguments:[[CSCapArguments alloc] init]
                            output:nil
                      acceptsStdin:NO];
    
    [self.registry registerCapHost:@"test" host:host capabilities:@[cap] error:nil];
    
    // Verify it's registered
    XCTAssertTrue([self.registry canHandle:@"cap:action=test"], @"Should handle capability before clearing");
    XCTAssertEqual([self.registry getHostNames].count, 1, @"Should have one host before clearing");
    
    // Clear
    [self.registry clear];
    
    // Verify everything is gone
    XCTAssertFalse([self.registry canHandle:@"cap:action=test"], @"Should not handle any capabilities after clearing");
    XCTAssertEqual([self.registry getHostNames].count, 0, @"Should have no hosts after clearing");
}

@end
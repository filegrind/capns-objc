//
//  CSCapRegistryTests.m
//  CapNsTests
//
//  Tests for registry functionality
//

#import <XCTest/XCTest.h>
#import "CSCapRegistry.h"
#import "CSCap.h"
#import "CSCapUrn.h"

@interface CSCapRegistryTests : XCTestCase

@end

@implementation CSCapRegistryTests

- (void)testRegistryCreation {
    CSCapRegistry *registry = [[CSCapRegistry alloc] init];
    XCTAssertNotNil(registry);
}

// Registry validator tests removed - not part of current API

- (void)testRegistryValidCapCheck {
    CSCapRegistry *registry = [[CSCapRegistry alloc] init];
    
    // Test that registry checks if cap exists in cache
    BOOL exists1 = [registry capExists:@"cap:op=extract;target=metadata"];
    BOOL exists2 = [registry capExists:@"cap:op=different"];
    
    // These should both be NO since cache is empty initially
    XCTAssertFalse(exists1);
    XCTAssertFalse(exists2);
}

// Note: These tests would make actual HTTP requests to capns.org
// Uncomment to test with real registry
/*
- (void)testGetCapDefinitionReal {
    CSCapRegistry *registry = [CSCapRegistry registry];
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"Get cap definition"];
    
    [registry getCapDefinition:@"cap:op=extract;target=metadata" completion:^(CSRegistryCapDefinition *definition, NSError *error) {
        if (error) {
            NSLog(@"Skipping real registry test: %@", error);
        } else {
            XCTAssertNotNil(definition);
            XCTAssertEqualObjects(definition.urn, @"cap:op=extract;target=metadata");
            XCTAssertNotNil(definition.version);
            XCTAssertNotNil(definition.command);
        }
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:15.0 handler:nil];
}

- (void)testValidateCapCanonical {
    CSRegistryValidator *validator = [CSRegistryValidator validator];
    
    NSError *error;
    CSCapUrn *urn = [CSCapUrn fromString:@"cap:op=extract;target=metadata" error:&error];
    XCTAssertNotNil(urn);
    
    CSCap *cap = [CSCap capWithUrn:urn
                           version:@"1.0.0"
                       description:nil
                          metadata:@{}
                           command:@"extract-metadata"
                         arguments:[CSCapArguments arguments]
                            output:nil
                      acceptsStdin:NO];
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"Validate cap"];
    
    [validator validateCapCanonical:cap completion:^(NSError *error) {
        if (error) {
            NSLog(@"Validation error (expected if registry has different version): %@", error);
        }
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:15.0 handler:nil];
}
*/

@end
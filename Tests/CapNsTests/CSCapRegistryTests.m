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
    CSCapRegistry *registry = [CSCapRegistry registry];
    XCTAssertNotNil(registry);
}

- (void)testRegistryValidatorCreation {
    CSRegistryValidator *validator = [CSRegistryValidator validator];
    XCTAssertNotNil(validator);
}

- (void)testCacheKeyGeneration {
    CSCapRegistry *registry = [CSCapRegistry registry];
    
    NSString *key1 = [registry cacheKeyForUrn:@"cap:action=extract;target=metadata"];
    NSString *key2 = [registry cacheKeyForUrn:@"cap:action=extract;target=metadata"];
    NSString *key3 = [registry cacheKeyForUrn:@"cap:action=different"];
    
    XCTAssertEqualObjects(key1, key2);
    XCTAssertNotEqualObjects(key1, key3);
    XCTAssertEqual(key1.length, 64); // SHA256 hex string length
}

// Note: These tests would make actual HTTP requests to capns.org
// Uncomment to test with real registry
/*
- (void)testGetCapDefinitionReal {
    CSCapRegistry *registry = [CSCapRegistry registry];
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"Get cap definition"];
    
    [registry getCapDefinition:@"cap:action=extract;target=metadata" completion:^(CSRegistryCapDefinition *definition, NSError *error) {
        if (error) {
            NSLog(@"Skipping real registry test: %@", error);
        } else {
            XCTAssertNotNil(definition);
            XCTAssertEqualObjects(definition.urn, @"cap:action=extract;target=metadata");
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
    CSCapUrn *urn = [CSCapUrn fromString:@"cap:action=extract;target=metadata" error:&error];
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
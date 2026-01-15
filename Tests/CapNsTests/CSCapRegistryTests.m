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

// Helper function to build registry URL (replicates logic from CSCapRegistry)
static NSString *buildRegistryURL(NSString *urn) {
    NSString *registryBaseURL = @"https://capns.org";

    // Normalize the cap URN using the proper parser
    NSString *normalizedUrn = urn;
    NSError *parseError = nil;
    CSCapUrn *parsedUrn = [CSCapUrn fromString:urn error:&parseError];
    if (parsedUrn) {
        normalizedUrn = [parsedUrn toString];
    }

    // URL-encode only the tags part (after "cap:") while keeping "cap:" literal
    NSString *tagsPart = normalizedUrn;
    if ([normalizedUrn hasPrefix:@"cap:"]) {
        tagsPart = [normalizedUrn substringFromIndex:4];
    }
    NSString *encodedTags = [tagsPart stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet alphanumericCharacterSet]];
    return [NSString stringWithFormat:@"%@/cap:%@", registryBaseURL, encodedTags];
}

@implementation CSCapRegistryTests

- (void)testRegistryCreation {
    CSCapRegistry *registry = [[CSCapRegistry alloc] init];
    XCTAssertNotNil(registry);
}

// Registry validator tests removed - not part of current API

- (void)testRegistryValidCapCheck {
    CSCapRegistry *registry = [[CSCapRegistry alloc] init];
    
    // Test that registry checks if cap exists in cache
    BOOL exists1 = [registry capExists:@"cap:in=\"media:type=void;v=1\";op=extract;out=\"media:type=object;v=1\";target=metadata"];
    BOOL exists2 = [registry capExists:@"cap:in=\"media:type=void;v=1\";op=different;out=\"media:type=object;v=1\""];
    
    // These should both be NO since cache is empty initially
    XCTAssertFalse(exists1);
    XCTAssertFalse(exists2);
}

// MARK: - URL Encoding Tests
// Guard against the bug where encoding "cap:" causes 404s

/// Test that URL construction keeps "cap:" literal and only encodes the tags part
- (void)testURLKeepsCapPrefixLiteral {
    NSString *urn = @"cap:in=\"media:type=string;v=1\";op=test;out=\"media:type=object;v=1\"";
    NSString *registryURL = buildRegistryURL(urn);

    // URL must contain literal "/cap:" not encoded
    XCTAssertTrue([registryURL containsString:@"/cap:"], @"URL must contain literal '/cap:' not encoded");
    // URL must NOT contain "cap%3A" (encoded version)
    XCTAssertFalse([registryURL containsString:@"cap%3A"], @"URL must not encode 'cap:' as 'cap%%3A'");
}

/// Test that quoted values in cap URNs are properly URL-encoded
- (void)testURLEncodesQuotedMediaUrns {
    NSString *urn = @"cap:in=\"media:type=listing-id;v=1\";op=use_grinder;out=\"media:type=task-id;v=1\"";
    NSString *registryURL = buildRegistryURL(urn);

    // Quotes must be encoded as %22 (this is the critical encoding for media URNs)
    XCTAssertTrue([registryURL containsString:@"%22"], @"Quotes must be URL-encoded as %%22");
}

/// Test the URL format is valid and can be parsed
- (void)testURLFormatIsValid {
    NSString *urn = @"cap:in=\"media:type=listing-id;v=1\";op=use_grinder;out=\"media:type=task-id;v=1\"";
    NSString *registryURL = buildRegistryURL(urn);

    // URL should be parseable
    NSURL *url = [NSURL URLWithString:registryURL];
    XCTAssertNotNil(url, @"Generated URL must be valid");

    // Host should be capns.org
    XCTAssertEqualObjects(url.host, @"capns.org", @"Host must be capns.org");

    // URL string should contain encoded quotes
    XCTAssertTrue([registryURL containsString:@"%22"], @"URL must contain encoded quotes");

    // URL should start with correct base
    XCTAssertTrue([registryURL hasPrefix:@"https://capns.org/cap:"], @"URL must start with base URL and /cap:");
}

/// Test that different tag orders normalize to the same URL
- (void)testNormalizeHandlesDifferentTagOrders {
    NSString *urn1 = @"cap:op=test;in=\"media:type=string;v=1\";out=\"media:type=object;v=1\"";
    NSString *urn2 = @"cap:in=\"media:type=string;v=1\";out=\"media:type=object;v=1\";op=test";

    NSString *url1 = buildRegistryURL(urn1);
    NSString *url2 = buildRegistryURL(urn2);

    XCTAssertEqualObjects(url1, url2, @"Different tag orders should produce the same URL");
}

// Note: These tests would make actual HTTP requests to capns.org
// Uncomment to test with real registry
/*
- (void)testGetCapDefinitionReal {
    CSCapRegistry *registry = [CSCapRegistry registry];
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"Get cap definition"];
    
    [registry getCapDefinition:@"cap:in=\"media:type=void;v=1\";op=extract;out=\"media:type=object;v=1\";target=metadata" completion:^(CSRegistryCapDefinition *definition, NSError *error) {
        if (error) {
            NSLog(@"Skipping real registry test: %@", error);
        } else {
            XCTAssertNotNil(definition);
            XCTAssertEqualObjects(definition.urn, @"cap:in=\"media:type=void;v=1\";op=extract;out=\"media:type=object;v=1\";target=metadata");
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
    CSCapUrn *urn = [CSCapUrn fromString:@"cap:in=\"media:type=void;v=1\";op=extract;out=\"media:type=object;v=1\";target=metadata" error:&error];
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
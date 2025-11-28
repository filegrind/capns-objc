//
//  CSCapCardTests.m
//  Tests for CSCapCard tag-based system
//

#import <XCTest/XCTest.h>
#import "CapDef.h"

@interface CSCapCardTests : XCTestCase
@end

@implementation CSCapCardTests

- (void)testCapCardCreation {
    NSError *error;
    CSCapCard *capCard = [CSCapCard fromString:@"cap:action=transform;format=json;type=data_processing" error:&error];
    
    XCTAssertNotNil(capCard);
    XCTAssertNil(error);
    
    XCTAssertEqualObjects([capCard getTag:@"type"], @"data_processing");
    XCTAssertEqualObjects([capCard getTag:@"action"], @"transform");
    XCTAssertEqualObjects([capCard getTag:@"format"], @"json");
}

- (void)testCanonicalStringFormat {
    NSError *error;
    CSCapCard *capCard = [CSCapCard fromString:@"cap:action=generate;target=thumbnail;ext=pdf" error:&error];
    
    XCTAssertNotNil(capCard);
    XCTAssertNil(error);
    
    // Should be sorted alphabetically
    XCTAssertEqualObjects([capCard toString], @"cap:action=generate;ext=pdf;target=thumbnail");
}

- (void)testCapPrefixRequired {
    NSError *error;
    // Missing cap: prefix should fail
    CSCapCard *capCard = [CSCapCard fromString:@"action=generate;ext=pdf" error:&error];
    XCTAssertNil(capCard);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, CSCapCardErrorMissingCapPrefix);
    
    // Valid cap: prefix should work
    error = nil;
    capCard = [CSCapCard fromString:@"cap:action=generate;ext=pdf" error:&error];
    XCTAssertNotNil(capCard);
    XCTAssertNil(error);
    XCTAssertEqualObjects([capCard getTag:@"action"], @"generate");
}

- (void)testTrailingSemicolonEquivalence {
    NSError *error;
    // Both with and without trailing semicolon should be equivalent
    CSCapCard *cap1 = [CSCapCard fromString:@"cap:action=generate;ext=pdf" error:&error];
    XCTAssertNotNil(cap1);
    
    CSCapCard *cap2 = [CSCapCard fromString:@"cap:action=generate;ext=pdf;" error:&error];
    XCTAssertNotNil(cap2);
    
    // They should be equal
    XCTAssertEqualObjects(cap1, cap2);
    
    // They should have same hash
    XCTAssertEqual([cap1 hash], [cap2 hash]);
    
    // They should have same string representation (canonical form)
    XCTAssertEqualObjects([cap1 toString], [cap2 toString]);
    
    // They should match each other
    XCTAssertTrue([cap1 matches:cap2]);
    XCTAssertTrue([cap2 matches:cap1]);
}

- (void)testInvalidCapCard {
    NSError *error;
    CSCapCard *capCard = [CSCapCard fromString:@"" error:&error];
    
    XCTAssertNil(capCard);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, CSCapCardErrorInvalidFormat);
}

- (void)testInvalidTagFormat {
    NSError *error;
    CSCapCard *capCard = [CSCapCard fromString:@"cap:invalid_tag" error:&error];
    
    XCTAssertNil(capCard);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, CSCapCardErrorInvalidTagFormat);
}

- (void)testInvalidCharacters {
    NSError *error;
    CSCapCard *capCard = [CSCapCard fromString:@"cap:type@invalid=value" error:&error];
    
    XCTAssertNil(capCard);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, CSCapCardErrorInvalidCharacter);
}

- (void)testTagMatching {
    NSError *error;
    CSCapCard *cap = [CSCapCard fromString:@"cap:action=generate;ext=pdf;target=thumbnail;" error:&error];
    
    // Exact match
    CSCapCard *request1 = [CSCapCard fromString:@"cap:action=generate;ext=pdf;target=thumbnail;" error:&error];
    XCTAssertTrue([cap matches:request1]);
    
    // Subset match
    CSCapCard *request2 = [CSCapCard fromString:@"action=generate" error:&error];
    XCTAssertTrue([cap matches:request2]);
    
    // Wildcard request should match specific cap
    CSCapCard *request3 = [CSCapCard fromString:@"cap:ext=*" error:&error];
    XCTAssertTrue([cap matches:request3]);
    
    // No match - conflicting value
    CSCapCard *request4 = [CSCapCard fromString:@"cap:action=extract" error:&error];
    XCTAssertFalse([cap matches:request4]);
}

- (void)testMissingTagHandling {
    NSError *error;
    CSCapCard *cap = [CSCapCard fromString:@"cap:action=generate" error:&error];
    
    // Request with tag should match cap without tag (treated as wildcard)
    CSCapCard *request1 = [CSCapCard fromString:@"cap:ext=pdf" error:&error];
    XCTAssertTrue([cap matches:request1]); // cap missing ext tag = wildcard, can handle any ext
    
    // But cap with extra tags can match subset requests
    CSCapCard *cap2 = [CSCapCard fromString:@"cap:action=generate;ext=pdf" error:&error];
    CSCapCard *request2 = [CSCapCard fromString:@"cap:action=generate" error:&error];
    XCTAssertTrue([cap2 matches:request2]);
}

- (void)testSpecificity {
    NSError *error;
    CSCapCard *cap1 = [CSCapCard fromString:@"cap:action=*" error:&error];
    CSCapCard *cap2 = [CSCapCard fromString:@"cap:action=generate" error:&error];
    CSCapCard *cap3 = [CSCapCard fromString:@"cap:action=*;ext=pdf" error:&error];
    
    XCTAssertEqual([cap1 specificity], 0); // wildcard doesn't count
    XCTAssertEqual([cap2 specificity], 1);
    XCTAssertEqual([cap3 specificity], 1); // only ext=pdf counts, action=* doesn't count
    
    XCTAssertTrue([cap2 isMoreSpecificThan:cap1]);
}

- (void)testCompatibility {
    NSError *error;
    CSCapCard *cap1 = [CSCapCard fromString:@"cap:action=generate;ext=pdf" error:&error];
    CSCapCard *cap2 = [CSCapCard fromString:@"cap:action=generate;format=*" error:&error];
    CSCapCard *cap3 = [CSCapCard fromString:@"cap:action=extract;ext=pdf" error:&error];
    
    XCTAssertTrue([cap1 isCompatibleWith:cap2]);
    XCTAssertTrue([cap2 isCompatibleWith:cap1]);
    XCTAssertFalse([cap1 isCompatibleWith:cap3]);
    
    // Missing tags are treated as wildcards for compatibility
    CSCapCard *cap4 = [CSCapCard fromString:@"cap:action=generate" error:&error];
    XCTAssertTrue([cap1 isCompatibleWith:cap4]);
    XCTAssertTrue([cap4 isCompatibleWith:cap1]);
}

- (void)testConvenienceMethods {
    NSError *error;
    CSCapCard *cap = [CSCapCard fromString:@"cap:action=generate;ext=pdf;output=binary;target=thumbnail" error:&error];
    
    XCTAssertEqualObjects([cap getTag:@"action"], @"generate");
    XCTAssertEqualObjects([cap getTag:@"target"], @"thumbnail");
    XCTAssertEqualObjects([cap getTag:@"ext"], @"pdf");
    XCTAssertEqualObjects([cap getTag:@"output"], @"binary");
    
    XCTAssertEqualObjects([cap getTag:@"output"], @"binary");
}

- (void)testBuilder {
    NSError *error;
    CSCapCardBuilder *builder = [CSCapCardBuilder builder];
    [builder tag:@"action" value:@"generate"];
    [builder tag:@"target" value:@"thumbnail"];
    [builder tag:@"ext" value:@"pdf"];
    [builder tag:@"output" value:@"binary"];
    CSCapCard *cap = [builder build:&error];
    
    XCTAssertNotNil(cap);
    XCTAssertNil(error);
    
    XCTAssertEqualObjects([cap getTag:@"action"], @"generate");
    XCTAssertEqualObjects([cap getTag:@"output"], @"binary");
}

- (void)testWithTag {
    NSError *error;
    CSCapCard *original = [CSCapCard fromString:@"cap:action=generate" error:&error];
    CSCapCard *modified = [original withTag:@"ext" value:@"pdf"];
    
    XCTAssertEqualObjects([modified toString], @"cap:action=generate;ext=pdf");
    
    // Original should be unchanged
    XCTAssertEqualObjects([original toString], @"cap:action=generate");
}

- (void)testWithoutTag {
    NSError *error;
    CSCapCard *original = [CSCapCard fromString:@"cap:action=generate;ext=pdf" error:&error];
    CSCapCard *modified = [original withoutTag:@"ext"];
    
    XCTAssertEqualObjects([modified toString], @"cap:action=generate");
    
    // Original should be unchanged
    XCTAssertEqualObjects([original toString], @"cap:action=generate;ext=pdf");
}

- (void)testWildcardTag {
    NSError *error;
    CSCapCard *cap = [CSCapCard fromString:@"cap:ext=pdf" error:&error];
    CSCapCard *wildcarded = [cap withWildcardTag:@"ext"];
    
    XCTAssertEqualObjects([wildcarded toString], @"cap:ext=*");
    
    // Test that wildcarded cap can match more requests
    CSCapCard *request = [CSCapCard fromString:@"cap:ext=jpg" error:&error];
    XCTAssertFalse([cap matches:request]);
    
    CSCapCard *wildcardRequest = [CSCapCard fromString:@"cap:ext=*" error:&error];
    XCTAssertTrue([wildcarded matches:wildcardRequest]);
}

- (void)testSubset {
    NSError *error;
    CSCapCard *cap = [CSCapCard fromString:@"cap:action=generate;ext=pdf;output=binary;target=thumbnail" error:&error];
    CSCapCard *subset = [cap subset:@[@"type", @"ext"]];
    
    XCTAssertEqualObjects([subset toString], @"cap:ext=pdf");
}

- (void)testMerge {
    NSError *error;
    CSCapCard *cap1 = [CSCapCard fromString:@"cap:action=generate" error:&error];
    CSCapCard *cap2 = [CSCapCard fromString:@"cap:ext=pdf;output=binary" error:&error];
    CSCapCard *merged = [cap1 merge:cap2];
    
    XCTAssertEqualObjects([merged toString], @"cap:action=generate;ext=pdf;output=binary");
}

- (void)testEquality {
    NSError *error;
    CSCapCard *cap1 = [CSCapCard fromString:@"cap:action=generate" error:&error];
    CSCapCard *cap2 = [CSCapCard fromString:@"cap:action=generate" error:&error]; // different order
    CSCapCard *cap3 = [CSCapCard fromString:@"cap:action=generate;type=image" error:&error];
    
    XCTAssertEqualObjects(cap1, cap2); // order doesn't matter
    XCTAssertNotEqualObjects(cap1, cap3);
    XCTAssertEqual([cap1 hash], [cap2 hash]);
}

- (void)testCoding {
    NSError *error;
    CSCapCard *original = [CSCapCard fromString:@"cap:action=generate" error:&error];
    XCTAssertNotNil(original);
    XCTAssertNil(error);
    
    // Test NSCoding
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:original];
    XCTAssertNotNil(data);
    
    CSCapCard *decoded = [NSKeyedUnarchiver unarchiveObjectWithData:data];
    XCTAssertNotNil(decoded);
    XCTAssertEqualObjects(original, decoded);
}

- (void)testCopying {
    NSError *error;
    CSCapCard *original = [CSCapCard fromString:@"cap:action=generate" error:&error];
    CSCapCard *copy = [original copy];
    
    XCTAssertEqualObjects(original, copy);
    XCTAssertNotEqual(original, copy); // Different objects
}

@end
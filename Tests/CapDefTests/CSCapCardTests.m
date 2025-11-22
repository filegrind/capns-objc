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
    CSCapCard *capCard = [CSCapCard fromString:@"action=transform;format=json;type=data_processing" error:&error];
    
    XCTAssertNotNil(capCard);
    XCTAssertNil(error);
    
    XCTAssertEqualObjects([capCard getTag:@"type"], @"data_processing");
    XCTAssertEqualObjects([capCard getTag:@"action"], @"transform");
    XCTAssertEqualObjects([capCard getTag:@"ext"], @"json");
}

- (void)testCanonicalStringFormat {
    NSError *error;
    CSCapCard *capCard = [CSCapCard fromString:@"action=generate;target=thumbnail;ext=pdf" error:&error];
    
    XCTAssertNotNil(capCard);
    XCTAssertNil(error);
    
    // Should be sorted alphabetically
    XCTAssertEqualObjects([capCard toString], @"action=generate;ext=pdf;target=thumbnail;");
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
    CSCapCard *capCard = [CSCapCard fromString:@"invalid_tag" error:&error];
    
    XCTAssertNil(capCard);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, CSCapCardErrorInvalidTagFormat);
}

- (void)testInvalidCharacters {
    NSError *error;
    CSCapCard *capCard = [CSCapCard fromString:@"type@invalid=value" error:&error];
    
    XCTAssertNil(capCard);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, CSCapCardErrorInvalidCharacter);
}

- (void)testTagMatching {
    NSError *error;
    CSCapCard *cap = [CSCapCard fromString:@"action=generate;ext=pdf;target=thumbnail;" error:&error];
    
    // Exact match
    CSCapCard *request1 = [CSCapCard fromString:@"action=generate;ext=pdf;target=thumbnail;" error:&error];
    XCTAssertTrue([cap matches:request1]);
    
    // Subset match
    CSCapCard *request2 = [CSCapCard fromString:@"action=generate" error:&error];
    XCTAssertTrue([cap matches:request2]);
    
    // Wildcard request should match specific cap
    CSCapCard *request3 = [CSCapCard fromString:@"format=*" error:&error];
    XCTAssertTrue([cap matches:request3]);
    
    // No match - conflicting value
    CSCapCard *request4 = [CSCapCard fromString:@"type=image" error:&error];
    XCTAssertFalse([cap matches:request4]);
}

- (void)testMissingTagHandling {
    NSError *error;
    CSCapCard *cap = [CSCapCard fromString:@"action=generate" error:&error];
    
    // Request with tag should match cap without tag (treated as wildcard)
    CSCapCard *request1 = [CSCapCard fromString:@"ext=pdf" error:&error];
    XCTAssertTrue([cap matches:request1]); // cap missing format tag = wildcard, can handle any format
    
    // But cap with extra tags can match subset requests
    CSCapCard *cap2 = [CSCapCard fromString:@"action=generate;ext=pdf" error:&error];
    CSCapCard *request2 = [CSCapCard fromString:@"action=generate" error:&error];
    XCTAssertTrue([cap2 matches:request2]);
}

- (void)testSpecificity {
    NSError *error;
    CSCapCard *cap1 = [CSCapCard fromString:@"" error:&error];
    CSCapCard *cap2 = [CSCapCard fromString:@"action=generate" error:&error];
    CSCapCard *cap3 = [CSCapCard fromString:@"action=*;ext=pdf" error:&error];
    
    XCTAssertEqual([cap1 specificity], 1);
    XCTAssertEqual([cap2 specificity], 2);
    XCTAssertEqual([cap3 specificity], 2); // wildcard doesn't count
    
    XCTAssertTrue([cap2 isMoreSpecificThan:cap1]);
}

- (void)testCompatibility {
    NSError *error;
    CSCapCard *cap1 = [CSCapCard fromString:@"action=generate;ext=pdf" error:&error];
    CSCapCard *cap2 = [CSCapCard fromString:@"action=generate;format=*" error:&error];
    CSCapCard *cap3 = [CSCapCard fromString:@"type=image;action=generate" error:&error];
    
    XCTAssertTrue([cap1 isCompatibleWith:cap2]);
    XCTAssertTrue([cap2 isCompatibleWith:cap1]);
    XCTAssertFalse([cap1 isCompatibleWith:cap3]);
    
    // Missing tags are treated as wildcards for compatibility
    CSCapCard *cap4 = [CSCapCard fromString:@"action=generate" error:&error];
    XCTAssertTrue([cap1 isCompatibleWith:cap4]);
    XCTAssertTrue([cap4 isCompatibleWith:cap1]);
}

- (void)testConvenienceMethods {
    NSError *error;
    CSCapCard *cap = [CSCapCard fromString:@"action=generate;ext=pdf;output=binary;target=thumbnail;" error:&error];
    
    XCTAssertEqualObjects([cap action], @"generate");
    XCTAssertEqualObjects([cap target], @"thumbnail");
    XCTAssertEqualObjects([cap format], @"pdf");
    XCTAssertEqualObjects([cap output], @"binary");
    
    XCTAssertEqualObjects([cap getTag:@"output"], @"binary");
}

- (void)testBuilder {
    NSError *error;
    CSCapCardBuilder *builder = [CSCapCardBuilder builder];
    [builder action:@"generate"];
    [builder target:@"thumbnail"];
    [builder format:@"pdf"];
    [builder binaryOutput];
    CSCapCard *cap = [builder build:&error];
    
    XCTAssertNotNil(cap);
    XCTAssertNil(error);
    
    XCTAssertEqualObjects([cap action], @"generate");
    XCTAssertEqualObjects([cap getTag:@"output"], @"binary");
}

- (void)testWithTag {
    NSError *error;
    CSCapCard *original = [CSCapCard fromString:@"action=generate" error:&error];
    CSCapCard *modified = [original withTag:@"ext" value:@"pdf"];
    
    XCTAssertEqualObjects([modified toString], @"action=generate;ext=pdf;");
    
    // Original should be unchanged
    XCTAssertEqualObjects([original toString], @"action=generate;");
}

- (void)testWithoutTag {
    NSError *error;
    CSCapCard *original = [CSCapCard fromString:@"action=generate;ext=pdf;" error:&error];
    CSCapCard *modified = [original withoutTag:@"ext"];
    
    XCTAssertEqualObjects([modified toString], @"action=generate;");
    
    // Original should be unchanged
    XCTAssertEqualObjects([original toString], @"action=generate;ext=pdf;");
}

- (void)testWildcardTag {
    NSError *error;
    CSCapCard *cap = [CSCapCard fromString:@"ext=pdf" error:&error];
    CSCapCard *wildcarded = [cap withWildcardTag:@"ext"];
    
    XCTAssertEqualObjects([wildcarded toString], @"format=*;");
    
    // Test that wildcarded cap can match more requests
    CSCapCard *request = [CSCapCard fromString:@"format=jpg" error:&error];
    XCTAssertFalse([cap matches:request]);
    
    CSCapCard *wildcardRequest = [CSCapCard fromString:@"format=*" error:&error];
    XCTAssertTrue([wildcarded matches:wildcardRequest]);
}

- (void)testSubset {
    NSError *error;
    CSCapCard *cap = [CSCapCard fromString:@"action=generate;ext=pdf;output=binary;target=thumbnail;" error:&error];
    CSCapCard *subset = [cap subset:@[@"type", @"ext"]];
    
    XCTAssertEqualObjects([subset toString], @"ext=pdf;");
}

- (void)testMerge {
    NSError *error;
    CSCapCard *cap1 = [CSCapCard fromString:@"action=generate" error:&error];
    CSCapCard *cap2 = [CSCapCard fromString:@"ext=pdf;output=binary" error:&error];
    CSCapCard *merged = [cap1 merge:cap2];
    
    XCTAssertEqualObjects([merged toString], @"action=generate;ext=pdf;output=binary;");
}

- (void)testEquality {
    NSError *error;
    CSCapCard *cap1 = [CSCapCard fromString:@"action=generate;" error:&error];
    CSCapCard *cap2 = [CSCapCard fromString:@"action=generate" error:&error]; // different order
    CSCapCard *cap3 = [CSCapCard fromString:@"action=generate;type=image" error:&error];
    
    XCTAssertEqualObjects(cap1, cap2); // order doesn't matter
    XCTAssertNotEqualObjects(cap1, cap3);
    XCTAssertEqual([cap1 hash], [cap2 hash]);
}

- (void)testCoding {
    NSError *error;
    CSCapCard *original = [CSCapCard fromString:@"action=generate;" error:&error];
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
    CSCapCard *original = [CSCapCard fromString:@"action=generate;" error:&error];
    CSCapCard *copy = [original copy];
    
    XCTAssertEqualObjects(original, copy);
    XCTAssertNotEqual(original, copy); // Different objects
}

@end
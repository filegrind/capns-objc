//
//  CSCapabilityKeyTests.m
//  Tests for CSCapabilityKey tag-based system
//

#import <XCTest/XCTest.h>
#import "CapDef.h"

@interface CSCapabilityKeyTests : XCTestCase
@end

@implementation CSCapabilityKeyTests

- (void)testCapabilityKeyCreation {
    NSError *error;
    CSCapabilityKey *capKey = [CSCapabilityKey fromString:@"action=transform;format=json;type=data_processing" error:&error];
    
    XCTAssertNotNil(capKey);
    XCTAssertNil(error);
    
    XCTAssertEqualObjects([capKey getTag:@"type"], @"data_processing");
    XCTAssertEqualObjects([capKey getTag:@"action"], @"transform");
    XCTAssertEqualObjects([capKey getTag:@"format"], @"json");
}

- (void)testCanonicalStringFormat {
    NSError *error;
    CSCapabilityKey *capKey = [CSCapabilityKey fromString:@"type=document;action=generate;target=thumbnail;format=pdf" error:&error];
    
    XCTAssertNotNil(capKey);
    XCTAssertNil(error);
    
    // Should be sorted alphabetically
    XCTAssertEqualObjects([capKey toString], @"action=generate;format=pdf;target=thumbnail;type=document");
}

- (void)testInvalidCapabilityKey {
    NSError *error;
    CSCapabilityKey *capKey = [CSCapabilityKey fromString:@"" error:&error];
    
    XCTAssertNil(capKey);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, CSCapabilityKeyErrorInvalidFormat);
}

- (void)testInvalidTagFormat {
    NSError *error;
    CSCapabilityKey *capKey = [CSCapabilityKey fromString:@"type=document;invalid_tag" error:&error];
    
    XCTAssertNil(capKey);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, CSCapabilityKeyErrorInvalidTagFormat);
}

- (void)testInvalidCharacters {
    NSError *error;
    CSCapabilityKey *capKey = [CSCapabilityKey fromString:@"type@invalid=value" error:&error];
    
    XCTAssertNil(capKey);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, CSCapabilityKeyErrorInvalidCharacter);
}

- (void)testTagMatching {
    NSError *error;
    CSCapabilityKey *cap = [CSCapabilityKey fromString:@"action=generate;format=pdf;target=thumbnail;type=document" error:&error];
    
    // Exact match
    CSCapabilityKey *request1 = [CSCapabilityKey fromString:@"action=generate;format=pdf;target=thumbnail;type=document" error:&error];
    XCTAssertTrue([cap matches:request1]);
    
    // Subset match
    CSCapabilityKey *request2 = [CSCapabilityKey fromString:@"type=document;action=generate" error:&error];
    XCTAssertTrue([cap matches:request2]);
    
    // Wildcard request should match specific capability
    CSCapabilityKey *request3 = [CSCapabilityKey fromString:@"type=document;format=*" error:&error];
    XCTAssertTrue([cap matches:request3]);
    
    // No match - conflicting value
    CSCapabilityKey *request4 = [CSCapabilityKey fromString:@"type=image" error:&error];
    XCTAssertFalse([cap matches:request4]);
}

- (void)testMissingTagHandling {
    NSError *error;
    CSCapabilityKey *cap = [CSCapabilityKey fromString:@"type=document;action=generate" error:&error];
    
    // Request with tag should match capability without tag (treated as wildcard)
    CSCapabilityKey *request1 = [CSCapabilityKey fromString:@"type=document;format=pdf" error:&error];
    XCTAssertTrue([cap matches:request1]); // cap missing format tag = wildcard, can handle any format
    
    // But capability with extra tags can match subset requests
    CSCapabilityKey *cap2 = [CSCapabilityKey fromString:@"type=document;action=generate;format=pdf" error:&error];
    CSCapabilityKey *request2 = [CSCapabilityKey fromString:@"type=document;action=generate" error:&error];
    XCTAssertTrue([cap2 matches:request2]);
}

- (void)testSpecificity {
    NSError *error;
    CSCapabilityKey *cap1 = [CSCapabilityKey fromString:@"type=document" error:&error];
    CSCapabilityKey *cap2 = [CSCapabilityKey fromString:@"type=document;action=generate" error:&error];
    CSCapabilityKey *cap3 = [CSCapabilityKey fromString:@"type=document;action=*;format=pdf" error:&error];
    
    XCTAssertEqual([cap1 specificity], 1);
    XCTAssertEqual([cap2 specificity], 2);
    XCTAssertEqual([cap3 specificity], 2); // wildcard doesn't count
    
    XCTAssertTrue([cap2 isMoreSpecificThan:cap1]);
}

- (void)testCompatibility {
    NSError *error;
    CSCapabilityKey *cap1 = [CSCapabilityKey fromString:@"type=document;action=generate;format=pdf" error:&error];
    CSCapabilityKey *cap2 = [CSCapabilityKey fromString:@"type=document;action=generate;format=*" error:&error];
    CSCapabilityKey *cap3 = [CSCapabilityKey fromString:@"type=image;action=generate" error:&error];
    
    XCTAssertTrue([cap1 isCompatibleWith:cap2]);
    XCTAssertTrue([cap2 isCompatibleWith:cap1]);
    XCTAssertFalse([cap1 isCompatibleWith:cap3]);
    
    // Missing tags are treated as wildcards for compatibility
    CSCapabilityKey *cap4 = [CSCapabilityKey fromString:@"type=document;action=generate" error:&error];
    XCTAssertTrue([cap1 isCompatibleWith:cap4]);
    XCTAssertTrue([cap4 isCompatibleWith:cap1]);
}

- (void)testConvenienceMethods {
    NSError *error;
    CSCapabilityKey *cap = [CSCapabilityKey fromString:@"action=generate;format=pdf;output=binary;target=thumbnail;type=document" error:&error];
    
    XCTAssertEqualObjects([cap capabilityType], @"document");
    XCTAssertEqualObjects([cap action], @"generate");
    XCTAssertEqualObjects([cap target], @"thumbnail");
    XCTAssertEqualObjects([cap format], @"pdf");
    XCTAssertEqualObjects([cap output], @"binary");
    
    XCTAssertTrue([cap isBinary]);
}

- (void)testBuilder {
    NSError *error;
    CSCapabilityKeyBuilder *builder = [CSCapabilityKeyBuilder builder];
    [builder type:@"document"];
    [builder action:@"generate"];
    [builder target:@"thumbnail"];
    [builder format:@"pdf"];
    [builder binaryOutput];
    CSCapabilityKey *cap = [builder build:&error];
    
    XCTAssertNotNil(cap);
    XCTAssertNil(error);
    
    XCTAssertEqualObjects([cap capabilityType], @"document");
    XCTAssertEqualObjects([cap action], @"generate");
    XCTAssertTrue([cap isBinary]);
}

- (void)testWithTag {
    NSError *error;
    CSCapabilityKey *original = [CSCapabilityKey fromString:@"type=document;action=generate" error:&error];
    CSCapabilityKey *modified = [original withTag:@"format" value:@"pdf"];
    
    XCTAssertEqualObjects([modified toString], @"action=generate;format=pdf;type=document");
    
    // Original should be unchanged
    XCTAssertEqualObjects([original toString], @"action=generate;type=document");
}

- (void)testWithoutTag {
    NSError *error;
    CSCapabilityKey *original = [CSCapabilityKey fromString:@"action=generate;format=pdf;type=document" error:&error];
    CSCapabilityKey *modified = [original withoutTag:@"format"];
    
    XCTAssertEqualObjects([modified toString], @"action=generate;type=document");
    
    // Original should be unchanged
    XCTAssertEqualObjects([original toString], @"action=generate;format=pdf;type=document");
}

- (void)testWildcardTag {
    NSError *error;
    CSCapabilityKey *cap = [CSCapabilityKey fromString:@"type=document;format=pdf" error:&error];
    CSCapabilityKey *wildcarded = [cap withWildcardTag:@"format"];
    
    XCTAssertEqualObjects([wildcarded toString], @"format=*;type=document");
    
    // Test that wildcarded capability can match more requests
    CSCapabilityKey *request = [CSCapabilityKey fromString:@"type=document;format=jpg" error:&error];
    XCTAssertFalse([cap matches:request]);
    
    CSCapabilityKey *wildcardRequest = [CSCapabilityKey fromString:@"type=document;format=*" error:&error];
    XCTAssertTrue([wildcarded matches:wildcardRequest]);
}

- (void)testSubset {
    NSError *error;
    CSCapabilityKey *cap = [CSCapabilityKey fromString:@"action=generate;format=pdf;output=binary;target=thumbnail;type=document" error:&error];
    CSCapabilityKey *subset = [cap subset:@[@"type", @"format"]];
    
    XCTAssertEqualObjects([subset toString], @"format=pdf;type=document");
}

- (void)testMerge {
    NSError *error;
    CSCapabilityKey *cap1 = [CSCapabilityKey fromString:@"type=document;action=generate" error:&error];
    CSCapabilityKey *cap2 = [CSCapabilityKey fromString:@"format=pdf;output=binary" error:&error];
    CSCapabilityKey *merged = [cap1 merge:cap2];
    
    XCTAssertEqualObjects([merged toString], @"action=generate;format=pdf;output=binary;type=document");
}

- (void)testEquality {
    NSError *error;
    CSCapabilityKey *cap1 = [CSCapabilityKey fromString:@"action=generate;type=document" error:&error];
    CSCapabilityKey *cap2 = [CSCapabilityKey fromString:@"type=document;action=generate" error:&error]; // different order
    CSCapabilityKey *cap3 = [CSCapabilityKey fromString:@"action=generate;type=image" error:&error];
    
    XCTAssertEqualObjects(cap1, cap2); // order doesn't matter
    XCTAssertNotEqualObjects(cap1, cap3);
    XCTAssertEqual([cap1 hash], [cap2 hash]);
}

- (void)testCoding {
    NSError *error;
    CSCapabilityKey *original = [CSCapabilityKey fromString:@"action=generate;type=document" error:&error];
    XCTAssertNotNil(original);
    XCTAssertNil(error);
    
    // Test NSCoding
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:original];
    XCTAssertNotNil(data);
    
    CSCapabilityKey *decoded = [NSKeyedUnarchiver unarchiveObjectWithData:data];
    XCTAssertNotNil(decoded);
    XCTAssertEqualObjects(original, decoded);
}

- (void)testCopying {
    NSError *error;
    CSCapabilityKey *original = [CSCapabilityKey fromString:@"action=generate;type=document" error:&error];
    CSCapabilityKey *copy = [original copy];
    
    XCTAssertEqualObjects(original, copy);
    XCTAssertNotEqual(original, copy); // Different objects
}

@end
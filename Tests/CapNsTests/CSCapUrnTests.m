//
//  CSCapUrnTests.m
//  Tests for CSCapUrn tag-based system
//

#import <XCTest/XCTest.h>
#import "CapNs.h"

@interface CSCapUrnTests : XCTestCase
@end

@implementation CSCapUrnTests

- (void)testCapUrnCreation {
    NSError *error;
    CSCapUrn *capUrn = [CSCapUrn fromString:@"cap:action=transform;format=json;type=data_processing" error:&error];
    
    XCTAssertNotNil(capUrn);
    XCTAssertNil(error);
    
    XCTAssertEqualObjects([capUrn getTag:@"type"], @"data_processing");
    XCTAssertEqualObjects([capUrn getTag:@"action"], @"transform");
    XCTAssertEqualObjects([capUrn getTag:@"format"], @"json");
}

- (void)testCanonicalStringFormat {
    NSError *error;
    CSCapUrn *capUrn = [CSCapUrn fromString:@"cap:action=generate;target=thumbnail;ext=pdf" error:&error];
    
    XCTAssertNotNil(capUrn);
    XCTAssertNil(error);
    
    // Should be sorted alphabetically
    XCTAssertEqualObjects([capUrn toString], @"cap:action=generate;ext=pdf;target=thumbnail");
}

- (void)testCapPrefixRequired {
    NSError *error;
    // Missing cap: prefix should fail
    CSCapUrn *capUrn = [CSCapUrn fromString:@"action=generate;ext=pdf" error:&error];
    XCTAssertNil(capUrn);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, CSCapUrnErrorMissingCapPrefix);
    
    // Valid cap: prefix should work
    error = nil;
    capUrn = [CSCapUrn fromString:@"cap:action=generate;ext=pdf" error:&error];
    XCTAssertNotNil(capUrn);
    XCTAssertNil(error);
    XCTAssertEqualObjects([capUrn getTag:@"action"], @"generate");
}

- (void)testTrailingSemicolonEquivalence {
    NSError *error;
    // Both with and without trailing semicolon should be equivalent
    CSCapUrn *cap1 = [CSCapUrn fromString:@"cap:action=generate;ext=pdf" error:&error];
    XCTAssertNotNil(cap1);
    
    CSCapUrn *cap2 = [CSCapUrn fromString:@"cap:action=generate;ext=pdf;" error:&error];
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

- (void)testInvalidCapUrn {
    NSError *error;
    CSCapUrn *capUrn = [CSCapUrn fromString:@"" error:&error];
    
    XCTAssertNil(capUrn);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, CSCapUrnErrorInvalidFormat);
}

- (void)testInvalidTagFormat {
    NSError *error;
    CSCapUrn *capUrn = [CSCapUrn fromString:@"cap:invalid_tag" error:&error];
    
    XCTAssertNil(capUrn);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, CSCapUrnErrorInvalidTagFormat);
}

- (void)testInvalidCharacters {
    NSError *error;
    CSCapUrn *capUrn = [CSCapUrn fromString:@"cap:type@invalid=value" error:&error];
    
    XCTAssertNil(capUrn);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, CSCapUrnErrorInvalidCharacter);
}

- (void)testTagMatching {
    NSError *error;
    CSCapUrn *cap = [CSCapUrn fromString:@"cap:action=generate;ext=pdf;target=thumbnail;" error:&error];
    
    // Exact match
    CSCapUrn *request1 = [CSCapUrn fromString:@"cap:action=generate;ext=pdf;target=thumbnail;" error:&error];
    XCTAssertTrue([cap matches:request1]);
    
    // Subset match
    CSCapUrn *request2 = [CSCapUrn fromString:@"action=generate" error:&error];
    XCTAssertTrue([cap matches:request2]);
    
    // Wildcard request should match specific cap
    CSCapUrn *request3 = [CSCapUrn fromString:@"cap:ext=*" error:&error];
    XCTAssertTrue([cap matches:request3]);
    
    // No match - conflicting value
    CSCapUrn *request4 = [CSCapUrn fromString:@"cap:action=extract" error:&error];
    XCTAssertFalse([cap matches:request4]);
}

- (void)testMissingTagHandling {
    NSError *error;
    CSCapUrn *cap = [CSCapUrn fromString:@"cap:action=generate" error:&error];
    
    // Request with tag should match cap without tag (treated as wildcard)
    CSCapUrn *request1 = [CSCapUrn fromString:@"cap:ext=pdf" error:&error];
    XCTAssertTrue([cap matches:request1]); // cap missing ext tag = wildcard, can handle any ext
    
    // But cap with extra tags can match subset requests
    CSCapUrn *cap2 = [CSCapUrn fromString:@"cap:action=generate;ext=pdf" error:&error];
    CSCapUrn *request2 = [CSCapUrn fromString:@"cap:action=generate" error:&error];
    XCTAssertTrue([cap2 matches:request2]);
}

- (void)testSpecificity {
    NSError *error;
    CSCapUrn *cap1 = [CSCapUrn fromString:@"cap:action=*" error:&error];
    CSCapUrn *cap2 = [CSCapUrn fromString:@"cap:action=generate" error:&error];
    CSCapUrn *cap3 = [CSCapUrn fromString:@"cap:action=*;ext=pdf" error:&error];
    
    XCTAssertEqual([cap1 specificity], 0); // wildcard doesn't count
    XCTAssertEqual([cap2 specificity], 1);
    XCTAssertEqual([cap3 specificity], 1); // only ext=pdf counts, action=* doesn't count
    
    XCTAssertTrue([cap2 isMoreSpecificThan:cap1]);
}

- (void)testCompatibility {
    NSError *error;
    CSCapUrn *cap1 = [CSCapUrn fromString:@"cap:action=generate;ext=pdf" error:&error];
    CSCapUrn *cap2 = [CSCapUrn fromString:@"cap:action=generate;format=*" error:&error];
    CSCapUrn *cap3 = [CSCapUrn fromString:@"cap:action=extract;ext=pdf" error:&error];
    
    XCTAssertTrue([cap1 isCompatibleWith:cap2]);
    XCTAssertTrue([cap2 isCompatibleWith:cap1]);
    XCTAssertFalse([cap1 isCompatibleWith:cap3]);
    
    // Missing tags are treated as wildcards for compatibility
    CSCapUrn *cap4 = [CSCapUrn fromString:@"cap:action=generate" error:&error];
    XCTAssertTrue([cap1 isCompatibleWith:cap4]);
    XCTAssertTrue([cap4 isCompatibleWith:cap1]);
}

- (void)testConvenienceMethods {
    NSError *error;
    CSCapUrn *cap = [CSCapUrn fromString:@"cap:action=generate;ext=pdf;output=binary;target=thumbnail" error:&error];
    
    XCTAssertEqualObjects([cap getTag:@"action"], @"generate");
    XCTAssertEqualObjects([cap getTag:@"target"], @"thumbnail");
    XCTAssertEqualObjects([cap getTag:@"ext"], @"pdf");
    XCTAssertEqualObjects([cap getTag:@"output"], @"binary");
    
    XCTAssertEqualObjects([cap getTag:@"output"], @"binary");
}

- (void)testBuilder {
    NSError *error;
    CSCapUrnBuilder *builder = [CSCapUrnBuilder builder];
    [builder tag:@"action" value:@"generate"];
    [builder tag:@"target" value:@"thumbnail"];
    [builder tag:@"ext" value:@"pdf"];
    [builder tag:@"output" value:@"binary"];
    CSCapUrn *cap = [builder build:&error];
    
    XCTAssertNotNil(cap);
    XCTAssertNil(error);
    
    XCTAssertEqualObjects([cap getTag:@"action"], @"generate");
    XCTAssertEqualObjects([cap getTag:@"output"], @"binary");
}

- (void)testWithTag {
    NSError *error;
    CSCapUrn *original = [CSCapUrn fromString:@"cap:action=generate" error:&error];
    CSCapUrn *modified = [original withTag:@"ext" value:@"pdf"];
    
    XCTAssertEqualObjects([modified toString], @"cap:action=generate;ext=pdf");
    
    // Original should be unchanged
    XCTAssertEqualObjects([original toString], @"cap:action=generate");
}

- (void)testWithoutTag {
    NSError *error;
    CSCapUrn *original = [CSCapUrn fromString:@"cap:action=generate;ext=pdf" error:&error];
    CSCapUrn *modified = [original withoutTag:@"ext"];
    
    XCTAssertEqualObjects([modified toString], @"cap:action=generate");
    
    // Original should be unchanged
    XCTAssertEqualObjects([original toString], @"cap:action=generate;ext=pdf");
}

- (void)testWildcardTag {
    NSError *error;
    CSCapUrn *cap = [CSCapUrn fromString:@"cap:ext=pdf" error:&error];
    CSCapUrn *wildcarded = [cap withWildcardTag:@"ext"];
    
    XCTAssertEqualObjects([wildcarded toString], @"cap:ext=*");
    
    // Test that wildcarded cap can match more requests
    CSCapUrn *request = [CSCapUrn fromString:@"cap:ext=jpg" error:&error];
    XCTAssertFalse([cap matches:request]);
    
    CSCapUrn *wildcardRequest = [CSCapUrn fromString:@"cap:ext=*" error:&error];
    XCTAssertTrue([wildcarded matches:wildcardRequest]);
}

- (void)testSubset {
    NSError *error;
    CSCapUrn *cap = [CSCapUrn fromString:@"cap:action=generate;ext=pdf;output=binary;target=thumbnail" error:&error];
    CSCapUrn *subset = [cap subset:@[@"type", @"ext"]];
    
    XCTAssertEqualObjects([subset toString], @"cap:ext=pdf");
}

- (void)testMerge {
    NSError *error;
    CSCapUrn *cap1 = [CSCapUrn fromString:@"cap:action=generate" error:&error];
    CSCapUrn *cap2 = [CSCapUrn fromString:@"cap:ext=pdf;output=binary" error:&error];
    CSCapUrn *merged = [cap1 merge:cap2];
    
    XCTAssertEqualObjects([merged toString], @"cap:action=generate;ext=pdf;output=binary");
}

- (void)testEquality {
    NSError *error;
    CSCapUrn *cap1 = [CSCapUrn fromString:@"cap:action=generate" error:&error];
    CSCapUrn *cap2 = [CSCapUrn fromString:@"cap:action=generate" error:&error]; // different order
    CSCapUrn *cap3 = [CSCapUrn fromString:@"cap:action=generate;type=image" error:&error];
    
    XCTAssertEqualObjects(cap1, cap2); // order doesn't matter
    XCTAssertNotEqualObjects(cap1, cap3);
    XCTAssertEqual([cap1 hash], [cap2 hash]);
}

- (void)testCoding {
    NSError *error;
    CSCapUrn *original = [CSCapUrn fromString:@"cap:action=generate" error:&error];
    XCTAssertNotNil(original);
    XCTAssertNil(error);
    
    // Test NSCoding
    NSError *archiveError = nil;
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:original requiringSecureCoding:YES error:&archiveError];
    XCTAssertNil(archiveError, @"Archive should succeed");
    XCTAssertNotNil(data);
    
    NSError *unarchiveError = nil;
    CSCapUrn *decoded = [NSKeyedUnarchiver unarchivedObjectOfClass:[CSCapUrn class] fromData:data error:&unarchiveError];
    XCTAssertNil(unarchiveError, @"Unarchive should succeed");
    XCTAssertNotNil(decoded);
    XCTAssertEqualObjects(original, decoded);
}

- (void)testCopying {
    NSError *error;
    CSCapUrn *original = [CSCapUrn fromString:@"cap:action=generate" error:&error];
    CSCapUrn *copy = [original copy];
    
    XCTAssertEqualObjects(original, copy);
    XCTAssertNotEqual(original, copy); // Different objects
}

#pragma mark - New Rule Tests

- (void)testEmptyCapUrn {
    NSError *error = nil;
    // Empty cap URN should be valid and match everything
    CSCapUrn *empty = [CSCapUrn fromString:@"cap:" error:&error];
    XCTAssertNotNil(empty);
    XCTAssertNil(error);
    XCTAssertEqual(empty.tags.count, 0);
    XCTAssertEqualObjects([empty toString], @"cap:");
    
    error = nil;
    // Should match any other cap
    CSCapUrn *specific = [CSCapUrn fromString:@"cap:action=generate;ext=pdf" error:&error];
    XCTAssertTrue([empty matches:specific]);
    XCTAssertTrue([empty matches:empty]);
}

- (void)testExtendedCharacterSupport {
    NSError *error = nil;
    // Test forward slashes and colons in tag components
    CSCapUrn *cap = [CSCapUrn fromString:@"cap:url=https://example_org/api;path=/some/file" error:&error];
    XCTAssertNotNil(cap);
    XCTAssertNil(error);
    XCTAssertEqualObjects([cap getTag:@"url"], @"https://example_org/api");
    XCTAssertEqualObjects([cap getTag:@"path"], @"/some/file");
}

- (void)testWildcardRestrictions {
    NSError *error = nil;
    // Wildcard should be rejected in keys
    CSCapUrn *invalidKey = [CSCapUrn fromString:@"cap:*=value" error:&error];
    XCTAssertNil(invalidKey);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, CSCapUrnErrorInvalidCharacter);
    
    // Reset error for next test
    error = nil;
    
    // Wildcard should be accepted in values
    CSCapUrn *validValue = [CSCapUrn fromString:@"cap:key=*" error:&error];
    XCTAssertNotNil(validValue);
    XCTAssertNil(error);
    XCTAssertEqualObjects([validValue getTag:@"key"], @"*");
}

- (void)testDuplicateKeyRejection {
    NSError *error = nil;
    // Duplicate keys should be rejected
    CSCapUrn *duplicate = [CSCapUrn fromString:@"cap:key=value1;key=value2" error:&error];
    XCTAssertNil(duplicate);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, CSCapUrnErrorDuplicateKey);
}

- (void)testNumericKeyRestriction {
    NSError *error = nil;
    
    // Pure numeric keys should be rejected
    CSCapUrn *numericKey = [CSCapUrn fromString:@"cap:123=value" error:&error];
    XCTAssertNil(numericKey);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, CSCapUrnErrorNumericKey);
    
    // Reset error for next test
    error = nil;
    
    // Mixed alphanumeric keys should be allowed
    CSCapUrn *mixedKey1 = [CSCapUrn fromString:@"cap:key123=value" error:&error];
    XCTAssertNotNil(mixedKey1);
    XCTAssertNil(error);
    
    error = nil;
    CSCapUrn *mixedKey2 = [CSCapUrn fromString:@"cap:123key=value" error:&error];
    XCTAssertNotNil(mixedKey2);
    XCTAssertNil(error);
    
    error = nil;
    // Pure numeric values should be allowed
    CSCapUrn *numericValue = [CSCapUrn fromString:@"cap:key=123" error:&error];
    XCTAssertNotNil(numericValue);
    XCTAssertNil(error);
    XCTAssertEqualObjects([numericValue getTag:@"key"], @"123");
}

@end
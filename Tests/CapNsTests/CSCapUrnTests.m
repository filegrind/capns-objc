//
//  CSCapUrnTests.m
//  Tests for CSCapUrn tag-based system with required direction (in/out)
//
//  NOTE: All caps now require 'in' and 'out' tags for direction.
//

#import <XCTest/XCTest.h>
#import "CapNs.h"

@interface CSCapUrnTests : XCTestCase
@end

@implementation CSCapUrnTests

#pragma mark - Helper Functions

// Helper function to create test URNs with default direction
// Use media:void for in (no input) and media:object for out by default
// Media URNs with form=map must be quoted because they contain = sign
static NSString* testUrn(NSString *tags) {
    if (tags == nil || tags.length == 0) {
        return @"cap:in=\"media:void\";out=\"media:form=map;textable\"";
    }
    return [NSString stringWithFormat:@"cap:in=\"media:void\";out=\"media:form=map;textable\";%@", tags];
}

#pragma mark - Basic Creation Tests

- (void)testCapUrnCreation {
    NSError *error;
    // Use type=data_processing key=value instead of flag
    CSCapUrn *capUrn = [CSCapUrn fromString:testUrn(@"op=transform;format=json;type=data_processing") error:&error];

    XCTAssertNotNil(capUrn);
    XCTAssertNil(error);

    XCTAssertEqualObjects([capUrn getTag:@"type"], @"data_processing");
    XCTAssertEqualObjects([capUrn getTag:@"op"], @"transform");
    XCTAssertEqualObjects([capUrn getTag:@"format"], @"json");
    // Direction should be accessible
    XCTAssertEqualObjects([capUrn getTag:@"in"], @"media:void");
    XCTAssertEqualObjects([capUrn getTag:@"out"], @"media:form=map;textable");
    XCTAssertEqualObjects([capUrn getInSpec], @"media:void");
    XCTAssertEqualObjects([capUrn getOutSpec], @"media:form=map;textable");
}

- (void)testCanonicalStringFormat {
    NSError *error;
    CSCapUrn *capUrn = [CSCapUrn fromString:testUrn(@"op=generate;target=thumbnail;ext=pdf") error:&error];

    XCTAssertNotNil(capUrn);
    XCTAssertNil(error);

    // Should be sorted alphabetically: ext, in, op, out, target
    XCTAssertEqualObjects([capUrn toString], @"cap:ext=pdf;in=media:void;op=generate;out=media:form=map;target=thumbnail");
}

- (void)testCapPrefixRequired {
    NSError *error;
    // Missing cap: prefix should fail
    CSCapUrn *capUrn = [CSCapUrn fromString:@"in=media:void;op=generate;out=\"media:form=map;textable\"" error:&error];
    XCTAssertNil(capUrn);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, CSCapUrnErrorMissingCapPrefix);

    // Valid cap: prefix with in/out should work
    error = nil;
    capUrn = [CSCapUrn fromString:testUrn(@"op=generate;ext=pdf") error:&error];
    XCTAssertNotNil(capUrn);
    XCTAssertNil(error);
    XCTAssertEqualObjects([capUrn getTag:@"op"], @"generate");
}

- (void)testTrailingSemicolonEquivalence {
    NSError *error;
    // Both with and without trailing semicolon should be equivalent
    CSCapUrn *cap1 = [CSCapUrn fromString:testUrn(@"op=generate;ext=pdf") error:&error];
    XCTAssertNotNil(cap1);

    CSCapUrn *cap2 = [CSCapUrn fromString:[testUrn(@"op=generate;ext=pdf") stringByAppendingString:@";"] error:&error];
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

- (void)testValuelessTagParsing {
    NSError *error;
    // Value-less tags are now valid (parsed as wildcards)
    // Cap URN with valid in/out and a value-less tag should succeed
    CSCapUrn *capUrn = [CSCapUrn fromString:@"cap:in=media:void;optimize;out=\"media:form=map;textable\"" error:&error];

    XCTAssertNotNil(capUrn);
    XCTAssertNil(error);
    // Value-less tag is parsed as wildcard
    XCTAssertEqualObjects([capUrn getTag:@"optimize"], @"*");

    // Test value-less tag at end of input
    error = nil;
    capUrn = [CSCapUrn fromString:@"cap:in=media:void;out=media:form=map;flag" error:&error];
    XCTAssertNotNil(capUrn);
    XCTAssertNil(error);
    XCTAssertEqualObjects([capUrn getTag:@"flag"], @"*");
}

- (void)testInvalidCharacters {
    NSError *error;
    CSCapUrn *capUrn = [CSCapUrn fromString:@"cap:in=media:void;type@invalid=value;out=\"media:form=map;textable\"" error:&error];

    XCTAssertNil(capUrn);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, CSCapUrnErrorInvalidCharacter);
}

#pragma mark - Required Direction Tests

- (void)testMissingInSpecFails {
    NSError *error = nil;
    // Missing 'in' should fail
    CSCapUrn *capUrn = [CSCapUrn fromString:@"cap:out=media:form=map;op=generate" error:&error];
    XCTAssertNil(capUrn);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, CSCapUrnErrorMissingInSpec);
}

- (void)testMissingOutSpecFails {
    NSError *error = nil;
    // Missing 'out' should fail
    CSCapUrn *capUrn = [CSCapUrn fromString:@"cap:in=media:void;op=generate" error:&error];
    XCTAssertNil(capUrn);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, CSCapUrnErrorMissingOutSpec);
}

- (void)testEmptyCapUrnFailsWithMissingInSpec {
    NSError *error = nil;
    // Empty cap URN now fails because in/out are required
    CSCapUrn *empty = [CSCapUrn fromString:@"cap:" error:&error];
    XCTAssertNil(empty);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, CSCapUrnErrorMissingInSpec);
}

- (void)testMinimalValidCapUrn {
    NSError *error = nil;
    // Minimal valid cap URN has just in and out
    CSCapUrn *minimal = [CSCapUrn fromString:@"cap:in=media:void;out=\"media:form=map;textable\"" error:&error];
    XCTAssertNotNil(minimal);
    XCTAssertNil(error);
    XCTAssertEqualObjects([minimal getInSpec], @"media:void");
    XCTAssertEqualObjects([minimal getOutSpec], @"media:form=map;textable");
    XCTAssertEqual(minimal.tags.count, 0); // No extra tags
}

- (void)testDirectionMismatchNoMatch {
    NSError *error = nil;
    // Different inSpec should not match
    CSCapUrn *cap1 = [CSCapUrn fromString:@"cap:in=media:string;op=test;out=\"media:form=map;textable\"" error:&error];
    XCTAssertNotNil(cap1);
    CSCapUrn *cap2 = [CSCapUrn fromString:@"cap:in=media:bytes;op=test;out=\"media:form=map;textable\"" error:&error];
    XCTAssertNotNil(cap2);
    XCTAssertFalse([cap1 matches:cap2]);

    // Different outSpec should not match
    CSCapUrn *cap3 = [CSCapUrn fromString:@"cap:in=media:void;op=test;out=\"media:form=map;textable\"" error:&error];
    XCTAssertNotNil(cap3);
    CSCapUrn *cap4 = [CSCapUrn fromString:@"cap:in=media:void;op=test;out=media:binary" error:&error];
    XCTAssertNotNil(cap4);
    XCTAssertFalse([cap3 matches:cap4]);
}

- (void)testDirectionWildcardMatches {
    NSError *error = nil;
    // Wildcard inSpec matches any
    CSCapUrn *wildcardIn = [CSCapUrn fromString:@"cap:in=*;op=test;out=\"media:form=map;textable\"" error:&error];
    XCTAssertNotNil(wildcardIn);
    CSCapUrn *specificIn = [CSCapUrn fromString:@"cap:in=media:string;op=test;out=\"media:form=map;textable\"" error:&error];
    XCTAssertNotNil(specificIn);
    XCTAssertTrue([wildcardIn matches:specificIn]);

    // Wildcard outSpec matches any
    CSCapUrn *wildcardOut = [CSCapUrn fromString:@"cap:in=media:void;op=test;out=*" error:&error];
    XCTAssertNotNil(wildcardOut);
    CSCapUrn *specificOut = [CSCapUrn fromString:@"cap:in=media:void;op=test;out=media:binary" error:&error];
    XCTAssertNotNil(specificOut);
    XCTAssertTrue([wildcardOut matches:specificOut]);
}

#pragma mark - Tag Matching Tests

- (void)testTagMatching {
    NSError *error;
    CSCapUrn *cap = [CSCapUrn fromString:testUrn(@"op=generate;ext=pdf;target=thumbnail") error:&error];
    XCTAssertNotNil(cap);

    // Exact match (same direction, same tags)
    CSCapUrn *request1 = [CSCapUrn fromString:testUrn(@"op=generate;ext=pdf;target=thumbnail") error:&error];
    XCTAssertTrue([cap matches:request1]);

    // Subset match (cap has more tags than request)
    CSCapUrn *request2 = [CSCapUrn fromString:testUrn(@"op=generate") error:&error];
    XCTAssertTrue([cap matches:request2]);

    // Wildcard request should match specific cap
    CSCapUrn *request3 = [CSCapUrn fromString:testUrn(@"ext=*") error:&error];
    XCTAssertTrue([cap matches:request3]);

    // No match - conflicting value
    CSCapUrn *request4 = [CSCapUrn fromString:testUrn(@"op=extract") error:&error];
    XCTAssertFalse([cap matches:request4]);
}

- (void)testMissingTagHandling {
    NSError *error;
    CSCapUrn *cap = [CSCapUrn fromString:testUrn(@"op=generate") error:&error];
    XCTAssertNotNil(cap);

    // Request with tag should match cap without tag (treated as wildcard)
    CSCapUrn *request1 = [CSCapUrn fromString:testUrn(@"ext=pdf") error:&error];
    XCTAssertTrue([cap matches:request1]); // cap missing ext tag = wildcard, can handle any ext

    // But cap with extra tags can match subset requests
    CSCapUrn *cap2 = [CSCapUrn fromString:testUrn(@"op=generate;ext=pdf") error:&error];
    CSCapUrn *request2 = [CSCapUrn fromString:testUrn(@"op=generate") error:&error];
    XCTAssertTrue([cap2 matches:request2]);
}

- (void)testSpecificity {
    NSError *error;
    // Specificity now includes in and out (if not wildcards)
    CSCapUrn *cap1 = [CSCapUrn fromString:@"cap:in=*;op=*;out=*" error:&error];
    XCTAssertNotNil(cap1);
    CSCapUrn *cap2 = [CSCapUrn fromString:testUrn(@"op=generate") error:&error]; // in + out + op = 3
    XCTAssertNotNil(cap2);
    CSCapUrn *cap3 = [CSCapUrn fromString:@"cap:in=*;op=*;out=*;ext=pdf" error:&error]; // ext = 1
    XCTAssertNotNil(cap3);

    XCTAssertEqual([cap1 specificity], 0); // all wildcards
    XCTAssertEqual([cap2 specificity], 3); // in=\"media:void" + out=\"media:object" + op=generate
    XCTAssertEqual([cap3 specificity], 1); // only ext=pdf counts

    XCTAssertTrue([cap2 isMoreSpecificThan:cap1]);
}

- (void)testCompatibility {
    NSError *error;
    CSCapUrn *cap1 = [CSCapUrn fromString:testUrn(@"op=generate;ext=pdf") error:&error];
    CSCapUrn *cap2 = [CSCapUrn fromString:testUrn(@"op=generate;format=*") error:&error];
    CSCapUrn *cap3 = [CSCapUrn fromString:testUrn(@"op=extract;ext=pdf") error:&error];

    XCTAssertTrue([cap1 isCompatibleWith:cap2]);
    XCTAssertTrue([cap2 isCompatibleWith:cap1]);
    XCTAssertFalse([cap1 isCompatibleWith:cap3]); // op mismatch

    // Missing tags are treated as wildcards for compatibility
    CSCapUrn *cap4 = [CSCapUrn fromString:testUrn(@"op=generate") error:&error];
    XCTAssertTrue([cap1 isCompatibleWith:cap4]);
    XCTAssertTrue([cap4 isCompatibleWith:cap1]);

    // Different direction is incompatible
    CSCapUrn *cap5 = [CSCapUrn fromString:@"cap:in=media:string;op=generate;out=\"media:form=map;textable\"" error:&error];
    XCTAssertFalse([cap1 isCompatibleWith:cap5]); // different inSpec
}

#pragma mark - Convenience Methods Tests

- (void)testConvenienceMethods {
    NSError *error;
    CSCapUrn *cap = [CSCapUrn fromString:testUrn(@"op=generate;ext=pdf;output=binary;target=thumbnail") error:&error];

    XCTAssertEqualObjects([cap getTag:@"op"], @"generate");
    XCTAssertEqualObjects([cap getTag:@"target"], @"thumbnail");
    XCTAssertEqualObjects([cap getTag:@"ext"], @"pdf");
    XCTAssertEqualObjects([cap getTag:@"output"], @"binary");
    // Direction via getTag
    XCTAssertEqualObjects([cap getTag:@"in"], @"media:void");
    XCTAssertEqualObjects([cap getTag:@"out"], @"media:form=map;textable");
}

- (void)testWithTag {
    NSError *error;
    CSCapUrn *original = [CSCapUrn fromString:testUrn(@"op=generate") error:&error];
    CSCapUrn *modified = [original withTag:@"ext" value:@"pdf"];

    // Direction preserved, new tag added in alphabetical order
    XCTAssertEqualObjects([modified toString], @"cap:ext=pdf;in=media:void;op=generate;out=\"media:form=map;textable\"");

    // Original should be unchanged
    XCTAssertEqualObjects([original toString], @"cap:in=media:void;op=generate;out=\"media:form=map;textable\"");
}

- (void)testWithTagIgnoresInOut {
    NSError *error;
    CSCapUrn *original = [CSCapUrn fromString:testUrn(@"op=generate") error:&error];

    // withTag for "in" or "out" should silently return self
    CSCapUrn *sameIn = [original withTag:@"in" value:@"different"];
    XCTAssertEqual(original, sameIn); // Same object

    CSCapUrn *sameOut = [original withTag:@"out" value:@"different"];
    XCTAssertEqual(original, sameOut); // Same object
}

- (void)testWithInSpec {
    NSError *error;
    CSCapUrn *original = [CSCapUrn fromString:testUrn(@"op=generate") error:&error];
    CSCapUrn *modified = [original withInSpec:@"media:string"];

    XCTAssertEqualObjects([modified getInSpec], @"media:string");
    XCTAssertEqualObjects([original getInSpec], @"media:void"); // Original unchanged
}

- (void)testWithOutSpec {
    NSError *error;
    CSCapUrn *original = [CSCapUrn fromString:testUrn(@"op=generate") error:&error];
    CSCapUrn *modified = [original withOutSpec:@"media:bytes"];

    XCTAssertEqualObjects([modified getOutSpec], @"media:bytes");
    XCTAssertEqualObjects([original getOutSpec], @"media:form=map;textable"); // Original unchanged
}

- (void)testWithoutTag {
    NSError *error;
    CSCapUrn *original = [CSCapUrn fromString:testUrn(@"op=generate;ext=pdf") error:&error];
    CSCapUrn *modified = [original withoutTag:@"ext"];

    XCTAssertEqualObjects([modified toString], @"cap:in=media:void;op=generate;out=\"media:form=map;textable\"");

    // Original should be unchanged
    XCTAssertEqualObjects([original toString], @"cap:ext=pdf;in=media:void;op=generate;out=\"media:form=map;textable\"");
}

- (void)testWithoutTagIgnoresInOut {
    NSError *error;
    CSCapUrn *original = [CSCapUrn fromString:testUrn(@"op=generate") error:&error];

    // withoutTag for "in" or "out" should silently return self
    CSCapUrn *sameIn = [original withoutTag:@"in"];
    XCTAssertEqual(original, sameIn); // Same object

    CSCapUrn *sameOut = [original withoutTag:@"out"];
    XCTAssertEqual(original, sameOut); // Same object
}

- (void)testWildcardTag {
    NSError *error;
    CSCapUrn *cap = [CSCapUrn fromString:testUrn(@"ext=pdf") error:&error];
    CSCapUrn *wildcarded = [cap withWildcardTag:@"ext"];

    XCTAssertEqualObjects([wildcarded getTag:@"ext"], @"*");

    // Test that wildcarded cap can match more requests
    CSCapUrn *request = [CSCapUrn fromString:testUrn(@"ext=jpg") error:&error];
    XCTAssertFalse([cap matches:request]);
    XCTAssertTrue([wildcarded matches:request]);
}

- (void)testWildcardTagDirection {
    NSError *error;
    CSCapUrn *cap = [CSCapUrn fromString:testUrn(@"op=generate") error:&error];

    // withWildcardTag for "in" should use withInSpec
    CSCapUrn *wildcardIn = [cap withWildcardTag:@"in"];
    XCTAssertEqualObjects([wildcardIn getInSpec], @"*");

    // withWildcardTag for "out" should use withOutSpec
    CSCapUrn *wildcardOut = [cap withWildcardTag:@"out"];
    XCTAssertEqualObjects([wildcardOut getOutSpec], @"*");
}

- (void)testSubset {
    NSError *error;
    CSCapUrn *cap = [CSCapUrn fromString:testUrn(@"op=generate;ext=pdf;output=binary;target=thumbnail") error:&error];
    CSCapUrn *subset = [cap subset:@[@"type", @"ext"]];

    // Direction is always preserved, only ext from the list
    XCTAssertEqualObjects([subset toString], @"cap:ext=pdf;in=media:void;out=\"media:form=map;textable\"");
}

- (void)testMerge {
    NSError *error;
    CSCapUrn *cap1 = [CSCapUrn fromString:@"cap:in=media:void;op=generate;out=\"media:form=map;textable\"" error:&error];
    CSCapUrn *cap2 = [CSCapUrn fromString:@"cap:ext=pdf;in=media:string;out=media:bytes;output=binary" error:&error];
    CSCapUrn *merged = [cap1 merge:cap2];

    // Direction comes from cap2 (other takes precedence)
    XCTAssertEqualObjects([merged getInSpec], @"media:string");
    XCTAssertEqualObjects([merged getOutSpec], @"media:bytes");
    // Tags are merged
    XCTAssertEqualObjects([merged getTag:@"op"], @"generate");
    XCTAssertEqualObjects([merged getTag:@"ext"], @"pdf");
    XCTAssertEqualObjects([merged getTag:@"output"], @"binary");
}

- (void)testEquality {
    NSError *error;
    CSCapUrn *cap1 = [CSCapUrn fromString:testUrn(@"op=generate") error:&error];
    CSCapUrn *cap2 = [CSCapUrn fromString:testUrn(@"op=generate") error:&error];
    CSCapUrn *cap3 = [CSCapUrn fromString:testUrn(@"op=generate;image") error:&error];
    CSCapUrn *cap4 = [CSCapUrn fromString:@"cap:in=media:string;op=generate;out=\"media:form=map;textable\"" error:&error]; // Different in

    XCTAssertEqualObjects(cap1, cap2);
    XCTAssertNotEqualObjects(cap1, cap3);
    XCTAssertNotEqualObjects(cap1, cap4); // Different direction
    XCTAssertEqual([cap1 hash], [cap2 hash]);
}

- (void)testCoding {
    NSError *error;
    CSCapUrn *original = [CSCapUrn fromString:testUrn(@"op=generate") error:&error];
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
    XCTAssertEqualObjects([decoded getInSpec], @"media:void");
    XCTAssertEqualObjects([decoded getOutSpec], @"media:form=map;textable");
}

- (void)testCopying {
    NSError *error;
    CSCapUrn *original = [CSCapUrn fromString:testUrn(@"op=generate") error:&error];
    CSCapUrn *copy = [original copy];

    XCTAssertEqualObjects(original, copy);
    XCTAssertNotEqual(original, copy); // Different objects
    XCTAssertEqualObjects([copy getInSpec], [original getInSpec]);
    XCTAssertEqualObjects([copy getOutSpec], [original getOutSpec]);
}

#pragma mark - Extended Character Support Tests

- (void)testExtendedCharacterSupport {
    NSError *error = nil;
    // Test forward slashes and colons in tag components
    CSCapUrn *cap = [CSCapUrn fromString:@"cap:in=media:void;out=media:form=map;url=https://example_org/api;path=/some/file" error:&error];
    XCTAssertNotNil(cap);
    XCTAssertNil(error);
    XCTAssertEqualObjects([cap getTag:@"url"], @"https://example_org/api");
    XCTAssertEqualObjects([cap getTag:@"path"], @"/some/file");
}

- (void)testWildcardRestrictions {
    NSError *error = nil;
    // Wildcard should be rejected in keys
    CSCapUrn *invalidKey = [CSCapUrn fromString:@"cap:in=media:void;out=media:form=map;*=value" error:&error];
    XCTAssertNil(invalidKey);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, CSCapUrnErrorInvalidCharacter);

    // Reset error for next test
    error = nil;

    // Wildcard should be accepted in values
    CSCapUrn *validValue = [CSCapUrn fromString:testUrn(@"key=*") error:&error];
    XCTAssertNotNil(validValue);
    XCTAssertNil(error);
    XCTAssertEqualObjects([validValue getTag:@"key"], @"*");
}

- (void)testDuplicateKeyRejection {
    NSError *error = nil;
    // Duplicate keys should be rejected
    CSCapUrn *duplicate = [CSCapUrn fromString:@"cap:in=media:void;key=value1;key=value2;out=\"media:form=map;textable\"" error:&error];
    XCTAssertNil(duplicate);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, CSCapUrnErrorDuplicateKey);
}

- (void)testNumericKeyRestriction {
    NSError *error = nil;

    // Pure numeric keys should be rejected
    CSCapUrn *numericKey = [CSCapUrn fromString:@"cap:in=media:void;123=value;out=\"media:form=map;textable\"" error:&error];
    XCTAssertNil(numericKey);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, CSCapUrnErrorNumericKey);

    // Reset error for next test
    error = nil;

    // Mixed alphanumeric keys should be allowed
    CSCapUrn *mixedKey1 = [CSCapUrn fromString:testUrn(@"key123=value") error:&error];
    XCTAssertNotNil(mixedKey1);
    XCTAssertNil(error);

    error = nil;
    CSCapUrn *mixedKey2 = [CSCapUrn fromString:testUrn(@"123key=value") error:&error];
    XCTAssertNotNil(mixedKey2);
    XCTAssertNil(error);

    error = nil;
    // Pure numeric values should be allowed
    CSCapUrn *numericValue = [CSCapUrn fromString:testUrn(@"key=123") error:&error];
    XCTAssertNotNil(numericValue);
    XCTAssertNil(error);
    XCTAssertEqualObjects([numericValue getTag:@"key"], @"123");
}

#pragma mark - Quoted Value Tests

- (void)testUnquotedValuesLowercased {
    NSError *error = nil;
    // Unquoted values are normalized to lowercase
    // Note: in/out values must be quoted since media URNs contain special chars
    CSCapUrn *cap = [CSCapUrn fromString:@"cap:EXT=PDF;IN=\"media:void\";OP=Generate;OUT=\"media:object\";Target=Thumbnail" error:&error];
    XCTAssertNotNil(cap);
    XCTAssertNil(error);

    // Keys are always lowercase
    XCTAssertEqualObjects([cap getTag:@"op"], @"generate");
    XCTAssertEqualObjects([cap getTag:@"ext"], @"pdf");
    XCTAssertEqualObjects([cap getTag:@"target"], @"thumbnail");

    // Key lookup is case-insensitive
    XCTAssertEqualObjects([cap getTag:@"OP"], @"generate");
    XCTAssertEqualObjects([cap getTag:@"Op"], @"generate");

    // Both URNs parse to same lowercase values
    error = nil;
    CSCapUrn *cap2 = [CSCapUrn fromString:testUrn(@"op=generate;ext=pdf;target=thumbnail") error:&error];
    XCTAssertEqualObjects([cap toString], [cap2 toString]);
    XCTAssertEqualObjects(cap, cap2);
}

- (void)testQuotedValuesPreserveCase {
    NSError *error = nil;
    // Quoted values preserve their case
    CSCapUrn *cap = [CSCapUrn fromString:@"cap:in=media:void;key=\"Value With Spaces\";out=\"media:form=map;textable\"" error:&error];
    XCTAssertNotNil(cap);
    XCTAssertNil(error);
    XCTAssertEqualObjects([cap getTag:@"key"], @"Value With Spaces");

    // Key is still lowercase
    error = nil;
    CSCapUrn *cap2 = [CSCapUrn fromString:@"cap:in=media:void;KEY=\"Value With Spaces\";out=\"media:form=map;textable\"" error:&error];
    XCTAssertNotNil(cap2);
    XCTAssertNil(error);
    XCTAssertEqualObjects([cap2 getTag:@"key"], @"Value With Spaces");

    // Unquoted vs quoted case difference
    error = nil;
    CSCapUrn *unquoted = [CSCapUrn fromString:testUrn(@"key=UPPERCASE") error:&error];
    XCTAssertNotNil(unquoted);
    error = nil;
    CSCapUrn *quoted = [CSCapUrn fromString:@"cap:in=media:void;key=\"UPPERCASE\";out=\"media:form=map;textable\"" error:&error];
    XCTAssertNotNil(quoted);

    XCTAssertEqualObjects([unquoted getTag:@"key"], @"uppercase"); // lowercase
    XCTAssertEqualObjects([quoted getTag:@"key"], @"UPPERCASE"); // preserved
    XCTAssertNotEqualObjects(unquoted, quoted); // NOT equal
}

- (void)testQuotedValueSpecialChars {
    NSError *error = nil;
    // Semicolons in quoted values
    CSCapUrn *cap = [CSCapUrn fromString:@"cap:in=media:void;key=\"value;with;semicolons\";out=\"media:form=map;textable\"" error:&error];
    XCTAssertNotNil(cap);
    XCTAssertNil(error);
    XCTAssertEqualObjects([cap getTag:@"key"], @"value;with;semicolons");

    // Equals in quoted values
    error = nil;
    CSCapUrn *cap2 = [CSCapUrn fromString:@"cap:in=media:void;key=\"value=with=equals\";out=\"media:form=map;textable\"" error:&error];
    XCTAssertNotNil(cap2);
    XCTAssertNil(error);
    XCTAssertEqualObjects([cap2 getTag:@"key"], @"value=with=equals");

    // Spaces in quoted values
    error = nil;
    CSCapUrn *cap3 = [CSCapUrn fromString:@"cap:in=media:void;key=\"hello world\";out=\"media:form=map;textable\"" error:&error];
    XCTAssertNotNil(cap3);
    XCTAssertNil(error);
    XCTAssertEqualObjects([cap3 getTag:@"key"], @"hello world");
}

- (void)testQuotedValueEscapeSequences {
    NSError *error = nil;
    // Escaped quotes
    CSCapUrn *cap = [CSCapUrn fromString:@"cap:in=media:void;key=\"value\\\"quoted\\\"\";out=\"media:form=map;textable\"" error:&error];
    XCTAssertNotNil(cap);
    XCTAssertNil(error);
    XCTAssertEqualObjects([cap getTag:@"key"], @"value\"quoted\"");

    // Escaped backslashes
    error = nil;
    CSCapUrn *cap2 = [CSCapUrn fromString:@"cap:in=media:void;key=\"path\\\\file\";out=\"media:form=map;textable\"" error:&error];
    XCTAssertNotNil(cap2);
    XCTAssertNil(error);
    XCTAssertEqualObjects([cap2 getTag:@"key"], @"path\\file");
}

- (void)testMixedQuotedUnquoted {
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:@"cap:a=\"Quoted\";b=simple;in=media:void;out=\"media:form=map;textable\"" error:&error];
    XCTAssertNotNil(cap);
    XCTAssertNil(error);
    XCTAssertEqualObjects([cap getTag:@"a"], @"Quoted");
    XCTAssertEqualObjects([cap getTag:@"b"], @"simple");
}

- (void)testUnterminatedQuoteError {
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:@"cap:in=media:void;key=\"unterminated;out=\"media:form=map;textable\"" error:&error];
    XCTAssertNil(cap);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, CSCapUrnErrorUnterminatedQuote);
}

- (void)testInvalidEscapeSequenceError {
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:@"cap:in=media:void;key=\"bad\\n\";out=\"media:form=map;textable\"" error:&error];
    XCTAssertNil(cap);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, CSCapUrnErrorInvalidEscapeSequence);
}

- (void)testRoundTripSimple {
    NSError *error = nil;
    NSString *original = testUrn(@"op=generate;ext=pdf");
    CSCapUrn *cap = [CSCapUrn fromString:original error:&error];
    XCTAssertNotNil(cap);
    NSString *serialized = [cap toString];
    CSCapUrn *reparsed = [CSCapUrn fromString:serialized error:&error];
    XCTAssertNotNil(reparsed);
    XCTAssertEqualObjects(cap, reparsed);
}

- (void)testRoundTripQuoted {
    NSError *error = nil;
    NSString *original = @"cap:in=media:void;key=\"Value With Spaces\";out=\"media:form=map;textable\"";
    CSCapUrn *cap = [CSCapUrn fromString:original error:&error];
    XCTAssertNotNil(cap);
    NSString *serialized = [cap toString];
    CSCapUrn *reparsed = [CSCapUrn fromString:serialized error:&error];
    XCTAssertNotNil(reparsed);
    XCTAssertEqualObjects(cap, reparsed);
    XCTAssertEqualObjects([reparsed getTag:@"key"], @"Value With Spaces");
}

- (void)testHasTagCaseSensitive {
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:@"cap:in=media:void;key=\"Value\";out=\"media:form=map;textable\"" error:&error];
    XCTAssertNotNil(cap);

    // Exact case match works
    XCTAssertTrue([cap hasTag:@"key" withValue:@"Value"]);

    // Different case does not match
    XCTAssertFalse([cap hasTag:@"key" withValue:@"value"]);
    XCTAssertFalse([cap hasTag:@"key" withValue:@"VALUE"]);

    // Key lookup is case-insensitive
    XCTAssertTrue([cap hasTag:@"KEY" withValue:@"Value"]);
    XCTAssertTrue([cap hasTag:@"Key" withValue:@"Value"]);

    // hasTag works for direction too
    XCTAssertTrue([cap hasTag:@"in" withValue:@"media:void"]);
    XCTAssertTrue([cap hasTag:@"IN" withValue:@"media:void"]);
    XCTAssertTrue([cap hasTag:@"out" withValue:@"media:form=map;textable"]);
}

- (void)testSemanticEquivalence {
    NSError *error = nil;
    // Unquoted and quoted simple lowercase values are equivalent
    CSCapUrn *unquoted = [CSCapUrn fromString:testUrn(@"key=simple") error:&error];
    XCTAssertNotNil(unquoted);
    CSCapUrn *quoted = [CSCapUrn fromString:@"cap:in=media:void;key=\"simple\";out=\"media:form=map;textable\"" error:&error];
    XCTAssertNotNil(quoted);
    XCTAssertEqualObjects(unquoted, quoted);

    // Both serialize the same way (unquoted)
    XCTAssertEqualObjects([unquoted toString], @"cap:in=media:void;key=simple;out=\"media:form=map;textable\"");
    XCTAssertEqualObjects([quoted toString], @"cap:in=media:void;key=simple;out=\"media:form=map;textable\"");
}

#pragma mark - Matching Semantics Specification Tests

// ============================================================================
// These tests verify the matching semantics with required direction
// All implementations (Rust, Go, JS, ObjC) must pass these identically
// ============================================================================

- (void)testMatchingSemantics_Test1_ExactMatch {
    // Test 1: Exact match
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:testUrn(@"op=generate;ext=pdf") error:&error];
    XCTAssertNotNil(cap);

    CSCapUrn *request = [CSCapUrn fromString:testUrn(@"op=generate;ext=pdf") error:&error];
    XCTAssertNotNil(request);

    XCTAssertTrue([cap matches:request], @"Test 1: Exact match should succeed");
}

- (void)testMatchingSemantics_Test2_CapMissingTag {
    // Test 2: Cap missing tag (implicit wildcard)
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:testUrn(@"op=generate") error:&error];
    XCTAssertNotNil(cap);

    CSCapUrn *request = [CSCapUrn fromString:testUrn(@"op=generate;ext=pdf") error:&error];
    XCTAssertNotNil(request);

    XCTAssertTrue([cap matches:request], @"Test 2: Cap missing tag should match (implicit wildcard)");
}

- (void)testMatchingSemantics_Test3_CapHasExtraTag {
    // Test 3: Cap has extra tag
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:testUrn(@"op=generate;ext=pdf;version=2") error:&error];
    XCTAssertNotNil(cap);

    CSCapUrn *request = [CSCapUrn fromString:testUrn(@"op=generate;ext=pdf") error:&error];
    XCTAssertNotNil(request);

    XCTAssertTrue([cap matches:request], @"Test 3: Cap with extra tag should match");
}

- (void)testMatchingSemantics_Test4_RequestHasWildcard {
    // Test 4: Request has wildcard
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:testUrn(@"op=generate;ext=pdf") error:&error];
    XCTAssertNotNil(cap);

    CSCapUrn *request = [CSCapUrn fromString:testUrn(@"op=generate;ext=*") error:&error];
    XCTAssertNotNil(request);

    XCTAssertTrue([cap matches:request], @"Test 4: Request wildcard should match");
}

- (void)testMatchingSemantics_Test5_CapHasWildcard {
    // Test 5: Cap has wildcard
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:testUrn(@"op=generate;ext=*") error:&error];
    XCTAssertNotNil(cap);

    CSCapUrn *request = [CSCapUrn fromString:testUrn(@"op=generate;ext=pdf") error:&error];
    XCTAssertNotNil(request);

    XCTAssertTrue([cap matches:request], @"Test 5: Cap wildcard should match");
}

- (void)testMatchingSemantics_Test6_ValueMismatch {
    // Test 6: Value mismatch
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:testUrn(@"op=generate;ext=pdf") error:&error];
    XCTAssertNotNil(cap);

    CSCapUrn *request = [CSCapUrn fromString:testUrn(@"op=generate;ext=docx") error:&error];
    XCTAssertNotNil(request);

    XCTAssertFalse([cap matches:request], @"Test 6: Value mismatch should not match");
}

- (void)testMatchingSemantics_Test7_FallbackPattern {
    // Test 7: Fallback pattern (cap missing tag = implicit wildcard)
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:testUrn(@"op=generate_thumbnail") error:&error];
    XCTAssertNotNil(cap);

    CSCapUrn *request = [CSCapUrn fromString:testUrn(@"op=generate_thumbnail;ext=wav") error:&error];
    XCTAssertNotNil(request);

    XCTAssertTrue([cap matches:request], @"Test 7: Fallback pattern should match");
}

- (void)testMatchingSemantics_Test8_WildcardCapMatchesAnything {
    // Test 8: Wildcard cap (in=*, out=*) matches anything
    // (This replaces the old "empty cap" test since empty caps are no longer valid)
    NSError *error = nil;
    CSCapUrn *wildcardCap = [CSCapUrn fromString:@"cap:in=*;out=*" error:&error];
    XCTAssertNotNil(wildcardCap);

    CSCapUrn *request = [CSCapUrn fromString:testUrn(@"op=generate;ext=pdf") error:&error];
    XCTAssertNotNil(request);

    XCTAssertTrue([wildcardCap matches:request], @"Test 8: Wildcard cap should match anything");
}

- (void)testMatchingSemantics_Test9_CrossDimensionIndependence {
    // Test 9: Cross-dimension independence (with same direction)
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:testUrn(@"op=generate") error:&error];
    XCTAssertNotNil(cap);

    CSCapUrn *request = [CSCapUrn fromString:testUrn(@"ext=pdf") error:&error];
    XCTAssertNotNil(request);

    XCTAssertTrue([cap matches:request], @"Test 9: Cross-dimension independence should match");
}

- (void)testMatchingSemantics_Test10_DirectionMismatch {
    // Test 10: Direction mismatch prevents match even with matching tags
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:@"cap:in=media:string;op=generate;out=\"media:form=map;textable\"" error:&error];
    XCTAssertNotNil(cap);

    CSCapUrn *request = [CSCapUrn fromString:@"cap:in=media:bytes;op=generate;out=\"media:form=map;textable\"" error:&error];
    XCTAssertNotNil(request);

    XCTAssertFalse([cap matches:request], @"Test 10: Direction mismatch should prevent match");
}

@end

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

// TEST001: Test that cap URN is created with tags parsed correctly and direction specs accessible
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

// TEST011: Test that serialization uses smart quoting (no quotes for simple lowercase, quotes for special chars/uppercase)
- (void)testCanonicalStringFormat {
    NSError *error;
    CSCapUrn *capUrn = [CSCapUrn fromString:testUrn(@"op=generate;target=thumbnail;ext=pdf") error:&error];

    XCTAssertNotNil(capUrn);
    XCTAssertNil(error);

    // Should be sorted alphabetically: ext, in, op, out, target
    // Note: out value contains ; so it must be quoted in the canonical form
    XCTAssertEqualObjects([capUrn toString], @"cap:ext=pdf;in=media:void;op=generate;out=\"media:form=map;textable\";target=thumbnail");
}

// TEST015: Test that cap: prefix is required and case-insensitive
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

// TEST016: Test that trailing semicolon is equivalent (same hash, same string, matches)
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
    XCTAssertTrue([cap1 accepts:cap2]);
    XCTAssertTrue([cap2 accepts:cap1]);
}

// TEST001 variant: Test empty URN fails
- (void)testInvalidCapUrn {
    NSError *error;
    CSCapUrn *capUrn = [CSCapUrn fromString:@"" error:&error];

    XCTAssertNil(capUrn);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, CSCapUrnErrorInvalidFormat);
}

// TEST031: Test wildcard rejected in keys but accepted in values (variant: solo tags as wildcards)
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
    capUrn = [CSCapUrn fromString:@"cap:in=media:void;out=\"media:form=map;textable\";flag" error:&error];
    XCTAssertNotNil(capUrn);
    XCTAssertNil(error);
    XCTAssertEqualObjects([capUrn getTag:@"flag"], @"*");
}

// TEST003: Invalid format/character test
- (void)testInvalidCharacters {
    NSError *error;
    CSCapUrn *capUrn = [CSCapUrn fromString:@"cap:in=media:void;type@invalid=value;out=\"media:form=map;textable\"" error:&error];

    XCTAssertNil(capUrn);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, CSCapUrnErrorInvalidCharacter);
}

#pragma mark - Required Direction Tests

// TEST002: Test that missing 'in' or 'out' defaults to media: wildcard
- (void)testMissingInSpecDefaultsToWildcard {
    NSError *error = nil;
    // Missing 'in' defaults to media:
    CSCapUrn *capUrn = [CSCapUrn fromString:@"cap:out=\"media:form=map;textable\";op=generate" error:&error];
    XCTAssertNotNil(capUrn, @"Missing in should default to media:");
    XCTAssertNil(error);
    XCTAssertEqualObjects([capUrn getInSpec], @"media:");
    XCTAssertEqualObjects([capUrn getOutSpec], @"media:form=map;textable");
}

// TEST002: Missing 'out' defaults to media:
- (void)testMissingOutSpecDefaultsToWildcard {
    NSError *error = nil;
    // Missing 'out' defaults to media:
    CSCapUrn *capUrn = [CSCapUrn fromString:@"cap:in=media:void;op=generate" error:&error];
    XCTAssertNotNil(capUrn, @"Missing out should default to media:");
    XCTAssertNil(error);
    XCTAssertEqualObjects([capUrn getInSpec], @"media:void");
    XCTAssertEqualObjects([capUrn getOutSpec], @"media:");
}

// TEST028: Test empty cap URN defaults to media: wildcard
- (void)testEmptyCapUrnDefaultsToWildcard {
    NSError *error = nil;
    // Empty cap URN defaults to media: for both in and out
    CSCapUrn *empty = [CSCapUrn fromString:@"cap:" error:&error];
    XCTAssertNotNil(empty, @"Empty cap should default to media: wildcard");
    XCTAssertNil(error);
    XCTAssertEqualObjects([empty getInSpec], @"media:");
    XCTAssertEqualObjects([empty getOutSpec], @"media:");

    // cap:op=raw also defaults - has tags but missing in/out defaults to media:
    error = nil;
    CSCapUrn *missingInOut = [CSCapUrn fromString:@"cap:op=raw" error:&error];
    XCTAssertNotNil(missingInOut, @"cap:op=raw should default in/out to media:");
    XCTAssertNil(error);
    XCTAssertEqualObjects([missingInOut getInSpec], @"media:");
    XCTAssertEqualObjects([missingInOut getOutSpec], @"media:");
    XCTAssertEqualObjects([missingInOut getTag:@"op"], @"raw");
}

// TEST029: Test minimal valid cap URN has just in and out, empty tags
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

// TEST003: Test that direction specs must match exactly, different in/out types don't match, wildcard matches any
- (void)testDirectionMismatchNoMatch {
    NSError *error = nil;
    // Different inSpec should not match
    CSCapUrn *cap1 = [CSCapUrn fromString:@"cap:in=media:string;op=test;out=\"media:form=map;textable\"" error:&error];
    XCTAssertNotNil(cap1);
    CSCapUrn *cap2 = [CSCapUrn fromString:@"cap:in=media:bytes;op=test;out=\"media:form=map;textable\"" error:&error];
    XCTAssertNotNil(cap2);
    XCTAssertFalse([cap1 accepts:cap2]);

    // Different outSpec should not match
    CSCapUrn *cap3 = [CSCapUrn fromString:@"cap:in=media:void;op=test;out=\"media:form=map;textable\"" error:&error];
    XCTAssertNotNil(cap3);
    CSCapUrn *cap4 = [CSCapUrn fromString:@"cap:in=media:void;op=test;out=media:binary" error:&error];
    XCTAssertNotNil(cap4);
    XCTAssertFalse([cap3 accepts:cap4]);
}

// TEST003: Direction wildcard matching
- (void)testDirectionWildcardMatches {
    NSError *error = nil;
    // Wildcard inSpec matches any
    CSCapUrn *wildcardIn = [CSCapUrn fromString:@"cap:in=*;op=test;out=\"media:form=map;textable\"" error:&error];
    XCTAssertNotNil(wildcardIn);
    CSCapUrn *specificIn = [CSCapUrn fromString:@"cap:in=media:string;op=test;out=\"media:form=map;textable\"" error:&error];
    XCTAssertNotNil(specificIn);
    XCTAssertTrue([wildcardIn accepts:specificIn]);

    // Wildcard outSpec matches any
    CSCapUrn *wildcardOut = [CSCapUrn fromString:@"cap:in=media:void;op=test;out=*" error:&error];
    XCTAssertNotNil(wildcardOut);
    CSCapUrn *specificOut = [CSCapUrn fromString:@"cap:in=media:void;op=test;out=media:binary" error:&error];
    XCTAssertNotNil(specificOut);
    XCTAssertTrue([wildcardOut accepts:specificOut]);
}

#pragma mark - Tag Matching Tests

// TEST017: Test tag matching: exact match, routing direction, wildcard match, value mismatch
- (void)testTagMatching {
    NSError *error;
    CSCapUrn *cap = [CSCapUrn fromString:testUrn(@"op=generate;ext=pdf;target=thumbnail") error:&error];
    XCTAssertNotNil(cap);

    // Exact match — both directions accept
    CSCapUrn *request1 = [CSCapUrn fromString:testUrn(@"op=generate;ext=pdf;target=thumbnail") error:&error];
    XCTAssertTrue([cap accepts:request1]);
    XCTAssertTrue([request1 accepts:cap]);

    // Routing direction: request(op=generate) accepts cap(op,ext,target) — request only needs op
    CSCapUrn *request2 = [CSCapUrn fromString:testUrn(@"op=generate") error:&error];
    XCTAssertTrue([request2 accepts:cap]);
    // Reverse: cap(op,ext,target) as pattern rejects request missing ext,target
    XCTAssertFalse([cap accepts:request2]);

    // Routing direction: request(ext=*) accepts cap(ext=pdf) — wildcard matches specific
    CSCapUrn *request3 = [CSCapUrn fromString:testUrn(@"ext=*") error:&error];
    XCTAssertTrue([request3 accepts:cap]);

    // Conflicting value — neither direction accepts
    CSCapUrn *request4 = [CSCapUrn fromString:testUrn(@"op=extract") error:&error];
    XCTAssertFalse([cap accepts:request4]);
    XCTAssertFalse([request4 accepts:cap]);
}

// TEST019: Missing tag in instance causes rejection — pattern's tags are constraints
- (void)testMissingTagHandling {
    NSError *error;
    CSCapUrn *cap = [CSCapUrn fromString:testUrn(@"op=generate") error:&error];
    CSCapUrn *request1 = [CSCapUrn fromString:testUrn(@"ext=pdf") error:&error];

    // cap(op) as pattern: instance(ext) missing op → reject
    XCTAssertFalse([cap accepts:request1]);
    // request(ext) as pattern: instance(cap) missing ext → reject
    XCTAssertFalse([request1 accepts:cap]);

    // Routing: request(op) accepts cap(op,ext) — instance has op → match
    CSCapUrn *cap2 = [CSCapUrn fromString:testUrn(@"op=generate;ext=pdf") error:&error];
    CSCapUrn *request2 = [CSCapUrn fromString:testUrn(@"op=generate") error:&error];
    XCTAssertTrue([request2 accepts:cap2]);
    // Reverse: cap(op,ext) as pattern rejects request missing ext
    XCTAssertFalse([cap2 accepts:request2]);
}

// TEST020: Test specificity calculation (in/out base, wildcards don't count)
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
    // Direction specs contribute MediaUrn tag count: void(1) + object(2) + op(1) = 4
    XCTAssertEqual([cap2 specificity], 4); // void(1) + object(2) + op=generate(1)
    XCTAssertEqual([cap3 specificity], 1); // only ext=pdf counts (direction wildcards contribute 0)

    XCTAssertTrue([cap2 isMoreSpecificThan:cap1]);
}

// TEST024: Directional accepts — pattern's tags are constraints, instance must satisfy
- (void)testDirectionalAccepts {
    NSError *error;
    CSCapUrn *cap1 = [CSCapUrn fromString:testUrn(@"op=generate;ext=pdf") error:&error];
    CSCapUrn *cap2 = [CSCapUrn fromString:testUrn(@"op=generate;format=*") error:&error];
    CSCapUrn *cap3 = [CSCapUrn fromString:testUrn(@"type=image;op=extract") error:&error];

    // cap1(op,ext) as pattern: cap2 missing ext → reject
    XCTAssertFalse([cap1 accepts:cap2]);
    // cap2(op,format) as pattern: cap1 missing format → reject
    XCTAssertFalse([cap2 accepts:cap1]);
    // op mismatch: neither direction accepts
    XCTAssertFalse([cap1 accepts:cap3]);
    XCTAssertFalse([cap3 accepts:cap1]);

    // Routing: general request(op) accepts specific cap(op,ext) — instance has op
    CSCapUrn *cap4 = [CSCapUrn fromString:testUrn(@"op=generate") error:&error];
    XCTAssertTrue([cap4 accepts:cap1]); // cap4 only requires op, cap1 has it
    // Reverse: specific cap(op,ext) rejects general request missing ext
    XCTAssertFalse([cap1 accepts:cap4]);

    // Different direction specs: neither accepts the other
    CSCapUrn *cap5 = [CSCapUrn fromString:@"cap:in=media:bytes;op=generate;out=\"media:form=map;textable\"" error:&error];
    XCTAssertFalse([cap1 accepts:cap5]);
    XCTAssertFalse([cap5 accepts:cap1]);
}

#pragma mark - Convenience Methods Tests

// TEST039: Test get_tag returns direction specs (in/out) with case-insensitive lookup
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

// TEST036: Test with_tag preserves value case
- (void)testWithTag {
    NSError *error;
    CSCapUrn *original = [CSCapUrn fromString:testUrn(@"op=generate") error:&error];
    CSCapUrn *modified = [original withTag:@"ext" value:@"pdf"];

    // Direction preserved, new tag added in alphabetical order
    XCTAssertEqualObjects([modified toString], @"cap:ext=pdf;in=media:void;op=generate;out=\"media:form=map;textable\"");

    // Original should be unchanged
    XCTAssertEqualObjects([original toString], @"cap:in=media:void;op=generate;out=\"media:form=map;textable\"");
}

// TEST036: with_tag ignores in/out (use with_in_spec/with_out_spec instead)
- (void)testWithTagIgnoresInOut {
    NSError *error;
    CSCapUrn *original = [CSCapUrn fromString:testUrn(@"op=generate") error:&error];

    // withTag for "in" or "out" should silently return self
    CSCapUrn *sameIn = [original withTag:@"in" value:@"different"];
    XCTAssertEqual(original, sameIn); // Same object

    CSCapUrn *sameOut = [original withTag:@"out" value:@"different"];
    XCTAssertEqual(original, sameOut); // Same object
}

// TEST036: Test with_in_spec sets input direction
- (void)testWithInSpec {
    NSError *error;
    CSCapUrn *original = [CSCapUrn fromString:testUrn(@"op=generate") error:&error];
    CSCapUrn *modified = [original withInSpec:@"media:string"];

    XCTAssertEqualObjects([modified getInSpec], @"media:string");
    XCTAssertEqualObjects([original getInSpec], @"media:void"); // Original unchanged
}

// TEST036: Test with_out_spec sets output direction
- (void)testWithOutSpec {
    NSError *error;
    CSCapUrn *original = [CSCapUrn fromString:testUrn(@"op=generate") error:&error];
    CSCapUrn *modified = [original withOutSpec:@"media:bytes"];

    XCTAssertEqualObjects([modified getOutSpec], @"media:bytes");
    XCTAssertEqualObjects([original getOutSpec], @"media:form=map;textable"); // Original unchanged
}

// TEST036: Test without_tag removes tag
- (void)testWithoutTag {
    NSError *error;
    CSCapUrn *original = [CSCapUrn fromString:testUrn(@"op=generate;ext=pdf") error:&error];
    CSCapUrn *modified = [original withoutTag:@"ext"];

    XCTAssertEqualObjects([modified toString], @"cap:in=media:void;op=generate;out=\"media:form=map;textable\"");

    // Original should be unchanged
    XCTAssertEqualObjects([original toString], @"cap:ext=pdf;in=media:void;op=generate;out=\"media:form=map;textable\"");
}

// TEST036: without_tag ignores in/out
- (void)testWithoutTagIgnoresInOut {
    NSError *error;
    CSCapUrn *original = [CSCapUrn fromString:testUrn(@"op=generate") error:&error];

    // withoutTag for "in" or "out" should silently return self
    CSCapUrn *sameIn = [original withoutTag:@"in"];
    XCTAssertEqual(original, sameIn); // Same object

    CSCapUrn *sameOut = [original withoutTag:@"out"];
    XCTAssertEqual(original, sameOut); // Same object
}

// TEST027: Test with_wildcard_tag sets tag to wildcard, including in/out
- (void)testWildcardTag {
    NSError *error;
    CSCapUrn *cap = [CSCapUrn fromString:testUrn(@"ext=pdf") error:&error];
    CSCapUrn *wildcarded = [cap withWildcardTag:@"ext"];

    XCTAssertEqualObjects([wildcarded getTag:@"ext"], @"*");

    // Test that wildcarded cap can match more requests
    CSCapUrn *request = [CSCapUrn fromString:testUrn(@"ext=jpg") error:&error];
    XCTAssertFalse([cap accepts:request]);
    XCTAssertTrue([wildcarded accepts:request]);
}

// TEST027: with_wildcard_tag for in/out direction
- (void)testWildcardTagDirection {
    NSError *error;
    CSCapUrn *cap = [CSCapUrn fromString:testUrn(@"op=generate") error:&error];

    // withWildcardTag for "in" should use withInSpec - wildcard is "media:" now
    CSCapUrn *wildcardIn = [cap withWildcardTag:@"in"];
    XCTAssertEqualObjects([wildcardIn getInSpec], @"media:");

    // withWildcardTag for "out" should use withOutSpec - wildcard is "media:" now
    CSCapUrn *wildcardOut = [cap withWildcardTag:@"out"];
    XCTAssertEqualObjects([wildcardOut getOutSpec], @"media:");
}

// TEST026: Test merge combines tags from both caps, subset keeps only specified tags
- (void)testSubset {
    NSError *error;
    CSCapUrn *cap = [CSCapUrn fromString:testUrn(@"op=generate;ext=pdf;output=binary;target=thumbnail") error:&error];
    CSCapUrn *subset = [cap subset:@[@"type", @"ext"]];

    // Direction is always preserved, only ext from the list
    XCTAssertEqualObjects([subset toString], @"cap:ext=pdf;in=media:void;out=\"media:form=map;textable\"");
}

// TEST026: Test merge
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

// TEST016: Test equality and hashing
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

// Obj-C specific: NSCoding support
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

// Obj-C specific: NSCopying support
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

// TEST030: Test extended characters (forward slashes, colons) in tag values
- (void)testExtendedCharacterSupport {
    NSError *error = nil;
    // Test forward slashes and colons in tag components
    CSCapUrn *cap = [CSCapUrn fromString:@"cap:in=media:void;out=\"media:form=map;textable\";url=https://example_org/api;path=/some/file" error:&error];
    XCTAssertNotNil(cap);
    XCTAssertNil(error);
    XCTAssertEqualObjects([cap getTag:@"url"], @"https://example_org/api");
    XCTAssertEqualObjects([cap getTag:@"path"], @"/some/file");
}

// TEST031: Test wildcard rejected in keys but accepted in values
- (void)testWildcardRestrictions {
    NSError *error = nil;
    // Wildcard should be rejected in keys
    CSCapUrn *invalidKey = [CSCapUrn fromString:@"cap:in=media:void;out=\"media:form=map;textable\";*=value" error:&error];
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

// TEST032: Test duplicate keys are rejected with DuplicateKey error
- (void)testDuplicateKeyRejection {
    NSError *error = nil;
    // Duplicate keys should be rejected
    CSCapUrn *duplicate = [CSCapUrn fromString:@"cap:in=media:void;key=value1;key=value2;out=\"media:form=map;textable\"" error:&error];
    XCTAssertNil(duplicate);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, CSCapUrnErrorDuplicateKey);
}

// TEST033: Test pure numeric keys rejected, mixed alphanumeric allowed, numeric values allowed
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

// TEST004: Test that unquoted keys and values are normalized to lowercase
- (void)testUnquotedValuesLowercased {
    NSError *error = nil;
    // Unquoted values are normalized to lowercase
    // Note: in/out values must be quoted since media URNs contain special chars
    CSCapUrn *cap = [CSCapUrn fromString:@"cap:EXT=PDF;IN=\"media:void\";OP=Generate;OUT=\"media:form=map;textable\";Target=Thumbnail" error:&error];
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

// TEST005: Test that quoted values preserve case while unquoted are lowercased
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

// TEST006: Test that quoted values can contain special characters (semicolons, equals, spaces)
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

// TEST007: Test that escape sequences in quoted values (\" and \\) are parsed correctly
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

// TEST008: Test that mixed quoted and unquoted values in same URN parse correctly
- (void)testMixedQuotedUnquoted {
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:@"cap:a=\"Quoted\";b=simple;in=media:void;out=\"media:form=map;textable\"" error:&error];
    XCTAssertNotNil(cap);
    XCTAssertNil(error);
    XCTAssertEqualObjects([cap getTag:@"a"], @"Quoted");
    XCTAssertEqualObjects([cap getTag:@"b"], @"simple");
}

// TEST009: Test that unterminated quote produces UnterminatedQuote error
- (void)testUnterminatedQuoteError {
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:@"cap:in=media:void;key=\"unterminated;out=\"media:form=map;textable\"" error:&error];
    XCTAssertNil(cap);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, CSCapUrnErrorUnterminatedQuote);
}

// TEST010: Test that invalid escape sequences (like \n, \x) produce InvalidEscapeSequence error
- (void)testInvalidEscapeSequenceError {
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:@"cap:in=media:void;key=\"bad\\n\";out=\"media:form=map;textable\"" error:&error];
    XCTAssertNil(cap);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, CSCapUrnErrorInvalidEscapeSequence);
}

// TEST012: Test that simple cap URN round-trips (parse -> serialize -> parse equals original)
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

// TEST013: Test that quoted values round-trip preserving case and spaces
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

// TEST035: Test has_tag is case-sensitive for values, case-insensitive for keys, works for in/out
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

// TEST038: Test semantic equivalence of unquoted and quoted simple lowercase values
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

// TEST040: Matching semantics - exact match succeeds
- (void)testMatchingSemantics_Test1_ExactMatch {
    // Test 1: Exact match
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:testUrn(@"op=generate;ext=pdf") error:&error];
    XCTAssertNotNil(cap);

    CSCapUrn *request = [CSCapUrn fromString:testUrn(@"op=generate;ext=pdf") error:&error];
    XCTAssertNotNil(request);

    XCTAssertTrue([cap accepts:request], @"Test 1: Exact match should succeed");
}

// TEST041: Matching semantics - cap missing tag matches (implicit wildcard)
- (void)testMatchingSemantics_Test2_CapMissingTag {
    // Test 2: Cap missing tag (implicit wildcard)
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:testUrn(@"op=generate") error:&error];
    XCTAssertNotNil(cap);

    CSCapUrn *request = [CSCapUrn fromString:testUrn(@"op=generate;ext=pdf") error:&error];
    XCTAssertNotNil(request);

    XCTAssertTrue([cap accepts:request], @"Test 2: Cap missing tag should match (implicit wildcard)");
}

// TEST042: Pattern rejects instance missing required tags
- (void)testMatchingSemantics_Test3_CapHasExtraTag {
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:testUrn(@"op=generate;ext=pdf;version=2") error:&error];
    CSCapUrn *request = [CSCapUrn fromString:testUrn(@"op=generate;ext=pdf") error:&error];
    // cap(op,ext,version) as pattern rejects request missing version
    XCTAssertFalse([cap accepts:request], @"Pattern rejects instance missing required tag");
    // Routing: request(op,ext) accepts cap(op,ext,version) — instance has all request needs
    XCTAssertTrue([request accepts:cap], @"Request pattern satisfied by more-specific cap");
}

// TEST043: Matching semantics - request wildcard matches specific cap value
- (void)testMatchingSemantics_Test4_RequestHasWildcard {
    // Test 4: Request has wildcard
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:testUrn(@"op=generate;ext=pdf") error:&error];
    XCTAssertNotNil(cap);

    CSCapUrn *request = [CSCapUrn fromString:testUrn(@"op=generate;ext=*") error:&error];
    XCTAssertNotNil(request);

    XCTAssertTrue([cap accepts:request], @"Test 4: Request wildcard should match");
}

// TEST044: Matching semantics - cap wildcard matches specific request value
- (void)testMatchingSemantics_Test5_CapHasWildcard {
    // Test 5: Cap has wildcard
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:testUrn(@"op=generate;ext=*") error:&error];
    XCTAssertNotNil(cap);

    CSCapUrn *request = [CSCapUrn fromString:testUrn(@"op=generate;ext=pdf") error:&error];
    XCTAssertNotNil(request);

    XCTAssertTrue([cap accepts:request], @"Test 5: Cap wildcard should match");
}

// TEST045: Matching semantics - value mismatch does not match
- (void)testMatchingSemantics_Test6_ValueMismatch {
    // Test 6: Value mismatch
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:testUrn(@"op=generate;ext=pdf") error:&error];
    XCTAssertNotNil(cap);

    CSCapUrn *request = [CSCapUrn fromString:testUrn(@"op=generate;ext=docx") error:&error];
    XCTAssertNotNil(request);

    XCTAssertFalse([cap accepts:request], @"Test 6: Value mismatch should not match");
}

// TEST046: Matching semantics - fallback pattern (cap missing tag = implicit wildcard)
- (void)testMatchingSemantics_Test7_FallbackPattern {
    // Test 7: Fallback pattern (cap missing tag = implicit wildcard)
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:testUrn(@"op=generate_thumbnail") error:&error];
    XCTAssertNotNil(cap);

    CSCapUrn *request = [CSCapUrn fromString:testUrn(@"op=generate_thumbnail;ext=wav") error:&error];
    XCTAssertNotNil(request);

    XCTAssertTrue([cap accepts:request], @"Test 7: Fallback pattern should match");
}

// TEST048: Matching semantics - wildcard direction matches anything
- (void)testMatchingSemantics_Test8_WildcardCapMatchesAnything {
    // Test 8: Wildcard cap (in=*, out=*) matches anything
    // (This replaces the old "empty cap" test since empty caps are no longer valid)
    NSError *error = nil;
    CSCapUrn *wildcardCap = [CSCapUrn fromString:@"cap:in=*;out=*" error:&error];
    XCTAssertNotNil(wildcardCap);

    CSCapUrn *request = [CSCapUrn fromString:testUrn(@"op=generate;ext=pdf") error:&error];
    XCTAssertNotNil(request);

    XCTAssertTrue([wildcardCap accepts:request], @"Test 8: Wildcard cap should match anything");
}

// TEST049: Non-overlapping tags — neither direction accepts
- (void)testMatchingSemantics_Test9_CrossDimensionIndependence {
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:testUrn(@"op=generate") error:&error];
    CSCapUrn *request = [CSCapUrn fromString:testUrn(@"ext=pdf") error:&error];
    // cap(op) rejects request missing op; request(ext) rejects cap missing ext
    XCTAssertFalse([cap accepts:request], @"Pattern rejects instance missing required tag");
    XCTAssertFalse([request accepts:cap], @"Reverse also rejects — non-overlapping tags");
}

// TEST050: Matching semantics - direction mismatch prevents matching
- (void)testMatchingSemantics_Test10_DirectionMismatch {
    // Test 10: Direction mismatch prevents match even with matching tags
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:@"cap:in=media:string;op=generate;out=\"media:form=map;textable\"" error:&error];
    XCTAssertNotNil(cap);

    CSCapUrn *request = [CSCapUrn fromString:@"cap:in=media:bytes;op=generate;out=\"media:form=map;textable\"" error:&error];
    XCTAssertNotNil(request);

    XCTAssertFalse([cap accepts:request], @"Test 10: Direction mismatch should prevent match");
}

// TEST051: Semantic direction matching - generic provider matches specific request
- (void)testDirectionSemanticMatching {
    NSError *error = nil;

    // A cap accepting media:bytes (generic) should match a request with media:pdf;bytes (specific)
    CSCapUrn *genericCap = [CSCapUrn fromString:@"cap:in=\"media:bytes\";op=generate_thumbnail;out=\"media:image;png;bytes;thumbnail\"" error:&error];
    XCTAssertNotNil(genericCap, @"Failed to parse generic cap: %@", error);
    CSCapUrn *pdfRequest = [CSCapUrn fromString:@"cap:in=\"media:pdf;bytes\";op=generate_thumbnail;out=\"media:image;png;bytes;thumbnail\"" error:&error];
    XCTAssertNotNil(pdfRequest, @"Failed to parse pdf request: %@", error);
    XCTAssertTrue([genericCap accepts:pdfRequest],
        @"Generic bytes provider must match specific pdf;bytes request");

    // Generic cap also matches epub;bytes (any bytes subtype)
    CSCapUrn *epubRequest = [CSCapUrn fromString:@"cap:in=\"media:epub;bytes\";op=generate_thumbnail;out=\"media:image;png;bytes;thumbnail\"" error:&error];
    XCTAssertNotNil(epubRequest, @"Failed to parse epub request: %@", error);
    XCTAssertTrue([genericCap accepts:epubRequest],
        @"Generic bytes provider must match epub;bytes request");

    // Reverse: specific cap does NOT match generic request
    CSCapUrn *pdfCap = [CSCapUrn fromString:@"cap:in=\"media:pdf;bytes\";op=generate_thumbnail;out=\"media:image;png;bytes;thumbnail\"" error:&error];
    XCTAssertNotNil(pdfCap, @"Failed to parse pdf cap: %@", error);
    CSCapUrn *genericRequest = [CSCapUrn fromString:@"cap:in=\"media:bytes\";op=generate_thumbnail;out=\"media:image;png;bytes;thumbnail\"" error:&error];
    XCTAssertNotNil(genericRequest, @"Failed to parse generic request: %@", error);
    XCTAssertFalse([pdfCap accepts:genericRequest],
        @"Specific pdf;bytes cap must NOT match generic bytes request");

    // Incompatible types: pdf cap does NOT match epub request
    XCTAssertFalse([pdfCap accepts:epubRequest],
        @"PDF-specific cap must NOT match epub request (epub lacks pdf marker)");

    // Output direction: cap producing more specific output matches less specific request
    CSCapUrn *specificOutCap = [CSCapUrn fromString:@"cap:in=\"media:bytes\";op=generate_thumbnail;out=\"media:image;png;bytes;thumbnail\"" error:&error];
    XCTAssertNotNil(specificOutCap);
    CSCapUrn *genericOutRequest = [CSCapUrn fromString:@"cap:in=\"media:bytes\";op=generate_thumbnail;out=\"media:image;bytes\"" error:&error];
    XCTAssertNotNil(genericOutRequest);
    XCTAssertTrue([specificOutCap accepts:genericOutRequest],
        @"Cap producing image;png;bytes;thumbnail must satisfy request for image;bytes");

    // Reverse output: generic output cap does NOT match specific output request
    CSCapUrn *genericOutCap = [CSCapUrn fromString:@"cap:in=\"media:bytes\";op=generate_thumbnail;out=\"media:image;bytes\"" error:&error];
    XCTAssertNotNil(genericOutCap);
    CSCapUrn *specificOutRequest = [CSCapUrn fromString:@"cap:in=\"media:bytes\";op=generate_thumbnail;out=\"media:image;png;bytes;thumbnail\"" error:&error];
    XCTAssertNotNil(specificOutRequest);
    XCTAssertFalse([genericOutCap accepts:specificOutRequest],
        @"Cap producing generic image;bytes must NOT satisfy request requiring image;png;bytes;thumbnail");
}

// TEST052: Semantic direction specificity - more media URN tags = higher specificity
- (void)testDirectionSemanticSpecificity {
    NSError *error = nil;

    CSCapUrn *genericCap = [CSCapUrn fromString:@"cap:in=\"media:bytes\";op=generate_thumbnail;out=\"media:image;png;bytes;thumbnail\"" error:&error];
    XCTAssertNotNil(genericCap, @"Failed to parse generic cap: %@", error);
    CSCapUrn *specificCap = [CSCapUrn fromString:@"cap:in=\"media:pdf;bytes\";op=generate_thumbnail;out=\"media:image;png;bytes;thumbnail\"" error:&error];
    XCTAssertNotNil(specificCap, @"Failed to parse specific cap: %@", error);

    // generic: bytes(1) + image;png;bytes;thumbnail(4) + op(1) = 6
    XCTAssertEqual([genericCap specificity], 6,
        @"Generic cap specificity: bytes(1) + image;png;bytes;thumbnail(4) + op(1)");
    // specific: pdf;bytes(2) + image;png;bytes;thumbnail(4) + op(1) = 7
    XCTAssertEqual([specificCap specificity], 7,
        @"Specific cap specificity: pdf;bytes(2) + image;png;bytes;thumbnail(4) + op(1)");

    XCTAssertGreaterThan([specificCap specificity], [genericCap specificity],
        @"pdf;bytes cap must be more specific than bytes cap");
}

// TEST_WILDCARD_001: cap: (empty) defaults to in=media:;out=media:
- (void)testWildcard001EmptyCapDefaultsToMediaWildcard {
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:@"cap:" error:&error];
    XCTAssertNotNil(cap, @"Empty cap should default to media: wildcard");
    XCTAssertNil(error);
    XCTAssertEqualObjects([cap getInSpec], @"media:");
    XCTAssertEqualObjects([cap getOutSpec], @"media:");
    XCTAssertEqual(cap.tags.count, 0);
}

// TEST_WILDCARD_002: cap:in defaults out to media:
- (void)testWildcard002InOnlyDefaultsOutToMedia {
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:@"cap:in" error:&error];
    XCTAssertNotNil(cap, @"in without out should default out to media:");
    XCTAssertEqualObjects([cap getInSpec], @"media:");
    XCTAssertEqualObjects([cap getOutSpec], @"media:");
}

// TEST_WILDCARD_003: cap:out defaults in to media:
- (void)testWildcard003OutOnlyDefaultsInToMedia {
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:@"cap:out" error:&error];
    XCTAssertNotNil(cap, @"out without in should default in to media:");
    XCTAssertEqualObjects([cap getInSpec], @"media:");
    XCTAssertEqualObjects([cap getOutSpec], @"media:");
}

// TEST_WILDCARD_004: cap:in;out both become media:
- (void)testWildcard004InOutNoValuesBecomeMedia {
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:@"cap:in;out" error:&error];
    XCTAssertNotNil(cap, @"in;out should both become media:");
    XCTAssertEqualObjects([cap getInSpec], @"media:");
    XCTAssertEqualObjects([cap getOutSpec], @"media:");
}

// TEST_WILDCARD_005: cap:in=*;out=* becomes media:
- (void)testWildcard005ExplicitAsteriskBecomesMedia {
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:@"cap:in=*;out=*" error:&error];
    XCTAssertNotNil(cap, @"in=*;out=* should become media:");
    XCTAssertEqualObjects([cap getInSpec], @"media:");
    XCTAssertEqualObjects([cap getOutSpec], @"media:");
}

// TEST_WILDCARD_006: cap:in=media:bytes;out=* has specific in, wildcard out
- (void)testWildcard006SpecificInWildcardOut {
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:@"cap:in=media:bytes;out=*" error:&error];
    XCTAssertNotNil(cap);
    XCTAssertEqualObjects([cap getInSpec], @"media:bytes");
    XCTAssertEqualObjects([cap getOutSpec], @"media:");
}

// TEST_WILDCARD_007: cap:in=*;out=media:text has wildcard in, specific out
- (void)testWildcard007WildcardInSpecificOut {
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:@"cap:in=*;out=media:text" error:&error];
    XCTAssertNotNil(cap);
    XCTAssertEqualObjects([cap getInSpec], @"media:");
    XCTAssertEqualObjects([cap getOutSpec], @"media:text");
}

// TEST_WILDCARD_008: cap:in=foo fails (invalid media URN)
- (void)testWildcard008InvalidInSpecFails {
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:@"cap:in=foo;out=media:" error:&error];
    XCTAssertNil(cap, @"Invalid in spec should fail");
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, CSCapUrnErrorInvalidInSpec);
}

// TEST_WILDCARD_009: cap:in=media:bytes;out=bar fails (invalid media URN)
- (void)testWildcard009InvalidOutSpecFails {
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:@"cap:in=media:bytes;out=bar" error:&error];
    XCTAssertNil(cap, @"Invalid out spec should fail");
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, CSCapUrnErrorInvalidOutSpec);
}

// TEST_WILDCARD_010: Wildcard in/out match specific caps
- (void)testWildcard010WildcardAcceptsSpecific {
    NSError *error = nil;
    CSCapUrn *wildcard = [CSCapUrn fromString:@"cap:" error:&error];
    CSCapUrn *specific = [CSCapUrn fromString:@"cap:in=media:bytes;out=media:text" error:&error];
    
    XCTAssertTrue([wildcard accepts:specific], @"Wildcard should accept specific cap");
    XCTAssertTrue([specific conformsTo:wildcard], @"Specific should conform to wildcard");
}

// TEST_WILDCARD_011: Specificity - wildcard has 0, specific has tag count
- (void)testWildcard011SpecificityScoring {
    NSError *error = nil;
    CSCapUrn *wildcard = [CSCapUrn fromString:@"cap:" error:&error];
    CSCapUrn *specific = [CSCapUrn fromString:@"cap:in=media:bytes;out=media:text" error:&error];
    
    XCTAssertEqual([wildcard specificity], 0, @"Wildcard should have 0 specificity");
    XCTAssertGreaterThan([specific specificity], 0, @"Specific cap should have non-zero specificity");
}

// TEST_WILDCARD_012: cap:in;out;op=test preserves other tags
- (void)testWildcard012PreserveOtherTags {
    NSError *error = nil;
    CSCapUrn *cap = [CSCapUrn fromString:@"cap:in;out;op=test" error:&error];
    XCTAssertNotNil(cap);
    XCTAssertEqualObjects([cap getInSpec], @"media:");
    XCTAssertEqualObjects([cap getOutSpec], @"media:");
    XCTAssertEqualObjects([cap getTag:@"op"], @"test");
}


@end

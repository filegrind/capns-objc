//
//  CSCapCardBuilderTests.m
//  Tests for CSCapCardBuilder tag-based system
//

#import <XCTest/XCTest.h>
#import "CapDef.h"

@interface CSCapCardBuilderTests : XCTestCase
@end

@implementation CSCapCardBuilderTests

- (void)testBuilderBasicConstruction {
    NSError *error;
    CSCapCardBuilder *builder = [CSCapCardBuilder builder];
    [builder type:@"data_processing"];
    [builder action:@"transform"];
    [builder format:@"json"];
    CSCapCard *capCard = [builder build:&error];
    
    XCTAssertNotNil(capCard);
    XCTAssertNil(error);
    XCTAssertEqualObjects([capCard toString], @"action=transform;format=json;type=data_processing");
}

- (void)testBuilderFluentAPI {
    NSError *error;
    CSCapCardBuilder *builder = [CSCapCardBuilder builder];
    [builder type:@"document"];
    [builder action:@"generate"];
    [builder target:@"thumbnail"];
    [builder format:@"pdf"];
    [builder binaryOutput];
    CSCapCard *cap = [builder build:&error];
    
    XCTAssertNotNil(cap);
    XCTAssertNil(error);
    
    XCTAssertEqualObjects([cap capType], @"document");
    XCTAssertEqualObjects([cap action], @"generate");
    XCTAssertEqualObjects([cap target], @"thumbnail");
    XCTAssertEqualObjects([cap format], @"pdf");
    XCTAssertEqualObjects([cap output], @"binary");
    XCTAssertTrue([cap isBinary]);
}

- (void)testBuilderJSONOutput {
    NSError *error;
    CSCapCardBuilder *builder = [CSCapCardBuilder builder];
    [builder type:@"api"];
    [builder action:@"process"];
    [builder target:@"data"];
    [builder jsonOutput];
    CSCapCard *cap = [builder build:&error];
    
    XCTAssertNotNil(cap);
    XCTAssertNil(error);
    
    XCTAssertEqualObjects([cap output], @"json");
    XCTAssertFalse([cap isBinary]);
}

- (void)testBuilderCustomTags {
    NSError *error;
    CSCapCardBuilder *builder = [CSCapCardBuilder builder];
    [builder tag:@"engine" value:@"v2"];
    [builder tag:@"quality" value:@"high"];
    [builder type:@"document"];
    [builder action:@"compress"];
    CSCapCard *cap = [builder build:&error];
    
    XCTAssertNotNil(cap);
    XCTAssertNil(error);
    
    XCTAssertEqualObjects([cap getTag:@"engine"], @"v2");
    XCTAssertEqualObjects([cap getTag:@"quality"], @"high");
    XCTAssertEqualObjects([cap capType], @"document");
    XCTAssertEqualObjects([cap action], @"compress");
}

- (void)testBuilderTagOverrides {
    NSError *error;
    CSCapCardBuilder *builder = [CSCapCardBuilder builder];
    [builder type:@"document"];
    [builder type:@"image"]; // Override previous type
    [builder action:@"convert"];
    [builder format:@"jpg"];
    CSCapCard *cap = [builder build:&error];
    
    XCTAssertNotNil(cap);
    XCTAssertNil(error);
    
    XCTAssertEqualObjects([cap capType], @"image"); // Should be the last set value
    XCTAssertEqualObjects([cap action], @"convert");
    XCTAssertEqualObjects([cap format], @"jpg");
}

- (void)testBuilderEmptyBuild {
    NSError *error;
    CSCapCard *cap = [[CSCapCardBuilder builder] build:&error];
    
    XCTAssertNil(cap);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, CSCapCardErrorInvalidFormat);
    XCTAssertTrue([error.localizedDescription containsString:@"cannot be empty"]);
}

- (void)testBuilderSingleTag {
    NSError *error;
    CSCapCardBuilder *builder = [CSCapCardBuilder builder];
    [builder type:@"utility"];
    CSCapCard *cap = [builder build:&error];
    
    XCTAssertNotNil(cap);
    XCTAssertNil(error);
    
    XCTAssertEqualObjects([cap toString], @"type=utility");
    XCTAssertEqualObjects([cap capType], @"utility");
    XCTAssertEqual([cap specificity], 1);
}

- (void)testBuilderComplex {
    NSError *error;
    CSCapCardBuilder *builder = [CSCapCardBuilder builder];
    [builder type:@"media"];
    [builder action:@"transcode"];
    [builder target:@"video"];
    [builder format:@"mp4"];
    [builder tag:@"codec" value:@"h264"];
    [builder tag:@"quality" value:@"1080p"];
    [builder tag:@"framerate" value:@"30fps"];
    [builder binaryOutput];
    CSCapCard *cap = [builder build:&error];
    
    XCTAssertNotNil(cap);
    XCTAssertNil(error);
    
    NSString *expected = @"action=transcode;codec=h264;format=mp4;framerate=30fps;output=binary;quality=1080p;target=video;type=media";
    XCTAssertEqualObjects([cap toString], expected);
    
    XCTAssertEqualObjects([cap capType], @"media");
    XCTAssertEqualObjects([cap action], @"transcode");
    XCTAssertEqualObjects([cap target], @"video");
    XCTAssertEqualObjects([cap format], @"mp4");
    XCTAssertEqualObjects([cap getTag:@"codec"], @"h264");
    XCTAssertEqualObjects([cap getTag:@"quality"], @"1080p");
    XCTAssertEqualObjects([cap getTag:@"framerate"], @"30fps");
    XCTAssertTrue([cap isBinary]);
    
    XCTAssertEqual([cap specificity], 8); // All 8 tags are non-wildcard
}

- (void)testBuilderWildcards {
    NSError *error;
    CSCapCardBuilder *builder = [CSCapCardBuilder builder];
    [builder type:@"document"];
    [builder action:@"convert"];
    [builder tag:@"format" value:@"*"]; // Wildcard format
    [builder tag:@"quality" value:@"*"]; // Wildcard quality
    CSCapCard *cap = [builder build:&error];
    
    XCTAssertNotNil(cap);
    XCTAssertNil(error);
    
    XCTAssertEqualObjects([cap toString], @"action=convert;format=*;quality=*;type=document");
    XCTAssertEqual([cap specificity], 2); // Only type and action are specific
    
    XCTAssertEqualObjects([cap getTag:@"format"], @"*");
    XCTAssertEqualObjects([cap getTag:@"quality"], @"*");
}

- (void)testBuilderStaticFactory {
    CSCapCardBuilder *builder1 = [CSCapCardBuilder builder];
    CSCapCardBuilder *builder2 = [CSCapCardBuilder builder];
    
    XCTAssertNotEqual(builder1, builder2); // Should be different instances
    XCTAssertNotNil(builder1);
    XCTAssertNotNil(builder2);
}

- (void)testBuilderMatchingWithBuiltCap {
    NSError *error;
    
    // Create a specific cap
    CSCapCardBuilder *builder1 = [CSCapCardBuilder builder];
    [builder1 type:@"document"];
    [builder1 action:@"generate"];
    [builder1 target:@"thumbnail"];
    [builder1 format:@"pdf"];
    CSCapCard *specificCap = [builder1 build:&error];
    
    // Create a more general request
    CSCapCardBuilder *builder2 = [CSCapCardBuilder builder];
    [builder2 type:@"document"];
    [builder2 action:@"generate"];
    CSCapCard *generalRequest = [builder2 build:&error];
    
    // Create a wildcard request
    CSCapCardBuilder *builder3 = [CSCapCardBuilder builder];
    [builder3 type:@"document"];
    [builder3 action:@"generate"];
    [builder3 target:@"thumbnail"];
    [builder3 tag:@"format" value:@"*"];
    CSCapCard *wildcardRequest = [builder3 build:&error];
    
    XCTAssertNotNil(specificCap);
    XCTAssertNotNil(generalRequest);
    XCTAssertNotNil(wildcardRequest);
    
    // Specific cap should handle general request
    XCTAssertTrue([specificCap matches:generalRequest]);
    
    // Specific cap should handle wildcard request
    XCTAssertTrue([specificCap matches:wildcardRequest]);
    
    // Check specificity
    XCTAssertTrue([specificCap isMoreSpecificThan:generalRequest]);
    XCTAssertEqual([specificCap specificity], 4);
    XCTAssertEqual([generalRequest specificity], 2);
    XCTAssertEqual([wildcardRequest specificity], 3); // type, action, target (format=* doesn't count)
}

@end
//
//  CSCapUrnBuilderTests.m
//  Tests for CSCapUrnBuilder tag-based system
//

#import <XCTest/XCTest.h>
#import "CapNs.h"

@interface CSCapUrnBuilderTests : XCTestCase
@end

@implementation CSCapUrnBuilderTests

- (void)testBuilderBasicConstruction {
    NSError *error;
    CSCapUrnBuilder *builder = [CSCapUrnBuilder builder];
    [builder tag:@"type" value:@"data_processing"];
    [builder tag:@"action" value:@"transform"];
    [builder tag:@"format" value:@"json"];
    CSCapUrn *capUrn = [builder build:&error];
    
    XCTAssertNotNil(capUrn);
    XCTAssertNil(error);
    XCTAssertEqualObjects([capUrn toString], @"cap:action=transform;format=json;type=data_processing");
}

- (void)testBuilderFluentAPI {
    NSError *error;
    CSCapUrnBuilder *builder = [CSCapUrnBuilder builder];
    [builder tag:@"action" value:@"generate"];
    [builder tag:@"target" value:@"thumbnail"];
    [builder tag:@"format" value:@"pdf"];
    [builder tag:@"output" value:@"binary"];
    CSCapUrn *cap = [builder build:&error];
    
    XCTAssertNotNil(cap);
    XCTAssertNil(error);
    
    XCTAssertEqualObjects([cap getTag:@"action"], @"generate");
    XCTAssertEqualObjects([cap getTag:@"target"], @"thumbnail");
    XCTAssertEqualObjects([cap getTag:@"format"], @"pdf");
    XCTAssertEqualObjects([cap getTag:@"output"], @"binary");
    XCTAssertEqualObjects([cap getTag:@"output"], @"binary");
}

- (void)testBuilderJSONOutput {
    NSError *error;
    CSCapUrnBuilder *builder = [CSCapUrnBuilder builder];
    [builder tag:@"type" value:@"api"];
    [builder tag:@"action" value:@"process"];
    [builder tag:@"target" value:@"data"];
    [builder tag:@"output" value:@"json"];
    CSCapUrn *cap = [builder build:&error];
    
    XCTAssertNotNil(cap);
    XCTAssertNil(error);
    
    XCTAssertEqualObjects([cap getTag:@"output"], @"json");
    XCTAssertEqualObjects([cap getTag:@"output"], @"json");
}

- (void)testBuilderCustomTags {
    NSError *error;
    CSCapUrnBuilder *builder = [CSCapUrnBuilder builder];
    [builder tag:@"engine" value:@"v2"];
    [builder tag:@"quality" value:@"high"];
    [builder tag:@"action" value:@"compress"];
    CSCapUrn *cap = [builder build:&error];
    
    XCTAssertNotNil(cap);
    XCTAssertNil(error);
    
    XCTAssertEqualObjects([cap getTag:@"engine"], @"v2");
    XCTAssertEqualObjects([cap getTag:@"quality"], @"high");
    XCTAssertEqualObjects([cap getTag:@"action"], @"compress");
}

- (void)testBuilderTagOverrides {
    NSError *error;
    CSCapUrnBuilder *builder = [CSCapUrnBuilder builder];
    [builder tag:@"action" value:@"convert"];
    [builder tag:@"format" value:@"jpg"];
    CSCapUrn *cap = [builder build:&error];
    
    XCTAssertNotNil(cap);
    XCTAssertNil(error);
    
    XCTAssertEqualObjects([cap getTag:@"action"], @"convert");
    XCTAssertEqualObjects([cap getTag:@"format"], @"jpg");
}

- (void)testBuilderEmptyBuild {
    NSError *error;
    CSCapUrn *cap = [[CSCapUrnBuilder builder] build:&error];
    
    XCTAssertNil(cap);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, CSCapUrnErrorInvalidFormat);
    XCTAssertTrue([error.localizedDescription containsString:@"cannot be empty"]);
}

- (void)testBuilderSingleTag {
    NSError *error;
    CSCapUrnBuilder *builder = [CSCapUrnBuilder builder];
    [builder tag:@"type" value:@"utility"];
    CSCapUrn *cap = [builder build:&error];
    
    XCTAssertNotNil(cap);
    XCTAssertNil(error);
    
    XCTAssertEqualObjects([cap toString], @"cap:type=utility");
    XCTAssertEqualObjects([cap getTag:@"type"], @"utility");
    XCTAssertEqual([cap specificity], 1);
}

- (void)testBuilderComplex {
    NSError *error;
    CSCapUrnBuilder *builder = [CSCapUrnBuilder builder];
    [builder tag:@"type" value:@"media"];
    [builder tag:@"action" value:@"transcode"];
    [builder tag:@"target" value:@"video"];
    [builder tag:@"format" value:@"mp4"];
    [builder tag:@"codec" value:@"h264"];
    [builder tag:@"quality" value:@"1080p"];
    [builder tag:@"framerate" value:@"30fps"];
    [builder tag:@"output" value:@"binary"];
    CSCapUrn *cap = [builder build:&error];
    
    XCTAssertNotNil(cap);
    XCTAssertNil(error);
    
    NSString *expected = @"cap:action=transcode;codec=h264;format=mp4;framerate=30fps;output=binary;quality=1080p;target=video;type=media";
    XCTAssertEqualObjects([cap toString], expected);
    
    XCTAssertEqualObjects([cap getTag:@"type"], @"media");
    XCTAssertEqualObjects([cap getTag:@"action"], @"transcode");
    XCTAssertEqualObjects([cap getTag:@"target"], @"video");
    XCTAssertEqualObjects([cap getTag:@"format"], @"mp4");
    XCTAssertEqualObjects([cap getTag:@"codec"], @"h264");
    XCTAssertEqualObjects([cap getTag:@"quality"], @"1080p");
    XCTAssertEqualObjects([cap getTag:@"framerate"], @"30fps");
    XCTAssertEqualObjects([cap getTag:@"output"], @"binary");
    
    XCTAssertEqual([cap specificity], 8); // All 8 tags are non-wildcard
}

- (void)testBuilderWildcards {
    NSError *error;
    CSCapUrnBuilder *builder = [CSCapUrnBuilder builder];
    [builder tag:@"action" value:@"convert"];
    [builder tag:@"ext" value:@"*"]; // Wildcard format
    [builder tag:@"quality" value:@"*"]; // Wildcard quality
    CSCapUrn *cap = [builder build:&error];
    
    XCTAssertNotNil(cap);
    XCTAssertNil(error);
    
    XCTAssertEqualObjects([cap toString], @"cap:action=convert;ext=*;quality=*");
    XCTAssertEqual([cap specificity], 1); // Only action is specific
    
    XCTAssertEqualObjects([cap getTag:@"ext"], @"*");
    XCTAssertEqualObjects([cap getTag:@"quality"], @"*");
}

- (void)testBuilderStaticFactory {
    CSCapUrnBuilder *builder1 = [CSCapUrnBuilder builder];
    CSCapUrnBuilder *builder2 = [CSCapUrnBuilder builder];
    
    XCTAssertNotEqual(builder1, builder2); // Should be different instances
    XCTAssertNotNil(builder1);
    XCTAssertNotNil(builder2);
}

- (void)testBuilderMatchingWithBuiltCap {
    NSError *error;
    
    // Create a specific cap
    CSCapUrnBuilder *builder1 = [CSCapUrnBuilder builder];
    [builder1 tag:@"action" value:@"generate"];
    [builder1 tag:@"target" value:@"thumbnail"];
    [builder1 tag:@"format" value:@"pdf"];
    CSCapUrn *specificCap = [builder1 build:&error];
    
    // Create a more general request
    CSCapUrnBuilder *builder2 = [CSCapUrnBuilder builder];
    [builder2 tag:@"action" value:@"generate"];
    CSCapUrn *generalRequest = [builder2 build:&error];
    
    // Create a wildcard request
    CSCapUrnBuilder *builder3 = [CSCapUrnBuilder builder];
    [builder3 tag:@"action" value:@"generate"];
    [builder3 tag:@"target" value:@"thumbnail"];
    [builder3 tag:@"ext" value:@"*"];
    CSCapUrn *wildcardRequest = [builder3 build:&error];
    
    XCTAssertNotNil(specificCap);
    XCTAssertNotNil(generalRequest);
    XCTAssertNotNil(wildcardRequest);
    
    // Specific cap should handle general request
    XCTAssertTrue([specificCap matches:generalRequest]);
    
    // Specific cap should handle wildcard request
    XCTAssertTrue([specificCap matches:wildcardRequest]);
    
    // Check specificity
    XCTAssertTrue([specificCap isMoreSpecificThan:generalRequest]);
    XCTAssertEqual([specificCap specificity], 3); // action, target, format
    XCTAssertEqual([generalRequest specificity], 1); // action
    XCTAssertEqual([wildcardRequest specificity], 2); // action, target (ext=* doesn't count)
}

@end
//
//  CSCapabilityKeyBuilderTests.m
//  Tests for CSCapabilityKeyBuilder tag-based system
//

#import <XCTest/XCTest.h>
#import "CapDef.h"

@interface CSCapabilityKeyBuilderTests : XCTestCase
@end

@implementation CSCapabilityKeyBuilderTests

- (void)testBuilderBasicConstruction {
    NSError *error;
    CSCapabilityKeyBuilder *builder = [CSCapabilityKeyBuilder builder];
    [builder type:@"data_processing"];
    [builder action:@"transform"];
    [builder format:@"json"];
    CSCapabilityKey *capabilityKey = [builder build:&error];
    
    XCTAssertNotNil(capabilityKey);
    XCTAssertNil(error);
    XCTAssertEqualObjects([capabilityKey toString], @"action=transform;format=json;type=data_processing");
}

- (void)testBuilderFluentAPI {
    NSError *error;
    CSCapabilityKeyBuilder *builder = [CSCapabilityKeyBuilder builder];
    [builder type:@"document"];
    [builder action:@"generate"];
    [builder target:@"thumbnail"];
    [builder format:@"pdf"];
    [builder binaryOutput];
    CSCapabilityKey *capability = [builder build:&error];
    
    XCTAssertNotNil(capability);
    XCTAssertNil(error);
    
    XCTAssertEqualObjects([capability capabilityType], @"document");
    XCTAssertEqualObjects([capability action], @"generate");
    XCTAssertEqualObjects([capability target], @"thumbnail");
    XCTAssertEqualObjects([capability format], @"pdf");
    XCTAssertEqualObjects([capability output], @"binary");
    XCTAssertTrue([capability isBinary]);
}

- (void)testBuilderJSONOutput {
    NSError *error;
    CSCapabilityKeyBuilder *builder = [CSCapabilityKeyBuilder builder];
    [builder type:@"api"];
    [builder action:@"process"];
    [builder target:@"data"];
    [builder jsonOutput];
    CSCapabilityKey *capability = [builder build:&error];
    
    XCTAssertNotNil(capability);
    XCTAssertNil(error);
    
    XCTAssertEqualObjects([capability output], @"json");
    XCTAssertFalse([capability isBinary]);
}

- (void)testBuilderCustomTags {
    NSError *error;
    CSCapabilityKeyBuilder *builder = [CSCapabilityKeyBuilder builder];
    [builder tag:@"engine" value:@"v2"];
    [builder tag:@"quality" value:@"high"];
    [builder type:@"document"];
    [builder action:@"compress"];
    CSCapabilityKey *capability = [builder build:&error];
    
    XCTAssertNotNil(capability);
    XCTAssertNil(error);
    
    XCTAssertEqualObjects([capability getTag:@"engine"], @"v2");
    XCTAssertEqualObjects([capability getTag:@"quality"], @"high");
    XCTAssertEqualObjects([capability capabilityType], @"document");
    XCTAssertEqualObjects([capability action], @"compress");
}

- (void)testBuilderTagOverrides {
    NSError *error;
    CSCapabilityKeyBuilder *builder = [CSCapabilityKeyBuilder builder];
    [builder type:@"document"];
    [builder type:@"image"]; // Override previous type
    [builder action:@"convert"];
    [builder format:@"jpg"];
    CSCapabilityKey *capability = [builder build:&error];
    
    XCTAssertNotNil(capability);
    XCTAssertNil(error);
    
    XCTAssertEqualObjects([capability capabilityType], @"image"); // Should be the last set value
    XCTAssertEqualObjects([capability action], @"convert");
    XCTAssertEqualObjects([capability format], @"jpg");
}

- (void)testBuilderEmptyBuild {
    NSError *error;
    CSCapabilityKey *capability = [[CSCapabilityKeyBuilder builder] build:&error];
    
    XCTAssertNil(capability);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, CSCapabilityKeyErrorInvalidFormat);
    XCTAssertTrue([error.localizedDescription containsString:@"cannot be empty"]);
}

- (void)testBuilderSingleTag {
    NSError *error;
    CSCapabilityKeyBuilder *builder = [CSCapabilityKeyBuilder builder];
    [builder type:@"utility"];
    CSCapabilityKey *capability = [builder build:&error];
    
    XCTAssertNotNil(capability);
    XCTAssertNil(error);
    
    XCTAssertEqualObjects([capability toString], @"type=utility");
    XCTAssertEqualObjects([capability capabilityType], @"utility");
    XCTAssertEqual([capability specificity], 1);
}

- (void)testBuilderComplex {
    NSError *error;
    CSCapabilityKeyBuilder *builder = [CSCapabilityKeyBuilder builder];
    [builder type:@"media"];
    [builder action:@"transcode"];
    [builder target:@"video"];
    [builder format:@"mp4"];
    [builder tag:@"codec" value:@"h264"];
    [builder tag:@"quality" value:@"1080p"];
    [builder tag:@"framerate" value:@"30fps"];
    [builder binaryOutput];
    CSCapabilityKey *capability = [builder build:&error];
    
    XCTAssertNotNil(capability);
    XCTAssertNil(error);
    
    NSString *expected = @"action=transcode;codec=h264;format=mp4;framerate=30fps;output=binary;quality=1080p;target=video;type=media";
    XCTAssertEqualObjects([capability toString], expected);
    
    XCTAssertEqualObjects([capability capabilityType], @"media");
    XCTAssertEqualObjects([capability action], @"transcode");
    XCTAssertEqualObjects([capability target], @"video");
    XCTAssertEqualObjects([capability format], @"mp4");
    XCTAssertEqualObjects([capability getTag:@"codec"], @"h264");
    XCTAssertEqualObjects([capability getTag:@"quality"], @"1080p");
    XCTAssertEqualObjects([capability getTag:@"framerate"], @"30fps");
    XCTAssertTrue([capability isBinary]);
    
    XCTAssertEqual([capability specificity], 8); // All 8 tags are non-wildcard
}

- (void)testBuilderWildcards {
    NSError *error;
    CSCapabilityKeyBuilder *builder = [CSCapabilityKeyBuilder builder];
    [builder type:@"document"];
    [builder action:@"convert"];
    [builder tag:@"format" value:@"*"]; // Wildcard format
    [builder tag:@"quality" value:@"*"]; // Wildcard quality
    CSCapabilityKey *capability = [builder build:&error];
    
    XCTAssertNotNil(capability);
    XCTAssertNil(error);
    
    XCTAssertEqualObjects([capability toString], @"action=convert;format=*;quality=*;type=document");
    XCTAssertEqual([capability specificity], 2); // Only type and action are specific
    
    XCTAssertEqualObjects([capability getTag:@"format"], @"*");
    XCTAssertEqualObjects([capability getTag:@"quality"], @"*");
}

- (void)testBuilderStaticFactory {
    CSCapabilityKeyBuilder *builder1 = [CSCapabilityKeyBuilder builder];
    CSCapabilityKeyBuilder *builder2 = [CSCapabilityKeyBuilder builder];
    
    XCTAssertNotEqual(builder1, builder2); // Should be different instances
    XCTAssertNotNil(builder1);
    XCTAssertNotNil(builder2);
}

- (void)testBuilderMatchingWithBuiltCapability {
    NSError *error;
    
    // Create a specific capability
    CSCapabilityKeyBuilder *builder1 = [CSCapabilityKeyBuilder builder];
    [builder1 type:@"document"];
    [builder1 action:@"generate"];
    [builder1 target:@"thumbnail"];
    [builder1 format:@"pdf"];
    CSCapabilityKey *specificCap = [builder1 build:&error];
    
    // Create a more general request
    CSCapabilityKeyBuilder *builder2 = [CSCapabilityKeyBuilder builder];
    [builder2 type:@"document"];
    [builder2 action:@"generate"];
    CSCapabilityKey *generalRequest = [builder2 build:&error];
    
    // Create a wildcard request
    CSCapabilityKeyBuilder *builder3 = [CSCapabilityKeyBuilder builder];
    [builder3 type:@"document"];
    [builder3 action:@"generate"];
    [builder3 target:@"thumbnail"];
    [builder3 tag:@"format" value:@"*"];
    CSCapabilityKey *wildcardRequest = [builder3 build:&error];
    
    XCTAssertNotNil(specificCap);
    XCTAssertNotNil(generalRequest);
    XCTAssertNotNil(wildcardRequest);
    
    // Specific capability should handle general request
    XCTAssertTrue([specificCap matches:generalRequest]);
    
    // Specific capability should handle wildcard request
    XCTAssertTrue([specificCap matches:wildcardRequest]);
    
    // Check specificity
    XCTAssertTrue([specificCap isMoreSpecificThan:generalRequest]);
    XCTAssertEqual([specificCap specificity], 4);
    XCTAssertEqual([generalRequest specificity], 2);
    XCTAssertEqual([wildcardRequest specificity], 3); // type, action, target (format=* doesn't count)
}

@end
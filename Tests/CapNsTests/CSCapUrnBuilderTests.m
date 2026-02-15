//
//  CSCapUrnBuilderTests.m
//  Tests for CSCapUrnBuilder with required direction (in/out)
//
//  NOTE: Builder now requires inSpec and outSpec to be set before build().
//

#import <XCTest/XCTest.h>
#import "CapNs.h"

@interface CSCapUrnBuilderTests : XCTestCase
@end

@implementation CSCapUrnBuilderTests

- (void)testBuilderBasicConstruction {
    NSError *error;
    CSCapUrnBuilder *builder = [CSCapUrnBuilder builder];
    [builder inSpec:@"media:void"];
    [builder outSpec:@"media:form=map;textable"];
    [builder tag:@"type" value:@"data_processing"];
    [builder tag:@"op" value:@"transform"];
    [builder tag:@"format" value:@"json"];
    CSCapUrn *capUrn = [builder build:&error];

    XCTAssertNotNil(capUrn);
    XCTAssertNil(error);
    // Alphabetical order: format, in, op, out, type
    XCTAssertEqualObjects([capUrn toString], @"cap:format=json;in=media:void;op=transform;out=\"media:form=map;textable\";type=data_processing");
}

- (void)testBuilderFluentAPI {
    NSError *error;
    CSCapUrnBuilder *builder = [CSCapUrnBuilder builder];
    [[[[[[builder inSpec:@"media:void"] outSpec:@"media:form=map;textable"]
        tag:@"op" value:@"generate"]
       tag:@"target" value:@"thumbnail"]
      tag:@"format" value:@"pdf"]
     tag:@"output" value:@"binary"];
    CSCapUrn *cap = [builder build:&error];

    XCTAssertNotNil(cap);
    XCTAssertNil(error);

    XCTAssertEqualObjects([cap getTag:@"op"], @"generate");
    XCTAssertEqualObjects([cap getTag:@"target"], @"thumbnail");
    XCTAssertEqualObjects([cap getTag:@"format"], @"pdf");
    XCTAssertEqualObjects([cap getTag:@"output"], @"binary");
    XCTAssertEqualObjects([cap getInSpec], @"media:void");
    XCTAssertEqualObjects([cap getOutSpec], @"media:form=map;textable");
}

- (void)testBuilderDirectionAccess {
    NSError *error;
    CSCapUrnBuilder *builder = [CSCapUrnBuilder builder];
    [builder inSpec:@"media:string"];
    [builder outSpec:@"media:bytes"];
    [builder tag:@"op" value:@"process"];
    CSCapUrn *cap = [builder build:&error];

    XCTAssertNotNil(cap);
    XCTAssertNil(error);

    XCTAssertEqualObjects([cap getInSpec], @"media:string");
    XCTAssertEqualObjects([cap getOutSpec], @"media:bytes");
    XCTAssertEqualObjects([cap getTag:@"in"], @"media:string");
    XCTAssertEqualObjects([cap getTag:@"out"], @"media:bytes");
}

- (void)testBuilderCustomTags {
    NSError *error;
    CSCapUrnBuilder *builder = [CSCapUrnBuilder builder];
    [builder inSpec:@"media:void"];
    [builder outSpec:@"media:form=map;textable"];
    [builder tag:@"engine" value:@"v2"];
    [builder tag:@"quality" value:@"high"];
    [builder tag:@"op" value:@"compress"];
    CSCapUrn *cap = [builder build:&error];

    XCTAssertNotNil(cap);
    XCTAssertNil(error);

    XCTAssertEqualObjects([cap getTag:@"engine"], @"v2");
    XCTAssertEqualObjects([cap getTag:@"quality"], @"high");
    XCTAssertEqualObjects([cap getTag:@"op"], @"compress");
}

- (void)testBuilderTagOverrides {
    NSError *error;
    CSCapUrnBuilder *builder = [CSCapUrnBuilder builder];
    [builder inSpec:@"media:void"];
    [builder outSpec:@"media:form=map;textable"];
    [builder tag:@"op" value:@"old"];
    [builder tag:@"op" value:@"convert"]; // Override
    [builder tag:@"format" value:@"jpg"];
    CSCapUrn *cap = [builder build:&error];

    XCTAssertNotNil(cap);
    XCTAssertNil(error);

    XCTAssertEqualObjects([cap getTag:@"op"], @"convert");
    XCTAssertEqualObjects([cap getTag:@"format"], @"jpg");
}

- (void)testBuilderMissingInSpecFails {
    NSError *error;
    CSCapUrnBuilder *builder = [CSCapUrnBuilder builder];
    // Only set outSpec, not inSpec
    [builder outSpec:@"media:form=map;textable"];
    [builder tag:@"op" value:@"test"];
    CSCapUrn *cap = [builder build:&error];

    XCTAssertNil(cap);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, CSCapUrnErrorMissingInSpec);
}

- (void)testBuilderMissingOutSpecFails {
    NSError *error;
    CSCapUrnBuilder *builder = [CSCapUrnBuilder builder];
    // Only set inSpec, not outSpec
    [builder inSpec:@"media:void"];
    [builder tag:@"op" value:@"test"];
    CSCapUrn *cap = [builder build:&error];

    XCTAssertNil(cap);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, CSCapUrnErrorMissingOutSpec);
}

- (void)testBuilderEmptyBuildFailsWithMissingInSpec {
    NSError *error;
    CSCapUrn *cap = [[CSCapUrnBuilder builder] build:&error];

    XCTAssertNil(cap);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, CSCapUrnErrorMissingInSpec);
}

- (void)testBuilderTagIgnoresInOut {
    NSError *error;
    CSCapUrnBuilder *builder = [CSCapUrnBuilder builder];
    [builder inSpec:@"media:void"];
    [builder outSpec:@"media:form=map;textable"];
    // Trying to set in/out via tag should be silently ignored
    [builder tag:@"in" value:@"different"];
    [builder tag:@"out" value:@"different"];
    [builder tag:@"op" value:@"test"];
    CSCapUrn *cap = [builder build:&error];

    XCTAssertNotNil(cap);
    XCTAssertNil(error);
    // Direction should be from inSpec/outSpec, not from tag calls
    XCTAssertEqualObjects([cap getInSpec], @"media:void");
    XCTAssertEqualObjects([cap getOutSpec], @"media:form=map;textable");
}

- (void)testBuilderMinimalValid {
    NSError *error;
    CSCapUrnBuilder *builder = [CSCapUrnBuilder builder];
    [builder inSpec:@"media:void"];
    [builder outSpec:@"media:form=map;textable"];
    // No other tags
    CSCapUrn *cap = [builder build:&error];

    XCTAssertNotNil(cap);
    XCTAssertNil(error);
    XCTAssertEqualObjects([cap toString], @"cap:in=media:void;out=\"media:form=map;textable\"");
    XCTAssertEqual(cap.tags.count, 0);
    XCTAssertEqual([cap specificity], 3); // void(1) + object(2)
}

- (void)testBuilderComplex {
    NSError *error;
    CSCapUrnBuilder *builder = [CSCapUrnBuilder builder];
    [builder inSpec:@"media:bytes"];
    [builder outSpec:@"media:bytes"];
    [builder tag:@"type" value:@"media"];
    [builder tag:@"op" value:@"transcode"];
    [builder tag:@"target" value:@"video"];
    [builder tag:@"format" value:@"mp4"];
    [builder tag:@"codec" value:@"h264"];
    [builder tag:@"quality" value:@"1080p"];
    [builder tag:@"framerate" value:@"30fps"];
    [builder tag:@"output" value:@"binary"];
    CSCapUrn *cap = [builder build:&error];

    XCTAssertNotNil(cap);
    XCTAssertNil(error);

    // Alphabetical order: codec, format, framerate, in, op, out, output, quality, target, type
    NSString *expected = @"cap:codec=h264;format=mp4;framerate=30fps;in=media:bytes;op=transcode;out=media:bytes;output=binary;quality=1080p;target=video;type=media";
    XCTAssertEqualObjects([cap toString], expected);

    XCTAssertEqualObjects([cap getTag:@"type"], @"media");
    XCTAssertEqualObjects([cap getTag:@"op"], @"transcode");
    XCTAssertEqualObjects([cap getTag:@"target"], @"video");
    XCTAssertEqualObjects([cap getTag:@"format"], @"mp4");
    XCTAssertEqualObjects([cap getTag:@"codec"], @"h264");
    XCTAssertEqualObjects([cap getTag:@"quality"], @"1080p");
    XCTAssertEqualObjects([cap getTag:@"framerate"], @"30fps");
    XCTAssertEqualObjects([cap getTag:@"output"], @"binary");

    XCTAssertEqual([cap specificity], 10); // in + out + 8 tags
}

- (void)testBuilderWildcards {
    NSError *error;
    CSCapUrnBuilder *builder = [CSCapUrnBuilder builder];
    [builder inSpec:@"*"]; // Wildcard in
    [builder outSpec:@"*"]; // Wildcard out
    [builder tag:@"op" value:@"convert"];
    [builder tag:@"ext" value:@"*"]; // Wildcard format
    [builder tag:@"quality" value:@"*"]; // Wildcard quality
    CSCapUrn *cap = [builder build:&error];

    XCTAssertNotNil(cap);
    XCTAssertNil(error);

    // Wildcards: in/out are "media:" now (not "*")
    // Alphabetical order: ext, in, op, out, quality
    XCTAssertEqualObjects([cap toString], @"cap:ext;in=media:;op=convert;out=media:;quality");
    XCTAssertEqual([cap specificity], 1); // Only op is specific (media: wildcard contributes 0)

    XCTAssertEqualObjects([cap getTag:@"ext"], @"*");
    XCTAssertEqualObjects([cap getTag:@"quality"], @"*");
    XCTAssertEqualObjects([cap getInSpec], @"media:");  // Wildcard is media: now
    XCTAssertEqualObjects([cap getOutSpec], @"media:");  // Wildcard is media: now
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

    // Create a specific cap (handler/instance)
    CSCapUrnBuilder *builder1 = [CSCapUrnBuilder builder];
    [builder1 inSpec:@"media:void"];
    [builder1 outSpec:@"media:form=map;textable"];
    [builder1 tag:@"op" value:@"generate"];
    [builder1 tag:@"target" value:@"thumbnail"];
    [builder1 tag:@"format" value:@"pdf"];
    [builder1 tag:@"ext" value:@"pdf"];  // Instance must have all tags that wildcard pattern requires
    CSCapUrn *specificCap = [builder1 build:&error];

    // Create a more general request (same direction)
    CSCapUrnBuilder *builder2 = [CSCapUrnBuilder builder];
    [builder2 inSpec:@"media:void"];
    [builder2 outSpec:@"media:form=map;textable"];
    [builder2 tag:@"op" value:@"generate"];
    CSCapUrn *generalRequest = [builder2 build:&error];

    // Create a wildcard request (same direction)
    CSCapUrnBuilder *builder3 = [CSCapUrnBuilder builder];
    [builder3 inSpec:@"media:void"];
    [builder3 outSpec:@"media:form=map;textable"];
    [builder3 tag:@"op" value:@"generate"];
    [builder3 tag:@"target" value:@"thumbnail"];
    [builder3 tag:@"ext" value:@"*"];
    CSCapUrn *wildcardRequest = [builder3 build:&error];

    XCTAssertNotNil(specificCap);
    XCTAssertNotNil(generalRequest);
    XCTAssertNotNil(wildcardRequest);

    // General request (pattern) should accept specific cap (instance)
    XCTAssertTrue([generalRequest accepts:specificCap]);

    // Wildcard request (pattern) should accept specific cap (instance)
    XCTAssertTrue([wildcardRequest accepts:specificCap]);

    // Check specificity (includes in + out now)
    XCTAssertTrue([specificCap isMoreSpecificThan:generalRequest]);
    XCTAssertEqual([specificCap specificity], 7); // void(1) + object(2) + op + target + format + ext
    XCTAssertEqual([generalRequest specificity], 4); // void(1) + object(2) + op
    XCTAssertEqual([wildcardRequest specificity], 5); // void(1) + object(2) + op + target (ext=* doesn't count)
}

- (void)testBuilderDirectionMismatchNoMatch {
    NSError *error;

    // Create caps with different directions
    CSCapUrnBuilder *builder1 = [CSCapUrnBuilder builder];
    [builder1 inSpec:@"media:string"];
    [builder1 outSpec:@"media:form=map;textable"];
    [builder1 tag:@"op" value:@"process"];
    CSCapUrn *cap1 = [builder1 build:&error];

    CSCapUrnBuilder *builder2 = [CSCapUrnBuilder builder];
    [builder2 inSpec:@"media:bytes"]; // Different inSpec
    [builder2 outSpec:@"media:form=map;textable"];
    [builder2 tag:@"op" value:@"process"];
    CSCapUrn *cap2 = [builder2 build:&error];

    XCTAssertNotNil(cap1);
    XCTAssertNotNil(cap2);

    // They should NOT match due to different inSpec
    XCTAssertFalse([cap1 accepts:cap2]);
    XCTAssertFalse([cap2 accepts:cap1]);
}

@end

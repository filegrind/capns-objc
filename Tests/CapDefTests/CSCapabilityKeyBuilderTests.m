//
//  CSCapabilityKeyBuilderTests.m
//  Tests for CSCapabilityKeyBuilder
//

#import <XCTest/XCTest.h>
#import "CapDef.h"

@interface CSCapabilityKeyBuilderTests : XCTestCase
@end

@implementation CSCapabilityKeyBuilderTests

- (void)testBuilderBasicConstruction {
    NSError *error;
    CSCapabilityKeyBuilder *builder = [CSCapabilityKeyBuilder builder];
    [[builder sub:@"data_processing"] sub:@"transform"];
    [builder sub:@"json"];
    CSCapabilityKey *capabilityKey = [builder build:&error];
    
    XCTAssertNotNil(capabilityKey);
    XCTAssertNil(error);
    XCTAssertEqualObjects([capabilityKey toString], @"data_processing:transform:json");
}

- (void)testBuilderFromString {
    NSError *error;
    CSCapabilityKeyBuilder *builder = [CSCapabilityKeyBuilder builderFromString:@"extract:metadata:pdf" error:&error];
    XCTAssertNotNil(builder);
    XCTAssertNil(error);
    
    CSCapabilityKey *capabilityKey = [builder build:&error];
    XCTAssertNotNil(capabilityKey);
    XCTAssertNil(error);
    XCTAssertEqualObjects([capabilityKey toString], @"extract:metadata:pdf");
}

- (void)testBuilderMakeMoreGeneral {
    NSError *error;
    CSCapabilityKeyBuilder *builder = [CSCapabilityKeyBuilder builderFromString:@"data_processing:transform:json" error:&error];
    XCTAssertNotNil(builder);
    
    CSCapabilityKey *capabilityKey = [[builder makeMoreGeneral] build:&error];
    XCTAssertNotNil(capabilityKey);
    XCTAssertNil(error);
    XCTAssertEqualObjects([capabilityKey toString], @"data_processing:transform");
}

- (void)testBuilderMakeWildcard {
    NSError *error;
    CSCapabilityKeyBuilder *builder = [CSCapabilityKeyBuilder builderFromString:@"data_processing:transform:json" error:&error];
    XCTAssertNotNil(builder);
    
    CSCapabilityKey *capabilityKey = [[builder makeWildcard] build:&error];
    XCTAssertNotNil(capabilityKey);
    XCTAssertNil(error);
    XCTAssertEqualObjects([capabilityKey toString], @"data_processing:transform:*");
}

- (void)testBuilderAddWildcard {
    NSError *error;
    CSCapabilityKeyBuilder *builder = [CSCapabilityKeyBuilder builder];
    [[builder sub:@"data_processing"] addWildcard];
    CSCapabilityKey *capabilityKey = [builder build:&error];
    
    XCTAssertNotNil(capabilityKey);
    XCTAssertNil(error);
    XCTAssertEqualObjects([capabilityKey toString], @"data_processing:*");
}

- (void)testBuilderReplaceSegment {
    NSError *error;
    CSCapabilityKeyBuilder *builder = [CSCapabilityKeyBuilder builderFromString:@"extract:metadata:pdf" error:&error];
    XCTAssertNotNil(builder);
    
    CSCapabilityKey *capabilityKey = [[builder replaceSegmentAtIndex:2 withSegment:@"xml"] build:&error];
    XCTAssertNotNil(capabilityKey);
    XCTAssertNil(error);
    XCTAssertEqualObjects([capabilityKey toString], @"extract:metadata:xml");
}

- (void)testBuilderSubs {
    NSError *error;
    CSCapabilityKeyBuilder *builder = [CSCapabilityKeyBuilder builder];
    [[builder subs:@[@"data", @"processing"]] sub:@"json"];
    CSCapabilityKey *capabilityKey = [builder build:&error];
    
    XCTAssertNotNil(capabilityKey);
    XCTAssertNil(error);
    XCTAssertEqualObjects([capabilityKey toString], @"data:processing:json");
}

- (void)testBuilderMakeGeneralToLevel {
    NSError *error;
    CSCapabilityKeyBuilder *builder = [CSCapabilityKeyBuilder builderFromString:@"a:b:c:d:e" error:&error];
    XCTAssertNotNil(builder);
    
    CSCapabilityKey *capabilityKey = [[builder makeGeneralToLevel:2] build:&error];
    XCTAssertNotNil(capabilityKey);
    XCTAssertNil(error);
    XCTAssertEqualObjects([capabilityKey toString], @"a:b");
}

- (void)testBuilderMakeWildcardFromLevel {
    NSError *error;
    CSCapabilityKeyBuilder *builder = [CSCapabilityKeyBuilder builderFromString:@"data:processing:transform:json" error:&error];
    XCTAssertNotNil(builder);
    
    CSCapabilityKey *capabilityKey = [[builder makeWildcardFromLevel:2] build:&error];
    XCTAssertNotNil(capabilityKey);
    XCTAssertNil(error);
    XCTAssertEqualObjects([capabilityKey toString], @"data:processing:*");
}

- (void)testBuilderProperties {
    NSError *error;
    CSCapabilityKeyBuilder *builder = [CSCapabilityKeyBuilder builderFromString:@"data:processing:transform" error:&error];
    XCTAssertNotNil(builder);
    
    XCTAssertEqual([builder count], 3);
    XCTAssertFalse([builder isEmpty]);
    
    NSArray<NSString *> *segments = [builder segments];
    XCTAssertEqual(segments.count, 3);
    XCTAssertEqualObjects(segments[0], @"data");
    XCTAssertEqualObjects(segments[1], @"processing");
    XCTAssertEqualObjects(segments[2], @"transform");
    
    [builder clear];
    XCTAssertEqual([builder count], 0);
    XCTAssertTrue([builder isEmpty]);
}

- (void)testBuilderClone {
    NSError *error;
    CSCapabilityKeyBuilder *original = [CSCapabilityKeyBuilder builderFromString:@"data:processing:transform" error:&error];
    XCTAssertNotNil(original);
    
    CSCapabilityKeyBuilder *clone = [original clone];
    
    // Modify original
    [original sub:@"json"];
    
    // Clone should remain unchanged
    CSCapabilityKey *originalId = [original build:&error];
    XCTAssertNotNil(originalId);
    XCTAssertEqualObjects([originalId toString], @"data:processing:transform:json");
    
    CSCapabilityKey *cloneId = [clone build:&error];
    XCTAssertNotNil(cloneId);
    XCTAssertEqualObjects([cloneId toString], @"data:processing:transform");
}

- (void)testBuilderBuildString {
    NSError *error;
    CSCapabilityKeyBuilder *builder = [[CSCapabilityKeyBuilder builder]
                                      sub:@"extract"];
    [builder sub:@"metadata"];
    [builder addWildcard];
    
    NSString *str = [builder buildString:&error];
    XCTAssertNotNil(str);
    XCTAssertNil(error);
    XCTAssertEqualObjects(str, @"extract:metadata:*");
}

- (void)testBuilderCategories {
    NSError *error;
    
    // Test NSString category
    CSCapabilityKeyBuilder *builder1 = [@"extract:metadata:pdf" cs_intoBuilder:&error];
    XCTAssertNotNil(builder1);
    XCTAssertNil(error);
    
    CSCapabilityKey *capId1 = [builder1 build:&error];
    XCTAssertNotNil(capId1);
    XCTAssertEqualObjects([capId1 toString], @"extract:metadata:pdf");
    
    // Test CSCapabilityKey category
    CSCapabilityKey *capId = [CSCapabilityKey fromString:@"extract:metadata:pdf" error:&error];
    XCTAssertNotNil(capId);
    
    CSCapabilityKeyBuilder *builder2 = [capId cs_intoBuilder];
    XCTAssertNotNil(builder2);
    
    CSCapabilityKey *capId2 = [builder2 build:&error];
    XCTAssertNotNil(capId2);
    XCTAssertEqualObjects([capId2 toString], @"extract:metadata:pdf");
}

- (void)testBuilderEdgeCases {
    NSError *error;
    
    // Test replace segment with invalid index
    CSCapabilityKeyBuilder *builder = [[CSCapabilityKeyBuilder builder] sub:@"test"];
    [builder replaceSegmentAtIndex:5 withSegment:@"invalid"]; // Should not crash
    CSCapabilityKey *capId = [builder build:&error];
    XCTAssertNotNil(capId);
    XCTAssertEqualObjects([capId toString], @"test");
    
    // Test make more general on empty builder
    CSCapabilityKeyBuilder *emptyBuilder = [CSCapabilityKeyBuilder builder];
    [emptyBuilder makeMoreGeneral]; // Should not crash
    XCTAssertTrue([emptyBuilder isEmpty]);
    
    // Test make wildcard on empty builder
    CSCapabilityKeyBuilder *emptyBuilder2 = [CSCapabilityKeyBuilder builder];
    [emptyBuilder2 makeWildcard]; // Should not crash
    XCTAssertTrue([emptyBuilder2 isEmpty]);
}

- (void)testBuilderToString {
    NSError *error;
    CSCapabilityKeyBuilder *builder = [CSCapabilityKeyBuilder builderFromString:@"data:processing:transform" error:&error];
    XCTAssertNotNil(builder);
    
    NSString *toString = [builder toString];
    XCTAssertEqualObjects(toString, @"data:processing:transform");
}

@end
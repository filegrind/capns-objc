//
//  CSCapabilityIdBuilderTests.m
//  Tests for CSCapabilityIdBuilder
//

#import <XCTest/XCTest.h>
#import "CapDef.h"

@interface CSCapabilityIdBuilderTests : XCTestCase
@end

@implementation CSCapabilityIdBuilderTests

- (void)testBuilderBasicConstruction {
    NSError *error;
    CSCapabilityIdBuilder *builder = [CSCapabilityIdBuilder builder];
    [[builder sub:@"data_processing"] sub:@"transform"];
    [builder sub:@"json"];
    CSCapabilityId *capabilityId = [builder build:&error];
    
    XCTAssertNotNil(capabilityId);
    XCTAssertNil(error);
    XCTAssertEqualObjects([capabilityId toString], @"data_processing:transform:json");
}

- (void)testBuilderFromString {
    NSError *error;
    CSCapabilityIdBuilder *builder = [CSCapabilityIdBuilder builderFromString:@"extract:metadata:pdf" error:&error];
    XCTAssertNotNil(builder);
    XCTAssertNil(error);
    
    CSCapabilityId *capabilityId = [builder build:&error];
    XCTAssertNotNil(capabilityId);
    XCTAssertNil(error);
    XCTAssertEqualObjects([capabilityId toString], @"extract:metadata:pdf");
}

- (void)testBuilderMakeMoreGeneral {
    NSError *error;
    CSCapabilityIdBuilder *builder = [CSCapabilityIdBuilder builderFromString:@"data_processing:transform:json" error:&error];
    XCTAssertNotNil(builder);
    
    CSCapabilityId *capabilityId = [[builder makeMoreGeneral] build:&error];
    XCTAssertNotNil(capabilityId);
    XCTAssertNil(error);
    XCTAssertEqualObjects([capabilityId toString], @"data_processing:transform");
}

- (void)testBuilderMakeWildcard {
    NSError *error;
    CSCapabilityIdBuilder *builder = [CSCapabilityIdBuilder builderFromString:@"data_processing:transform:json" error:&error];
    XCTAssertNotNil(builder);
    
    CSCapabilityId *capabilityId = [[builder makeWildcard] build:&error];
    XCTAssertNotNil(capabilityId);
    XCTAssertNil(error);
    XCTAssertEqualObjects([capabilityId toString], @"data_processing:transform:*");
}

- (void)testBuilderAddWildcard {
    NSError *error;
    CSCapabilityIdBuilder *builder = [CSCapabilityIdBuilder builder];
    [[builder sub:@"data_processing"] addWildcard];
    CSCapabilityId *capabilityId = [builder build:&error];
    
    XCTAssertNotNil(capabilityId);
    XCTAssertNil(error);
    XCTAssertEqualObjects([capabilityId toString], @"data_processing:*");
}

- (void)testBuilderReplaceSegment {
    NSError *error;
    CSCapabilityIdBuilder *builder = [CSCapabilityIdBuilder builderFromString:@"extract:metadata:pdf" error:&error];
    XCTAssertNotNil(builder);
    
    CSCapabilityId *capabilityId = [[builder replaceSegmentAtIndex:2 withSegment:@"xml"] build:&error];
    XCTAssertNotNil(capabilityId);
    XCTAssertNil(error);
    XCTAssertEqualObjects([capabilityId toString], @"extract:metadata:xml");
}

- (void)testBuilderSubs {
    NSError *error;
    CSCapabilityIdBuilder *builder = [CSCapabilityIdBuilder builder];
    [[builder subs:@[@"data", @"processing"]] sub:@"json"];
    CSCapabilityId *capabilityId = [builder build:&error];
    
    XCTAssertNotNil(capabilityId);
    XCTAssertNil(error);
    XCTAssertEqualObjects([capabilityId toString], @"data:processing:json");
}

- (void)testBuilderMakeGeneralToLevel {
    NSError *error;
    CSCapabilityIdBuilder *builder = [CSCapabilityIdBuilder builderFromString:@"a:b:c:d:e" error:&error];
    XCTAssertNotNil(builder);
    
    CSCapabilityId *capabilityId = [[builder makeGeneralToLevel:2] build:&error];
    XCTAssertNotNil(capabilityId);
    XCTAssertNil(error);
    XCTAssertEqualObjects([capabilityId toString], @"a:b");
}

- (void)testBuilderMakeWildcardFromLevel {
    NSError *error;
    CSCapabilityIdBuilder *builder = [CSCapabilityIdBuilder builderFromString:@"data:processing:transform:json" error:&error];
    XCTAssertNotNil(builder);
    
    CSCapabilityId *capabilityId = [[builder makeWildcardFromLevel:2] build:&error];
    XCTAssertNotNil(capabilityId);
    XCTAssertNil(error);
    XCTAssertEqualObjects([capabilityId toString], @"data:processing:*");
}

- (void)testBuilderProperties {
    NSError *error;
    CSCapabilityIdBuilder *builder = [CSCapabilityIdBuilder builderFromString:@"data:processing:transform" error:&error];
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
    CSCapabilityIdBuilder *original = [CSCapabilityIdBuilder builderFromString:@"data:processing:transform" error:&error];
    XCTAssertNotNil(original);
    
    CSCapabilityIdBuilder *clone = [original clone];
    
    // Modify original
    [original sub:@"json"];
    
    // Clone should remain unchanged
    CSCapabilityId *originalId = [original build:&error];
    XCTAssertNotNil(originalId);
    XCTAssertEqualObjects([originalId toString], @"data:processing:transform:json");
    
    CSCapabilityId *cloneId = [clone build:&error];
    XCTAssertNotNil(cloneId);
    XCTAssertEqualObjects([cloneId toString], @"data:processing:transform");
}

- (void)testBuilderBuildString {
    NSError *error;
    CSCapabilityIdBuilder *builder = [[CSCapabilityIdBuilder builder]
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
    CSCapabilityIdBuilder *builder1 = [@"extract:metadata:pdf" cs_intoBuilder:&error];
    XCTAssertNotNil(builder1);
    XCTAssertNil(error);
    
    CSCapabilityId *capId1 = [builder1 build:&error];
    XCTAssertNotNil(capId1);
    XCTAssertEqualObjects([capId1 toString], @"extract:metadata:pdf");
    
    // Test CSCapabilityId category
    CSCapabilityId *capId = [CSCapabilityId fromString:@"extract:metadata:pdf" error:&error];
    XCTAssertNotNil(capId);
    
    CSCapabilityIdBuilder *builder2 = [capId cs_intoBuilder];
    XCTAssertNotNil(builder2);
    
    CSCapabilityId *capId2 = [builder2 build:&error];
    XCTAssertNotNil(capId2);
    XCTAssertEqualObjects([capId2 toString], @"extract:metadata:pdf");
}

- (void)testBuilderEdgeCases {
    NSError *error;
    
    // Test replace segment with invalid index
    CSCapabilityIdBuilder *builder = [[CSCapabilityIdBuilder builder] sub:@"test"];
    [builder replaceSegmentAtIndex:5 withSegment:@"invalid"]; // Should not crash
    CSCapabilityId *capId = [builder build:&error];
    XCTAssertNotNil(capId);
    XCTAssertEqualObjects([capId toString], @"test");
    
    // Test make more general on empty builder
    CSCapabilityIdBuilder *emptyBuilder = [CSCapabilityIdBuilder builder];
    [emptyBuilder makeMoreGeneral]; // Should not crash
    XCTAssertTrue([emptyBuilder isEmpty]);
    
    // Test make wildcard on empty builder
    CSCapabilityIdBuilder *emptyBuilder2 = [CSCapabilityIdBuilder builder];
    [emptyBuilder2 makeWildcard]; // Should not crash
    XCTAssertTrue([emptyBuilder2 isEmpty]);
}

- (void)testBuilderToString {
    NSError *error;
    CSCapabilityIdBuilder *builder = [CSCapabilityIdBuilder builderFromString:@"data:processing:transform" error:&error];
    XCTAssertNotNil(builder);
    
    NSString *toString = [builder toString];
    XCTAssertEqualObjects(toString, @"data:processing:transform");
}

@end
//
//  CSCapabilityIdTests.m
//  Tests for CSCapabilityId
//

#import <XCTest/XCTest.h>
#import "CapabilitySDK.h"

@interface CSCapabilityIdTests : XCTestCase
@end

@implementation CSCapabilityIdTests

- (void)testCapabilityIdCreation {
    NSError *error;
    CSCapabilityId *capId = [CSCapabilityId fromString:@"data_processing:transform:json" error:&error];
    
    XCTAssertNotNil(capId);
    XCTAssertNil(error);
    XCTAssertEqualObjects([capId toString], @"data_processing:transform:json");
    XCTAssertEqual(capId.segments.count, 3);
    XCTAssertEqualObjects(capId.segments[0], @"data_processing");
    XCTAssertEqualObjects(capId.segments[1], @"transform");
    XCTAssertEqualObjects(capId.segments[2], @"json");
}

- (void)testInvalidCapabilityId {
    NSError *error;
    CSCapabilityId *capId = [CSCapabilityId fromString:@"" error:&error];
    
    XCTAssertNil(capId);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, CSCapabilityIdErrorInvalidFormat);
}

- (void)testCapabilityMatching {
    NSError *error;
    CSCapabilityId *capability = [CSCapabilityId fromString:@"data_processing:transform:json" error:&error];
    CSCapabilityId *request1 = [CSCapabilityId fromString:@"data_processing:transform:json" error:&error];
    CSCapabilityId *request2 = [CSCapabilityId fromString:@"data_processing:transform" error:&error];
    CSCapabilityId *request3 = [CSCapabilityId fromString:@"data_processing" error:&error];
    CSCapabilityId *request4 = [CSCapabilityId fromString:@"compute:math" error:&error];
    
    XCTAssertTrue([capability canHandle:request1]);
    XCTAssertTrue([capability canHandle:request2]);
    XCTAssertTrue([capability canHandle:request3]);
    XCTAssertFalse([capability canHandle:request4]);
}

- (void)testWildcardMatching {
    NSError *error;
    CSCapabilityId *wildcard = [CSCapabilityId fromString:@"data_processing:*" error:&error];
    CSCapabilityId *request1 = [CSCapabilityId fromString:@"data_processing:transform:json" error:&error];
    CSCapabilityId *request2 = [CSCapabilityId fromString:@"data_processing:validate:xml" error:&error];
    CSCapabilityId *request3 = [CSCapabilityId fromString:@"compute:math" error:&error];
    
    XCTAssertTrue([wildcard canHandle:request1]);
    XCTAssertTrue([wildcard canHandle:request2]);
    XCTAssertFalse([wildcard canHandle:request3]);
}

- (void)testSpecificity {
    NSError *error;
    CSCapabilityId *specific = [CSCapabilityId fromString:@"data_processing:transform:json" error:&error];
    CSCapabilityId *general = [CSCapabilityId fromString:@"data_processing:*" error:&error];
    
    XCTAssertTrue([specific isMoreSpecificThan:general]);
    XCTAssertFalse([general isMoreSpecificThan:specific]);
    XCTAssertEqual([specific specificityLevel], 3);
    XCTAssertEqual([general specificityLevel], 1);
}

- (void)testCompatibility {
    NSError *error;
    CSCapabilityId *cap1 = [CSCapabilityId fromString:@"data_processing:transform:json" error:&error];
    CSCapabilityId *cap2 = [CSCapabilityId fromString:@"data_processing:*" error:&error];
    CSCapabilityId *cap3 = [CSCapabilityId fromString:@"compute:math" error:&error];
    
    XCTAssertTrue([cap1 isCompatibleWith:cap2]);
    XCTAssertTrue([cap2 isCompatibleWith:cap1]);
    XCTAssertFalse([cap1 isCompatibleWith:cap3]);
}

- (void)testEquality {
    NSError *error;
    CSCapabilityId *cap1 = [CSCapabilityId fromString:@"data_processing:transform:json" error:&error];
    CSCapabilityId *cap2 = [CSCapabilityId fromString:@"data_processing:transform:json" error:&error];
    CSCapabilityId *cap3 = [CSCapabilityId fromString:@"data_processing:transform:xml" error:&error];
    
    XCTAssertEqualObjects(cap1, cap2);
    XCTAssertNotEqualObjects(cap1, cap3);
    XCTAssertEqual([cap1 hash], [cap2 hash]);
}

- (void)testCoding {
    NSError *error;
    CSCapabilityId *original = [CSCapabilityId fromString:@"data_processing:transform:json" error:&error];
    XCTAssertNotNil(original);
    XCTAssertNil(error);
    
    // Test NSCoding without secure coding for simplicity
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:original];
    XCTAssertNotNil(data);
    
    CSCapabilityId *decoded = [NSKeyedUnarchiver unarchiveObjectWithData:data];
    XCTAssertNotNil(decoded);
    XCTAssertEqualObjects(original, decoded);
}

@end
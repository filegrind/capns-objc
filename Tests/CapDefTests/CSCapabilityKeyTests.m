//
//  CSCapabilityKeyTests.m
//  Tests for CSCapabilityKey
//

#import <XCTest/XCTest.h>
#import "CapDef.h"

@interface CSCapabilityKeyTests : XCTestCase
@end

@implementation CSCapabilityKeyTests

- (void)testCapabilityKeyCreation {
    NSError *error;
    CSCapabilityKey *capId = [CSCapabilityKey fromString:@"data_processing:transform:json" error:&error];
    
    XCTAssertNotNil(capId);
    XCTAssertNil(error);
    XCTAssertEqualObjects([capId toString], @"data_processing:transform:json");
    XCTAssertEqual(capId.segments.count, 3);
    XCTAssertEqualObjects(capId.segments[0], @"data_processing");
    XCTAssertEqualObjects(capId.segments[1], @"transform");
    XCTAssertEqualObjects(capId.segments[2], @"json");
}

- (void)testInvalidCapabilityKey {
    NSError *error;
    CSCapabilityKey *capId = [CSCapabilityKey fromString:@"" error:&error];
    
    XCTAssertNil(capId);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, CSCapabilityKeyErrorInvalidFormat);
}

- (void)testCapabilityMatching {
    NSError *error;
    CSCapabilityKey *capability = [CSCapabilityKey fromString:@"data_processing:transform:json" error:&error];
    CSCapabilityKey *request1 = [CSCapabilityKey fromString:@"data_processing:transform:json" error:&error];
    CSCapabilityKey *request2 = [CSCapabilityKey fromString:@"data_processing:transform" error:&error];
    CSCapabilityKey *request3 = [CSCapabilityKey fromString:@"data_processing" error:&error];
    CSCapabilityKey *request4 = [CSCapabilityKey fromString:@"compute:math" error:&error];
    
    XCTAssertTrue([capability canHandle:request1]);
    XCTAssertTrue([capability canHandle:request2]);
    XCTAssertTrue([capability canHandle:request3]);
    XCTAssertFalse([capability canHandle:request4]);
}

- (void)testWildcardMatching {
    NSError *error;
    CSCapabilityKey *wildcard = [CSCapabilityKey fromString:@"data_processing:*" error:&error];
    CSCapabilityKey *request1 = [CSCapabilityKey fromString:@"data_processing:transform:json" error:&error];
    CSCapabilityKey *request2 = [CSCapabilityKey fromString:@"data_processing:validate:xml" error:&error];
    CSCapabilityKey *request3 = [CSCapabilityKey fromString:@"compute:math" error:&error];
    
    XCTAssertTrue([wildcard canHandle:request1]);
    XCTAssertTrue([wildcard canHandle:request2]);
    XCTAssertFalse([wildcard canHandle:request3]);
}

- (void)testSpecificity {
    NSError *error;
    CSCapabilityKey *specific = [CSCapabilityKey fromString:@"data_processing:transform:json" error:&error];
    CSCapabilityKey *general = [CSCapabilityKey fromString:@"data_processing:*" error:&error];
    
    XCTAssertTrue([specific isMoreSpecificThan:general]);
    XCTAssertFalse([general isMoreSpecificThan:specific]);
    XCTAssertEqual([specific specificityLevel], 3);
    XCTAssertEqual([general specificityLevel], 1);
}

- (void)testCompatibility {
    NSError *error;
    CSCapabilityKey *cap1 = [CSCapabilityKey fromString:@"data_processing:transform:json" error:&error];
    CSCapabilityKey *cap2 = [CSCapabilityKey fromString:@"data_processing:*" error:&error];
    CSCapabilityKey *cap3 = [CSCapabilityKey fromString:@"compute:math" error:&error];
    
    XCTAssertTrue([cap1 isCompatibleWith:cap2]);
    XCTAssertTrue([cap2 isCompatibleWith:cap1]);
    XCTAssertFalse([cap1 isCompatibleWith:cap3]);
}

- (void)testEquality {
    NSError *error;
    CSCapabilityKey *cap1 = [CSCapabilityKey fromString:@"data_processing:transform:json" error:&error];
    CSCapabilityKey *cap2 = [CSCapabilityKey fromString:@"data_processing:transform:json" error:&error];
    CSCapabilityKey *cap3 = [CSCapabilityKey fromString:@"data_processing:transform:xml" error:&error];
    
    XCTAssertEqualObjects(cap1, cap2);
    XCTAssertNotEqualObjects(cap1, cap3);
    XCTAssertEqual([cap1 hash], [cap2 hash]);
}

- (void)testCoding {
    NSError *error;
    CSCapabilityKey *original = [CSCapabilityKey fromString:@"data_processing:transform:json" error:&error];
    XCTAssertNotNil(original);
    XCTAssertNil(error);
    
    // Test NSCoding without secure coding for simplicity
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:original];
    XCTAssertNotNil(data);
    
    CSCapabilityKey *decoded = [NSKeyedUnarchiver unarchiveObjectWithData:data];
    XCTAssertNotNil(decoded);
    XCTAssertEqualObjects(original, decoded);
}

@end
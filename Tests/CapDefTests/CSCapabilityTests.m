//
//  CSCapabilityTests.m
//  CapDefTests
//

#import <XCTest/XCTest.h>
#import "CSCapability.h"
#import "CSCapabilityKey.h"

@interface CSCapabilityTests : XCTestCase

@end

@implementation CSCapabilityTests

- (void)testCapabilityCreation {
    NSError *error;
    CSCapabilityKey *key = [CSCapabilityKey fromString:@"action=transform;format=json;type=data_processing" error:&error];
    XCTAssertNotNil(key, @"Failed to create capability key: %@", error);
    
    CSCapability *capability = [CSCapability capabilityWithId:key version:@"1.0.0" command:@"test-command"];
    
    XCTAssertNotNil(capability);
    XCTAssertEqualObjects([capability idString], @"action=transform;format=json;type=data_processing");
    XCTAssertEqualObjects(capability.version, @"1.0.0");
    XCTAssertEqualObjects(capability.command, @"test-command");
    XCTAssertFalse(capability.acceptsStdin, @"Capabilities should not accept stdin by default");
}

- (void)testCapabilityWithDescription {
    NSError *error;
    CSCapabilityKey *key = [CSCapabilityKey fromString:@"action=parse;format=json;type=data" error:&error];
    XCTAssertNotNil(key, @"Failed to create capability key: %@", error);
    
    CSCapability *capability = [CSCapability capabilityWithId:key 
                                                      version:@"1.0.0"
                                                      command:@"parse-cmd"
                                                  description:@"Parse JSON data"];
    
    XCTAssertNotNil(capability);
    XCTAssertEqualObjects(capability.capabilityDescription, @"Parse JSON data");
    XCTAssertFalse(capability.acceptsStdin, @"Capabilities should not accept stdin by default");
}

- (void)testCapabilityAcceptsStdin {
    NSError *error;
    CSCapabilityKey *key = [CSCapabilityKey fromString:@"action=generate;target=embeddings;type=document" error:&error];
    XCTAssertNotNil(key, @"Failed to create capability key: %@", error);
    
    // Test with acceptsStdin = NO (default)
    CSCapability *capability1 = [CSCapability capabilityWithId:key
                                                       version:@"1.0.0"
                                                   description:@"Generate embeddings"
                                                      metadata:@{}
                                                       command:@"generate"
                                                     arguments:[CSCapabilityArguments arguments]
                                                        output:nil
                                                  acceptsStdin:NO];
    
    XCTAssertNotNil(capability1);
    XCTAssertFalse(capability1.acceptsStdin, @"Should not accept stdin when explicitly set to NO");
    
    // Test with acceptsStdin = YES
    CSCapability *capability2 = [CSCapability capabilityWithId:key
                                                       version:@"1.0.0"
                                                   description:@"Generate embeddings"
                                                      metadata:@{}
                                                       command:@"generate"
                                                     arguments:[CSCapabilityArguments arguments]
                                                        output:nil
                                                  acceptsStdin:YES];
    
    XCTAssertNotNil(capability2);
    XCTAssertTrue(capability2.acceptsStdin, @"Should accept stdin when explicitly set to YES");
}

- (void)testCapabilityMatching {
    NSError *error;
    CSCapabilityKey *key = [CSCapabilityKey fromString:@"action=transform;format=json;type=data_processing" error:&error];
    XCTAssertNotNil(key, @"Failed to create capability key: %@", error);
    
    CSCapability *capability = [CSCapability capabilityWithId:key version:@"1.0.0" command:@"test-command"];
    
    XCTAssertTrue([capability matchesRequest:@"action=transform;format=json;type=data_processing"]);
    XCTAssertTrue([capability matchesRequest:@"action=transform;format=*;type=data_processing"]); // Request wants any format, cap handles json specifically
    XCTAssertTrue([capability matchesRequest:@"type=data_processing"]);
    XCTAssertFalse([capability matchesRequest:@"type=compute"]);
}

- (void)testCapabilityStdinSerialization {
    NSError *error;
    CSCapabilityKey *key = [CSCapabilityKey fromString:@"action=generate;target=embeddings;type=document" error:&error];
    XCTAssertNotNil(key, @"Failed to create capability key: %@", error);
    
    // Test copying preserves acceptsStdin
    CSCapability *original = [CSCapability capabilityWithId:key
                                                    version:@"1.0.0"
                                                description:@"Generate embeddings"
                                                   metadata:@{@"model": @"sentence-transformer"}
                                                    command:@"generate"
                                                  arguments:[CSCapabilityArguments arguments]
                                                     output:nil
                                               acceptsStdin:YES];
    
    CSCapability *copied = [original copy];
    XCTAssertNotNil(copied);
    XCTAssertEqual(original.acceptsStdin, copied.acceptsStdin);
    XCTAssertTrue(copied.acceptsStdin);
}

@end
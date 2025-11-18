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
    
    CSCapabilityArguments *arguments = [CSCapabilityArguments arguments];
    CSCapability *capability = [CSCapability capabilityWithId:key 
                                                      version:@"1.0.0" 
                                                  description:nil 
                                                     metadata:@{} 
                                                      command:@"test-command" 
                                                    arguments:arguments 
                                                       output:nil 
                                                 acceptsStdin:NO];
    
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
    
    CSCapabilityArguments *arguments = [CSCapabilityArguments arguments];
    CSCapability *capability = [CSCapability capabilityWithId:key 
                                                      version:@"1.0.0" 
                                                  description:@"Parse JSON data" 
                                                     metadata:@{} 
                                                      command:@"parse-cmd" 
                                                    arguments:arguments 
                                                       output:nil 
                                                 acceptsStdin:NO];
    
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
    
    CSCapabilityArguments *arguments = [CSCapabilityArguments arguments];
    CSCapability *capability = [CSCapability capabilityWithId:key 
                                                      version:@"1.0.0" 
                                                  description:nil 
                                                     metadata:@{} 
                                                      command:@"test-command" 
                                                    arguments:arguments 
                                                       output:nil 
                                                 acceptsStdin:NO];
    
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

- (void)testCanonicalDictionaryDeserialization {
    // Test CSCapability.capabilityWithDictionary
    NSDictionary *capabilityDict = @{
        @"id": @"action=extract;target=metadata;type=document",
        @"version": @"1.0.0",
        @"command": @"extract-metadata",
        @"description": @"Extract metadata from documents",
        @"metadata": @{@"format": @"json"},
        @"accepts_stdin": @YES
    };
    
    NSError *error;
    CSCapability *capability = [CSCapability capabilityWithDictionary:capabilityDict error:&error];
    
    XCTAssertNil(error, @"Dictionary deserialization should not fail: %@", error.localizedDescription);
    XCTAssertNotNil(capability, @"Capability should be created from dictionary");
    XCTAssertEqualObjects([capability idString], @"action=extract;target=metadata;type=document");
    XCTAssertEqualObjects(capability.version, @"1.0.0");
    XCTAssertEqualObjects(capability.command, @"extract-metadata");
    XCTAssertEqualObjects(capability.capabilityDescription, @"Extract metadata from documents");
    XCTAssertTrue(capability.acceptsStdin, @"Should accept stdin when specified in dictionary");
    
    // Test with missing required fields - should fail hard
    NSDictionary *invalidDict = @{
        @"version": @"1.0.0",
        @"command": @"extract-metadata"
        // Missing "id" field
    };
    
    error = nil;
    CSCapability *invalidCapability = [CSCapability capabilityWithDictionary:invalidDict error:&error];
    
    XCTAssertNotNil(error, @"Should fail when required fields are missing");
    XCTAssertNil(invalidCapability, @"Should return nil when deserialization fails");
    XCTAssertTrue([error.localizedDescription containsString:@"required"], @"Error should mention missing required fields");
}

- (void)testCanonicalArgumentsDeserialization {
    // Test CSCapabilityArguments.argumentsWithDictionary
    NSDictionary *argumentsDict = @{
        @"required": @[
            @{
                @"name": @"file_path",
                @"type": @"string", 
                @"description": @"Path to file",
                @"cli_flag": @"file_path",
                @"position": @0
            }
        ],
        @"optional": @[
            @{
                @"name": @"output_format",
                @"type": @"string",
                @"description": @"Output format",
                @"cli_flag": @"format",
                @"default_value": @"json"
            }
        ]
    };
    
    NSError *error;
    CSCapabilityArguments *arguments = [CSCapabilityArguments argumentsWithDictionary:argumentsDict error:&error];
    
    XCTAssertNil(error, @"Arguments dictionary deserialization should not fail: %@", error.localizedDescription);
    XCTAssertNotNil(arguments, @"Arguments should be created from dictionary");
    XCTAssertEqual(arguments.required.count, 1, @"Should have one required argument");
    XCTAssertEqual(arguments.optional.count, 1, @"Should have one optional argument");
    
    CSCapabilityArgument *requiredArg = arguments.required.firstObject;
    XCTAssertEqualObjects(requiredArg.name, @"file_path");
    XCTAssertEqual(requiredArg.type, CSArgumentTypeString);
    XCTAssertEqualObjects(requiredArg.position, @0);
}

- (void)testCanonicalOutputDeserialization {
    // Test CSCapabilityOutput.outputWithDictionary
    NSDictionary *outputDict = @{
        @"type": @"object",
        @"description": @"JSON metadata object",
        @"content_type": @"application/json",
        @"schema_ref": @"file-metadata.json"
    };
    
    NSError *error;
    CSCapabilityOutput *output = [CSCapabilityOutput outputWithDictionary:outputDict error:&error];
    
    XCTAssertNil(error, @"Output dictionary deserialization should not fail: %@", error.localizedDescription);
    XCTAssertNotNil(output, @"Output should be created from dictionary");
    XCTAssertEqual(output.type, CSOutputTypeObject);
    XCTAssertEqualObjects(output.outputDescription, @"JSON metadata object");
    XCTAssertEqualObjects(output.contentType, @"application/json");
    XCTAssertEqualObjects(output.schemaRef, @"file-metadata.json");
}

- (void)testCanonicalValidationDeserialization {
    // Test CSArgumentValidation.validationWithDictionary
    NSDictionary *validationDict = @{
        @"min_length": @1,
        @"max_length": @255,
        @"pattern": @"^[^\\0]+$",
        @"allowed_values": @[@"json", @"xml", @"yaml"]
    };
    
    NSError *error;
    CSArgumentValidation *validation = [CSArgumentValidation validationWithDictionary:validationDict error:&error];
    
    XCTAssertNil(error, @"Validation dictionary deserialization should not fail: %@", error.localizedDescription);
    XCTAssertNotNil(validation, @"Validation should be created from dictionary");
    XCTAssertEqualObjects(validation.minLength, @1);
    XCTAssertEqualObjects(validation.maxLength, @255);
    XCTAssertEqualObjects(validation.pattern, @"^[^\\0]+$");
    XCTAssertEqualObjects(validation.allowedValues, (@[@"json", @"xml", @"yaml"]));
}

- (void)testCompleteCapabilityDeserialization {
    // Test a complete capability with all nested structures
    NSDictionary *completeCapabilityDict = @{
        @"id": @"action=transform;format=json;type=data",
        @"version": @"2.0.0",
        @"command": @"transform-data",
        @"description": @"Transform JSON data with validation",
        @"metadata": @{@"engine": @"jq", @"performance": @"high"},
        @"accepts_stdin": @YES,
        @"arguments": @{
            @"required": @[
                @{
                    @"name": @"transformation",
                    @"type": @"string",
                    @"description": @"JQ transformation expression",
                    @"cli_flag": @"transform",
                    @"position": @0,
                    @"validation": @{
                        @"min_length": @1,
                        @"max_length": @1000
                    }
                }
            ],
            @"optional": @[
                @{
                    @"name": @"output_format",
                    @"type": @"string", 
                    @"description": @"Output format",
                    @"cli_flag": @"format",
                    @"default_value": @"json",
                    @"validation": @{
                        @"allowed_values": @[@"json", @"yaml", @"xml"]
                    }
                }
            ]
        },
        @"output": @{
            @"type": @"object",
            @"description": @"Transformed data",
            @"content_type": @"application/json"
        }
    };
    
    NSError *error;
    CSCapability *capability = [CSCapability capabilityWithDictionary:completeCapabilityDict error:&error];
    
    XCTAssertNil(error, @"Complete capability deserialization should not fail: %@", error.localizedDescription);
    XCTAssertNotNil(capability, @"Complete capability should be created");
    
    // Verify basic properties
    XCTAssertEqualObjects([capability idString], @"action=transform;format=json;type=data");
    XCTAssertEqualObjects(capability.version, @"2.0.0");
    XCTAssertEqualObjects(capability.command, @"transform-data");
    XCTAssertTrue(capability.acceptsStdin);
    
    // Verify metadata
    XCTAssertEqualObjects(capability.metadata[@"engine"], @"jq");
    XCTAssertEqualObjects(capability.metadata[@"performance"], @"high");
    
    // Verify arguments
    XCTAssertEqual(capability.arguments.required.count, 1);
    XCTAssertEqual(capability.arguments.optional.count, 1);
    
    CSCapabilityArgument *requiredArg = capability.arguments.required.firstObject;
    XCTAssertEqualObjects(requiredArg.name, @"transformation");
    XCTAssertEqualObjects(requiredArg.validation.minLength, @1);
    XCTAssertEqualObjects(requiredArg.validation.maxLength, @1000);
    
    CSCapabilityArgument *optionalArg = capability.arguments.optional.firstObject;
    XCTAssertEqualObjects(optionalArg.name, @"output_format");
    XCTAssertTrue([optionalArg.validation.allowedValues containsObject:@"json"]);
    
    // Verify output
    XCTAssertNotNil(capability.output);
    XCTAssertEqual(capability.output.type, CSOutputTypeObject);
    XCTAssertEqualObjects(capability.output.contentType, @"application/json");
}

@end
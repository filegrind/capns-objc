//
//  CSCapTests.m
//  CapDefTests
//

#import <XCTest/XCTest.h>
#import "CSCap.h"
#import "CSCapCard.h"
#import "CSCapManifest.h"

@interface CSCapTests : XCTestCase

@end

@implementation CSCapTests

- (void)testCapCreation {
    NSError *error;
    CSCapCard *key = [CSCapCard fromString:@"action=transform;format=json;type=data_processing" error:&error];
    XCTAssertNotNil(key, @"Failed to create cap card: %@", error);
    
    CSCapArguments *arguments = [CSCapArguments arguments];
    CSCap *cap = [CSCap capWithId:key 
                                                      version:@"1.0.0" 
                                                  description:nil 
                                                     metadata:@{} 
                                                      command:@"test-command" 
                                                    arguments:arguments 
                                                       output:nil 
                                                 acceptsStdin:NO];
    
    XCTAssertNotNil(cap);
    XCTAssertEqualObjects([cap idString], @"action=transform;format=json;type=data_processing");
    XCTAssertEqualObjects(cap.version, @"1.0.0");
    XCTAssertEqualObjects(cap.command, @"test-command");
    XCTAssertFalse(cap.acceptsStdin, @"Caps should not accept stdin by default");
}

- (void)testCapWithDescription {
    NSError *error;
    CSCapCard *key = [CSCapCard fromString:@"action=parse;format=json;type=data" error:&error];
    XCTAssertNotNil(key, @"Failed to create cap card: %@", error);
    
    CSCapArguments *arguments = [CSCapArguments arguments];
    CSCap *cap = [CSCap capWithId:key 
                                                      version:@"1.0.0" 
                                                  description:@"Parse JSON data" 
                                                     metadata:@{} 
                                                      command:@"parse-cmd" 
                                                    arguments:arguments 
                                                       output:nil 
                                                 acceptsStdin:NO];
    
    XCTAssertNotNil(cap);
    XCTAssertEqualObjects(cap.capDescription, @"Parse JSON data");
    XCTAssertFalse(cap.acceptsStdin, @"Caps should not accept stdin by default");
}

- (void)testCapAcceptsStdin {
    NSError *error;
    CSCapCard *key = [CSCapCard fromString:@"action=generate;target=embeddings" error:&error];
    XCTAssertNotNil(key, @"Failed to create cap card: %@", error);
    
    // Test with acceptsStdin = NO (default)
    CSCap *cap1 = [CSCap capWithId:key
                                                       version:@"1.0.0"
                                                   description:@"Generate embeddings"
                                                      metadata:@{}
                                                       command:@"generate"
                                                     arguments:[CSCapArguments arguments]
                                                        output:nil
                                                  acceptsStdin:NO];
    
    XCTAssertNotNil(cap1);
    XCTAssertFalse(cap1.acceptsStdin, @"Should not accept stdin when explicitly set to NO");
    
    // Test with acceptsStdin = YES
    CSCap *cap2 = [CSCap capWithId:key
                                                       version:@"1.0.0"
                                                   description:@"Generate embeddings"
                                                      metadata:@{}
                                                       command:@"generate"
                                                     arguments:[CSCapArguments arguments]
                                                        output:nil
                                                  acceptsStdin:YES];
    
    XCTAssertNotNil(cap2);
    XCTAssertTrue(cap2.acceptsStdin, @"Should accept stdin when explicitly set to YES");
}

- (void)testCapMatching {
    NSError *error;
    CSCapCard *key = [CSCapCard fromString:@"action=transform;format=json;type=data_processing" error:&error];
    XCTAssertNotNil(key, @"Failed to create cap card: %@", error);
    
    CSCapArguments *arguments = [CSCapArguments arguments];
    CSCap *cap = [CSCap capWithId:key 
                                                      version:@"1.0.0" 
                                                  description:nil 
                                                     metadata:@{} 
                                                      command:@"test-command" 
                                                    arguments:arguments 
                                                       output:nil 
                                                 acceptsStdin:NO];
    
    XCTAssertTrue([cap matchesRequest:@"action=transform;format=json;type=data_processing"]);
    XCTAssertTrue([cap matchesRequest:@"action=transform;format=*;type=data_processing"]); // Request wants any format, cap handles json specifically
    XCTAssertTrue([cap matchesRequest:@"type=data_processing"]);
    XCTAssertFalse([cap matchesRequest:@"type=compute"]);
}

- (void)testCapStdinSerialization {
    NSError *error;
    CSCapCard *key = [CSCapCard fromString:@"action=generate;target=embeddings" error:&error];
    XCTAssertNotNil(key, @"Failed to create cap card: %@", error);
    
    // Test copying preserves acceptsStdin
    CSCap *original = [CSCap capWithId:key
                                                    version:@"1.0.0"
                                                description:@"Generate embeddings"
                                                   metadata:@{@"model": @"sentence-transformer"}
                                                    command:@"generate"
                                                  arguments:[CSCapArguments arguments]
                                                     output:nil
                                               acceptsStdin:YES];
    
    CSCap *copied = [original copy];
    XCTAssertNotNil(copied);
    XCTAssertEqual(original.acceptsStdin, copied.acceptsStdin);
    XCTAssertTrue(copied.acceptsStdin);
}

- (void)testCanonicalDictionaryDeserialization {
    // Test CSCap.capWithDictionary
    NSDictionary *capDict = @{
        @"id": @"action=extract;target=metadata;",
        @"version": @"1.0.0",
        @"command": @"extract-metadata",
        @"description": @"Extract metadata from documents",
        @"metadata": @{@"ext": @"json"},
        @"accepts_stdin": @YES
    };
    
    NSError *error;
    CSCap *cap = [CSCap capWithDictionary:capDict error:&error];
    
    XCTAssertNil(error, @"Dictionary deserialization should not fail: %@", error.localizedDescription);
    XCTAssertNotNil(cap, @"Cap should be created from dictionary");
    XCTAssertEqualObjects([cap idString], @"action=extract;target=metadata;");
    XCTAssertEqualObjects(cap.version, @"1.0.0");
    XCTAssertEqualObjects(cap.command, @"extract-metadata");
    XCTAssertEqualObjects(cap.capDescription, @"Extract metadata from documents");
    XCTAssertTrue(cap.acceptsStdin, @"Should accept stdin when specified in dictionary");
    
    // Test with missing required fields - should fail hard
    NSDictionary *invalidDict = @{
        @"version": @"1.0.0",
        @"command": @"extract-metadata"
        // Missing "id" field
    };
    
    error = nil;
    CSCap *invalidCap = [CSCap capWithDictionary:invalidDict error:&error];
    
    XCTAssertNotNil(error, @"Should fail when required fields are missing");
    XCTAssertNil(invalidCap, @"Should return nil when deserialization fails");
    XCTAssertTrue([error.localizedDescription containsString:@"required"], @"Error should mention missing required fields");
}

- (void)testCanonicalArgumentsDeserialization {
    // Test CSCapArguments.argumentsWithDictionary
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
                @"cli_flag": @"ext",
                @"default_value": @"json"
            }
        ]
    };
    
    NSError *error;
    CSCapArguments *arguments = [CSCapArguments argumentsWithDictionary:argumentsDict error:&error];
    
    XCTAssertNil(error, @"Arguments dictionary deserialization should not fail: %@", error.localizedDescription);
    XCTAssertNotNil(arguments, @"Arguments should be created from dictionary");
    XCTAssertEqual(arguments.required.count, 1, @"Should have one required argument");
    XCTAssertEqual(arguments.optional.count, 1, @"Should have one optional argument");
    
    CSCapArgument *requiredArg = arguments.required.firstObject;
    XCTAssertEqualObjects(requiredArg.name, @"file_path");
    XCTAssertEqual(requiredArg.type, CSArgumentTypeString);
    XCTAssertEqualObjects(requiredArg.position, @0);
}

- (void)testCanonicalOutputDeserialization {
    // Test CSCapOutput.outputWithDictionary
    NSDictionary *outputDict = @{
        @"type": @"object",
        @"description": @"JSON metadata object",
        @"content_type": @"application/json",
        @"schema_ref": @"file-metadata.json"
    };
    
    NSError *error;
    CSCapOutput *output = [CSCapOutput outputWithDictionary:outputDict error:&error];
    
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

- (void)testCompleteCapDeserialization {
    // Test a complete cap with all nested structures
    NSDictionary *completeCapDict = @{
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
                    @"cli_flag": @"ext",
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
    CSCap *cap = [CSCap capWithDictionary:completeCapDict error:&error];
    
    XCTAssertNil(error, @"Complete cap deserialization should not fail: %@", error.localizedDescription);
    XCTAssertNotNil(cap, @"Complete cap should be created");
    
    // Verify basic properties
    XCTAssertEqualObjects([cap idString], @"action=transform;format=json;type=data");
    XCTAssertEqualObjects(cap.version, @"2.0.0");
    XCTAssertEqualObjects(cap.command, @"transform-data");
    XCTAssertTrue(cap.acceptsStdin);
    
    // Verify metadata
    XCTAssertEqualObjects(cap.metadata[@"engine"], @"jq");
    XCTAssertEqualObjects(cap.metadata[@"performance"], @"high");
    
    // Verify arguments
    XCTAssertEqual(cap.arguments.required.count, 1);
    XCTAssertEqual(cap.arguments.optional.count, 1);
    
    CSCapArgument *requiredArg = cap.arguments.required.firstObject;
    XCTAssertEqualObjects(requiredArg.name, @"transformation");
    XCTAssertEqualObjects(requiredArg.validation.minLength, @1);
    XCTAssertEqualObjects(requiredArg.validation.maxLength, @1000);
    
    CSCapArgument *optionalArg = cap.arguments.optional.firstObject;
    XCTAssertEqualObjects(optionalArg.name, @"output_format");
    XCTAssertTrue([optionalArg.validation.allowedValues containsObject:@"json"]);
    
    // Verify output
    XCTAssertNotNil(cap.output);
    XCTAssertEqual(cap.output.type, CSOutputTypeObject);
    XCTAssertEqualObjects(cap.output.contentType, @"application/json");
}

// MARK: - Cap Manifest Tests

- (void)testCapManifestCreation {
    NSError *error;
    CSCapCard *key = [CSCapCard fromString:@"action=extract;target=metadata;" error:&error];
    XCTAssertNotNil(key, @"Failed to create cap card: %@", error);
    
    CSCapArguments *arguments = [CSCapArguments arguments];
    CSCap *cap = [CSCap capWithId:key 
                                                      version:@"1.0.0" 
                                                  description:nil 
                                                     metadata:@{} 
                                                      command:@"extract-metadata" 
                                                    arguments:arguments 
                                                       output:nil 
                                                 acceptsStdin:NO];
    
    CSCapManifest *manifest = [CSCapManifest manifestWithName:@"TestComponent"
                                                                     version:@"0.1.0"
                                                                 description:@"A test component for validation"
                                                                caps:@[cap]];
    
    XCTAssertEqualObjects(manifest.name, @"TestComponent");
    XCTAssertEqualObjects(manifest.version, @"0.1.0");
    XCTAssertEqualObjects(manifest.manifestDescription, @"A test component for validation");
    XCTAssertEqual(manifest.caps.count, 1);
    XCTAssertNil(manifest.author);
}

- (void)testCapManifestWithAuthor {
    NSError *error;
    CSCapCard *key = [CSCapCard fromString:@"action=extract;target=metadata;" error:&error];
    XCTAssertNotNil(key, @"Failed to create cap card: %@", error);
    
    CSCapArguments *arguments = [CSCapArguments arguments];
    CSCap *cap = [CSCap capWithId:key 
                                                      version:@"1.0.0" 
                                                  description:nil 
                                                     metadata:@{} 
                                                      command:@"extract-metadata" 
                                                    arguments:arguments 
                                                       output:nil 
                                                 acceptsStdin:NO];
    
    CSCapManifest *manifest = [[CSCapManifest manifestWithName:@"TestComponent"
                                                                      version:@"0.1.0"
                                                                  description:@"A test component for validation"
                                                                 caps:@[cap]]
                                      withAuthor:@"Test Author"];
    
    XCTAssertEqualObjects(manifest.author, @"Test Author");
}

- (void)testCapManifestDictionaryDeserialization {
    NSDictionary *manifestDict = @{
        @"name": @"TestComponent",
        @"version": @"0.1.0",
        @"description": @"A test component for validation",
        @"author": @"Test Author",
        @"caps": @[
            @{
                @"id": @"action=extract;target=metadata;",
                @"version": @"1.0.0",
                @"command": @"extract-metadata",
                @"accepts_stdin": @YES,
                @"arguments": @{
                    @"required": @[],
                    @"optional": @[]
                }
            }
        ]
    };
    
    NSError *error;
    CSCapManifest *manifest = [CSCapManifest manifestWithDictionary:manifestDict error:&error];
    
    XCTAssertNil(error, @"Manifest dictionary deserialization should not fail: %@", error.localizedDescription);
    XCTAssertNotNil(manifest, @"Manifest should be created from dictionary");
    XCTAssertEqualObjects(manifest.name, @"TestComponent");
    XCTAssertEqualObjects(manifest.version, @"0.1.0");
    XCTAssertEqualObjects(manifest.manifestDescription, @"A test component for validation");
    XCTAssertEqualObjects(manifest.author, @"Test Author");
    XCTAssertEqual(manifest.caps.count, 1);
    
    CSCap *cap = manifest.caps.firstObject;
    XCTAssertEqualObjects([cap idString], @"action=extract;target=metadata;");
    XCTAssertTrue(cap.acceptsStdin);
}

- (void)testCapManifestRequiredFields {
    // Test that deserialization fails when required fields are missing
    NSDictionary *invalidDict = @{@"name": @"TestComponent"};
    
    NSError *error;
    CSCapManifest *manifest = [CSCapManifest manifestWithDictionary:invalidDict error:&error];
    
    XCTAssertNil(manifest, @"Manifest creation should fail with missing required fields");
    XCTAssertNotNil(error, @"Error should be set when required fields are missing");
    XCTAssertEqualObjects(error.domain, @"CSCapManifestError");
    XCTAssertEqual(error.code, 1007);
}

- (void)testCapManifestWithMultipleCaps {
    NSError *error;
    CSCapCard *key1 = [CSCapCard fromString:@"action=extract;target=metadata;" error:&error];
    XCTAssertNotNil(key1, @"Failed to create cap card: %@", error);
    
    CSCapCard *key2 = [CSCapCard fromString:@"action=extract;target=outline;" error:&error];
    XCTAssertNotNil(key2, @"Failed to create cap card: %@", error);
    
    CSCapArguments *arguments = [CSCapArguments arguments];
    
    CSCap *cap1 = [CSCap capWithId:key1 
                                                       version:@"1.0.0" 
                                                   description:nil 
                                                      metadata:@{} 
                                                       command:@"extract-metadata" 
                                                     arguments:arguments 
                                                        output:nil 
                                                  acceptsStdin:NO];
    
    CSCap *cap2 = [CSCap capWithId:key2 
                                                       version:@"1.0.0" 
                                                   description:nil 
                                                      metadata:@{@"supports_outline": @"true"} 
                                                       command:@"extract-outline" 
                                                     arguments:arguments 
                                                        output:nil 
                                                  acceptsStdin:NO];
    
    CSCapManifest *manifest = [CSCapManifest manifestWithName:@"MultiCapComponent"
                                                                     version:@"1.0.0"
                                                                 description:@"Component with multiple caps"
                                                                caps:@[cap1, cap2]];
    
    XCTAssertEqual(manifest.caps.count, 2);
    XCTAssertEqualObjects([manifest.caps[0] idString], @"action=extract;target=metadata;");
    XCTAssertEqualObjects([manifest.caps[1] idString], @"action=extract;target=outline;");
    XCTAssertEqualObjects(cap2.metadata[@"supports_outline"], @"true");
}

- (void)testCapManifestEmptyCaps {
    CSCapManifest *manifest = [CSCapManifest manifestWithName:@"EmptyComponent"
                                                                     version:@"1.0.0"
                                                                 description:@"Component with no caps"
                                                                caps:@[]];
    
    XCTAssertEqual(manifest.caps.count, 0);
    
    // Test dictionary serialization preserves empty array
    NSDictionary *manifestDict = @{
        @"name": @"EmptyComponent",
        @"version": @"1.0.0", 
        @"description": @"Component with no caps",
        @"caps": @[]
    };
    
    NSError *error;
    CSCapManifest *deserializedManifest = [CSCapManifest manifestWithDictionary:manifestDict error:&error];
    
    XCTAssertNil(error, @"Empty caps manifest should deserialize successfully");
    XCTAssertNotNil(deserializedManifest);
    XCTAssertEqual(deserializedManifest.caps.count, 0);
}

- (void)testCapManifestOptionalAuthorField {
    NSError *error;
    CSCapCard *key = [CSCapCard fromString:@"action=validate;type=file" error:&error];
    XCTAssertNotNil(key, @"Failed to create cap card: %@", error);
    
    CSCapArguments *arguments = [CSCapArguments arguments];
    CSCap *cap = [CSCap capWithId:key 
                                                      version:@"1.0.0" 
                                                  description:nil 
                                                     metadata:@{} 
                                                      command:@"validate" 
                                                    arguments:arguments 
                                                       output:nil 
                                                 acceptsStdin:NO];
    
    CSCapManifest *manifestWithoutAuthor = [CSCapManifest manifestWithName:@"ValidatorComponent"
                                                                                  version:@"1.0.0"
                                                                              description:@"File validation component"
                                                                             caps:@[cap]];
    
    // Manifest without author should not include author field in dictionary representation
    NSDictionary *manifestDict = @{
        @"name": @"ValidatorComponent",
        @"version": @"1.0.0",
        @"description": @"File validation component", 
        @"caps": @[
            @{
                @"id": @"action=validate;type=file",
                @"version": @"1.0.0",
                @"command": @"validate",
                @"arguments": @{
                    @"required": @[],
                    @"optional": @[]
                }
            }
        ]
    };
    
    CSCapManifest *deserializedManifest = [CSCapManifest manifestWithDictionary:manifestDict error:&error];
    
    XCTAssertNil(error, @"Manifest without author should deserialize successfully");
    XCTAssertNotNil(deserializedManifest);
    XCTAssertNil(deserializedManifest.author, @"Author should be nil when not provided");
}

- (void)testCapManifestCompatibility {
    // Test that manifest format is compatible between different component types
    NSError *error;
    CSCapCard *key = [CSCapCard fromString:@"action=process" error:&error];
    XCTAssertNotNil(key, @"Failed to create cap card: %@", error);
    
    CSCapArguments *arguments = [CSCapArguments arguments];
    CSCap *cap = [CSCap capWithId:key 
                                                      version:@"1.0.0" 
                                                  description:nil 
                                                     metadata:@{} 
                                                      command:@"process" 
                                                    arguments:arguments 
                                                       output:nil 
                                                 acceptsStdin:NO];
    
    // Create manifest similar to what a plugin would have
    CSCapManifest *pluginStyleManifest = [CSCapManifest manifestWithName:@"PluginComponent"
                                                                                version:@"0.1.0"
                                                                            description:@"Plugin-style component"
                                                                           caps:@[cap]];
    
    // Create manifest similar to what a provider would have
    CSCapManifest *providerStyleManifest = [CSCapManifest manifestWithName:@"ProviderComponent"
                                                                                  version:@"0.1.0"
                                                                              description:@"Provider-style component"
                                                                             caps:@[cap]];
    
    // Both should have the same structure
    XCTAssertNotNil(pluginStyleManifest.name);
    XCTAssertNotNil(pluginStyleManifest.version);
    XCTAssertNotNil(pluginStyleManifest.manifestDescription);
    XCTAssertNotNil(pluginStyleManifest.caps);
    
    XCTAssertNotNil(providerStyleManifest.name);
    XCTAssertNotNil(providerStyleManifest.version);
    XCTAssertNotNil(providerStyleManifest.manifestDescription);
    XCTAssertNotNil(providerStyleManifest.caps);
    
    // Same cap structure
    XCTAssertEqual(pluginStyleManifest.caps.count, providerStyleManifest.caps.count);
    XCTAssertEqualObjects([pluginStyleManifest.caps.firstObject idString], 
                         [providerStyleManifest.caps.firstObject idString]);
}

@end
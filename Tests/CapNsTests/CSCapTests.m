//
//  CSCapTests.m
//  CapNsTests
//
//  NOTE: All ArgumentType/OutputType enums have been removed.
//  Arguments and outputs now use mediaSpec fields containing spec IDs
//  (e.g., "std:str.v1") that resolve via the mediaSpecs table.
//

#import <XCTest/XCTest.h>
#import "CSCap.h"
#import "CSCapUrn.h"
#import "CSCapManifest.h"
#import "CSMediaSpec.h"

@interface CSCapTests : XCTestCase

@end

@implementation CSCapTests

- (void)testCapCreation {
    NSError *error;
    CSCapUrn *key = [CSCapUrn fromString:@"cap:op=transform;format=json;type=data_processing" error:&error];
    XCTAssertNotNil(key, @"Failed to create cap URN: %@", error);

    CSCapArguments *arguments = [CSCapArguments arguments];
    CSCap *cap = [CSCap capWithUrn:key
                             title:@"Test Cap"
                           command:@"test-command"
                       description:nil
                          metadata:@{}
                        mediaSpecs:@{}
                         arguments:arguments
                            output:nil
                      acceptsStdin:NO
                      metadataJSON:nil];

    XCTAssertNotNil(cap);
    // URN tags are sorted alphabetically: format, op, type
    XCTAssertEqualObjects([cap urnString], @"cap:format=json;op=transform;type=data_processing");
    XCTAssertEqualObjects(cap.command, @"test-command");
    XCTAssertFalse(cap.acceptsStdin, @"Caps should not accept stdin by default");
}

- (void)testCapWithDescription {
    NSError *error;
    CSCapUrn *key = [CSCapUrn fromString:@"cap:op=parse;format=json;type=data" error:&error];
    XCTAssertNotNil(key, @"Failed to create cap URN: %@", error);

    CSCapArguments *arguments = [CSCapArguments arguments];
    CSCap *cap = [CSCap capWithUrn:key
                             title:@"Parse JSON"
                           command:@"parse-cmd"
                       description:@"Parse JSON data"
                          metadata:@{}
                        mediaSpecs:@{}
                         arguments:arguments
                            output:nil
                      acceptsStdin:NO
                      metadataJSON:nil];

    XCTAssertNotNil(cap);
    XCTAssertEqualObjects(cap.capDescription, @"Parse JSON data");
    XCTAssertFalse(cap.acceptsStdin, @"Caps should not accept stdin by default");
}

- (void)testCapAcceptsStdin {
    NSError *error;
    CSCapUrn *key = [CSCapUrn fromString:@"cap:op=generate;target=embeddings" error:&error];
    XCTAssertNotNil(key, @"Failed to create cap URN: %@", error);

    // Test with acceptsStdin = NO (default)
    CSCap *cap1 = [CSCap capWithUrn:key
                              title:@"Generate"
                            command:@"generate"
                        description:@"Generate embeddings"
                           metadata:@{}
                         mediaSpecs:@{}
                          arguments:[CSCapArguments arguments]
                             output:nil
                       acceptsStdin:NO
                       metadataJSON:nil];

    XCTAssertNotNil(cap1);
    XCTAssertFalse(cap1.acceptsStdin, @"Should not accept stdin when explicitly set to NO");

    // Test with acceptsStdin = YES
    CSCap *cap2 = [CSCap capWithUrn:key
                              title:@"Generate"
                            command:@"generate"
                        description:@"Generate embeddings"
                           metadata:@{}
                         mediaSpecs:@{}
                          arguments:[CSCapArguments arguments]
                             output:nil
                       acceptsStdin:YES
                       metadataJSON:nil];

    XCTAssertNotNil(cap2);
    XCTAssertTrue(cap2.acceptsStdin, @"Should accept stdin when explicitly set to YES");
}

- (void)testCapMatching {
    NSError *error;
    CSCapUrn *key = [CSCapUrn fromString:@"cap:op=transform;format=json;type=data_processing" error:&error];
    XCTAssertNotNil(key, @"Failed to create cap URN: %@", error);

    CSCapArguments *arguments = [CSCapArguments arguments];
    CSCap *cap = [CSCap capWithUrn:key
                             title:@"Transform"
                           command:@"test-command"
                       description:nil
                          metadata:@{}
                        mediaSpecs:@{}
                         arguments:arguments
                            output:nil
                      acceptsStdin:NO
                      metadataJSON:nil];

    // URN tags are sorted alphabetically
    XCTAssertTrue([cap matchesRequest:@"cap:format=json;op=transform;type=data_processing"]);
    XCTAssertTrue([cap matchesRequest:@"cap:format=*;op=transform;type=data_processing"]); // Request wants any format, cap handles json specifically
    XCTAssertTrue([cap matchesRequest:@"cap:type=data_processing"]);
    XCTAssertFalse([cap matchesRequest:@"cap:type=compute"]);
}

- (void)testCapStdinSerialization {
    NSError *error;
    CSCapUrn *key = [CSCapUrn fromString:@"cap:op=generate;target=embeddings" error:&error];
    XCTAssertNotNil(key, @"Failed to create cap URN: %@", error);

    // Test copying preserves acceptsStdin
    CSCap *original = [CSCap capWithUrn:key
                                  title:@"Generate"
                                command:@"generate"
                            description:@"Generate embeddings"
                               metadata:@{@"model": @"sentence-transformer"}
                             mediaSpecs:@{}
                              arguments:[CSCapArguments arguments]
                                 output:nil
                           acceptsStdin:YES
                           metadataJSON:nil];

    CSCap *copied = [original copy];
    XCTAssertNotNil(copied);
    XCTAssertEqual(original.acceptsStdin, copied.acceptsStdin);
    XCTAssertTrue(copied.acceptsStdin);
}

- (void)testCanonicalDictionaryDeserialization {
    // Test CSCap.capWithDictionary with new format
    NSDictionary *capDict = @{
        @"urn": @"cap:op=extract;target=metadata",
        @"title": @"Extract Metadata",
        @"command": @"extract-metadata",
        @"cap_description": @"Extract metadata from documents",
        @"metadata": @{@"ext": @"json"},
        @"accepts_stdin": @YES
    };

    NSError *error;
    CSCap *cap = [CSCap capWithDictionary:capDict error:&error];

    XCTAssertNil(error, @"Dictionary deserialization should not fail: %@", error.localizedDescription);
    XCTAssertNotNil(cap, @"Cap should be created from dictionary");
    XCTAssertEqualObjects([cap urnString], @"cap:op=extract;target=metadata");
    XCTAssertEqualObjects(cap.command, @"extract-metadata");
    XCTAssertEqualObjects(cap.capDescription, @"Extract metadata from documents");
    XCTAssertTrue(cap.acceptsStdin, @"Should accept stdin when specified in dictionary");

    // Test with missing required fields - should fail hard
    NSDictionary *invalidDict = @{
        @"command": @"extract-metadata"
        // Missing "urn" field
    };

    error = nil;
    CSCap *invalidCap = [CSCap capWithDictionary:invalidDict error:&error];

    XCTAssertNotNil(error, @"Should fail when required fields are missing");
    XCTAssertNil(invalidCap, @"Should return nil when deserialization fails");
    XCTAssertTrue([error.localizedDescription containsString:@"urn"], @"Error should mention missing urn field");
}

- (void)testCanonicalArgumentsDeserialization {
    // Test CSCapArguments.argumentsWithDictionary with new media_spec format
    NSDictionary *argumentsDict = @{
        @"required": @[
            @{
                @"name": @"file_path",
                @"media_spec": CSSpecIdStr,  // Use spec ID instead of arg_type
                @"arg_description": @"Path to file",
                @"cli_flag": @"--file_path",
                @"position": @0
            }
        ],
        @"optional": @[
            @{
                @"name": @"output_format",
                @"media_spec": CSSpecIdStr,
                @"arg_description": @"Output format",
                @"cli_flag": @"--ext",
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
    XCTAssertEqualObjects(requiredArg.mediaSpec, CSSpecIdStr);  // Verify spec ID
    XCTAssertEqualObjects(requiredArg.position, @0);
}

- (void)testCanonicalOutputDeserialization {
    // Test CSCapOutput.outputWithDictionary with new media_spec format
    NSDictionary *outputDict = @{
        @"media_spec": CSSpecIdObj,  // Use spec ID instead of output_type
        @"output_description": @"JSON metadata object"
    };

    NSError *error;
    CSCapOutput *output = [CSCapOutput outputWithDictionary:outputDict error:&error];

    XCTAssertNil(error, @"Output dictionary deserialization should not fail: %@", error.localizedDescription);
    XCTAssertNotNil(output, @"Output should be created from dictionary");
    XCTAssertEqualObjects(output.mediaSpec, CSSpecIdObj);  // Verify spec ID
    XCTAssertEqualObjects(output.outputDescription, @"JSON metadata object");
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
    // Test a complete cap with all nested structures using new format
    NSDictionary *completeCapDict = @{
        @"urn": @"cap:op=transform;format=json;type=data",
        @"title": @"Transform Data",
        @"command": @"transform-data",
        @"cap_description": @"Transform JSON data with validation",
        @"metadata": @{@"engine": @"jq", @"performance": @"high"},
        @"accepts_stdin": @YES,
        @"media_specs": @{
            @"my:output.v1": @{
                @"media_type": @"application/json",
                @"profile_uri": @"https://capns.org/schema/transform-output"
            }
        },
        @"arguments": @{
            @"required": @[
                @{
                    @"name": @"transformation",
                    @"media_spec": CSSpecIdStr,
                    @"arg_description": @"JQ transformation expression",
                    @"cli_flag": @"--transform",
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
                    @"media_spec": CSSpecIdStr,
                    @"arg_description": @"Output format",
                    @"cli_flag": @"--ext",
                    @"default_value": @"json",
                    @"validation": @{
                        @"allowed_values": @[@"json", @"yaml", @"xml"]
                    }
                }
            ]
        },
        @"output": @{
            @"media_spec": @"my:output.v1",
            @"output_description": @"Transformed data"
        }
    };

    NSError *error;
    CSCap *cap = [CSCap capWithDictionary:completeCapDict error:&error];

    XCTAssertNil(error, @"Complete cap deserialization should not fail: %@", error.localizedDescription);
    XCTAssertNotNil(cap, @"Complete cap should be created");

    // Verify basic properties - URN tags are sorted alphabetically
    XCTAssertEqualObjects([cap urnString], @"cap:format=json;op=transform;type=data");
    XCTAssertEqualObjects(cap.command, @"transform-data");
    XCTAssertTrue(cap.acceptsStdin);

    // Verify metadata
    XCTAssertEqualObjects(cap.metadata[@"engine"], @"jq");
    XCTAssertEqualObjects(cap.metadata[@"performance"], @"high");

    // Verify media_specs
    XCTAssertNotNil(cap.mediaSpecs[@"my:output.v1"]);

    // Verify arguments
    XCTAssertEqual(cap.arguments.required.count, 1);
    XCTAssertEqual(cap.arguments.optional.count, 1);

    CSCapArgument *requiredArg = cap.arguments.required.firstObject;
    XCTAssertEqualObjects(requiredArg.name, @"transformation");
    XCTAssertEqualObjects(requiredArg.mediaSpec, CSSpecIdStr);
    XCTAssertEqualObjects(requiredArg.validation.minLength, @1);
    XCTAssertEqualObjects(requiredArg.validation.maxLength, @1000);

    CSCapArgument *optionalArg = cap.arguments.optional.firstObject;
    XCTAssertEqualObjects(optionalArg.name, @"output_format");
    XCTAssertEqualObjects(optionalArg.mediaSpec, CSSpecIdStr);
    XCTAssertTrue([optionalArg.validation.allowedValues containsObject:@"json"]);

    // Verify output
    XCTAssertNotNil(cap.output);
    XCTAssertEqualObjects(cap.output.mediaSpec, @"my:output.v1");
}

- (void)testMediaSpecsResolution {
    // Test that spec IDs can be resolved from the mediaSpecs table
    NSError *error;
    CSCapUrn *key = [CSCapUrn fromString:@"cap:op=test" error:&error];
    XCTAssertNotNil(key);

    NSDictionary *mediaSpecs = @{
        @"my:custom-output.v1": @{
            @"media_type": @"application/json",
            @"profile_uri": @"https://example.com/schema/custom-output",
            @"schema": @{
                @"type": @"object",
                @"properties": @{
                    @"result": @{@"type": @"string"}
                },
                @"required": @[@"result"]
            }
        },
        @"my:text-input.v1": @"text/plain; profile=https://example.com/schema/text-input"
    };

    CSCap *cap = [CSCap capWithUrn:key
                             title:@"Test"
                           command:@"test"
                       description:nil
                          metadata:@{}
                        mediaSpecs:mediaSpecs
                         arguments:[CSCapArguments arguments]
                            output:nil
                      acceptsStdin:NO
                      metadataJSON:nil];

    // Resolve custom spec ID
    CSMediaSpec *resolved = [cap resolveSpecId:@"my:custom-output.v1" error:&error];
    XCTAssertNotNil(resolved, @"Should resolve custom spec ID from mediaSpecs: %@", error);
    XCTAssertEqualObjects(resolved.contentType, @"application/json");
    XCTAssertNotNil(resolved.schema);

    // Resolve string-form spec
    CSMediaSpec *resolvedString = [cap resolveSpecId:@"my:text-input.v1" error:&error];
    XCTAssertNotNil(resolvedString, @"Should resolve string-form spec ID: %@", error);
    XCTAssertEqualObjects(resolvedString.contentType, @"text/plain");

    // Resolve built-in spec ID
    CSMediaSpec *resolvedBuiltin = [cap resolveSpecId:CSSpecIdStr error:&error];
    XCTAssertNotNil(resolvedBuiltin, @"Should resolve built-in spec ID: %@", error);
    XCTAssertEqualObjects(resolvedBuiltin.contentType, @"text/plain");

    // Fail on unknown spec ID
    CSMediaSpec *unknown = [cap resolveSpecId:@"unknown:spec.v1" error:&error];
    XCTAssertNil(unknown, @"Should fail on unknown spec ID");
    XCTAssertNotNil(error, @"Should set error for unknown spec ID");
}

- (void)testBuiltinSpecIds {
    // Test all built-in spec IDs are recognized
    XCTAssertTrue(CSIsBuiltinSpecId(CSSpecIdStr));
    XCTAssertTrue(CSIsBuiltinSpecId(CSSpecIdInt));
    XCTAssertTrue(CSIsBuiltinSpecId(CSSpecIdNum));
    XCTAssertTrue(CSIsBuiltinSpecId(CSSpecIdBool));
    XCTAssertTrue(CSIsBuiltinSpecId(CSSpecIdObj));
    XCTAssertTrue(CSIsBuiltinSpecId(CSSpecIdStrArray));
    XCTAssertTrue(CSIsBuiltinSpecId(CSSpecIdIntArray));
    XCTAssertTrue(CSIsBuiltinSpecId(CSSpecIdNumArray));
    XCTAssertTrue(CSIsBuiltinSpecId(CSSpecIdBoolArray));
    XCTAssertTrue(CSIsBuiltinSpecId(CSSpecIdObjArray));
    XCTAssertTrue(CSIsBuiltinSpecId(CSSpecIdBinary));

    // Test non-builtin returns false
    XCTAssertFalse(CSIsBuiltinSpecId(@"custom:spec.v1"));
    XCTAssertFalse(CSIsBuiltinSpecId(@"my:output.v1"));
}

// MARK: - Cap Manifest Tests

- (void)testCapManifestCreation {
    NSError *error;
    CSCapUrn *key = [CSCapUrn fromString:@"cap:op=extract;target=metadata" error:&error];
    XCTAssertNotNil(key, @"Failed to create cap URN: %@", error);

    CSCapArguments *arguments = [CSCapArguments arguments];
    CSCap *cap = [CSCap capWithUrn:key
                             title:@"Extract Metadata"
                           command:@"extract-metadata"
                       description:nil
                          metadata:@{}
                        mediaSpecs:@{}
                         arguments:arguments
                            output:nil
                      acceptsStdin:NO
                      metadataJSON:nil];

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
    CSCapUrn *key = [CSCapUrn fromString:@"cap:op=extract;target=metadata" error:&error];
    XCTAssertNotNil(key, @"Failed to create cap URN: %@", error);

    CSCapArguments *arguments = [CSCapArguments arguments];
    CSCap *cap = [CSCap capWithUrn:key
                             title:@"Extract Metadata"
                           command:@"extract-metadata"
                       description:nil
                          metadata:@{}
                        mediaSpecs:@{}
                         arguments:arguments
                            output:nil
                      acceptsStdin:NO
                      metadataJSON:nil];

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
                @"urn": @"cap:op=extract;target=metadata",
                @"title": @"Extract Metadata",
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
    XCTAssertEqualObjects([cap urnString], @"cap:op=extract;target=metadata");
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
    CSCapUrn *key1 = [CSCapUrn fromString:@"cap:op=extract;target=metadata" error:&error];
    XCTAssertNotNil(key1, @"Failed to create cap URN: %@", error);

    CSCapUrn *key2 = [CSCapUrn fromString:@"cap:op=extract;target=outline" error:&error];
    XCTAssertNotNil(key2, @"Failed to create cap URN: %@", error);

    CSCapArguments *arguments = [CSCapArguments arguments];

    CSCap *cap1 = [CSCap capWithUrn:key1
                             title:@"Extract Metadata"
                           command:@"extract-metadata"
                       description:nil
                          metadata:@{}
                        mediaSpecs:@{}
                         arguments:arguments
                            output:nil
                      acceptsStdin:NO
                      metadataJSON:nil];

    CSCap *cap2 = [CSCap capWithUrn:key2
                             title:@"Extract Outline"
                           command:@"extract-outline"
                       description:nil
                          metadata:@{@"supports_outline": @"true"}
                        mediaSpecs:@{}
                         arguments:arguments
                            output:nil
                      acceptsStdin:NO
                      metadataJSON:nil];

    CSCapManifest *manifest = [CSCapManifest manifestWithName:@"MultiCapComponent"
                                                                     version:@"1.0.0"
                                                                 description:@"Component with multiple caps"
                                                                caps:@[cap1, cap2]];

    XCTAssertEqual(manifest.caps.count, 2);
    XCTAssertEqualObjects([manifest.caps[0] urnString], @"cap:op=extract;target=metadata");
    XCTAssertEqualObjects([manifest.caps[1] urnString], @"cap:op=extract;target=outline");
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
    CSCapUrn *key = [CSCapUrn fromString:@"cap:op=validate;type=file" error:&error];
    XCTAssertNotNil(key, @"Failed to create cap URN: %@", error);

    CSCapArguments *arguments = [CSCapArguments arguments];
    CSCap *cap = [CSCap capWithUrn:key
                             title:@"Validate"
                           command:@"validate"
                       description:nil
                          metadata:@{}
                        mediaSpecs:@{}
                         arguments:arguments
                            output:nil
                      acceptsStdin:NO
                      metadataJSON:nil];

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
                @"urn": @"cap:op=validate;type=file",
                @"title": @"Validate",
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
    CSCapUrn *key = [CSCapUrn fromString:@"cap:op=process" error:&error];
    XCTAssertNotNil(key, @"Failed to create cap URN: %@", error);

    CSCapArguments *arguments = [CSCapArguments arguments];
    CSCap *cap = [CSCap capWithUrn:key
                             title:@"Process"
                           command:@"process"
                       description:nil
                          metadata:@{}
                        mediaSpecs:@{}
                         arguments:arguments
                            output:nil
                      acceptsStdin:NO
                      metadataJSON:nil];

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
    XCTAssertEqualObjects([pluginStyleManifest.caps.firstObject urnString],
                         [providerStyleManifest.caps.firstObject urnString]);
}

- (void)testArgumentCreationWithNewAPI {
    // Test creating arguments with the new mediaSpec API
    CSCapArgument *stringArg = [CSCapArgument argumentWithName:@"input"
                                                     mediaSpec:CSSpecIdStr
                                                 argDescription:@"Input text"
                                                       cliFlag:@"--input"
                                                      position:@0
                                                    validation:nil
                                                  defaultValue:nil];

    XCTAssertNotNil(stringArg);
    XCTAssertEqualObjects(stringArg.name, @"input");
    XCTAssertEqualObjects(stringArg.mediaSpec, CSSpecIdStr);
    XCTAssertEqualObjects(stringArg.cliFlag, @"--input");
    XCTAssertEqualObjects(stringArg.position, @0);

    // Test with integer spec
    CSCapArgument *intArg = [CSCapArgument argumentWithName:@"count"
                                                  mediaSpec:CSSpecIdInt
                                              argDescription:@"Count value"
                                                    cliFlag:@"--count"
                                                   position:nil
                                                 validation:nil
                                               defaultValue:@10];

    XCTAssertNotNil(intArg);
    XCTAssertEqualObjects(intArg.mediaSpec, CSSpecIdInt);
    XCTAssertEqualObjects(intArg.defaultValue, @10);

    // Test with object spec
    CSCapArgument *objArg = [CSCapArgument argumentWithName:@"data"
                                                  mediaSpec:CSSpecIdObj
                                              argDescription:@"JSON data"
                                                    cliFlag:@"--data"
                                                   position:nil
                                                 validation:nil
                                               defaultValue:nil];

    XCTAssertNotNil(objArg);
    XCTAssertEqualObjects(objArg.mediaSpec, CSSpecIdObj);
}

- (void)testOutputCreationWithNewAPI {
    // Test creating output with the new mediaSpec API
    CSCapOutput *output = [CSCapOutput outputWithMediaSpec:CSSpecIdObj
                                                validation:nil
                                         outputDescription:@"JSON output"];

    XCTAssertNotNil(output);
    XCTAssertEqualObjects(output.mediaSpec, CSSpecIdObj);
    XCTAssertEqualObjects(output.outputDescription, @"JSON output");

    // Test with custom spec ID
    CSCapOutput *customOutput = [CSCapOutput outputWithMediaSpec:@"my:custom-output.v1"
                                                      validation:nil
                                               outputDescription:@"Custom output"];

    XCTAssertNotNil(customOutput);
    XCTAssertEqualObjects(customOutput.mediaSpec, @"my:custom-output.v1");
}

@end

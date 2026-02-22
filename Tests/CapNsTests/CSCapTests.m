//
//  CSCapTests.m
//  CapNsTests
//
//  NOTE: All ArgumentType/OutputType enums have been removed.
//  Arguments and outputs now use mediaUrn fields containing media URNs
//  (e.g., "media:string") that resolve via the mediaSpecs table.
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
    CSCapUrn *key = [CSCapUrn fromString:@"cap:in=media:void;op=transform;out=\"media:form=map;textable\";format=json;data_processing" error:&error];
    XCTAssertNotNil(key, @"Failed to create cap URN: %@", error);

    NSArray<CSCapArg *> *args = @[];
    CSCap *cap = [CSCap capWithUrn:key
                             title:@"Test Cap"
                           command:@"test-command"
                       description:nil
                          metadata:@{}
                        mediaSpecs:@[]
                         args:args
                            output:nil
                      metadataJSON:nil];

    XCTAssertNotNil(cap);
    // URN tags are sorted alphabetically - flags sort with key=value pairs by key name
    // data_processing (flag) sorts before format=json
    XCTAssertEqualObjects([cap urnString], @"cap:data_processing;format=json;in=media:void;op=transform;out=\"media:form=map;textable\"");
    XCTAssertEqualObjects(cap.command, @"test-command");
    XCTAssertNil([cap getStdinMediaUrn], @"stdinType should be nil when not specified");
}

- (void)testCapWithDescription {
    NSError *error;
    CSCapUrn *key = [CSCapUrn fromString:@"cap:in=media:void;op=parse;out=\"media:form=map;textable\";format=json;data" error:&error];
    XCTAssertNotNil(key, @"Failed to create cap URN: %@", error);

    NSArray<CSCapArg *> *args = @[];
    CSCap *cap = [CSCap capWithUrn:key
                             title:@"Parse JSON"
                           command:@"parse-cmd"
                       description:@"Parse JSON data"
                          metadata:@{}
                        mediaSpecs:@[]
                         args:args
                            output:nil
                      metadataJSON:nil];

    XCTAssertNotNil(cap);
    XCTAssertEqualObjects(cap.capDescription, @"Parse JSON data");
    XCTAssertNil([cap getStdinMediaUrn], @"stdinType should be nil when not specified");
}

- (void)testCapStdinType {
    NSError *error;
    CSCapUrn *key = [CSCapUrn fromString:@"cap:in=media:void;op=generate;out=\"media:form=map;textable\";target=embeddings" error:&error];
    XCTAssertNotNil(key, @"Failed to create cap URN: %@", error);

    // Test with stdin = nil (does not accept stdin)
    CSCap *cap1 = [CSCap capWithUrn:key
                              title:@"Generate"
                            command:@"generate"
                        description:@"Generate embeddings"
                           metadata:@{}
                         mediaSpecs:@[]
                          args:@[]
                             output:nil
                       metadataJSON:nil];

    XCTAssertNotNil(cap1);
    XCTAssertNil([cap1 getStdinMediaUrn], @"stdinType should be nil when not set");
    XCTAssertFalse([cap1 acceptsStdin], @"Cap should not accept stdin when no stdin source is defined");

    // Test with stdin = media type (accepts stdin) - encoded as arg with stdin source
    NSString *stdinMediaType = @"media:textable";
    CSArgSource *stdinSource = [CSArgSource stdinSourceWithMediaUrn:stdinMediaType];
    CSCapArg *stdinArg = [CSCapArg argWithMediaUrn:stdinMediaType
                                          required:YES
                                           sources:@[stdinSource]];
    CSCap *cap2 = [CSCap capWithUrn:key
                              title:@"Generate"
                            command:@"generate"
                        description:@"Generate embeddings"
                           metadata:@{}
                         mediaSpecs:@[]
                               args:@[stdinArg]
                             output:nil
                       metadataJSON:nil];

    XCTAssertNotNil(cap2);
    XCTAssertNotNil([cap2 getStdinMediaUrn], @"stdinType should be set");
    XCTAssertEqualObjects([cap2 getStdinMediaUrn], stdinMediaType, @"stdinType should match the set value");
    XCTAssertTrue([cap2 acceptsStdin], @"Cap should accept stdin");
}

- (void)testCapMatching {
    NSError *error;
    // Use type=data_processing key=value for proper matching tests
    CSCapUrn *key = [CSCapUrn fromString:@"cap:in=media:void;op=transform;out=\"media:form=map;textable\";format=json;type=data_processing" error:&error];
    XCTAssertNotNil(key, @"Failed to create cap URN: %@", error);

    NSArray<CSCapArg *> *args = @[];
    CSCap *cap = [CSCap capWithUrn:key
                             title:@"Transform"
                           command:@"test-command"
                       description:nil
                          metadata:@{}
                        mediaSpecs:@[]
                         args:args
                            output:nil
                      metadataJSON:nil];

    // URN tags are sorted alphabetically
    XCTAssertTrue([cap acceptsRequest:@"cap:format=json;in=media:void;op=transform;out=\"media:form=map;textable\";type=data_processing"]);
    XCTAssertTrue([cap acceptsRequest:@"cap:format=*;in=media:void;op=transform;out=\"media:form=map;textable\";type=data_processing"]); // Request wants any format, cap handles json specifically
    XCTAssertTrue([cap acceptsRequest:@"cap:in=media:void;out=\"media:form=map;textable\";type=data_processing"]);
    XCTAssertFalse([cap acceptsRequest:@"cap:in=media:void;out=\"media:form=map;textable\";type=compute"]);
}

- (void)testCapStdinSerialization {
    NSError *error;
    CSCapUrn *key = [CSCapUrn fromString:@"cap:in=media:void;op=generate;out=\"media:form=map;textable\";target=embeddings" error:&error];
    XCTAssertNotNil(key, @"Failed to create cap URN: %@", error);

    NSString *stdinMediaType = @"media:textable";

    // Test copying preserves stdin - encoded as arg with stdin source
    CSArgSource *stdinSource = [CSArgSource stdinSourceWithMediaUrn:stdinMediaType];
    CSCapArg *stdinArg = [CSCapArg argWithMediaUrn:stdinMediaType
                                          required:YES
                                           sources:@[stdinSource]];
    CSCap *original = [CSCap capWithUrn:key
                                  title:@"Generate"
                                command:@"generate"
                            description:@"Generate embeddings"
                               metadata:@{@"model": @"sentence-transformer"}
                             mediaSpecs:@[]
                                   args:@[stdinArg]
                                 output:nil
                           metadataJSON:nil];

    CSCap *copied = [original copy];
    XCTAssertNotNil(copied);
    XCTAssertEqualObjects([original getStdinMediaUrn], [copied getStdinMediaUrn]);
    XCTAssertEqualObjects([copied getStdinMediaUrn], stdinMediaType);
    XCTAssertNotNil([copied getStdinMediaUrn], @"stdinType should be preserved after copy");
}

- (void)testCanonicalDictionaryDeserialization {
    // Test CSCap.capWithDictionary with new args format (stdin is part of arg sources)
    NSString *stdinMediaType = @"media:pdf";
    NSDictionary *capDict = @{
        @"urn": @"cap:in=media:void;op=extract;out=\"media:form=map;textable\";target=metadata",
        @"title": @"Extract Metadata",
        @"command": @"extract-metadata",
        @"cap_description": @"Extract metadata from documents",
        @"metadata": @{@"ext": @"json"},
        @"args": @[
            @{
                @"media_urn": @"media:file-path;textable;form=scalar",
                @"required": @YES,
                @"sources": @[
                    @{@"stdin": stdinMediaType},
                    @{@"position": @0}
                ],
                @"arg_description": @"Path to the document file"
            }
        ]
    };

    NSError *error;
    CSCap *cap = [CSCap capWithDictionary:capDict error:&error];

    XCTAssertNil(error, @"Dictionary deserialization should not fail: %@", error.localizedDescription);
    XCTAssertNotNil(cap, @"Cap should be created from dictionary");
    XCTAssertEqualObjects([cap urnString], @"cap:in=media:void;op=extract;out=\"media:form=map;textable\";target=metadata");
    XCTAssertEqualObjects(cap.command, @"extract-metadata");
    XCTAssertEqualObjects(cap.capDescription, @"Extract metadata from documents");
    XCTAssertNotNil([cap getStdinMediaUrn], @"stdinType should be set when arg has stdin source");
    XCTAssertEqualObjects([cap getStdinMediaUrn], stdinMediaType, @"stdinType should match stdin source value");

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
    // Test CSCapArg.argWithDictionary with media_urn format
    NSDictionary *argDict = @{
        @"media_urn": CSMediaString,
        @"required": @YES,
        @"sources": @[
            @{@"position": @0},
            @{@"cli_flag": @"--file_path"}
        ],
        @"arg_description": @"Path to file"
    };

    NSError *error;
    CSCapArg *arg = [CSCapArg argWithDictionary:argDict error:&error];

    XCTAssertNil(error, @"Argument dictionary deserialization should not fail: %@", error.localizedDescription);
    XCTAssertNotNil(arg, @"Argument should be created from dictionary");
    XCTAssertEqualObjects(arg.mediaUrn, CSMediaString);  // Verify spec ID
    XCTAssertTrue(arg.required, @"Should be a required argument");
    XCTAssertNotNil([arg getPosition], @"Should have position source");
    XCTAssertEqualObjects([arg getPosition], @0);
    XCTAssertEqualObjects([arg getCliFlag], @"--file_path");
}

- (void)testCanonicalOutputDeserialization {
    // Test CSCapOutput.outputWithDictionary with media_urn format
    NSDictionary *outputDict = @{
        @"media_urn": CSMediaObject,
        @"output_description": @"JSON metadata object"
    };

    NSError *error;
    CSCapOutput *output = [CSCapOutput outputWithDictionary:outputDict error:&error];

    XCTAssertNil(error, @"Output dictionary deserialization should not fail: %@", error.localizedDescription);
    XCTAssertNotNil(output, @"Output should be created from dictionary");
    XCTAssertEqualObjects(output.mediaUrn, CSMediaObject);  // Verify spec ID
    XCTAssertEqualObjects(output.outputDescription, @"JSON metadata object");
}

- (void)testCanonicalValidationDeserialization {
    // Test CSMediaValidation.validationWithDictionary
    NSDictionary *validationDict = @{
        @"min_length": @1,
        @"max_length": @255,
        @"pattern": @"^[^\\0]+$",
        @"allowed_values": @[@"json", @"xml", @"yaml"]
    };

    NSError *error;
    CSMediaValidation *validation = [CSMediaValidation validationWithDictionary:validationDict error:&error];

    XCTAssertNil(error, @"Validation dictionary deserialization should not fail: %@", error.localizedDescription);
    XCTAssertNotNil(validation, @"Validation should be created from dictionary");
    XCTAssertEqualObjects(validation.minLength, @1);
    XCTAssertEqualObjects(validation.maxLength, @255);
    XCTAssertEqualObjects(validation.pattern, @"^[^\\0]+$");
    XCTAssertEqualObjects(validation.allowedValues, (@[@"json", @"xml", @"yaml"]));
}

- (void)testCompleteCapDeserialization {
    // Test a complete cap with all nested structures using new args format
    NSString *stdinMediaType = @"media:json;textable;form=map";
    NSDictionary *completeCapDict = @{
        @"urn": @"cap:in=media:void;op=transform;out=\"media:form=map;textable\";format=json;data",
        @"title": @"Transform Data",
        @"command": @"transform-data",
        @"cap_description": @"Transform JSON data with validation",
        @"metadata": @{@"engine": @"jq", @"performance": @"high"},
        @"media_specs": @[
            @{
                @"urn": @"my:output.v1",
                @"media_type": @"application/json",
                @"profile_uri": @"https://capns.org/schema/transform-output"
            }
        ],
        @"args": @[
            @{
                @"media_urn": CSMediaString,
                @"required": @YES,
                @"sources": @[
                    @{@"stdin": stdinMediaType},
                    @{@"position": @0}
                ],
                @"arg_description": @"JQ transformation expression",
                @"validation": @{
                    @"min_length": @1,
                    @"max_length": @1000
                }
            },
            @{
                @"media_urn": CSMediaString,
                @"required": @NO,
                @"sources": @[
                    @{@"cli_flag": @"--ext"}
                ],
                @"arg_description": @"Output format",
                @"default_value": @"json",
                @"validation": @{
                    @"allowed_values": @[@"json", @"yaml", @"xml"]
                }
            }
        ],
        @"output": @{
            @"media_urn": @"my:output.v1",
            @"output_description": @"Transformed data"
        }
    };

    NSError *error;
    CSCap *cap = [CSCap capWithDictionary:completeCapDict error:&error];

    XCTAssertNil(error, @"Complete cap deserialization should not fail: %@", error.localizedDescription);
    XCTAssertNotNil(cap, @"Complete cap should be created");

    // Verify basic properties - URN tags are sorted alphabetically
    // Flags sort with key=value pairs by key name: data (flag) < format
    XCTAssertEqualObjects([cap urnString], @"cap:data;format=json;in=media:void;op=transform;out=\"media:form=map;textable\"");
    XCTAssertEqualObjects(cap.command, @"transform-data");
    XCTAssertNotNil([cap getStdinMediaUrn], @"stdinType should be set");
    XCTAssertEqualObjects([cap getStdinMediaUrn], stdinMediaType);

    // Verify metadata
    XCTAssertEqualObjects(cap.metadata[@"engine"], @"jq");
    XCTAssertEqualObjects(cap.metadata[@"performance"], @"high");

    // Verify media_specs (array format)
    XCTAssertEqual(cap.mediaSpecs.count, 1);
    XCTAssertEqualObjects(cap.mediaSpecs[0][@"urn"], @"my:output.v1");

    // Verify arguments
    XCTAssertEqual([cap getRequiredArgs].count, 1);
    XCTAssertEqual([cap getOptionalArgs].count, 1);

    CSCapArg *requiredArg = [cap getRequiredArgs].firstObject;
    XCTAssertEqualObjects(requiredArg.mediaUrn, CSMediaString);

    CSCapArg *optionalArg = [cap getOptionalArgs].firstObject;
    XCTAssertEqualObjects(optionalArg.mediaUrn, CSMediaString);

    // Verify output
    XCTAssertNotNil(cap.output);
    XCTAssertEqualObjects(cap.output.mediaUrn, @"my:output.v1");
}

- (void)testMediaSpecsResolution {
    // Test that spec IDs can be resolved from the mediaSpecs array
    NSError *error;
    CSCapUrn *key = [CSCapUrn fromString:@"cap:in=media:void;op=test;out=\"media:form=map;textable\"" error:&error];
    XCTAssertNotNil(key);

    NSArray<NSDictionary *> *mediaSpecs = @[
        @{
            @"urn": @"my:custom-output.v1",
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
        @{
            @"urn": @"my:text-input.v1",
            @"media_type": @"text/plain",
            @"profile_uri": @"https://example.com/schema/text-input"
        },
        @{
            @"urn": CSMediaString,
            @"media_type": @"text/plain",
            @"profile_uri": @"https://capns.org/schema/string"
        }
    ];

    CSCap *cap = [CSCap capWithUrn:key
                             title:@"Test"
                           command:@"test"
                       description:nil
                          metadata:@{}
                        mediaSpecs:mediaSpecs
                         args:@[]
                            output:nil
                      metadataJSON:nil];

    // Resolve custom spec ID
    CSMediaSpec *resolved = [cap resolveSpecId:@"my:custom-output.v1" error:&error];
    XCTAssertNotNil(resolved, @"Should resolve custom spec ID from mediaSpecs: %@", error);
    XCTAssertEqualObjects(resolved.contentType, @"application/json");
    XCTAssertNotNil(resolved.schema);

    // Resolve object-form spec
    CSMediaSpec *resolvedText = [cap resolveSpecId:@"my:text-input.v1" error:&error];
    XCTAssertNotNil(resolvedText, @"Should resolve spec ID: %@", error);
    XCTAssertEqualObjects(resolvedText.contentType, @"text/plain");

    // Resolve media URN from mediaSpecs (no built-in resolution)
    CSMediaSpec *resolvedFromArray = [cap resolveSpecId:CSMediaString error:&error];
    XCTAssertNotNil(resolvedFromArray, @"Should resolve media URN from mediaSpecs: %@", error);
    XCTAssertEqualObjects(resolvedFromArray.contentType, @"text/plain");

    // Fail on unknown spec ID
    CSMediaSpec *unknown = [cap resolveSpecId:@"unknown:spec.v1" error:&error];
    XCTAssertNil(unknown, @"Should fail on unknown spec ID");
    XCTAssertNotNil(error, @"Should set error for unknown spec ID");
}

// MARK: - Cap Manifest Tests

- (void)testCapManifestCreation {
    NSError *error;
    CSCapUrn *key = [CSCapUrn fromString:@"cap:in=media:void;op=extract;out=\"media:form=map;textable\";target=metadata" error:&error];
    XCTAssertNotNil(key, @"Failed to create cap URN: %@", error);

    NSArray<CSCapArg *> *args = @[];
    CSCap *cap = [CSCap capWithUrn:key
                             title:@"Extract Metadata"
                           command:@"extract-metadata"
                       description:nil
                          metadata:@{}
                        mediaSpecs:@[]
                         args:args
                            output:nil
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
    CSCapUrn *key = [CSCapUrn fromString:@"cap:in=media:void;op=extract;out=\"media:form=map;textable\";target=metadata" error:&error];
    XCTAssertNotNil(key, @"Failed to create cap URN: %@", error);

    NSArray<CSCapArg *> *args = @[];
    CSCap *cap = [CSCap capWithUrn:key
                             title:@"Extract Metadata"
                           command:@"extract-metadata"
                       description:nil
                          metadata:@{}
                        mediaSpecs:@[]
                         args:args
                            output:nil
                      metadataJSON:nil];

    CSCapManifest *manifest = [[CSCapManifest manifestWithName:@"TestComponent"
                                                                      version:@"0.1.0"
                                                                  description:@"A test component for validation"
                                                                 caps:@[cap]]
                                      withAuthor:@"Test Author"];

    XCTAssertEqualObjects(manifest.author, @"Test Author");
}

- (void)testCapManifestWithPageUrl {
    NSError *error;
    CSCapUrn *key = [CSCapUrn fromString:@"cap:in=media:void;op=extract;out=\"media:form=map;textable\";target=metadata" error:&error];
    XCTAssertNotNil(key, @"Failed to create cap URN: %@", error);

    NSArray<CSCapArg *> *args = @[];
    CSCap *cap = [CSCap capWithUrn:key
                             title:@"Extract Metadata"
                           command:@"extract-metadata"
                       description:nil
                          metadata:@{}
                        mediaSpecs:@[]
                         args:args
                            output:nil
                      metadataJSON:nil];

    CSCapManifest *manifest = [[[CSCapManifest manifestWithName:@"TestComponent"
                                                                       version:@"0.1.0"
                                                                   description:@"A test component for validation"
                                                                  caps:@[cap]]
                                       withAuthor:@"Test Author"]
                                       withPageUrl:@"https://github.com/example/test"];

    XCTAssertEqualObjects(manifest.author, @"Test Author");
    XCTAssertEqualObjects(manifest.pageUrl, @"https://github.com/example/test");
}

- (void)testCapManifestDictionaryDeserialization {
    NSString *stdinMediaType = @"media:pdf";
    NSDictionary *manifestDict = @{
        @"name": @"TestComponent",
        @"version": @"0.1.0",
        @"description": @"A test component for validation",
        @"author": @"Test Author",
        @"page_url": @"https://github.com/example/test",
        @"caps": @[
            @{
                @"urn": @"cap:in=media:void;op=extract;out=\"media:form=map;textable\";target=metadata",
                @"title": @"Extract Metadata",
                @"command": @"extract-metadata",
                @"args": @[
                    @{
                        @"media_urn": @"media:file-path;textable;form=scalar",
                        @"required": @YES,
                        @"sources": @[
                            @{@"stdin": stdinMediaType},
                            @{@"position": @0}
                        ],
                        @"arg_description": @"Path to the document file"
                    }
                ]
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
    XCTAssertEqualObjects(manifest.pageUrl, @"https://github.com/example/test");
    XCTAssertEqual(manifest.caps.count, 1);

    CSCap *cap = manifest.caps.firstObject;
    XCTAssertEqualObjects([cap urnString], @"cap:in=media:void;op=extract;out=\"media:form=map;textable\";target=metadata");
    XCTAssertNotNil([cap getStdinMediaUrn], @"stdinType should be set from arg with stdin source");
    XCTAssertEqualObjects([cap getStdinMediaUrn], stdinMediaType);
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
    CSCapUrn *key1 = [CSCapUrn fromString:@"cap:in=media:void;op=extract;out=\"media:form=map;textable\";target=metadata" error:&error];
    XCTAssertNotNil(key1, @"Failed to create cap URN: %@", error);

    CSCapUrn *key2 = [CSCapUrn fromString:@"cap:in=media:void;op=extract;out=\"media:form=map;textable\";target=outline" error:&error];
    XCTAssertNotNil(key2, @"Failed to create cap URN: %@", error);

    NSArray<CSCapArg *> *args = @[];

    CSCap *cap1 = [CSCap capWithUrn:key1
                             title:@"Extract Metadata"
                           command:@"extract-metadata"
                       description:nil
                          metadata:@{}
                        mediaSpecs:@[]
                         args:args
                            output:nil
                      metadataJSON:nil];

    CSCap *cap2 = [CSCap capWithUrn:key2
                             title:@"Extract Outline"
                           command:@"extract-outline"
                       description:nil
                          metadata:@{@"supports_outline": @"true"}
                        mediaSpecs:@[]
                         args:args
                            output:nil
                      metadataJSON:nil];

    CSCapManifest *manifest = [CSCapManifest manifestWithName:@"MultiCapComponent"
                                                                     version:@"1.0.0"
                                                                 description:@"Component with multiple caps"
                                                                caps:@[cap1, cap2]];

    XCTAssertEqual(manifest.caps.count, 2);
    XCTAssertEqualObjects([manifest.caps[0] urnString], @"cap:in=media:void;op=extract;out=\"media:form=map;textable\";target=metadata");
    XCTAssertEqualObjects([manifest.caps[1] urnString], @"cap:in=media:void;op=extract;out=\"media:form=map;textable\";target=outline");
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
    CSCapUrn *key = [CSCapUrn fromString:@"cap:in=media:void;op=validate;out=\"media:form=map;textable\";file" error:&error];
    XCTAssertNotNil(key, @"Failed to create cap URN: %@", error);

    NSArray<CSCapArg *> *args = @[];
    CSCap *cap = [CSCap capWithUrn:key
                             title:@"Validate"
                           command:@"validate"
                       description:nil
                          metadata:@{}
                        mediaSpecs:@[]
                         args:args
                            output:nil
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
                @"urn": @"cap:in=media:void;op=validate;out=\"media:form=map;textable\";file",
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
    CSCapUrn *key = [CSCapUrn fromString:@"cap:in=media:void;op=process;out=\"media:form=map;textable\"" error:&error];
    XCTAssertNotNil(key, @"Failed to create cap URN: %@", error);

    NSArray<CSCapArg *> *args = @[];
    CSCap *cap = [CSCap capWithUrn:key
                             title:@"Process"
                           command:@"process"
                       description:nil
                          metadata:@{}
                        mediaSpecs:@[]
                         args:args
                            output:nil
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
    // Test creating arguments with the new CSCapArg API
    CSArgSource *positionSource = [CSArgSource positionSource:0];
    CSArgSource *cliFlagSource = [CSArgSource cliFlagSource:@"--input"];
    CSCapArg *stringArg = [CSCapArg argWithMediaUrn:CSMediaString
                                           required:YES
                                            sources:@[positionSource, cliFlagSource]
                                     argDescription:@"Input text"
                                       defaultValue:nil];

    XCTAssertNotNil(stringArg);
    XCTAssertEqualObjects(stringArg.mediaUrn, CSMediaString);
    XCTAssertEqualObjects([stringArg getCliFlag], @"--input");
    XCTAssertEqualObjects([stringArg getPosition], @0);

    // Test with integer spec
    CSCapArg *intArg = [CSCapArg argWithMediaUrn:CSMediaInteger
                                        required:NO
                                         sources:@[[CSArgSource cliFlagSource:@"--count"]]
                                  argDescription:@"Count value"
                                    defaultValue:@10];

    XCTAssertNotNil(intArg);
    XCTAssertEqualObjects(intArg.mediaUrn, CSMediaInteger);
    XCTAssertEqualObjects(intArg.defaultValue, @10);

    // Test with object spec
    CSCapArg *objArg = [CSCapArg argWithMediaUrn:CSMediaObject
                                        required:YES
                                         sources:@[[CSArgSource cliFlagSource:@"--data"]]
                                  argDescription:@"JSON data"
                                    defaultValue:nil];

    XCTAssertNotNil(objArg);
    XCTAssertEqualObjects(objArg.mediaUrn, CSMediaObject);
}

- (void)testOutputCreationWithNewAPI {
    // Test creating output with the new mediaUrn API
    CSCapOutput *output = [CSCapOutput outputWithMediaUrn:CSMediaObject
                                        outputDescription:@"JSON output"];

    XCTAssertNotNil(output);
    XCTAssertEqualObjects(output.mediaUrn, CSMediaObject);
    XCTAssertEqualObjects(output.outputDescription, @"JSON output");

    // Test with custom spec ID
    CSCapOutput *customOutput = [CSCapOutput outputWithMediaUrn:@"my:custom-output.v1"
                                              outputDescription:@"Custom output"];

    XCTAssertNotNil(customOutput);
    XCTAssertEqualObjects(customOutput.mediaUrn, @"my:custom-output.v1");
}

@end

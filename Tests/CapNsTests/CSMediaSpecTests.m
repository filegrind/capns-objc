//
//  CSMediaSpecTests.m
//  Tests for CSMediaSpec metadata propagation
//

#import <XCTest/XCTest.h>
#import "CSMediaSpec.h"

@interface CSMediaSpecTests : XCTestCase
@end

@implementation CSMediaSpecTests

- (void)testMetadataPropagationFromObjectDef {
    // Create a media spec definition with metadata
    NSArray<NSDictionary *> *mediaSpecs = @[
        @{
            @"urn": @"media:custom-setting;setting",
            @"media_type": @"text/plain",
            @"profile_uri": @"https://example.com/schema",
            @"title": @"Custom Setting",
            @"description": @"A custom setting",
            @"metadata": @{
                @"category_key": @"interface",
                @"ui_type": @"SETTING_UI_TYPE_CHECKBOX",
                @"subcategory_key": @"appearance",
                @"display_index": @5
            }
        }
    ];

    NSError *error = nil;
    CSMediaSpec *resolved = CSResolveMediaUrn(@"media:custom-setting;setting", mediaSpecs, &error);

    XCTAssertNil(error, @"Should not have error");
    XCTAssertNotNil(resolved, @"Should resolve successfully");
    XCTAssertNotNil(resolved.metadata, @"Should have metadata");
    XCTAssertEqualObjects(resolved.metadata[@"category_key"], @"interface", @"Should have category_key");
    XCTAssertEqualObjects(resolved.metadata[@"ui_type"], @"SETTING_UI_TYPE_CHECKBOX", @"Should have ui_type");
    XCTAssertEqualObjects(resolved.metadata[@"subcategory_key"], @"appearance", @"Should have subcategory_key");
    XCTAssertEqualObjects(resolved.metadata[@"display_index"], @5, @"Should have display_index");
}

- (void)testMetadataNilByDefault {
    // Media specs without metadata field should have nil metadata
    NSArray<NSDictionary *> *mediaSpecs = @[
        @{
            @"urn": CSMediaString,
            @"media_type": @"text/plain",
            @"profile_uri": @"https://capns.org/schema/string"
        }
    ];

    NSError *error = nil;
    CSMediaSpec *resolved = CSResolveMediaUrn(CSMediaString, mediaSpecs, &error);

    XCTAssertNil(error, @"Should not have error");
    XCTAssertNotNil(resolved, @"Should resolve successfully");
    XCTAssertNil(resolved.metadata, @"Should have nil metadata when not provided");
}

- (void)testMetadataWithValidation {
    // Ensure metadata and validation can coexist
    NSArray<NSDictionary *> *mediaSpecs = @[
        @{
            @"urn": @"media:bounded-number;numeric;setting",
            @"media_type": @"text/plain",
            @"profile_uri": @"https://example.com/schema",
            @"title": @"Bounded Number",
            @"validation": @{
                @"min": @0,
                @"max": @100
            },
            @"metadata": @{
                @"category_key": @"inference",
                @"ui_type": @"SETTING_UI_TYPE_SLIDER"
            }
        }
    ];

    NSError *error = nil;
    CSMediaSpec *resolved = CSResolveMediaUrn(@"media:bounded-number;numeric;setting", mediaSpecs, &error);

    XCTAssertNil(error, @"Should not have error");
    XCTAssertNotNil(resolved, @"Should resolve successfully");

    // Verify validation
    XCTAssertNotNil(resolved.validation, @"Should have validation");
    XCTAssertEqualObjects(resolved.validation.min, @0, @"Should have min validation");
    XCTAssertEqualObjects(resolved.validation.max, @100, @"Should have max validation");

    // Verify metadata
    XCTAssertNotNil(resolved.metadata, @"Should have metadata");
    XCTAssertEqualObjects(resolved.metadata[@"category_key"], @"inference", @"Should have category_key");
    XCTAssertEqualObjects(resolved.metadata[@"ui_type"], @"SETTING_UI_TYPE_SLIDER", @"Should have ui_type");
}

- (void)testResolveMediaUrnNotFound {
    // Should fail hard for unknown media URNs
    NSError *error = nil;
    CSMediaSpec *resolved = CSResolveMediaUrn(@"media:unknown;type", @[], &error);

    XCTAssertNotNil(error, @"Should have error for unknown media URN");
    XCTAssertNil(resolved, @"Should not resolve unknown media URN");
    XCTAssertEqual(error.code, CSMediaSpecErrorUnresolvableMediaUrn, @"Should be UNRESOLVABLE_MEDIA_URN error");
}

// Extension field tests

- (void)testExtensionPropagationFromObjectDef {
    // Create a media spec definition with extension
    NSArray<NSDictionary *> *mediaSpecs = @[
        @{
            @"urn": @"media:pdf;bytes",
            @"media_type": @"application/pdf",
            @"profile_uri": @"https://capns.org/schema/pdf",
            @"title": @"PDF Document",
            @"description": @"A PDF document",
            @"extension": @"pdf"
        }
    ];

    NSError *error = nil;
    CSMediaSpec *resolved = CSResolveMediaUrn(@"media:pdf;bytes", mediaSpecs, &error);

    XCTAssertNil(error, @"Should not have error");
    XCTAssertNotNil(resolved, @"Should resolve successfully");
    XCTAssertEqualObjects(resolved.extension, @"pdf", @"Should have extension");
}

- (void)testExtensionEmptyWhenNotSet {
    // Media specs without extension field should have nil extension
    NSArray<NSDictionary *> *mediaSpecs = @[
        @{
            @"urn": @"media:text;textable",
            @"media_type": @"text/plain",
            @"profile_uri": @"https://example.com"
        }
    ];

    NSError *error = nil;
    CSMediaSpec *resolved = CSResolveMediaUrn(@"media:text;textable", mediaSpecs, &error);

    XCTAssertNil(error, @"Should not have error");
    XCTAssertNotNil(resolved, @"Should resolve successfully");
    XCTAssertNil(resolved.extension, @"Should have nil extension when not provided");
}

- (void)testExtensionWithMetadataAndValidation {
    // Ensure extension, metadata, and validation can coexist
    NSArray<NSDictionary *> *mediaSpecs = @[
        @{
            @"urn": @"media:custom-output",
            @"media_type": @"application/json",
            @"profile_uri": @"https://example.com/schema",
            @"title": @"Custom Output",
            @"validation": @{
                @"min_length": @1,
                @"max_length": @1000
            },
            @"metadata": @{
                @"category": @"output"
            },
            @"extension": @"json"
        }
    ];

    NSError *error = nil;
    CSMediaSpec *resolved = CSResolveMediaUrn(@"media:custom-output", mediaSpecs, &error);

    XCTAssertNil(error, @"Should not have error");
    XCTAssertNotNil(resolved, @"Should resolve successfully");

    // Verify all fields are present
    XCTAssertNotNil(resolved.validation, @"Should have validation");
    XCTAssertNotNil(resolved.metadata, @"Should have metadata");
    XCTAssertEqualObjects(resolved.extension, @"json", @"Should have extension");
}

// Duplicate URN validation tests

- (void)testValidateNoMediaSpecDuplicatesPass {
    // No duplicates should pass
    NSArray<NSDictionary *> *mediaSpecs = @[
        @{@"urn": @"media:text;textable", @"media_type": @"text/plain"},
        @{@"urn": @"media:json;textable", @"media_type": @"application/json"}
    ];

    NSError *error = nil;
    BOOL result = CSValidateNoMediaSpecDuplicates(mediaSpecs, &error);

    XCTAssertTrue(result, @"Should pass validation with no duplicates");
    XCTAssertNil(error, @"Should have no error");
}

- (void)testValidateNoMediaSpecDuplicatesFail {
    // Duplicates should fail
    NSArray<NSDictionary *> *mediaSpecs = @[
        @{@"urn": @"media:text;textable", @"media_type": @"text/plain"},
        @{@"urn": @"media:json;textable", @"media_type": @"application/json"},
        @{@"urn": @"media:text;textable", @"media_type": @"text/html"}  // Duplicate URN
    ];

    NSError *error = nil;
    BOOL result = CSValidateNoMediaSpecDuplicates(mediaSpecs, &error);

    XCTAssertFalse(result, @"Should fail validation with duplicates");
    XCTAssertNotNil(error, @"Should have error");
    XCTAssertEqual(error.code, CSMediaSpecErrorDuplicateMediaUrn, @"Should be DUPLICATE_MEDIA_URN error");
    XCTAssertTrue([error.localizedDescription containsString:@"media:text;textable"], @"Error should mention the duplicate URN");
}

- (void)testValidateNoMediaSpecDuplicatesEmpty {
    // Empty array should pass
    NSError *error = nil;
    BOOL result = CSValidateNoMediaSpecDuplicates(@[], &error);

    XCTAssertTrue(result, @"Should pass validation with empty array");
    XCTAssertNil(error, @"Should have no error");
}

- (void)testValidateNoMediaSpecDuplicatesNil {
    // Nil array should pass
    NSError *error = nil;
    BOOL result = CSValidateNoMediaSpecDuplicates(nil, &error);

    XCTAssertTrue(result, @"Should pass validation with nil array");
    XCTAssertNil(error, @"Should have no error");
}

@end

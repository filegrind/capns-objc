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
            @"profile_uri": @"https://capdag.com/schema/string"
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

// Extensions field tests

- (void)testExtensionsPropagationFromObjectDef {
    // Create a media spec definition with extensions array
    NSArray<NSDictionary *> *mediaSpecs = @[
        @{
            @"urn": @"media:pdf",
            @"media_type": @"application/pdf",
            @"profile_uri": @"https://capdag.com/schema/pdf",
            @"title": @"PDF Document",
            @"description": @"A PDF document",
            @"extensions": @[@"pdf"]
        }
    ];

    NSError *error = nil;
    CSMediaSpec *resolved = CSResolveMediaUrn(@"media:pdf", mediaSpecs, &error);

    XCTAssertNil(error, @"Should not have error");
    XCTAssertNotNil(resolved, @"Should resolve successfully");
    XCTAssertNotNil(resolved.extensions, @"Should have extensions array");
    XCTAssertEqual(resolved.extensions.count, 1, @"Should have one extension");
    XCTAssertEqualObjects(resolved.extensions[0], @"pdf", @"Should have pdf extension");
}

- (void)testExtensionsEmptyWhenNotSet {
    // Media specs without extensions field should have empty array
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
    XCTAssertNotNil(resolved.extensions, @"Extensions should not be nil");
    XCTAssertEqual(resolved.extensions.count, 0, @"Should have empty extensions array when not provided");
}

- (void)testExtensionsWithMetadataAndValidation {
    // Ensure extensions, metadata, and validation can coexist
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
            @"extensions": @[@"json"]
        }
    ];

    NSError *error = nil;
    CSMediaSpec *resolved = CSResolveMediaUrn(@"media:custom-output", mediaSpecs, &error);

    XCTAssertNil(error, @"Should not have error");
    XCTAssertNotNil(resolved, @"Should resolve successfully");

    // Verify all fields are present
    XCTAssertNotNil(resolved.validation, @"Should have validation");
    XCTAssertNotNil(resolved.metadata, @"Should have metadata");
    XCTAssertEqual(resolved.extensions.count, 1, @"Should have one extension");
    XCTAssertEqualObjects(resolved.extensions[0], @"json", @"Should have json extension");
}

- (void)testMultipleExtensions {
    // Test multiple extensions in a media spec
    NSArray<NSDictionary *> *mediaSpecs = @[
        @{
            @"urn": @"media:image;jpeg",
            @"media_type": @"image/jpeg",
            @"profile_uri": @"https://capdag.com/schema/jpeg",
            @"title": @"JPEG Image",
            @"description": @"JPEG image data",
            @"extensions": @[@"jpg", @"jpeg"]
        }
    ];

    NSError *error = nil;
    CSMediaSpec *resolved = CSResolveMediaUrn(@"media:image;jpeg", mediaSpecs, &error);

    XCTAssertNil(error, @"Should not have error");
    XCTAssertNotNil(resolved, @"Should resolve successfully");
    XCTAssertNotNil(resolved.extensions, @"Should have extensions array");
    XCTAssertEqual(resolved.extensions.count, 2, @"Should have two extensions");
    XCTAssertEqualObjects(resolved.extensions[0], @"jpg", @"Should have jpg extension first");
    XCTAssertEqualObjects(resolved.extensions[1], @"jpeg", @"Should have jpeg extension second");
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

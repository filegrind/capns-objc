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
    NSDictionary *mediaSpecs = @{
        @"media:custom-setting;setting": @{
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
    };

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

- (void)testMetadataNoneForStringDef {
    // String form definitions should have no metadata
    NSDictionary *mediaSpecs = @{
        @"media:simple;textable": @"text/plain; profile=https://example.com"
    };

    NSError *error = nil;
    CSMediaSpec *resolved = CSResolveMediaUrn(@"media:simple;textable", mediaSpecs, &error);

    XCTAssertNil(error, @"Should not have error");
    XCTAssertNotNil(resolved, @"Should resolve successfully");
    XCTAssertNil(resolved.metadata, @"String form should have no metadata");
}

- (void)testMetadataNoneForBuiltin {
    // Media URNs resolved from string-form definitions should have no metadata
    // (Built-in resolution removed - all URNs must be in mediaSpecs table)
    NSDictionary *mediaSpecs = @{
        CSMediaString: @"text/plain; profile=https://capns.org/schema/string"
    };

    NSError *error = nil;
    CSMediaSpec *resolved = CSResolveMediaUrn(CSMediaString, mediaSpecs, &error);

    XCTAssertNil(error, @"Should not have error");
    XCTAssertNotNil(resolved, @"Should resolve successfully");
    XCTAssertNil(resolved.metadata, @"String-form definition should have no metadata");
}

- (void)testMetadataWithValidation {
    // Ensure metadata and validation can coexist
    NSDictionary *mediaSpecs = @{
        @"media:bounded-number;numeric;setting": @{
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
    };

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
    CSMediaSpec *resolved = CSResolveMediaUrn(@"media:unknown;type", @{}, &error);

    XCTAssertNotNil(error, @"Should have error for unknown media URN");
    XCTAssertNil(resolved, @"Should not resolve unknown media URN");
    XCTAssertEqual(error.code, CSMediaSpecErrorUnresolvableMediaUrn, @"Should be UNRESOLVABLE_MEDIA_URN error");
}

// Extension field tests

- (void)testExtensionPropagationFromObjectDef {
    // Create a media spec definition with extension
    NSDictionary *mediaSpecs = @{
        @"media:pdf;bytes": @{
            @"media_type": @"application/pdf",
            @"profile_uri": @"https://capns.org/schema/pdf",
            @"title": @"PDF Document",
            @"description": @"A PDF document",
            @"extension": @"pdf"
        }
    };

    NSError *error = nil;
    CSMediaSpec *resolved = CSResolveMediaUrn(@"media:pdf;bytes", mediaSpecs, &error);

    XCTAssertNil(error, @"Should not have error");
    XCTAssertNotNil(resolved, @"Should resolve successfully");
    XCTAssertEqualObjects(resolved.extension, @"pdf", @"Should have extension");
}

- (void)testExtensionNoneForStringDef {
    // String form definitions should have no extension
    NSDictionary *mediaSpecs = @{
        @"media:text;textable": @"text/plain; profile=https://example.com"
    };

    NSError *error = nil;
    CSMediaSpec *resolved = CSResolveMediaUrn(@"media:text;textable", mediaSpecs, &error);

    XCTAssertNil(error, @"Should not have error");
    XCTAssertNotNil(resolved, @"Should resolve successfully");
    XCTAssertNil(resolved.extension, @"String form should have no extension");
}

- (void)testExtensionWithMetadataAndValidation {
    // Ensure extension, metadata, and validation can coexist
    NSDictionary *mediaSpecs = @{
        @"media:custom-output": @{
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
    };

    NSError *error = nil;
    CSMediaSpec *resolved = CSResolveMediaUrn(@"media:custom-output", mediaSpecs, &error);

    XCTAssertNil(error, @"Should not have error");
    XCTAssertNotNil(resolved, @"Should resolve successfully");

    // Verify all fields are present
    XCTAssertNotNil(resolved.validation, @"Should have validation");
    XCTAssertNotNil(resolved.metadata, @"Should have metadata");
    XCTAssertEqualObjects(resolved.extension, @"json", @"Should have extension");
}

@end

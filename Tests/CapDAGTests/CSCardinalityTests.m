//
//  CSCardinalityTests.m
//  CapDAGTests
//
//  Tests for cardinality and shape analysis — mirrors Rust planner/cardinality.rs
//

#import <XCTest/XCTest.h>
@import CapDAG;

@interface CSCardinalityTests : XCTestCase
@end

@implementation CSCardinalityTests

// ==================== InputCardinality Tests ====================

// TEST684: Tests InputCardinality correctly identifies single-value media URNs
// Verifies that URNs without list marker are parsed as Single cardinality
- (void)test684_from_media_urn_single {
    XCTAssertEqual(CSInputCardinalityFromMediaUrn(@"media:pdf"), CSInputCardinalitySingle);
    XCTAssertEqual(CSInputCardinalityFromMediaUrn(@"media:textable"), CSInputCardinalitySingle);
    XCTAssertEqual(CSInputCardinalityFromMediaUrn(@"media:integer"), CSInputCardinalitySingle);
    // Record marker doesn't affect cardinality
    XCTAssertEqual(CSInputCardinalityFromMediaUrn(@"media:record;textable"), CSInputCardinalitySingle);
}

// TEST685: Tests InputCardinality correctly identifies list/vector media URNs
// Verifies that URNs with list marker tag are parsed as Sequence cardinality
- (void)test685_from_media_urn_vector {
    XCTAssertEqual(CSInputCardinalityFromMediaUrn(@"media:pdf;list"), CSInputCardinalitySequence);
    XCTAssertEqual(CSInputCardinalityFromMediaUrn(@"media:list;png"), CSInputCardinalitySequence);
    XCTAssertEqual(CSInputCardinalityFromMediaUrn(@"media:disbound-pages;list;textable"), CSInputCardinalitySequence);
    // List of records
    XCTAssertEqual(CSInputCardinalityFromMediaUrn(@"media:json;list;record;textable"), CSInputCardinalitySequence);
}

// TEST686: Tests that list marker tag position doesn't affect vector detection
// Verifies cardinality parsing is independent of tag order in URN
- (void)test686_from_media_urn_vector_tag_position {
    XCTAssertEqual(CSInputCardinalityFromMediaUrn(@"media:pdf;list"), CSInputCardinalitySequence);
    XCTAssertEqual(CSInputCardinalityFromMediaUrn(@"media:list;pdf"), CSInputCardinalitySequence);
}

// TEST687: Tests that URN content doesn't cause false positive vector detection
// Verifies that "list" in media type name doesn't trigger Sequence cardinality
- (void)test687_from_media_urn_no_false_positives {
    // "list-data" is a tag with value "data", not a marker
    XCTAssertEqual(CSInputCardinalityFromMediaUrn(@"media:list-data=something"), CSInputCardinalitySingle);
    XCTAssertEqual(CSInputCardinalityFromMediaUrn(@"media:sequence-data"), CSInputCardinalitySingle);
}

// TEST688: Tests is_multiple method correctly identifies multi-value cardinalities
// Verifies Single returns false while Sequence and AtLeastOne return true
- (void)test688_is_multiple {
    XCTAssertFalse(CSInputCardinalityIsMultiple(CSInputCardinalitySingle));
    XCTAssertTrue(CSInputCardinalityIsMultiple(CSInputCardinalitySequence));
    XCTAssertTrue(CSInputCardinalityIsMultiple(CSInputCardinalityAtLeastOne));
}

// TEST689: Tests accepts_single method identifies cardinalities that accept single values
// Verifies Single and AtLeastOne accept singles while Sequence does not
- (void)test689_accepts_single {
    XCTAssertTrue(CSInputCardinalityAcceptsSingle(CSInputCardinalitySingle));
    XCTAssertFalse(CSInputCardinalityAcceptsSingle(CSInputCardinalitySequence));
    XCTAssertTrue(CSInputCardinalityAcceptsSingle(CSInputCardinalityAtLeastOne));
}

// ==================== Compatibility Tests ====================

// TEST690: Tests cardinality compatibility for single-to-single data flow
// Verifies Direct compatibility when both input and output are Single
- (void)test690_compatibility_single_to_single {
    XCTAssertEqual(CSInputCardinalityIsCompatibleWith(CSInputCardinalitySingle, CSInputCardinalitySingle),
                   CSCardinalityCompatibilityDirect);
}

// TEST691: Tests cardinality compatibility when wrapping single value into array
// Verifies WrapInArray compatibility when Sequence expects Single input
- (void)test691_compatibility_single_to_vector {
    XCTAssertEqual(CSInputCardinalityIsCompatibleWith(CSInputCardinalitySequence, CSInputCardinalitySingle),
                   CSCardinalityCompatibilityWrapInArray);
}

// TEST692: Tests cardinality compatibility when unwrapping array to singles
// Verifies RequiresFanOut compatibility when Single expects Sequence input
- (void)test692_compatibility_vector_to_single {
    XCTAssertEqual(CSInputCardinalityIsCompatibleWith(CSInputCardinalitySingle, CSInputCardinalitySequence),
                   CSCardinalityCompatibilityRequiresFanOut);
}

// TEST693: Tests cardinality compatibility for sequence-to-sequence data flow
// Verifies Direct compatibility when both input and output are Sequence
- (void)test693_compatibility_vector_to_vector {
    XCTAssertEqual(CSInputCardinalityIsCompatibleWith(CSInputCardinalitySequence, CSInputCardinalitySequence),
                   CSCardinalityCompatibilityDirect);
}

// ==================== URN Manipulation Tests ====================

// TEST694: Tests applying Sequence cardinality adds list marker to URN
// Verifies that apply_to_urn correctly modifies URN to indicate list
- (void)test694_apply_to_urn_add_vector {
    NSString *result = CSInputCardinalityApplyToUrn(CSInputCardinalitySequence, @"media:pdf");
    // URN tags are alphabetized, so list comes first
    XCTAssertEqualObjects(result, @"media:list;pdf");
}

// TEST695: Tests applying Single cardinality removes list marker from URN
// Verifies that apply_to_urn correctly strips list marker
- (void)test695_apply_to_urn_remove_vector {
    NSString *result = CSInputCardinalityApplyToUrn(CSInputCardinalitySingle, @"media:list;pdf");
    XCTAssertEqualObjects(result, @"media:pdf");
}

// TEST696: Tests apply_to_urn is idempotent when URN already matches cardinality
// Verifies that URN remains unchanged when cardinality already matches desired
- (void)test696_apply_to_urn_no_change_needed {
    XCTAssertEqualObjects(CSInputCardinalityApplyToUrn(CSInputCardinalitySingle, @"media:pdf"), @"media:pdf");
    XCTAssertEqualObjects(CSInputCardinalityApplyToUrn(CSInputCardinalitySequence, @"media:list;pdf"), @"media:list;pdf");
}

// ==================== CapCardinalityInfo Cardinality Pattern Tests ====================

// TEST697: Tests CapCardinalityInfo correctly identifies one-to-one pattern
// Verifies Single input and Single output result in OneToOne pattern
- (void)test697_cap_shape_info_one_to_one {
    CSCapShapeInfo *info = [CSCapShapeInfo fromCapUrn:@"cap:test" inSpec:@"media:pdf" outSpec:@"media:png"];
    XCTAssertEqual(info.input.cardinality, CSInputCardinalitySingle);
    XCTAssertEqual(info.output.cardinality, CSInputCardinalitySingle);
    XCTAssertEqual([info cardinalityPattern], CSCardinalityPatternOneToOne);
}

// TEST698: Tests CapCardinalityInfo correctly identifies one-to-many pattern
// Verifies Single input and Sequence output result in OneToMany pattern
- (void)test698_cap_shape_info_one_to_many {
    CSCapShapeInfo *info = [CSCapShapeInfo fromCapUrn:@"cap:pdf-to-pages" inSpec:@"media:pdf" outSpec:@"media:list;png"];
    XCTAssertEqual(info.input.cardinality, CSInputCardinalitySingle);
    XCTAssertEqual(info.output.cardinality, CSInputCardinalitySequence);
    XCTAssertEqual([info cardinalityPattern], CSCardinalityPatternOneToMany);
}

// TEST699: Tests CapCardinalityInfo correctly identifies many-to-one pattern
// Verifies Sequence input and Single output result in ManyToOne pattern
- (void)test699_cap_shape_info_many_to_one {
    CSCapShapeInfo *info = [CSCapShapeInfo fromCapUrn:@"cap:merge-pdfs" inSpec:@"media:list;pdf" outSpec:@"media:pdf"];
    XCTAssertEqual(info.input.cardinality, CSInputCardinalitySequence);
    XCTAssertEqual(info.output.cardinality, CSInputCardinalitySingle);
    XCTAssertEqual([info cardinalityPattern], CSCardinalityPatternManyToOne);
}

// ==================== CardinalityPattern Tests ====================

// TEST709: Tests CardinalityPattern correctly identifies patterns that produce vectors
// Verifies OneToMany and ManyToMany return true, others return false
- (void)test709_pattern_produces_vector {
    XCTAssertFalse(CSCardinalityPatternProducesVector(CSCardinalityPatternOneToOne));
    XCTAssertTrue(CSCardinalityPatternProducesVector(CSCardinalityPatternOneToMany));
    XCTAssertFalse(CSCardinalityPatternProducesVector(CSCardinalityPatternManyToOne));
    XCTAssertTrue(CSCardinalityPatternProducesVector(CSCardinalityPatternManyToMany));
}

// TEST710: Tests CardinalityPattern correctly identifies patterns that require vectors
// Verifies ManyToOne and ManyToMany return true, others return false
- (void)test710_pattern_requires_vector {
    XCTAssertFalse(CSCardinalityPatternRequiresVector(CSCardinalityPatternOneToOne));
    XCTAssertFalse(CSCardinalityPatternRequiresVector(CSCardinalityPatternOneToMany));
    XCTAssertTrue(CSCardinalityPatternRequiresVector(CSCardinalityPatternManyToOne));
    XCTAssertTrue(CSCardinalityPatternRequiresVector(CSCardinalityPatternManyToMany));
}

// ==================== Shape Chain Analysis Tests ====================

// TEST711: Tests shape chain analysis for simple linear one-to-one capability chains
// Verifies chains with no fan-out are valid and require no transformation
- (void)test711_shape_chain_analysis_simple_linear {
    NSArray *infos = @[
        [CSCapShapeInfo fromCapUrn:@"cap:pdf-to-png" inSpec:@"media:pdf" outSpec:@"media:png"],
        [CSCapShapeInfo fromCapUrn:@"cap:resize" inSpec:@"media:png" outSpec:@"media:png"],
    ];
    CSShapeChainAnalysis *analysis = [CSShapeChainAnalysis analyze:infos];
    XCTAssertTrue(analysis.isValid);
    XCTAssertEqual(analysis.fanOutPoints.count, 0);
    XCTAssertFalse([analysis requiresTransformation]);
}

// TEST712: Tests shape chain analysis detects fan-out points in capability chains
// Verifies chains with one-to-many transitions are marked for transformation
- (void)test712_shape_chain_analysis_with_fan_out {
    NSArray *infos = @[
        [CSCapShapeInfo fromCapUrn:@"cap:pdf-to-pages" inSpec:@"media:pdf" outSpec:@"media:list;png"],
        [CSCapShapeInfo fromCapUrn:@"cap:thumbnail" inSpec:@"media:png" outSpec:@"media:png"],
    ];
    CSShapeChainAnalysis *analysis = [CSShapeChainAnalysis analyze:infos];
    XCTAssertTrue(analysis.isValid);
    XCTAssertEqualObjects(analysis.fanOutPoints, (@[@1]));
    XCTAssertTrue([analysis requiresTransformation]);
}

// TEST713: Tests shape chain analysis handles empty capability chains correctly
// Verifies empty chains are valid and require no transformation
- (void)test713_shape_chain_analysis_empty {
    CSShapeChainAnalysis *analysis = [CSShapeChainAnalysis analyze:@[]];
    XCTAssertTrue(analysis.isValid);
    XCTAssertFalse([analysis requiresTransformation]);
}

// ==================== Serialization Tests ====================
// TEST714 and TEST715 test JSON serialization which is Rust/serde-specific.
// ObjC does not serialize these enums to JSON, so we test string representation instead.

// TEST714: Tests InputCardinality enum values are distinct and stable
- (void)test714_cardinality_enum_values {
    XCTAssertNotEqual(CSInputCardinalitySingle, CSInputCardinalitySequence);
    XCTAssertNotEqual(CSInputCardinalitySingle, CSInputCardinalityAtLeastOne);
    XCTAssertNotEqual(CSInputCardinalitySequence, CSInputCardinalityAtLeastOne);
}

// TEST715: Tests CardinalityPattern enum values are distinct and stable
- (void)test715_pattern_enum_values {
    XCTAssertNotEqual(CSCardinalityPatternOneToOne, CSCardinalityPatternOneToMany);
    XCTAssertNotEqual(CSCardinalityPatternOneToOne, CSCardinalityPatternManyToOne);
    XCTAssertNotEqual(CSCardinalityPatternOneToOne, CSCardinalityPatternManyToMany);
}

// ==================== InputStructure Tests ====================

// TEST720: Tests InputStructure correctly identifies opaque media URNs
// Verifies that URNs without record marker are parsed as Opaque
- (void)test720_from_media_urn_opaque {
    XCTAssertEqual(CSInputStructureFromMediaUrn(@"media:pdf"), CSInputStructureOpaque);
    XCTAssertEqual(CSInputStructureFromMediaUrn(@"media:textable"), CSInputStructureOpaque);
    XCTAssertEqual(CSInputStructureFromMediaUrn(@"media:integer"), CSInputStructureOpaque);
    // List marker doesn't affect structure
    XCTAssertEqual(CSInputStructureFromMediaUrn(@"media:file-path;list"), CSInputStructureOpaque);
}

// TEST721: Tests InputStructure correctly identifies record media URNs
// Verifies that URNs with record marker tag are parsed as Record
- (void)test721_from_media_urn_record {
    XCTAssertEqual(CSInputStructureFromMediaUrn(@"media:json;record"), CSInputStructureRecord);
    XCTAssertEqual(CSInputStructureFromMediaUrn(@"media:record;textable"), CSInputStructureRecord);
    XCTAssertEqual(CSInputStructureFromMediaUrn(@"media:file-metadata;record;textable"), CSInputStructureRecord);
    // List of records
    XCTAssertEqual(CSInputStructureFromMediaUrn(@"media:json;list;record"), CSInputStructureRecord);
}

// TEST722: Tests structure compatibility for opaque-to-opaque data flow
- (void)test722_structure_compatibility_opaque_to_opaque {
    XCTAssertEqual(CSInputStructureIsCompatibleWith(CSInputStructureOpaque, CSInputStructureOpaque),
                   CSStructureCompatibilityDirect);
}

// TEST723: Tests structure compatibility for record-to-record data flow
- (void)test723_structure_compatibility_record_to_record {
    XCTAssertEqual(CSInputStructureIsCompatibleWith(CSInputStructureRecord, CSInputStructureRecord),
                   CSStructureCompatibilityDirect);
}

// TEST724: Tests structure incompatibility for opaque-to-record flow
- (void)test724_structure_incompatibility_opaque_to_record {
    XCTAssertEqual(CSInputStructureIsCompatibleWith(CSInputStructureRecord, CSInputStructureOpaque),
                   CSStructureCompatibilityIncompatible);
}

// TEST725: Tests structure incompatibility for record-to-opaque flow
- (void)test725_structure_incompatibility_record_to_opaque {
    XCTAssertEqual(CSInputStructureIsCompatibleWith(CSInputStructureOpaque, CSInputStructureRecord),
                   CSStructureCompatibilityIncompatible);
}

// TEST726: Tests applying Record structure adds record marker to URN
- (void)test726_apply_structure_add_record {
    NSString *result = CSInputStructureApplyToUrn(CSInputStructureRecord, @"media:json");
    XCTAssertTrue([result containsString:@"record"]);
}

// TEST727: Tests applying Opaque structure removes record marker from URN
- (void)test727_apply_structure_remove_record {
    NSString *result = CSInputStructureApplyToUrn(CSInputStructureOpaque, @"media:json;record");
    XCTAssertFalse([result containsString:@"record"]);
}

// ==================== MediaShape Tests ====================

// TEST730: Tests MediaShape correctly parses all four combinations
- (void)test730_media_shape_from_urn_all_combinations {
    // Scalar opaque (default)
    CSMediaShape *shape = [CSMediaShape fromMediaUrn:@"media:textable"];
    XCTAssertEqual(shape.cardinality, CSInputCardinalitySingle);
    XCTAssertEqual(shape.structure, CSInputStructureOpaque);

    // Scalar record
    shape = [CSMediaShape fromMediaUrn:@"media:json;record"];
    XCTAssertEqual(shape.cardinality, CSInputCardinalitySingle);
    XCTAssertEqual(shape.structure, CSInputStructureRecord);

    // List opaque
    shape = [CSMediaShape fromMediaUrn:@"media:file-path;list"];
    XCTAssertEqual(shape.cardinality, CSInputCardinalitySequence);
    XCTAssertEqual(shape.structure, CSInputStructureOpaque);

    // List record
    shape = [CSMediaShape fromMediaUrn:@"media:json;list;record"];
    XCTAssertEqual(shape.cardinality, CSInputCardinalitySequence);
    XCTAssertEqual(shape.structure, CSInputStructureRecord);
}

// TEST731: Tests MediaShape compatibility for matching shapes
- (void)test731_media_shape_compatible_direct {
    CSMediaShape *scalarOpaque = [CSMediaShape scalarOpaque];
    CSMediaShape *scalarRecord = [CSMediaShape scalarRecord];
    CSMediaShape *listOpaque = [CSMediaShape listOpaque];
    CSMediaShape *listRecord = [CSMediaShape listRecord];

    // Same shape = Direct
    XCTAssertEqual(CSMediaShapeIsCompatibleWith(scalarOpaque, scalarOpaque), CSShapeCompatibilityDirect);
    XCTAssertEqual(CSMediaShapeIsCompatibleWith(scalarRecord, scalarRecord), CSShapeCompatibilityDirect);
    XCTAssertEqual(CSMediaShapeIsCompatibleWith(listOpaque, listOpaque), CSShapeCompatibilityDirect);
    XCTAssertEqual(CSMediaShapeIsCompatibleWith(listRecord, listRecord), CSShapeCompatibilityDirect);
}

// TEST732: Tests MediaShape compatibility for cardinality changes with matching structure
- (void)test732_media_shape_cardinality_changes {
    CSMediaShape *scalarOpaque = [CSMediaShape scalarOpaque];
    CSMediaShape *listOpaque = [CSMediaShape listOpaque];
    CSMediaShape *scalarRecord = [CSMediaShape scalarRecord];
    CSMediaShape *listRecord = [CSMediaShape listRecord];

    // Scalar to list (same structure) = WrapInArray
    XCTAssertEqual(CSMediaShapeIsCompatibleWith(listOpaque, scalarOpaque), CSShapeCompatibilityWrapInArray);
    XCTAssertEqual(CSMediaShapeIsCompatibleWith(listRecord, scalarRecord), CSShapeCompatibilityWrapInArray);

    // List to scalar (same structure) = RequiresFanOut
    XCTAssertEqual(CSMediaShapeIsCompatibleWith(scalarOpaque, listOpaque), CSShapeCompatibilityRequiresFanOut);
    XCTAssertEqual(CSMediaShapeIsCompatibleWith(scalarRecord, listRecord), CSShapeCompatibilityRequiresFanOut);
}

// TEST733: Tests MediaShape incompatibility when structures don't match
- (void)test733_media_shape_structure_mismatch {
    CSMediaShape *scalarOpaque = [CSMediaShape scalarOpaque];
    CSMediaShape *scalarRecord = [CSMediaShape scalarRecord];
    CSMediaShape *listOpaque = [CSMediaShape listOpaque];
    CSMediaShape *listRecord = [CSMediaShape listRecord];

    // Structure mismatch = Incompatible (regardless of cardinality)
    XCTAssertEqual(CSMediaShapeIsCompatibleWith(scalarRecord, scalarOpaque), CSShapeCompatibilityIncompatible);
    XCTAssertEqual(CSMediaShapeIsCompatibleWith(scalarOpaque, scalarRecord), CSShapeCompatibilityIncompatible);
    XCTAssertEqual(CSMediaShapeIsCompatibleWith(listRecord, listOpaque), CSShapeCompatibilityIncompatible);
    XCTAssertEqual(CSMediaShapeIsCompatibleWith(listOpaque, listRecord), CSShapeCompatibilityIncompatible);

    // Cross cardinality + structure mismatch
    XCTAssertEqual(CSMediaShapeIsCompatibleWith(listRecord, scalarOpaque), CSShapeCompatibilityIncompatible);
    XCTAssertEqual(CSMediaShapeIsCompatibleWith(scalarOpaque, listRecord), CSShapeCompatibilityIncompatible);
}

// ==================== CapShapeInfo Tests ====================

// TEST740: Tests CapShapeInfo correctly parses cap specs
- (void)test740_cap_shape_info_from_specs {
    CSCapShapeInfo *info = [CSCapShapeInfo fromCapUrn:@"cap:test"
                                              inSpec:@"media:textable"
                                             outSpec:@"media:json;record"];
    XCTAssertEqual(info.input.cardinality, CSInputCardinalitySingle);
    XCTAssertEqual(info.input.structure, CSInputStructureOpaque);
    XCTAssertEqual(info.output.cardinality, CSInputCardinalitySingle);
    XCTAssertEqual(info.output.structure, CSInputStructureRecord);
}

// TEST741: Tests CapShapeInfo pattern detection
- (void)test741_cap_shape_info_pattern {
    CSCapShapeInfo *oneToMany = [CSCapShapeInfo fromCapUrn:@"cap:disbind"
                                                   inSpec:@"media:pdf"
                                                  outSpec:@"media:disbound-page;list;textable"];
    XCTAssertEqual([oneToMany cardinalityPattern], CSCardinalityPatternOneToMany);
}

// ==================== ShapeChainAnalysis Tests ====================

// TEST750: Tests shape chain analysis for valid chain with matching structures
- (void)test750_shape_chain_valid {
    NSArray *infos = @[
        [CSCapShapeInfo fromCapUrn:@"cap:resize" inSpec:@"media:png" outSpec:@"media:png"],
        [CSCapShapeInfo fromCapUrn:@"cap:compress" inSpec:@"media:png" outSpec:@"media:png"],
    ];
    CSShapeChainAnalysis *analysis = [CSShapeChainAnalysis analyze:infos];
    XCTAssertTrue(analysis.isValid);
    XCTAssertNil(analysis.error);
}

// TEST751: Tests shape chain analysis detects structure mismatch
- (void)test751_shape_chain_structure_mismatch {
    NSArray *infos = @[
        [CSCapShapeInfo fromCapUrn:@"cap:extract" inSpec:@"media:pdf" outSpec:@"media:textable"],
        // This cap expects record but gets opaque - should fail
        [CSCapShapeInfo fromCapUrn:@"cap:parse" inSpec:@"media:json;record" outSpec:@"media:data;record"],
    ];
    CSShapeChainAnalysis *analysis = [CSShapeChainAnalysis analyze:infos];
    XCTAssertFalse(analysis.isValid);
    XCTAssertNotNil(analysis.error);
    XCTAssertTrue([analysis.error containsString:@"Shape mismatch"]);
}

// TEST752: Tests shape chain analysis with fan-out (matching structures)
- (void)test752_shape_chain_with_fanout {
    NSArray *infos = @[
        [CSCapShapeInfo fromCapUrn:@"cap:disbind" inSpec:@"media:pdf" outSpec:@"media:page;list;textable"],
        [CSCapShapeInfo fromCapUrn:@"cap:process" inSpec:@"media:textable" outSpec:@"media:result;textable"],
    ];
    CSShapeChainAnalysis *analysis = [CSShapeChainAnalysis analyze:infos];
    XCTAssertTrue(analysis.isValid);
    XCTAssertTrue([analysis requiresTransformation]);
    XCTAssertEqualObjects(analysis.fanOutPoints, (@[@1]));
}

// TEST753: Tests shape chain analysis correctly handles list-to-list record flow
- (void)test753_shape_chain_list_record_to_list_record {
    NSArray *infos = @[
        [CSCapShapeInfo fromCapUrn:@"cap:parse_csv"
                            inSpec:@"media:csv;textable"
                           outSpec:@"media:json;list;record"],
        [CSCapShapeInfo fromCapUrn:@"cap:transform"
                            inSpec:@"media:json;list;record"
                           outSpec:@"media:result;list;record"],
    ];
    CSShapeChainAnalysis *analysis = [CSShapeChainAnalysis analyze:infos];
    XCTAssertTrue(analysis.isValid);
    XCTAssertFalse([analysis requiresTransformation]);
}

@end

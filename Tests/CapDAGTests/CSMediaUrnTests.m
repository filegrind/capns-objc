//
//  CSMediaUrnTests.m
//  Tests for CSMediaUrn withList/withoutList/lub and predicates
//

#import <XCTest/XCTest.h>
#import "CapDAG.h"

@interface CSMediaUrnTests : XCTestCase
@end

@implementation CSMediaUrnTests

#pragma mark - withList / withoutList

// TEST850: with_list adds list marker, without_list removes it
- (void)test850_with_list_without_list {
    NSError *error;
    CSMediaUrn *pdf = [CSMediaUrn fromString:@"media:pdf" error:&error];
    XCTAssertNotNil(pdf);
    XCTAssertTrue([pdf isScalar]);
    XCTAssertFalse([pdf isList]);

    CSMediaUrn *pdfList = [pdf withList];
    XCTAssertTrue([pdfList isList]);
    XCTAssertFalse([pdfList isScalar]);
    // The list URN should still conform to scalar pattern
    XCTAssertTrue([pdfList conformsTo:pdf], @"list version should still conform to scalar pattern");

    CSMediaUrn *backToScalar = [pdfList withoutList];
    XCTAssertTrue([backToScalar isScalar]);
    XCTAssertTrue([backToScalar isEquivalentTo:pdf], @"removing list should restore original");
}

// TEST851: with_list is idempotent
- (void)test851_with_list_idempotent {
    NSError *error;
    CSMediaUrn *listUrn = [CSMediaUrn fromString:@"media:json;list;textable" error:&error];
    XCTAssertNotNil(listUrn);
    XCTAssertTrue([listUrn isList]);

    CSMediaUrn *doubleList = [listUrn withList];
    XCTAssertTrue([doubleList isList]);
    XCTAssertTrue([doubleList isEquivalentTo:listUrn], @"adding list to already-list should be no-op");
}

#pragma mark - Least Upper Bound (LUB)

// TEST852: LUB of identical URNs returns the same URN
- (void)test852_lub_identical {
    NSError *error;
    CSMediaUrn *pdf = [CSMediaUrn fromString:@"media:pdf" error:&error];
    XCTAssertNotNil(pdf);
    CSMediaUrn *lub = [CSMediaUrn lub:@[pdf, pdf]];
    XCTAssertTrue([lub isEquivalentTo:pdf]);
}

// TEST853: LUB of URNs with no common tags returns media: (universal)
- (void)test853_lub_no_common_tags {
    NSError *error;
    CSMediaUrn *pdf = [CSMediaUrn fromString:@"media:pdf" error:&error];
    CSMediaUrn *png = [CSMediaUrn fromString:@"media:png" error:&error];
    XCTAssertNotNil(pdf);
    XCTAssertNotNil(png);
    CSMediaUrn *lub = [CSMediaUrn lub:@[pdf, png]];
    CSMediaUrn *universal = [CSMediaUrn fromString:@"media:" error:&error];
    XCTAssertNotNil(universal);
    XCTAssertTrue([lub isEquivalentTo:universal],
        @"LUB of pdf and png should be media: but got %@", [lub toString]);
}

// TEST854: LUB keeps common tags, drops differing ones
- (void)test854_lub_partial_overlap {
    NSError *error;
    CSMediaUrn *jsonText = [CSMediaUrn fromString:@"media:json;textable" error:&error];
    CSMediaUrn *csvText = [CSMediaUrn fromString:@"media:csv;textable" error:&error];
    XCTAssertNotNil(jsonText);
    XCTAssertNotNil(csvText);
    CSMediaUrn *lub = [CSMediaUrn lub:@[jsonText, csvText]];
    CSMediaUrn *expected = [CSMediaUrn fromString:@"media:textable" error:&error];
    XCTAssertNotNil(expected);
    XCTAssertTrue([lub isEquivalentTo:expected],
        @"LUB should be media:textable but got %@", [lub toString]);
}

// TEST855: LUB of list and non-list drops list tag
- (void)test855_lub_list_vs_scalar {
    NSError *error;
    CSMediaUrn *jsonList = [CSMediaUrn fromString:@"media:json;list;textable" error:&error];
    CSMediaUrn *jsonScalar = [CSMediaUrn fromString:@"media:json;textable" error:&error];
    XCTAssertNotNil(jsonList);
    XCTAssertNotNil(jsonScalar);
    CSMediaUrn *lub = [CSMediaUrn lub:@[jsonList, jsonScalar]];
    CSMediaUrn *expected = [CSMediaUrn fromString:@"media:json;textable" error:&error];
    XCTAssertNotNil(expected);
    XCTAssertTrue([lub isEquivalentTo:expected],
        @"LUB should drop list tag, got %@", [lub toString]);
}

// TEST856: LUB of empty input returns universal type
- (void)test856_lub_empty {
    NSError *error;
    CSMediaUrn *lub = [CSMediaUrn lub:@[]];
    CSMediaUrn *universal = [CSMediaUrn fromString:@"media:" error:&error];
    XCTAssertNotNil(universal);
    XCTAssertTrue([lub isEquivalentTo:universal]);
}

// TEST857: LUB of single input returns that input
- (void)test857_lub_single {
    NSError *error;
    CSMediaUrn *pdf = [CSMediaUrn fromString:@"media:pdf" error:&error];
    XCTAssertNotNil(pdf);
    CSMediaUrn *lub = [CSMediaUrn lub:@[pdf]];
    XCTAssertTrue([lub isEquivalentTo:pdf]);
}

// TEST858: LUB with three+ inputs narrows correctly
- (void)test858_lub_three_inputs {
    NSError *error;
    CSMediaUrn *a = [CSMediaUrn fromString:@"media:json;list;record;textable" error:&error];
    CSMediaUrn *b = [CSMediaUrn fromString:@"media:csv;list;record;textable" error:&error];
    CSMediaUrn *c = [CSMediaUrn fromString:@"media:ndjson;list;textable" error:&error];
    XCTAssertNotNil(a);
    XCTAssertNotNil(b);
    XCTAssertNotNil(c);
    CSMediaUrn *lub = [CSMediaUrn lub:@[a, b, c]];
    CSMediaUrn *expected = [CSMediaUrn fromString:@"media:list;textable" error:&error];
    XCTAssertNotNil(expected);
    XCTAssertTrue([lub isEquivalentTo:expected],
        @"LUB should be media:list;textable but got %@", [lub toString]);
}

// TEST859: LUB with valued tags (non-marker) that differ
- (void)test859_lub_valued_tags {
    NSError *error;
    CSMediaUrn *v1 = [CSMediaUrn fromString:@"media:image;format=png" error:&error];
    CSMediaUrn *v2 = [CSMediaUrn fromString:@"media:image;format=jpeg" error:&error];
    XCTAssertNotNil(v1);
    XCTAssertNotNil(v2);
    CSMediaUrn *lub = [CSMediaUrn lub:@[v1, v2]];
    CSMediaUrn *expected = [CSMediaUrn fromString:@"media:image" error:&error];
    XCTAssertNotNil(expected);
    XCTAssertTrue([lub isEquivalentTo:expected],
        @"LUB should drop conflicting format tag, got %@", [lub toString]);
}

#pragma mark - Parsing & Prefix

// TEST060: Wrong prefix fails
- (void)test060_wrong_prefix_fails {
    NSError *error;
    CSMediaUrn *result = [CSMediaUrn fromString:@"cap:string" error:&error];
    XCTAssertNil(result);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, CSMediaUrnErrorInvalidPrefix);
}

#pragma mark - Predicates

// TEST061: is_binary
- (void)test061_is_binary {
    NSError *e;
    // Binary types: no textable tag
    XCTAssertTrue([[CSMediaUrn fromString:CSMediaIdentity error:&e] isBinary]);
    XCTAssertTrue([[CSMediaUrn fromString:CSMediaPng error:&e] isBinary]);
    XCTAssertTrue([[CSMediaUrn fromString:CSMediaPdf error:&e] isBinary]);
    XCTAssertTrue([[CSMediaUrn fromString:CSMediaVideo error:&e] isBinary]);
    XCTAssertTrue([[CSMediaUrn fromString:CSMediaEpub error:&e] isBinary]);
    // Textable types: is_binary is false
    XCTAssertFalse([[CSMediaUrn fromString:@"media:textable" error:&e] isBinary]);
    XCTAssertFalse([[CSMediaUrn fromString:CSMediaString error:&e] isBinary]);
    XCTAssertFalse([[CSMediaUrn fromString:CSMediaJson error:&e] isBinary]);
    XCTAssertFalse([[CSMediaUrn fromString:CSMediaMd error:&e] isBinary]);
}

// TEST062: is_record
- (void)test062_is_record {
    NSError *e;
    XCTAssertTrue([[CSMediaUrn fromString:CSMediaObject error:&e] isRecord]);
    XCTAssertTrue([[CSMediaUrn fromString:@"media:custom;record" error:&e] isRecord]);
    XCTAssertTrue([[CSMediaUrn fromString:CSMediaJson error:&e] isRecord]);
    // Without record marker
    XCTAssertFalse([[CSMediaUrn fromString:@"media:textable" error:&e] isRecord]);
    XCTAssertFalse([[CSMediaUrn fromString:CSMediaString error:&e] isRecord]);
    XCTAssertFalse([[CSMediaUrn fromString:CSMediaStringArray error:&e] isRecord]);
}

// TEST063: is_scalar
- (void)test063_is_scalar {
    NSError *e;
    XCTAssertTrue([[CSMediaUrn fromString:CSMediaString error:&e] isScalar]);
    XCTAssertTrue([[CSMediaUrn fromString:CSMediaInteger error:&e] isScalar]);
    XCTAssertTrue([[CSMediaUrn fromString:CSMediaNumber error:&e] isScalar]);
    XCTAssertTrue([[CSMediaUrn fromString:CSMediaBoolean error:&e] isScalar]);
    XCTAssertTrue([[CSMediaUrn fromString:CSMediaObject error:&e] isScalar]);
    XCTAssertTrue([[CSMediaUrn fromString:@"media:textable" error:&e] isScalar]);
    // With list marker
    XCTAssertFalse([[CSMediaUrn fromString:CSMediaStringArray error:&e] isScalar]);
    XCTAssertFalse([[CSMediaUrn fromString:CSMediaObjectArray error:&e] isScalar]);
}

// TEST064: is_list
- (void)test064_is_list {
    NSError *e;
    XCTAssertTrue([[CSMediaUrn fromString:CSMediaStringArray error:&e] isList]);
    XCTAssertTrue([[CSMediaUrn fromString:CSMediaIntegerArray error:&e] isList]);
    XCTAssertTrue([[CSMediaUrn fromString:CSMediaObjectArray error:&e] isList]);
    XCTAssertTrue([[CSMediaUrn fromString:@"media:custom;list" error:&e] isList]);
    // Without list marker
    XCTAssertFalse([[CSMediaUrn fromString:CSMediaString error:&e] isList]);
    XCTAssertFalse([[CSMediaUrn fromString:CSMediaObject error:&e] isList]);
}

// TEST065: is_opaque
- (void)test065_is_opaque {
    NSError *e;
    XCTAssertTrue([[CSMediaUrn fromString:CSMediaString error:&e] isOpaque]);
    XCTAssertTrue([[CSMediaUrn fromString:CSMediaStringArray error:&e] isOpaque]);
    XCTAssertTrue([[CSMediaUrn fromString:CSMediaPdf error:&e] isOpaque]);
    XCTAssertTrue([[CSMediaUrn fromString:@"media:textable" error:&e] isOpaque]);
    // With record marker
    XCTAssertFalse([[CSMediaUrn fromString:CSMediaObject error:&e] isOpaque]);
    XCTAssertFalse([[CSMediaUrn fromString:CSMediaJson error:&e] isOpaque]);
    XCTAssertFalse([[CSMediaUrn fromString:CSMediaObjectArray error:&e] isOpaque]);
}

// TEST066: is_json
- (void)test066_is_json {
    NSError *e;
    XCTAssertTrue([[CSMediaUrn fromString:CSMediaJson error:&e] isJson]);
    XCTAssertTrue([[CSMediaUrn fromString:@"media:custom;json" error:&e] isJson]);
    // record alone does not mean JSON
    XCTAssertFalse([[CSMediaUrn fromString:CSMediaObject error:&e] isJson]);
    XCTAssertFalse([[CSMediaUrn fromString:@"media:textable" error:&e] isJson]);
}

// TEST067: is_text
- (void)test067_is_text {
    NSError *e;
    XCTAssertTrue([[CSMediaUrn fromString:CSMediaString error:&e] isText]);
    XCTAssertTrue([[CSMediaUrn fromString:CSMediaInteger error:&e] isText]);
    XCTAssertTrue([[CSMediaUrn fromString:CSMediaJson error:&e] isText]);
    // Without textable tag
    XCTAssertFalse([[CSMediaUrn fromString:CSMediaIdentity error:&e] isText]);
    XCTAssertFalse([[CSMediaUrn fromString:CSMediaPng error:&e] isText]);
}

// TEST068: is_void
- (void)test068_is_void {
    NSError *e;
    XCTAssertTrue([[CSMediaUrn fromString:CSMediaVoid error:&e] isVoid]);
    XCTAssertFalse([[CSMediaUrn fromString:@"media:string" error:&e] isVoid]);
}

// TEST546: is_image
- (void)test546_is_image {
    NSError *e;
    XCTAssertTrue([[CSMediaUrn fromString:CSMediaPng error:&e] isImage]);
    XCTAssertTrue([[CSMediaUrn fromString:CSMediaImageThumbnail error:&e] isImage]);
    XCTAssertTrue([[CSMediaUrn fromString:@"media:image;jpg" error:&e] isImage]);
    XCTAssertFalse([[CSMediaUrn fromString:CSMediaPdf error:&e] isImage]);
    XCTAssertFalse([[CSMediaUrn fromString:CSMediaString error:&e] isImage]);
    XCTAssertFalse([[CSMediaUrn fromString:CSMediaAudio error:&e] isImage]);
    XCTAssertFalse([[CSMediaUrn fromString:CSMediaVideo error:&e] isImage]);
}

// TEST547: is_audio
- (void)test547_is_audio {
    NSError *e;
    XCTAssertTrue([[CSMediaUrn fromString:CSMediaAudio error:&e] isAudio]);
    XCTAssertTrue([[CSMediaUrn fromString:CSMediaAudioSpeech error:&e] isAudio]);
    XCTAssertTrue([[CSMediaUrn fromString:@"media:audio;mp3" error:&e] isAudio]);
    XCTAssertFalse([[CSMediaUrn fromString:CSMediaVideo error:&e] isAudio]);
    XCTAssertFalse([[CSMediaUrn fromString:CSMediaPng error:&e] isAudio]);
    XCTAssertFalse([[CSMediaUrn fromString:CSMediaString error:&e] isAudio]);
}

// TEST548: is_video
- (void)test548_is_video {
    NSError *e;
    XCTAssertTrue([[CSMediaUrn fromString:CSMediaVideo error:&e] isVideo]);
    XCTAssertTrue([[CSMediaUrn fromString:@"media:video;mp4" error:&e] isVideo]);
    XCTAssertFalse([[CSMediaUrn fromString:CSMediaAudio error:&e] isVideo]);
    XCTAssertFalse([[CSMediaUrn fromString:CSMediaPng error:&e] isVideo]);
    XCTAssertFalse([[CSMediaUrn fromString:CSMediaString error:&e] isVideo]);
}

// TEST549: is_numeric
- (void)test549_is_numeric {
    NSError *e;
    XCTAssertTrue([[CSMediaUrn fromString:CSMediaInteger error:&e] isNumeric]);
    XCTAssertTrue([[CSMediaUrn fromString:CSMediaNumber error:&e] isNumeric]);
    XCTAssertTrue([[CSMediaUrn fromString:CSMediaIntegerArray error:&e] isNumeric]);
    XCTAssertTrue([[CSMediaUrn fromString:CSMediaNumberArray error:&e] isNumeric]);
    XCTAssertFalse([[CSMediaUrn fromString:CSMediaString error:&e] isNumeric]);
    XCTAssertFalse([[CSMediaUrn fromString:CSMediaBoolean error:&e] isNumeric]);
    XCTAssertFalse([[CSMediaUrn fromString:CSMediaIdentity error:&e] isNumeric]);
}

// TEST550: is_bool
- (void)test550_is_bool {
    NSError *e;
    XCTAssertTrue([[CSMediaUrn fromString:CSMediaBoolean error:&e] isBool]);
    XCTAssertTrue([[CSMediaUrn fromString:CSMediaBooleanArray error:&e] isBool]);
    XCTAssertTrue([[CSMediaUrn fromString:CSMediaDecision error:&e] isBool]);
    XCTAssertTrue([[CSMediaUrn fromString:CSMediaDecisionArray error:&e] isBool]);
    XCTAssertFalse([[CSMediaUrn fromString:CSMediaString error:&e] isBool]);
    XCTAssertFalse([[CSMediaUrn fromString:CSMediaInteger error:&e] isBool]);
    XCTAssertFalse([[CSMediaUrn fromString:CSMediaIdentity error:&e] isBool]);
}

// TEST551: is_file_path
- (void)test551_is_file_path {
    NSError *e;
    XCTAssertTrue([[CSMediaUrn fromString:CSMediaFilePath error:&e] isFilePath]);
    // Array file-path is NOT isFilePath (it's isFilePathArray)
    XCTAssertFalse([[CSMediaUrn fromString:CSMediaFilePathArray error:&e] isFilePath]);
    XCTAssertFalse([[CSMediaUrn fromString:CSMediaString error:&e] isFilePath]);
    XCTAssertFalse([[CSMediaUrn fromString:CSMediaIdentity error:&e] isFilePath]);
}

// TEST552: is_file_path_array
- (void)test552_is_file_path_array {
    NSError *e;
    XCTAssertTrue([[CSMediaUrn fromString:CSMediaFilePathArray error:&e] isFilePathArray]);
    XCTAssertFalse([[CSMediaUrn fromString:CSMediaFilePath error:&e] isFilePathArray]);
    XCTAssertFalse([[CSMediaUrn fromString:CSMediaStringArray error:&e] isFilePathArray]);
}

// TEST553: is_any_file_path
- (void)test553_is_any_file_path {
    NSError *e;
    XCTAssertTrue([[CSMediaUrn fromString:CSMediaFilePath error:&e] isAnyFilePath]);
    XCTAssertTrue([[CSMediaUrn fromString:CSMediaFilePathArray error:&e] isAnyFilePath]);
    XCTAssertFalse([[CSMediaUrn fromString:CSMediaString error:&e] isAnyFilePath]);
    XCTAssertFalse([[CSMediaUrn fromString:CSMediaStringArray error:&e] isAnyFilePath]);
}

// TEST555: with_tag and without_tag
- (void)test555_with_tag_and_without_tag {
    NSError *e;
    CSMediaUrn *urn = [CSMediaUrn fromString:@"media:string" error:&e];
    XCTAssertNotNil(urn);
    CSMediaUrn *withExt = [urn withTag:@"ext" value:@"pdf"];
    XCTAssertEqualObjects([withExt getTag:@"ext"], @"pdf");
    // Original unchanged
    XCTAssertNil([urn getTag:@"ext"]);

    // Remove the tag
    CSMediaUrn *withoutExt = [withExt withoutTag:@"ext"];
    XCTAssertNil([withoutExt getTag:@"ext"]);
    // Removing non-existent tag is a no-op
    CSMediaUrn *same = [urn withoutTag:@"nonexistent"];
    XCTAssertTrue([same isEquivalentTo:urn]);
}

// TEST558: predicate/constant consistency
- (void)test558_predicate_constant_consistency {
    NSError *e;
    CSMediaUrn *intUrn = [CSMediaUrn fromString:CSMediaInteger error:&e];
    XCTAssertTrue([intUrn isNumeric]);
    XCTAssertTrue([intUrn isText]);
    XCTAssertTrue([intUrn isScalar]);
    XCTAssertFalse([intUrn isBinary]);
    XCTAssertFalse([intUrn isBool]);
    XCTAssertFalse([intUrn isImage]);
    XCTAssertFalse([intUrn isList]);

    CSMediaUrn *boolUrn = [CSMediaUrn fromString:CSMediaBoolean error:&e];
    XCTAssertTrue([boolUrn isBool]);
    XCTAssertTrue([boolUrn isText]);
    XCTAssertTrue([boolUrn isScalar]);
    XCTAssertFalse([boolUrn isNumeric]);

    CSMediaUrn *jsonUrn = [CSMediaUrn fromString:CSMediaJson error:&e];
    XCTAssertTrue([jsonUrn isJson]);
    XCTAssertTrue([jsonUrn isText]);
    XCTAssertTrue([jsonUrn isRecord]);
    XCTAssertTrue([jsonUrn isScalar], @"MEDIA_JSON is a scalar record (single object)");
    XCTAssertFalse([jsonUrn isBinary]);
    XCTAssertFalse([jsonUrn isList]);

    CSMediaUrn *voidUrn = [CSMediaUrn fromString:CSMediaVoid error:&e];
    XCTAssertTrue([voidUrn isVoid]);
    XCTAssertFalse([voidUrn isText]);
    XCTAssertTrue([voidUrn isBinary], @"void has no textable tag, so is_binary is true");
    XCTAssertFalse([voidUrn isNumeric]);
}

#pragma mark - Roundtrip & Conformance

// TEST071: to_string roundtrip
- (void)test071_to_string_roundtrip {
    NSError *e;
    CSMediaUrn *urn = [CSMediaUrn fromString:@"media:string" error:&e];
    XCTAssertNotNil(urn);
    NSString *s = [urn toString];
    CSMediaUrn *urn2 = [CSMediaUrn fromString:s error:&e];
    XCTAssertNotNil(urn2);
    XCTAssertTrue([urn isEquivalentTo:urn2]);
}

// TEST072: constants parse
- (void)test072_constants_parse {
    NSError *e;
    XCTAssertNotNil([CSMediaUrn fromString:CSMediaVoid error:&e]);
    XCTAssertNotNil([CSMediaUrn fromString:CSMediaString error:&e]);
    XCTAssertNotNil([CSMediaUrn fromString:CSMediaInteger error:&e]);
    XCTAssertNotNil([CSMediaUrn fromString:CSMediaNumber error:&e]);
    XCTAssertNotNil([CSMediaUrn fromString:CSMediaBoolean error:&e]);
    XCTAssertNotNil([CSMediaUrn fromString:CSMediaObject error:&e]);
    XCTAssertNotNil([CSMediaUrn fromString:CSMediaIdentity error:&e]);
    XCTAssertNotNil([CSMediaUrn fromString:CSMediaStringArray error:&e]);
    XCTAssertNotNil([CSMediaUrn fromString:CSMediaIntegerArray error:&e]);
    XCTAssertNotNil([CSMediaUrn fromString:CSMediaNumberArray error:&e]);
    XCTAssertNotNil([CSMediaUrn fromString:CSMediaBooleanArray error:&e]);
    XCTAssertNotNil([CSMediaUrn fromString:CSMediaObjectArray error:&e]);
    XCTAssertNotNil([CSMediaUrn fromString:CSMediaPng error:&e]);
    XCTAssertNotNil([CSMediaUrn fromString:CSMediaAudio error:&e]);
    XCTAssertNotNil([CSMediaUrn fromString:CSMediaVideo error:&e]);
    XCTAssertNotNil([CSMediaUrn fromString:CSMediaPdf error:&e]);
    XCTAssertNotNil([CSMediaUrn fromString:CSMediaEpub error:&e]);
    XCTAssertNotNil([CSMediaUrn fromString:CSMediaMd error:&e]);
    XCTAssertNotNil([CSMediaUrn fromString:CSMediaTxt error:&e]);
    XCTAssertNotNil([CSMediaUrn fromString:CSMediaRst error:&e]);
    XCTAssertNotNil([CSMediaUrn fromString:CSMediaLog error:&e]);
    XCTAssertNotNil([CSMediaUrn fromString:CSMediaHtml error:&e]);
    XCTAssertNotNil([CSMediaUrn fromString:CSMediaXml error:&e]);
    XCTAssertNotNil([CSMediaUrn fromString:CSMediaJson error:&e]);
    XCTAssertNotNil([CSMediaUrn fromString:CSMediaYaml error:&e]);
}

// TEST074: media URN conforms_to matching
- (void)test074_media_urn_matching {
    NSError *e;
    CSMediaUrn *pdfListing = [CSMediaUrn fromString:CSMediaPdf error:&e];
    CSMediaUrn *pdfReq = [CSMediaUrn fromString:@"media:pdf" error:&e];
    XCTAssertTrue([pdfListing conformsTo:pdfReq]);

    CSMediaUrn *mdListing = [CSMediaUrn fromString:CSMediaMd error:&e];
    CSMediaUrn *mdReq = [CSMediaUrn fromString:@"media:md" error:&e];
    XCTAssertTrue([mdListing conformsTo:mdReq error:&e]);

    CSMediaUrn *strUrn = [CSMediaUrn fromString:CSMediaString error:&e];
    CSMediaUrn *strReq = [CSMediaUrn fromString:CSMediaString error:&e];
    XCTAssertTrue([strUrn conformsTo:strReq]);
}

// TEST075: accepts matching
- (void)test075_matching {
    NSError *e;
    CSMediaUrn *handler = [CSMediaUrn fromString:@"media:string" error:&e];
    CSMediaUrn *request = [CSMediaUrn fromString:@"media:string" error:&e];
    XCTAssertTrue([handler accepts:request error:&e]);

    CSMediaUrn *same = [CSMediaUrn fromString:@"media:string" error:&e];
    XCTAssertTrue([handler accepts:same error:&e]);
}

// TEST076: specificity
- (void)test076_specificity {
    NSError *e;
    CSMediaUrn *urn1 = [CSMediaUrn fromString:@"media:string" error:&e];
    CSMediaUrn *urn2 = [CSMediaUrn fromString:@"media:textable" error:&e];
    CSMediaUrn *urn3 = [CSMediaUrn fromString:@"media:textable;numeric" error:&e];

    NSInteger s1 = [urn1 specificity];
    NSInteger s2 = [urn2 specificity];
    NSInteger s3 = [urn3 specificity];

    XCTAssertGreaterThanOrEqual(s2, s1);
    XCTAssertGreaterThanOrEqual(s3, s2);
}

// TEST078: object does not conform to string
- (void)test078_object_does_not_conform_to_string {
    NSError *e;
    CSMediaUrn *strUrn = [CSMediaUrn fromString:CSMediaString error:&e];
    CSMediaUrn *objUrn = [CSMediaUrn fromString:CSMediaObject error:&e];

    XCTAssertTrue([strUrn conformsTo:strUrn], @"string conforms to string");
    XCTAssertTrue([objUrn conformsTo:objUrn], @"object conforms to object");
    XCTAssertFalse([objUrn conformsTo:strUrn],
        @"MEDIA_OBJECT should NOT conform to MEDIA_STRING (missing textable)");
}

// TEST304: MEDIA_AVAILABILITY_OUTPUT constant
- (void)test304_media_availability_output_constant {
    NSError *e;
    CSMediaUrn *urn = [CSMediaUrn fromString:CSMediaAvailabilityOutput error:&e];
    XCTAssertNotNil(urn);
    XCTAssertTrue([urn isText], @"model-availability must be textable");
    XCTAssertTrue([urn isRecord], @"model-availability must have record marker");
    XCTAssertFalse([urn isBinary], @"model-availability must not be binary");
    CSMediaUrn *reparsed = [CSMediaUrn fromString:[urn toString] error:&e];
    XCTAssertTrue([urn conformsTo:reparsed], @"roundtrip must conform to original");
}

// TEST305: MEDIA_PATH_OUTPUT constant
- (void)test305_media_path_output_constant {
    NSError *e;
    CSMediaUrn *urn = [CSMediaUrn fromString:CSMediaPathOutput error:&e];
    XCTAssertNotNil(urn);
    XCTAssertTrue([urn isText], @"model-path must be textable");
    XCTAssertTrue([urn isRecord], @"model-path must have record marker");
    XCTAssertFalse([urn isBinary], @"model-path must not be binary");
    CSMediaUrn *reparsed = [CSMediaUrn fromString:[urn toString] error:&e];
    XCTAssertTrue([urn conformsTo:reparsed], @"roundtrip must conform to original");
}

// TEST306: availability and path output are distinct
- (void)test306_availability_and_path_output_distinct {
    NSError *e;
    XCTAssertFalse([CSMediaAvailabilityOutput isEqualToString:CSMediaPathOutput],
        @"availability and path output must be distinct media URNs");
    CSMediaUrn *avail = [CSMediaUrn fromString:CSMediaAvailabilityOutput error:&e];
    CSMediaUrn *path = [CSMediaUrn fromString:CSMediaPathOutput error:&e];
    XCTAssertFalse([avail conformsTo:path],
        @"availability must not conform to path");
}

@end

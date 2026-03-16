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

@end

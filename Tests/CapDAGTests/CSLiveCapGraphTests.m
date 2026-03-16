//
//  CSLiveCapGraphTests.m
//  CapDAGTests
//
//  Tests for CSLiveCapGraph — mirrors Rust live_cap_graph.rs tests.
//

#import <XCTest/XCTest.h>
#import "CapDAG.h"
#import "CSMediaUrn.h"

@interface CSLiveCapGraphTests : XCTestCase
@end

// Helper: build a test cap with given in/out/op/title
static CSCap *makeTestCap(NSString *inSpec, NSString *outSpec, NSString *op, NSString *title) {
    NSError *error = nil;
    CSCapUrnBuilder *builder = [CSCapUrnBuilder builder];
    [builder inSpec:inSpec];
    [builder outSpec:outSpec];
    [builder tag:@"op" value:op];
    CSCapUrn *built = [builder build:&error];
    NSCAssert(built != nil, @"Failed to build test cap URN: %@", error);

    return [CSCap capWithUrn:built title:title command:@"test"];
}

@implementation CSLiveCapGraphTests

// MARK: - Basic Tests (unnumbered, match Rust unnumbered tests)

- (void)testAddCapAndBasicTraversal {
    CSLiveCapGraph *graph = [CSLiveCapGraph graph];

    CSCap *cap = makeTestCap(@"media:pdf", @"media:extracted-text", @"extract_text", @"Extract Text");
    [graph addCap:cap];

    XCTAssertEqual([graph edgeCount], 1u);
    XCTAssertEqual([graph nodeCount], 2u);

    NSError *error = nil;
    CSMediaUrn *source = [CSMediaUrn fromString:@"media:pdf" error:&error];
    XCTAssertNotNil(source);

    NSArray<CSReachableTargetInfo *> *targets = [graph getReachableTargetsFromSource:source maxDepth:5];
    XCTAssertEqual(targets.count, 1u);
    XCTAssertEqual(targets[0].minDepth, 1u);
}

- (void)testExactVsConformanceMatching {
    // Verify is_equivalent distinguishes singular vs list
    NSError *error = nil;
    CSMediaUrn *singular = [CSMediaUrn fromString:@"media:analysis-result" error:&error];
    CSMediaUrn *list = [CSMediaUrn fromString:@"media:analysis-result;list" error:&error];

    XCTAssertFalse([singular isEquivalentTo:list], @"singular and list should NOT be equivalent");
    XCTAssertFalse([list isEquivalentTo:singular], @"list and singular should NOT be equivalent (reverse)");

    CSLiveCapGraph *graph = [CSLiveCapGraph graph];

    CSCap *cap1 = makeTestCap(@"media:pdf", @"media:analysis-result", @"analyze", @"Analyze PDF");
    CSCap *cap2 = makeTestCap(@"media:pdf", @"media:analysis-result;list", @"analyze_multi", @"Analyze PDF Multi");
    [graph addCap:cap1];
    [graph addCap:cap2];

    CSMediaUrn *source = [CSMediaUrn fromString:@"media:pdf" error:&error];

    // Query for singular — should find exactly 1 path
    CSMediaUrn *targetSingular = [CSMediaUrn fromString:@"media:analysis-result" error:&error];
    NSArray *pathsSingular = [graph findPathsToExactTarget:source target:targetSingular maxDepth:5 maxPaths:10];
    XCTAssertEqual(pathsSingular.count, 1u, @"singular query should find exactly 1 path");
    XCTAssertEqualObjects([pathsSingular[0] steps][0].capUrn ? [pathsSingular[0] steps][0].capUrn : @"", [cap1.capUrn toString]);

    // Query for list — should find exactly 1 path
    CSMediaUrn *targetPlural = [CSMediaUrn fromString:@"media:analysis-result;list" error:&error];
    NSArray *pathsPlural = [graph findPathsToExactTarget:source target:targetPlural maxDepth:5 maxPaths:10];
    XCTAssertEqual(pathsPlural.count, 1u, @"list query should find exactly 1 path");
}

- (void)testMultiStepPath {
    CSLiveCapGraph *graph = [CSLiveCapGraph graph];

    CSCap *cap1 = makeTestCap(@"media:pdf", @"media:extracted-text", @"extract", @"Extract");
    CSCap *cap2 = makeTestCap(@"media:extracted-text", @"media:summary-text", @"summarize", @"Summarize");
    [graph addCap:cap1];
    [graph addCap:cap2];

    NSError *error = nil;
    CSMediaUrn *source = [CSMediaUrn fromString:@"media:pdf" error:&error];
    CSMediaUrn *target = [CSMediaUrn fromString:@"media:summary-text" error:&error];

    NSArray<CSCapChainPathInfo *> *paths = [graph findPathsToExactTarget:source target:target maxDepth:5 maxPaths:10];

    XCTAssertEqual(paths.count, 1u);
    XCTAssertEqual(paths[0].totalSteps, 2);
    XCTAssertEqualObjects(paths[0].steps[0].capUrn, [cap1.capUrn toString]);
    XCTAssertEqualObjects(paths[0].steps[1].capUrn, [cap2.capUrn toString]);
}

- (void)testDeterministicOrdering {
    CSLiveCapGraph *graph = [CSLiveCapGraph graph];

    CSCap *cap1 = makeTestCap(@"media:pdf", @"media:extracted-text", @"extract_a", @"Extract A");
    CSCap *cap2 = makeTestCap(@"media:pdf", @"media:extracted-text", @"extract_b", @"Extract B");
    [graph addCap:cap1];
    [graph addCap:cap2];

    NSError *error = nil;
    CSMediaUrn *source = [CSMediaUrn fromString:@"media:pdf" error:&error];
    CSMediaUrn *target = [CSMediaUrn fromString:@"media:extracted-text" error:&error];

    // Run twice — same order
    NSArray *paths1 = [graph findPathsToExactTarget:source target:target maxDepth:5 maxPaths:10];
    NSArray *paths2 = [graph findPathsToExactTarget:source target:target maxDepth:5 maxPaths:10];

    XCTAssertEqual(paths1.count, paths2.count);
    for (NSUInteger i = 0; i < paths1.count; i++) {
        CSCapChainPathInfo *p1 = paths1[i];
        CSCapChainPathInfo *p2 = paths2[i];
        XCTAssertEqualObjects(p1.steps[0].capUrn, p2.steps[0].capUrn);
    }
}

- (void)testSyncFromCaps {
    CSLiveCapGraph *graph = [CSLiveCapGraph graph];

    NSArray *caps = @[
        makeTestCap(@"media:pdf", @"media:extracted-text", @"op1", @"Op1"),
        makeTestCap(@"media:extracted-text", @"media:summary-text", @"op2", @"Op2"),
    ];
    [graph syncFromCaps:caps];

    XCTAssertEqual([graph edgeCount], 2u);
    XCTAssertEqual([graph nodeCount], 3u);

    // Sync again — should replace
    NSArray *newCaps = @[
        makeTestCap(@"media:image", @"media:extracted-text", @"ocr", @"OCR"),
    ];
    [graph syncFromCaps:newCaps];

    XCTAssertEqual([graph edgeCount], 1u);
    XCTAssertEqual([graph nodeCount], 2u);
}

// MARK: - Numbered Tests

// TEST772: Multi-step path through intermediate node
- (void)test772FindPathsMultiStep {
    CSLiveCapGraph *graph = [CSLiveCapGraph graph];

    CSCap *cap1 = makeTestCap(@"media:a", @"media:b", @"step1", @"A to B");
    CSCap *cap2 = makeTestCap(@"media:b", @"media:c", @"step2", @"B to C");
    [graph addCap:cap1];
    [graph addCap:cap2];

    NSError *error = nil;
    CSMediaUrn *source = [CSMediaUrn fromString:@"media:a" error:&error];
    CSMediaUrn *target = [CSMediaUrn fromString:@"media:c" error:&error];

    NSArray *paths = [graph findPathsToExactTarget:source target:target maxDepth:5 maxPaths:10];

    XCTAssertEqual(paths.count, 1u, @"Should find one path through intermediate");
    CSCapChainPathInfo *path = paths[0];
    XCTAssertEqual(path.steps.count, 2u, @"Path should have 2 steps");
    XCTAssertEqualObjects(path.steps[0].capUrn, [cap1.capUrn toString]);
    XCTAssertEqualObjects(path.steps[1].capUrn, [cap2.capUrn toString]);
}

// TEST773: Empty when target unreachable
- (void)test773FindPathsEmptyWhenNoPath {
    CSLiveCapGraph *graph = [CSLiveCapGraph graph];

    CSCap *cap1 = makeTestCap(@"media:a", @"media:b", @"step1", @"A to B");
    [graph addCap:cap1];

    NSError *error = nil;
    CSMediaUrn *source = [CSMediaUrn fromString:@"media:a" error:&error];
    CSMediaUrn *target = [CSMediaUrn fromString:@"media:c" error:&error];

    NSArray *paths = [graph findPathsToExactTarget:source target:target maxDepth:5 maxPaths:10];

    XCTAssertEqual(paths.count, 0u, @"Should find no paths when target unreachable");
}

// TEST774: BFS finds multiple direct targets
- (void)test774GetReachableTargetsAll {
    CSLiveCapGraph *graph = [CSLiveCapGraph graph];

    CSCap *cap1 = makeTestCap(@"media:a", @"media:b", @"step1", @"A to B");
    CSCap *cap2 = makeTestCap(@"media:a", @"media:d", @"step3", @"A to D");
    [graph addCap:cap1];
    [graph addCap:cap2];

    NSError *error = nil;
    CSMediaUrn *source = [CSMediaUrn fromString:@"media:a" error:&error];

    NSArray<CSReachableTargetInfo *> *targets = [graph getReachableTargetsFromSource:source maxDepth:5];

    XCTAssertEqual(targets.count, 2u, @"Should find 2 reachable targets");
    NSMutableSet *targetSpecs = [NSMutableSet set];
    for (CSReachableTargetInfo *t in targets) {
        [targetSpecs addObject:t.mediaUrn];
    }
    XCTAssertTrue([targetSpecs containsObject:@"media:b"], @"B should be reachable");
    XCTAssertTrue([targetSpecs containsObject:@"media:d"], @"D should be reachable");
}

// TEST777: PDF cap does not match PNG input
- (void)test777TypeMismatchPdfPng {
    CSLiveCapGraph *graph = [CSLiveCapGraph graph];

    CSCap *cap = makeTestCap(@"media:pdf", @"media:textable", @"pdf2text", @"PDF to Text");
    [graph addCap:cap];

    NSError *error = nil;
    CSMediaUrn *source = [CSMediaUrn fromString:@"media:png" error:&error];
    CSMediaUrn *target = [CSMediaUrn fromString:@"media:textable" error:&error];

    NSArray *paths = [graph findPathsToExactTarget:source target:target maxDepth:5 maxPaths:10];
    XCTAssertEqual(paths.count, 0u, @"Should NOT find path from PNG via PDF cap");
}

// TEST778: PNG cap does not match PDF input
- (void)test778TypeMismatchPngPdf {
    CSLiveCapGraph *graph = [CSLiveCapGraph graph];

    CSCap *cap = makeTestCap(@"media:png", @"media:thumbnail", @"png2thumb", @"PNG to Thumbnail");
    [graph addCap:cap];

    NSError *error = nil;
    CSMediaUrn *source = [CSMediaUrn fromString:@"media:pdf" error:&error];
    CSMediaUrn *target = [CSMediaUrn fromString:@"media:thumbnail" error:&error];

    NSArray *paths = [graph findPathsToExactTarget:source target:target maxDepth:5 maxPaths:10];
    XCTAssertEqual(paths.count, 0u, @"Should NOT find path from PDF via PNG cap");
}

// TEST779: BFS respects type matching
- (void)test779ReachableTargetsTypeMatching {
    CSLiveCapGraph *graph = [CSLiveCapGraph graph];

    CSCap *pdfCap = makeTestCap(@"media:pdf", @"media:textable", @"pdf2text", @"PDF to Text");
    CSCap *pngCap = makeTestCap(@"media:png", @"media:thumbnail", @"png2thumb", @"PNG to Thumbnail");
    [graph addCap:pdfCap];
    [graph addCap:pngCap];

    NSError *error = nil;
    // PNG should only reach thumbnail
    CSMediaUrn *pngSource = [CSMediaUrn fromString:@"media:png" error:&error];
    NSArray *pngTargets = [graph getReachableTargetsFromSource:pngSource maxDepth:5];
    XCTAssertEqual(pngTargets.count, 1u, @"PNG should reach 1 target");
    XCTAssertEqualObjects(((CSReachableTargetInfo *)pngTargets[0]).mediaUrn, @"media:thumbnail");

    // PDF should only reach textable
    CSMediaUrn *pdfSource = [CSMediaUrn fromString:@"media:pdf" error:&error];
    NSArray *pdfTargets = [graph getReachableTargetsFromSource:pdfSource maxDepth:5];
    XCTAssertEqual(pdfTargets.count, 1u, @"PDF should reach 1 target");
    XCTAssertEqualObjects(((CSReachableTargetInfo *)pdfTargets[0]).mediaUrn, @"media:textable");
}

// TEST781: Multi-step type chain enforcement
- (void)test781FindPathsTypeChain {
    CSLiveCapGraph *graph = [CSLiveCapGraph graph];

    CSCap *resize = makeTestCap(@"media:png", @"media:resized-png", @"resize", @"Resize PNG");
    CSCap *toThumb = makeTestCap(@"media:resized-png", @"media:thumbnail", @"thumb", @"To Thumbnail");
    [graph addCap:resize];
    [graph addCap:toThumb];

    NSError *error = nil;
    // PNG should find 2-step path
    CSMediaUrn *pngSource = [CSMediaUrn fromString:@"media:png" error:&error];
    CSMediaUrn *thumbTarget = [CSMediaUrn fromString:@"media:thumbnail" error:&error];
    NSArray *pngPaths = [graph findPathsToExactTarget:pngSource target:thumbTarget maxDepth:5 maxPaths:10];
    XCTAssertEqual(pngPaths.count, 1u, @"PNG should find 1 path to thumbnail");
    XCTAssertEqual(((CSCapChainPathInfo *)pngPaths[0]).steps.count, 2u, @"Path should have 2 steps");

    // PDF should find no path
    CSMediaUrn *pdfSource = [CSMediaUrn fromString:@"media:pdf" error:&error];
    NSArray *pdfPaths = [graph findPathsToExactTarget:pdfSource target:thumbTarget maxDepth:5 maxPaths:10];
    XCTAssertEqual(pdfPaths.count, 0u, @"PDF should find no path to thumbnail");
}

// TEST787: Sorting prefers shorter paths
- (void)test787SortingShorterFirst {
    CSLiveCapGraph *graph = [CSLiveCapGraph graph];

    CSCap *direct = makeTestCap(@"media:format-a", @"media:format-c", @"direct", @"Direct");
    CSCap *step1 = makeTestCap(@"media:format-a", @"media:format-b", @"step1", @"Step 1");
    CSCap *step2 = makeTestCap(@"media:format-b", @"media:format-c", @"step2", @"Step 2");
    [graph addCap:direct];
    [graph addCap:step1];
    [graph addCap:step2];

    NSError *error = nil;
    CSMediaUrn *source = [CSMediaUrn fromString:@"media:format-a" error:&error];
    CSMediaUrn *target = [CSMediaUrn fromString:@"media:format-c" error:&error];

    NSArray<CSCapChainPathInfo *> *paths = [graph findPathsToExactTarget:source target:target maxDepth:5 maxPaths:10];

    XCTAssertGreaterThanOrEqual(paths.count, 2u, @"Should find at least 2 paths");
    XCTAssertEqual(paths[0].steps.count, 1u, @"Shortest path should be first (1 step)");
    XCTAssertEqualObjects(paths[0].steps[0].capUrn, [direct.capUrn toString]);
}

// TEST788: ForEach edges inserted for list→singular transitions
- (void)test788ForEachEdgesInserted {
    CSLiveCapGraph *graph = [CSLiveCapGraph graph];

    CSCap *disbind = makeTestCap(@"media:pdf", @"media:page;textable;list", @"disbind", @"Disbind PDF");
    CSCap *choose = makeTestCap(@"media:textable", @"media:decision;bool;textable", @"choose", @"Make Choice");

    [graph syncFromCaps:@[disbind, choose]];

    // Check ForEach edges were inserted
    BOOL hasForEach = NO;
    // Access edges via edge count — we can't directly access the array, but
    // we can check by querying paths
    NSError *error = nil;
    CSMediaUrn *source = [CSMediaUrn fromString:@"media:pdf" error:&error];
    CSMediaUrn *target = [CSMediaUrn fromString:@"media:decision;bool;textable" error:&error];

    NSArray<CSCapChainPathInfo *> *paths = [graph findPathsToExactTarget:source target:target maxDepth:10 maxPaths:20];

    // Should find at least one path that goes through ForEach
    for (CSCapChainPathInfo *path in paths) {
        for (CSCapChainStepInfo *step in path.steps) {
            if (step.stepType == CSCapChainStepTypeForEach) {
                hasForEach = YES;
                break;
            }
        }
        if (hasForEach) break;
    }

    XCTAssertTrue(hasForEach, @"Should find path with ForEach step (pdf → disbind → ForEach → choose)");
}

// TEST790: Identity URN is specific, not equivalent to everything
- (void)test790IdentityUrnSpecific {
    NSError *error = nil;
    CSCapUrn *identity = [CSCapUrn fromString:CSCapIdentity error:&error];
    XCTAssertNotNil(identity, @"Should parse identity URN");

    // Identity has wildcard specs
    XCTAssertEqualObjects([identity getInSpec], @"media:");
    XCTAssertEqualObjects([identity getOutSpec], @"media:");

    // A specific cap should NOT be equivalent to identity
    CSCapUrnBuilder *specificBuilder = [CSCapUrnBuilder builder];
    [specificBuilder inSpec:@"media:pdf"];
    [specificBuilder outSpec:@"media:disbound-page;list;textable"];
    [specificBuilder tag:@"op" value:@"disbind"];
    CSCapUrn *built = [specificBuilder build:&error];
    XCTAssertNotNil(built);

    XCTAssertFalse([built isEquivalent:identity],
                   @"A specific disbind cap should NOT be equivalent to identity");
}

@end

//
//  CSProgressMapperTests.m
//  CapDAGTests
//
//  Tests for CSProgressMapper — mirrors Rust executor.rs tests TEST908-TEST917.
//

#import <XCTest/XCTest.h>
#import "CapDAG.h"

@interface CSProgressMapperTests : XCTestCase
@end

@implementation CSProgressMapperTests

// TEST908: map_progress basic mapping — identity, subdivision, clamping
- (void)test908_map_progress_basic_mapping {
    // Identity mapping: base=0, weight=1
    XCTAssertEqualWithAccuracy(CSMapProgress(0.0f, 0.0f, 1.0f), 0.0f, 0.001f);
    XCTAssertEqualWithAccuracy(CSMapProgress(0.5f, 0.0f, 1.0f), 0.5f, 0.001f);
    XCTAssertEqualWithAccuracy(CSMapProgress(1.0f, 0.0f, 1.0f), 1.0f, 0.001f);

    // Subdivision: base=0.2, weight=0.6 → range [0.2, 0.8]
    XCTAssertEqualWithAccuracy(CSMapProgress(0.0f, 0.2f, 0.6f), 0.2f, 0.001f);
    XCTAssertEqualWithAccuracy(CSMapProgress(0.5f, 0.2f, 0.6f), 0.5f, 0.001f);
    XCTAssertEqualWithAccuracy(CSMapProgress(1.0f, 0.2f, 0.6f), 0.8f, 0.001f);

    // Clamping: values outside [0, 1] are clamped before mapping
    XCTAssertEqualWithAccuracy(CSMapProgress(-0.5f, 0.2f, 0.6f), 0.2f, 0.001f);
    XCTAssertEqualWithAccuracy(CSMapProgress(1.5f, 0.2f, 0.6f), 0.8f, 0.001f);
}

// TEST909: map_progress is deterministic — identical inputs produce identical outputs
- (void)test909_map_progress_deterministic {
    for (int i = 0; i <= 100; i++) {
        float p = (float)i / 100.0f;
        float a = CSMapProgress(p, 0.1f, 0.8f);
        float b = CSMapProgress(p, 0.1f, 0.8f);
        XCTAssertEqual(a, b, @"map_progress must be deterministic for p=%f", p);
    }
}

// TEST910: map_progress output is monotonic for monotonically increasing input
- (void)test910_map_progress_monotonic {
    float prev = CSMapProgress(0.0f, 0.1f, 0.7f);
    for (int i = 1; i <= 100; i++) {
        float p = (float)i / 100.0f;
        float curr = CSMapProgress(p, 0.1f, 0.7f);
        XCTAssertGreaterThanOrEqual(curr, prev,
            @"map_progress must be monotonic: p=%f, prev=%f, curr=%f", p, prev, curr);
        prev = curr;
    }
}

// TEST911: map_progress output is bounded within [base, base+weight]
- (void)test911_map_progress_bounded {
    float base = 0.15f;
    float weight = 0.55f;
    for (int i = -10; i <= 110; i++) {
        float p = (float)i / 100.0f;
        float result = CSMapProgress(p, base, weight);
        XCTAssertGreaterThanOrEqual(result, base,
            @"map_progress(%f, %f, %f) = %f must be >= %f", p, base, weight, result, base);
        XCTAssertLessThanOrEqual(result, base + weight,
            @"map_progress(%f, %f, %f) = %f must be <= %f", p, base, weight, result, base + weight);
    }
}

// TEST912: ProgressMapper correctly maps through parent callback
- (void)test912_progress_mapper_reports_through_parent {
    NSMutableArray<NSNumber *> *reported = [NSMutableArray array];

    CSCapProgressFn parent = ^(float p, NSString *capUrn, NSString *msg) {
        [reported addObject:@(p)];
    };

    CSProgressMapper *mapper = [[CSProgressMapper alloc] initWithParent:parent base:0.2f weight:0.6f];
    [mapper report:0.0f capUrn:@"" message:@"start"];
    [mapper report:0.5f capUrn:@"" message:@"half"];
    [mapper report:1.0f capUrn:@"" message:@"done"];

    XCTAssertEqual(reported.count, 3u);
    XCTAssertEqualWithAccuracy(reported[0].floatValue, 0.2f, 0.001f, @"0%% maps to base=0.2");
    XCTAssertEqualWithAccuracy(reported[1].floatValue, 0.5f, 0.001f, @"50%% maps to 0.5");
    XCTAssertEqualWithAccuracy(reported[2].floatValue, 0.8f, 0.001f, @"100%% maps to base+weight=0.8");
}

// TEST913: ProgressMapper conversion to CapProgressFn preserves mapping
- (void)test913_progress_mapper_as_cap_progress_fn {
    NSMutableArray<NSNumber *> *reported = [NSMutableArray array];

    CSCapProgressFn parent = ^(float p, NSString *capUrn, NSString *msg) {
        [reported addObject:@(p)];
    };

    CSProgressMapper *mapper = [[CSProgressMapper alloc] initWithParent:parent base:0.1f weight:0.3f];
    CSCapProgressFn pfn = [mapper asCapProgressFn];

    pfn(0.0f, @"", @"a");
    pfn(0.5f, @"", @"b");
    pfn(1.0f, @"", @"c");

    XCTAssertEqual(reported.count, 3u);
    XCTAssertEqualWithAccuracy(reported[0].floatValue, 0.1f, 0.001f);
    XCTAssertEqualWithAccuracy(reported[1].floatValue, 0.25f, 0.001f);
    XCTAssertEqualWithAccuracy(reported[2].floatValue, 0.4f, 0.001f);
}

// TEST914: ProgressMapper sub_mapper chains correctly
- (void)test914_progress_mapper_sub_mapper {
    NSMutableArray<NSNumber *> *reported = [NSMutableArray array];

    CSCapProgressFn parent = ^(float p, NSString *capUrn, NSString *msg) {
        [reported addObject:@(p)];
    };

    // Parent maps [0, 1] to [0.2, 0.8] (base=0.2, weight=0.6)
    CSProgressMapper *mapper = [[CSProgressMapper alloc] initWithParent:parent base:0.2f weight:0.6f];

    // Sub-mapper maps [0, 1] to the second half of parent's range
    // sub_base=0.5, sub_weight=0.5 → [0.2 + 0.5*0.6, 0.2 + (0.5+0.5)*0.6] = [0.5, 0.8]
    CSProgressMapper *sub = [mapper subMapperWithBase:0.5f weight:0.5f];
    [sub report:0.0f capUrn:@"" message:@"sub_start"];
    [sub report:1.0f capUrn:@"" message:@"sub_end"];

    XCTAssertEqual(reported.count, 2u);
    XCTAssertEqualWithAccuracy(reported[0].floatValue, 0.5f, 0.001f, @"Sub start maps to 0.5");
    XCTAssertEqualWithAccuracy(reported[1].floatValue, 0.8f, 0.001f, @"Sub end maps to 0.8");
}

// TEST915: Per-group subdivision is monotonic and bounded for N groups
- (void)test915_per_group_subdivision_monotonic_bounded {
    NSMutableArray<NSNumber *> *allProgress = [NSMutableArray array];

    CSCapProgressFn parent = ^(float p, NSString *capUrn, NSString *msg) {
        [allProgress addObject:@(p)];
    };

    NSUInteger nGroups = 5;
    NSMutableArray<NSNumber *> *boundaries = [NSMutableArray array];
    for (NSUInteger i = 0; i <= nGroups; i++) {
        [boundaries addObject:@((float)i / (float)nGroups)];
    }

    for (NSUInteger i = 0; i < nGroups; i++) {
        float base = boundaries[i].floatValue;
        float weight = boundaries[i + 1].floatValue - base;
        CSProgressMapper *mapper = [[CSProgressMapper alloc] initWithParent:parent base:base weight:weight];

        for (int j = 0; j <= 10; j++) {
            float p = (float)j / 10.0f;
            [mapper report:p capUrn:@"" message:@""];
        }
    }

    // Verify monotonic
    for (NSUInteger i = 1; i < allProgress.count; i++) {
        XCTAssertGreaterThanOrEqual(allProgress[i].floatValue, allProgress[i - 1].floatValue,
            @"Progress must be monotonic at index %lu", (unsigned long)i);
    }

    // Verify bounded [0.0, 1.0]
    for (NSNumber *p in allProgress) {
        XCTAssertGreaterThanOrEqual(p.floatValue, 0.0f);
        XCTAssertLessThanOrEqual(p.floatValue, 1.0f + 0.001f);
    }
}

// TEST917: High-frequency progress updates stay bounded
- (void)test917_high_frequency_progress_bounded {
    __block NSUInteger count = 0;
    __block float maxVal = -FLT_MAX;
    __block float minVal = FLT_MAX;

    CSCapProgressFn parent = ^(float p, NSString *capUrn, NSString *msg) {
        count++;
        if (p > maxVal) maxVal = p;
        if (p < minVal) minVal = p;
    };

    float base = 0.1f;
    float weight = 0.7f;
    CSProgressMapper *mapper = [[CSProgressMapper alloc] initWithParent:parent base:base weight:weight];

    for (int i = 0; i < 100000; i++) {
        float p = (float)(i % 1001) / 1000.0f;
        [mapper report:p capUrn:@"cap:op=test" message:@"fast"];
    }

    XCTAssertEqual(count, 100000u);
    XCTAssertGreaterThanOrEqual(minVal, base - 0.001f);
    XCTAssertLessThanOrEqual(maxVal, base + weight + 0.001f);
}

@end

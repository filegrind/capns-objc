//
//  CSCardinality.m
//  CapDAG
//
//  Cardinality Detection from Media URNs
//  Mirrors Rust: src/planner/cardinality.rs
//

#import "CSCardinality.h"
#import "CSMediaUrn.h"

// MARK: - InputCardinality Functions

CSInputCardinality CSInputCardinalityFromMediaUrn(NSString *urn) {
    NSError *error = nil;
    CSMediaUrn *mediaUrn = [CSMediaUrn fromString:urn error:&error];

    if (error || !mediaUrn) {
        // Invalid URN - fail hard, don't hide the issue
        [NSException raise:NSInvalidArgumentException
                    format:@"Invalid media URN in cardinality detection: %@ - %@", urn, error.localizedDescription];
    }

    if ([mediaUrn isList]) {
        return CSInputCardinalitySequence;
    } else {
        return CSInputCardinalitySingle;
    }
}

BOOL CSInputCardinalityIsMultiple(CSInputCardinality cardinality) {
    return cardinality == CSInputCardinalitySequence || cardinality == CSInputCardinalityAtLeastOne;
}

BOOL CSInputCardinalityAcceptsSingle(CSInputCardinality cardinality) {
    return cardinality == CSInputCardinalitySingle || cardinality == CSInputCardinalityAtLeastOne;
}

NSString *CSInputCardinalityApplyToUrn(CSInputCardinality cardinality, NSString *baseUrn) {
    NSError *error = nil;
    CSMediaUrn *mediaUrn = [CSMediaUrn fromString:baseUrn error:&error];

    if (error || !mediaUrn) {
        [NSException raise:NSInvalidArgumentException
                    format:@"Invalid media URN in apply_to_urn: %@ - %@", baseUrn, error.localizedDescription];
    }

    BOOL hasList = [mediaUrn isList];

    switch (cardinality) {
        case CSInputCardinalitySingle:
        case CSInputCardinalityAtLeastOne:
            if (hasList) {
                // Remove list marker
                return [[mediaUrn withoutTag:@"list"] toString];
            } else {
                return baseUrn;
            }

        case CSInputCardinalitySequence:
            if (hasList) {
                return baseUrn;
            } else {
                // Add list marker (wildcard value)
                return [[mediaUrn withTag:@"list" value:@"*"] toString];
            }
    }
}

// MARK: - CardinalityCompatibility Functions

CSCardinalityCompatibility CSInputCardinalityIsCompatibleWith(CSInputCardinality target, CSInputCardinality source) {
    // Match Rust logic exactly
    if (source == CSInputCardinalitySingle && target == CSInputCardinalitySingle) {
        return CSCardinalityCompatibilityDirect;
    }
    if (source == CSInputCardinalitySingle && target == CSInputCardinalitySequence) {
        return CSCardinalityCompatibilityWrapInArray;
    }
    if (source == CSInputCardinalitySequence && target == CSInputCardinalitySingle) {
        return CSCardinalityCompatibilityRequiresFanOut;
    }
    if (source == CSInputCardinalitySequence && target == CSInputCardinalitySequence) {
        return CSCardinalityCompatibilityDirect;
    }
    // AtLeastOne always compatible
    if (source == CSInputCardinalityAtLeastOne || target == CSInputCardinalityAtLeastOne) {
        return CSCardinalityCompatibilityDirect;
    }

    return CSCardinalityCompatibilityDirect;
}

// MARK: - CardinalityPattern Functions

BOOL CSCardinalityPatternProducesVector(CSCardinalityPattern pattern) {
    return pattern == CSCardinalityPatternOneToMany || pattern == CSCardinalityPatternManyToMany;
}

BOOL CSCardinalityPatternRequiresVector(CSCardinalityPattern pattern) {
    return pattern == CSCardinalityPatternManyToOne || pattern == CSCardinalityPatternManyToMany;
}

// MARK: - CapCardinalityInfo

@implementation CSCapCardinalityInfo

+ (instancetype)fromCapUrn:(NSString *)capUrn inSpec:(NSString *)inSpec outSpec:(NSString *)outSpec {
    CSCapCardinalityInfo *info = [[CSCapCardinalityInfo alloc] init];
    info->_input = CSInputCardinalityFromMediaUrn(inSpec);
    info->_output = CSInputCardinalityFromMediaUrn(outSpec);
    info->_capUrn = [capUrn copy];
    return info;
}

- (CSCardinalityPattern)pattern {
    // Match Rust logic exactly
    if (self.input == CSInputCardinalitySingle && self.output == CSInputCardinalitySingle) {
        return CSCardinalityPatternOneToOne;
    }
    if (self.input == CSInputCardinalitySingle && self.output == CSInputCardinalitySequence) {
        return CSCardinalityPatternOneToMany;
    }
    if (self.input == CSInputCardinalitySequence && self.output == CSInputCardinalitySingle) {
        return CSCardinalityPatternManyToOne;
    }
    if (self.input == CSInputCardinalitySequence && self.output == CSInputCardinalitySequence) {
        return CSCardinalityPatternManyToMany;
    }

    // Handle AtLeastOne cases
    if (self.input == CSInputCardinalityAtLeastOne && self.output == CSInputCardinalitySingle) {
        return CSCardinalityPatternOneToOne;
    }
    if (self.input == CSInputCardinalityAtLeastOne && self.output == CSInputCardinalitySequence) {
        return CSCardinalityPatternOneToMany;
    }
    if (self.input == CSInputCardinalitySingle && self.output == CSInputCardinalityAtLeastOne) {
        return CSCardinalityPatternOneToOne;
    }
    if (self.input == CSInputCardinalitySequence && self.output == CSInputCardinalityAtLeastOne) {
        return CSCardinalityPatternManyToMany;
    }
    if (self.input == CSInputCardinalityAtLeastOne && self.output == CSInputCardinalityAtLeastOne) {
        return CSCardinalityPatternOneToOne;
    }

    return CSCardinalityPatternOneToOne;
}

@end

// MARK: - CardinalityChainAnalysis

@implementation CSCardinalityChainAnalysis

+ (instancetype)analyzeChain:(NSArray<CSCapCardinalityInfo *> *)chain {
    CSCardinalityChainAnalysis *analysis = [[CSCardinalityChainAnalysis alloc] init];

    if (chain.count == 0) {
        analysis->_initialInput = CSInputCardinalitySingle;
        analysis->_finalOutput = CSInputCardinalitySingle;
        analysis->_fanOutPoints = @[];
        return analysis;
    }

    analysis->_initialInput = chain.firstObject.input;
    analysis->_finalOutput = chain.lastObject.output;

    NSMutableArray<NSNumber *> *fanOutPoints = [NSMutableArray array];

    CSInputCardinality currentCardinality = chain.firstObject.input;

    for (NSInteger i = 0; i < chain.count; i++) {
        CSCapCardinalityInfo *info = chain[i];
        CSCardinalityCompatibility compatibility = CSInputCardinalityIsCompatibleWith(info.input, currentCardinality);

        if (compatibility == CSCardinalityCompatibilityRequiresFanOut) {
            [fanOutPoints addObject:@(i)];
        }

        currentCardinality = info.output;
    }

    analysis->_fanOutPoints = [fanOutPoints copy];

    return analysis;
}

@end

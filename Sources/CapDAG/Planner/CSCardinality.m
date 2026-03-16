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

// MARK: - InputStructure Functions

CSInputStructure CSInputStructureFromMediaUrn(NSString *urn) {
    NSError *error = nil;
    CSMediaUrn *mediaUrn = [CSMediaUrn fromString:urn error:&error];

    if (error || !mediaUrn) {
        [NSException raise:NSInvalidArgumentException
                    format:@"Invalid media URN in structure detection: %@ - %@", urn, error.localizedDescription];
    }

    if ([mediaUrn isRecord]) {
        return CSInputStructureRecord;
    } else {
        return CSInputStructureOpaque;
    }
}

CSStructureCompatibility CSInputStructureIsCompatibleWith(CSInputStructure target, CSInputStructure source) {
    if (source == target) {
        return CSStructureCompatibilityDirect;
    }
    return CSStructureCompatibilityIncompatible;
}

NSString *CSInputStructureApplyToUrn(CSInputStructure structure, NSString *baseUrn) {
    NSError *error = nil;
    CSMediaUrn *mediaUrn = [CSMediaUrn fromString:baseUrn error:&error];

    if (error || !mediaUrn) {
        [NSException raise:NSInvalidArgumentException
                    format:@"Invalid media URN in apply_to_urn: %@ - %@", baseUrn, error.localizedDescription];
    }

    BOOL hasRecord = [mediaUrn isRecord];

    switch (structure) {
        case CSInputStructureOpaque:
            if (hasRecord) {
                return [[mediaUrn withoutTag:@"record"] toString];
            } else {
                return baseUrn;
            }

        case CSInputStructureRecord:
            if (hasRecord) {
                return baseUrn;
            } else {
                return [[mediaUrn withTag:@"record" value:@"*"] toString];
            }
    }
}

// MARK: - MediaShape

@implementation CSMediaShape

+ (instancetype)fromMediaUrn:(NSString *)urn {
    CSMediaShape *shape = [[CSMediaShape alloc] init];
    shape->_cardinality = CSInputCardinalityFromMediaUrn(urn);
    shape->_structure = CSInputStructureFromMediaUrn(urn);
    return shape;
}

+ (instancetype)scalarOpaque {
    CSMediaShape *shape = [[CSMediaShape alloc] init];
    shape->_cardinality = CSInputCardinalitySingle;
    shape->_structure = CSInputStructureOpaque;
    return shape;
}

+ (instancetype)scalarRecord {
    CSMediaShape *shape = [[CSMediaShape alloc] init];
    shape->_cardinality = CSInputCardinalitySingle;
    shape->_structure = CSInputStructureRecord;
    return shape;
}

+ (instancetype)listOpaque {
    CSMediaShape *shape = [[CSMediaShape alloc] init];
    shape->_cardinality = CSInputCardinalitySequence;
    shape->_structure = CSInputStructureOpaque;
    return shape;
}

+ (instancetype)listRecord {
    CSMediaShape *shape = [[CSMediaShape alloc] init];
    shape->_cardinality = CSInputCardinalitySequence;
    shape->_structure = CSInputStructureRecord;
    return shape;
}

@end

CSShapeCompatibility CSMediaShapeIsCompatibleWith(CSMediaShape *target, CSMediaShape *source) {
    CSStructureCompatibility structCompat = CSInputStructureIsCompatibleWith(target.structure, source.structure);
    if (structCompat == CSStructureCompatibilityIncompatible) {
        return CSShapeCompatibilityIncompatible;
    }

    CSCardinalityCompatibility cardCompat = CSInputCardinalityIsCompatibleWith(target.cardinality, source.cardinality);
    switch (cardCompat) {
        case CSCardinalityCompatibilityDirect:
            return CSShapeCompatibilityDirect;
        case CSCardinalityCompatibilityWrapInArray:
            return CSShapeCompatibilityWrapInArray;
        case CSCardinalityCompatibilityRequiresFanOut:
            return CSShapeCompatibilityRequiresFanOut;
    }
}

// MARK: - CapShapeInfo

@implementation CSCapShapeInfo

+ (instancetype)fromCapUrn:(NSString *)capUrn inSpec:(NSString *)inSpec outSpec:(NSString *)outSpec {
    CSCapShapeInfo *info = [[CSCapShapeInfo alloc] init];
    info->_input = [CSMediaShape fromMediaUrn:inSpec];
    info->_output = [CSMediaShape fromMediaUrn:outSpec];
    info->_capUrn = [capUrn copy];
    return info;
}

- (CSCardinalityPattern)cardinalityPattern {
    CSInputCardinality inCard = self.input.cardinality;
    CSInputCardinality outCard = self.output.cardinality;

    if (inCard == CSInputCardinalitySingle && outCard == CSInputCardinalitySingle) return CSCardinalityPatternOneToOne;
    if (inCard == CSInputCardinalitySingle && outCard == CSInputCardinalitySequence) return CSCardinalityPatternOneToMany;
    if (inCard == CSInputCardinalitySequence && outCard == CSInputCardinalitySingle) return CSCardinalityPatternManyToOne;
    if (inCard == CSInputCardinalitySequence && outCard == CSInputCardinalitySequence) return CSCardinalityPatternManyToMany;

    if (inCard == CSInputCardinalityAtLeastOne && outCard == CSInputCardinalitySingle) return CSCardinalityPatternOneToOne;
    if (inCard == CSInputCardinalityAtLeastOne && outCard == CSInputCardinalitySequence) return CSCardinalityPatternOneToMany;
    if (inCard == CSInputCardinalitySingle && outCard == CSInputCardinalityAtLeastOne) return CSCardinalityPatternOneToOne;
    if (inCard == CSInputCardinalitySequence && outCard == CSInputCardinalityAtLeastOne) return CSCardinalityPatternManyToMany;
    if (inCard == CSInputCardinalityAtLeastOne && outCard == CSInputCardinalityAtLeastOne) return CSCardinalityPatternOneToOne;

    return CSCardinalityPatternOneToOne;
}

- (BOOL)structuresMatch {
    return self.input.structure == self.output.structure;
}

@end

// MARK: - ShapeChainAnalysis

@implementation CSShapeChainAnalysis

+ (instancetype)analyze:(NSArray<CSCapShapeInfo *> *)capInfos {
    CSShapeChainAnalysis *analysis = [[CSShapeChainAnalysis alloc] init];

    if (capInfos.count == 0) {
        analysis->_capInfos = @[];
        analysis->_fanOutPoints = @[];
        analysis->_fanInPoints = @[];
        analysis->_isValid = YES;
        analysis->_error = nil;
        return analysis;
    }

    NSMutableArray<NSNumber *> *fanOutPoints = [NSMutableArray array];
    NSMutableArray<NSNumber *> *fanInPoints = [NSMutableArray array];
    CSMediaShape *currentShape = capInfos[0].input;
    NSString *errorMsg = nil;

    for (NSInteger i = 0; i < (NSInteger)capInfos.count; i++) {
        CSCapShapeInfo *info = capInfos[i];
        CSShapeCompatibility compat = CSMediaShapeIsCompatibleWith(info.input, currentShape);

        switch (compat) {
            case CSShapeCompatibilityDirect:
                break;
            case CSShapeCompatibilityWrapInArray:
                break;
            case CSShapeCompatibilityRequiresFanOut:
                [fanOutPoints addObject:@(i)];
                break;
            case CSShapeCompatibilityIncompatible:
                errorMsg = [NSString stringWithFormat:
                    @"Shape mismatch at cap %ld (%@): structure incompatible",
                    (long)i, info.capUrn];
                break;
        }

        if (errorMsg) break;
        currentShape = info.output;
    }

    if (errorMsg) {
        analysis->_capInfos = [capInfos copy];
        analysis->_fanOutPoints = [fanOutPoints copy];
        analysis->_fanInPoints = [fanInPoints copy];
        analysis->_isValid = NO;
        analysis->_error = errorMsg;
        return analysis;
    }

    if (fanOutPoints.count > 0) {
        [fanInPoints addObject:@(capInfos.count)];
    }

    analysis->_capInfos = [capInfos copy];
    analysis->_fanOutPoints = [fanOutPoints copy];
    analysis->_fanInPoints = [fanInPoints copy];
    analysis->_isValid = YES;
    analysis->_error = nil;
    return analysis;
}

- (BOOL)requiresTransformation {
    return self.fanOutPoints.count > 0 || self.fanInPoints.count > 0;
}

- (nullable CSMediaShape *)finalOutputShape {
    if (self.capInfos.count == 0) return nil;
    return self.capInfos.lastObject.output;
}

@end

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

//
//  CSCardinality.h
//  CapNs
//
//  Cardinality Detection from Media URNs
//  Mirrors Rust: src/planner/cardinality.rs
//

#import <Foundation/Foundation.h>

@class CSMediaUrn;

NS_ASSUME_NONNULL_BEGIN

// MARK: - InputCardinality

/// Cardinality of cap inputs/outputs
/// Mirrors Rust: pub enum InputCardinality
typedef NS_ENUM(NSInteger, CSInputCardinality) {
    /// Exactly 1 item (no list marker = scalar by default)
    CSInputCardinalitySingle,
    /// Array of items (has list marker)
    CSInputCardinalitySequence,
    /// 1 or more items (cap can handle either)
    CSInputCardinalityAtLeastOne
};

/// Parse cardinality from a media URN string.
/// Uses the `list` marker tag to determine if this represents an array.
/// No list marker = scalar (default), list marker = sequence.
/// Mirrors Rust: InputCardinality::from_media_urn
CSInputCardinality CSInputCardinalityFromMediaUrn(NSString *urn);

/// Check if this cardinality accepts multiple items
/// Mirrors Rust: pub fn is_multiple(&self) -> bool
BOOL CSInputCardinalityIsMultiple(CSInputCardinality cardinality);

/// Check if this cardinality can accept a single item
/// Mirrors Rust: pub fn accepts_single(&self) -> bool
BOOL CSInputCardinalityAcceptsSingle(CSInputCardinality cardinality);

/// Create a media URN with this cardinality from a base URN
/// Mirrors Rust: pub fn apply_to_urn(&self, base_urn: &str) -> String
NSString *CSInputCardinalityApplyToUrn(CSInputCardinality cardinality, NSString *baseUrn);

// MARK: - CardinalityCompatibility

/// Result of checking cardinality compatibility
/// Mirrors Rust: pub enum CardinalityCompatibility
typedef NS_ENUM(NSInteger, CSCardinalityCompatibility) {
    /// Direct flow, no transformation needed
    CSCardinalityCompatibilityDirect,
    /// Need to wrap single item in array
    CSCardinalityCompatibilityWrapInArray,
    /// Need to fan-out: iterate over sequence, run for each item
    CSCardinalityCompatibilityRequiresFanOut
};

/// Check if cardinalities are compatible for data flow
/// Returns compatibility mode if data with `source` cardinality can flow into
/// an input expecting `target` cardinality.
/// Mirrors Rust: pub fn is_compatible_with(&self, source: InputCardinality)
CSCardinalityCompatibility CSInputCardinalityIsCompatibleWith(CSInputCardinality target, CSInputCardinality source);

// MARK: - CardinalityPattern

/// Pattern describing input/output cardinality relationship
/// Mirrors Rust: pub enum CardinalityPattern
typedef NS_ENUM(NSInteger, CSCardinalityPattern) {
    /// Single input → Single output (e.g., resize image)
    CSCardinalityPatternOneToOne,
    /// Single input → Multiple outputs (e.g., PDF to pages)
    CSCardinalityPatternOneToMany,
    /// Multiple inputs → Single output (e.g., merge PDFs)
    CSCardinalityPatternManyToOne,
    /// Multiple inputs → Multiple outputs (e.g., batch process)
    CSCardinalityPatternManyToMany
};

/// Check if this pattern may produce multiple outputs
/// Mirrors Rust: pub fn produces_vector(&self) -> bool
BOOL CSCardinalityPatternProducesVector(CSCardinalityPattern pattern);

/// Check if this pattern requires multiple inputs
/// Mirrors Rust: pub fn requires_vector(&self) -> bool
BOOL CSCardinalityPatternRequiresVector(CSCardinalityPattern pattern);

// MARK: - CapCardinalityInfo

/// Cardinality analysis for a cap transformation
/// Mirrors Rust: pub struct CapCardinalityInfo
@interface CSCapCardinalityInfo : NSObject

/// Input cardinality from cap's in_spec
@property (nonatomic, assign, readonly) CSInputCardinality input;

/// Output cardinality from cap's out_spec
@property (nonatomic, assign, readonly) CSInputCardinality output;

/// Cap URN this applies to
@property (nonatomic, copy, readonly) NSString *capUrn;

/// Create cardinality info by parsing a cap's input and output specs
/// Mirrors Rust: pub fn from_cap_specs
+ (instancetype)fromCapUrn:(NSString *)capUrn inSpec:(NSString *)inSpec outSpec:(NSString *)outSpec;

/// Describe the cardinality transformation pattern
/// Mirrors Rust: pub fn pattern(&self) -> CardinalityPattern
- (CSCardinalityPattern)pattern;

@end

// MARK: - CardinalityChainAnalysis

/// Analysis of cardinality through a chain of caps
/// Mirrors Rust: pub struct CardinalityChainAnalysis
@interface CSCardinalityChainAnalysis : NSObject

/// Input cardinality at chain start
@property (nonatomic, assign, readonly) CSInputCardinality initialInput;

/// Output cardinality at chain end
@property (nonatomic, assign, readonly) CSInputCardinality finalOutput;

/// Indices of caps where fan-out is required
@property (nonatomic, copy, readonly) NSArray<NSNumber *> *fanOutPoints;

/// Create chain analysis from array of CapCardinalityInfo
/// Mirrors Rust: pub fn analyze_chain
+ (instancetype)analyzeChain:(NSArray<CSCapCardinalityInfo *> *)chain;

@end

NS_ASSUME_NONNULL_END

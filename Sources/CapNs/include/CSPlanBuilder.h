//
//  CSPlanBuilder.h
//  CapNs
//
//  Cap Plan Builder
//  Mirrors Rust: src/planner/plan_builder.rs
//

#import <Foundation/Foundation.h>
#import "CSCardinality.h"

@class CSCap;
@class CSCapExecutionPlan;
@class CSCapInputFile;
@class CSCardinalityChainAnalysis;

NS_ASSUME_NONNULL_BEGIN

// MARK: - Error Domain

extern NSString * const CSPlannerErrorDomain;

typedef NS_ENUM(NSInteger, CSPlannerErrorCode) {
    CSPlannerErrorCodeInvalidInput = 1,
    CSPlannerErrorCodeNotFound,
    CSPlannerErrorCodeInternal,
    CSPlannerErrorCodeRegistryError
};

// MARK: - Registry Protocols

/// Protocol for cap registry access
@protocol CSCapRegistryProtocol <NSObject>
- (void)getCachedCaps:(void (^)(NSArray<CSCap *> * _Nullable caps, NSError * _Nullable error))completion;
@end

/// Protocol for media URN registry access
@protocol CSMediaUrnRegistryProtocol <NSObject>
- (void)getMediaSpec:(NSString *)urn completion:(void (^)(NSDictionary * _Nullable spec, NSError * _Nullable error))completion;
@end

// MARK: - Supporting Structures

/// Information about a reachable target with metadata
@interface CSReachableTargetInfo : NSObject
@property (nonatomic, copy) NSString *mediaUrn;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, assign) NSUInteger minDepth;
@property (nonatomic, assign) NSUInteger maxDepth;
@end

/// Information about a step in a cap chain
@interface CSCapChainStepInfo : NSObject
@property (nonatomic, copy) NSString *capUrn;
@property (nonatomic, copy, nullable) NSString *preferredCap;
@property (nonatomic, strong, nullable) NSDictionary *metadata;
@end

/// Information about a cap chain path
@interface CSCapChainPathInfo : NSObject
@property (nonatomic, copy) NSString *sourceSpec;
@property (nonatomic, copy) NSString *targetSpec;
@property (nonatomic, strong) NSArray<CSCapChainStepInfo *> *steps;
@end

/// Information about an argument
@interface CSArgumentInfo : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *mediaUrn;
@property (nonatomic, assign) BOOL isRequired;
@property (nonatomic, strong, nullable) id defaultValue;
@property (nonatomic, strong, nullable) NSDictionary *schema;
@end

/// Argument requirements for a step
@interface CSStepArgumentRequirements : NSObject
@property (nonatomic, copy) NSString *capUrn;
@property (nonatomic, strong) NSArray<CSArgumentInfo *> *arguments;
@end

/// Argument requirements for a path
@interface CSPathArgumentRequirements : NSObject
@property (nonatomic, strong) NSArray<CSStepArgumentRequirements *> *steps;
@property (nonatomic, strong) NSArray<CSArgumentInfo *> *allSlots;
@end

// MARK: - CapPlanBuilder

/// Builder for creating cap execution plans
@interface CSCapPlanBuilder : NSObject

/// Create a new plan builder with the given registries
- (instancetype)initWithCapRegistry:(id<CSCapRegistryProtocol>)capRegistry
                      mediaRegistry:(id<CSMediaUrnRegistryProtocol>)mediaRegistry;

/// Set the filter for available cap URNs
- (instancetype)withAvailableCaps:(NSSet<NSString *> *)availableCaps;

/// Find a path through the cap graph from source to target media type
- (void)findPathFromSource:(NSString *)sourceMedia
                  toTarget:(NSString *)targetMedia
                completion:(void (^)(NSArray<NSString *> * _Nullable capUrns, NSError * _Nullable error))completion;

/// Build an execution plan for transforming from source to target media type
- (void)buildPlanFromSource:(NSString *)sourceMedia
                   toTarget:(NSString *)targetMedia
                 inputFiles:(NSArray<CSCapInputFile *> *)inputFiles
                 completion:(void (^)(CSCapExecutionPlan * _Nullable plan, NSError * _Nullable error))completion;

/// Analyze what transformations would be needed for a path
- (void)analyzePathCardinalityFromSource:(NSString *)sourceMedia
                                toTarget:(NSString *)targetMedia
                              completion:(void (^)(CSCardinalityChainAnalysis * _Nullable analysis, NSError * _Nullable error))completion;

/// Build a plan from a pre-defined path
- (void)buildPlanFromPath:(CSCapChainPathInfo *)path
                     name:(NSString *)name
        inputCardinality:(CSInputCardinality)cardinality
              completion:(void (^)(CSCapExecutionPlan * _Nullable plan, NSError * _Nullable error))completion;

/// Get all possible target media specs from a given source
- (void)getReachableTargetsFromSource:(NSString *)sourceMedia
                           completion:(void (^)(NSArray<NSString *> * _Nullable targets, NSError * _Nullable error))completion;

/// Get all reachable targets with additional metadata
- (void)getReachableTargetsWithMetadataFromSource:(NSString *)sourceMedia
                                         maxDepth:(NSUInteger)maxDepth
                                       completion:(void (^)(NSArray<CSReachableTargetInfo *> * _Nullable targets, NSError * _Nullable error))completion;

/// Find all paths (up to max depth) from source to target
- (void)findAllPathsFromSource:(NSString *)sourceMedia
                      toTarget:(NSString *)targetMedia
                      maxDepth:(NSUInteger)maxDepth
                    completion:(void (^)(NSArray<NSArray<NSString *> *> * _Nullable paths, NSError * _Nullable error))completion;

/// Analyze argument requirements for a path
- (void)analyzePathArgumentsForPath:(NSArray<NSString *> *)capUrns
                         completion:(void (^)(CSPathArgumentRequirements * _Nullable requirements, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END

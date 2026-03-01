//
//  CSPlan.h
//  CapDAG
//
//  Cap Execution Plan structures
//  Mirrors Rust: src/planner/plan.rs
//

#import <Foundation/Foundation.h>
#import "CSCardinality.h"

@class CSArgumentBinding;
@class CSCapNode;
@class CSCapEdge;

NS_ASSUME_NONNULL_BEGIN

/// Unique identifier for a node in the execution plan
typedef NSString * CSNodeId;

// MARK: - MergeStrategy

/// Strategy for merging outputs from parallel branches
typedef NS_ENUM(NSInteger, CSMergeStrategy) {
    /// Concatenate all outputs into a sequence
    CSMergeStrategyConcat,
    /// Zip outputs together (requires same length)
    CSMergeStrategyZipWith,
    /// Take first successful output
    CSMergeStrategyFirstSuccess,
    /// Take all successful outputs
    CSMergeStrategyAllSuccessful
};

// MARK: - EdgeType

/// Edge type for execution plans
typedef NS_ENUM(NSInteger, CSEdgeType) {
    /// Direct data flow
    CSEdgeTypeDirect,
    /// Extract field from JSON output
    CSEdgeTypeJsonField,
    /// Extract via JSONPath
    CSEdgeTypeJsonPath,
    /// Iteration edge (from ForEach to body)
    CSEdgeTypeIteration,
    /// Collection edge (from body to Collect)
    CSEdgeTypeCollection
};

// MARK: - CapEdge

/// An edge in the execution plan
/// Mirrors Rust: pub struct CapEdge
@interface CSCapEdge : NSObject

/// Source node
@property (nonatomic, copy) CSNodeId fromNode;

/// Target node
@property (nonatomic, copy) CSNodeId toNode;

/// Type of data flow
@property (nonatomic, assign) CSEdgeType edgeType;

/// JSON field (for JsonField edge type)
@property (nonatomic, copy, nullable) NSString *jsonField;

/// JSON path (for JsonPath edge type)
@property (nonatomic, copy, nullable) NSString *jsonPath;

/// Create a direct edge
+ (instancetype)directFrom:(NSString *)from to:(NSString *)to;

/// Create an iteration edge (ForEach -> body)
+ (instancetype)iterationFrom:(NSString *)from to:(NSString *)to;

/// Create a collection edge (body -> Collect)
+ (instancetype)collectionFrom:(NSString *)from to:(NSString *)to;

/// Create a JSON field extraction edge
+ (instancetype)jsonFieldFrom:(NSString *)from to:(NSString *)to field:(NSString *)field;

/// Create a JSON path extraction edge
+ (instancetype)jsonPathFrom:(NSString *)from to:(NSString *)to path:(NSString *)path;

@end

// MARK: - CapNode

/// A node in the execution DAG
/// Mirrors Rust: pub struct CapNode and pub enum ExecutionNodeType
@interface CSCapNode : NSObject

/// Unique identifier for this node
@property (nonatomic, copy) CSNodeId nodeId;

/// Optional description
@property (nonatomic, copy, nullable) NSString *nodeDescription;

// Node type - mutually exclusive properties

// Cap node properties
@property (nonatomic, copy, nullable) NSString *capUrn;
@property (nonatomic, strong, nullable) NSDictionary<NSString *, CSArgumentBinding *> *argBindings;
@property (nonatomic, copy, nullable) NSString *preferredCap;

// ForEach node properties
@property (nonatomic, copy, nullable) CSNodeId inputNode;
@property (nonatomic, copy, nullable) CSNodeId bodyEntry;
@property (nonatomic, copy, nullable) CSNodeId bodyExit;

// Collect node properties
@property (nonatomic, strong, nullable) NSArray<CSNodeId> *inputNodes;
@property (nonatomic, copy, nullable) NSString *outputMediaUrn;

// Merge node properties
@property (nonatomic, assign) CSMergeStrategy mergeStrategy;

// Split node properties
@property (nonatomic, assign) NSUInteger outputCount;

// InputSlot node properties
@property (nonatomic, copy, nullable) NSString *slotName;
@property (nonatomic, copy, nullable) NSString *expectedMediaUrn;
@property (nonatomic, assign) CSInputCardinality cardinality;

// Output node properties
@property (nonatomic, copy, nullable) NSString *outputName;
@property (nonatomic, copy, nullable) CSNodeId sourceNode;

/// Create a cap execution node
+ (instancetype)capNode:(NSString *)nodeId capUrn:(NSString *)capUrn;

/// Create a cap node with argument bindings
+ (instancetype)capNode:(NSString *)nodeId capUrn:(NSString *)capUrn bindings:(NSDictionary<NSString *, CSArgumentBinding *> *)bindings;

/// Create a cap node with argument bindings and routing preference
+ (instancetype)capNode:(NSString *)nodeId capUrn:(NSString *)capUrn bindings:(NSDictionary<NSString *, CSArgumentBinding *> *)bindings preferredCap:(nullable NSString *)preferredCap;

/// Create a ForEach (fan-out) node
+ (instancetype)forEachNode:(NSString *)nodeId inputNode:(NSString *)inputNode bodyEntry:(NSString *)bodyEntry bodyExit:(NSString *)bodyExit;

/// Create a Collect (fan-in) node
+ (instancetype)collectNode:(NSString *)nodeId inputNodes:(NSArray<CSNodeId> *)inputNodes;

/// Create an input slot node
+ (instancetype)inputSlotNode:(NSString *)nodeId slotName:(NSString *)slotName mediaUrn:(NSString *)mediaUrn cardinality:(CSInputCardinality)cardinality;

/// Create an output node
+ (instancetype)outputNode:(NSString *)nodeId outputName:(NSString *)outputName sourceNode:(NSString *)sourceNode;

/// Check if this is a cap execution node
- (BOOL)isCap;

/// Check if this is a fan-out node
- (BOOL)isFanOut;

/// Check if this is a fan-in node
- (BOOL)isFanIn;

@end

// MARK: - CapExecutionPlan

/// The structured execution plan for a cap chain
/// Mirrors Rust: pub struct CapExecutionPlan
@interface CSCapExecutionPlan : NSObject

/// Human-readable name for this execution plan
@property (nonatomic, copy) NSString *name;

/// All nodes in the DAG (nodeId -> node)
@property (nonatomic, strong) NSMutableDictionary<CSNodeId, CSCapNode *> *nodes;

/// Edges describing data flow
@property (nonatomic, strong) NSMutableArray<CSCapEdge *> *edges;

/// Entry point nodes (InputSlots)
@property (nonatomic, strong) NSMutableArray<CSNodeId> *entryNodes;

/// Output nodes
@property (nonatomic, strong) NSMutableArray<CSNodeId> *outputNodes;

/// Plan metadata
@property (nonatomic, strong, nullable) NSDictionary<NSString *, id> *metadata;

/// Create an empty plan
+ (instancetype)planWithName:(NSString *)name;

/// Add a node to the plan
- (void)addNode:(CSCapNode *)node;

/// Add an edge to the plan
- (void)addEdge:(CSCapEdge *)edge;

/// Get a node by ID
- (nullable CSCapNode *)getNode:(NSString *)nodeId;

/// Validate the plan structure
- (NSError * _Nullable)validate;

/// Get topological ordering of nodes
- (nullable NSArray<CSCapNode *> *)topologicalOrder:(NSError **)error;

/// Create a plan for a single cap execution
+ (instancetype)singleCapPlan:(NSString *)capUrn inputMedia:(NSString *)inputMedia outputMedia:(NSString *)outputMedia filePathArgName:(NSString *)filePathArgName;

/// Create a linear chain of caps
+ (instancetype)linearChainPlan:(NSArray<NSString *> *)capUrns inputMedia:(NSString *)inputMedia outputMedia:(NSString *)outputMedia filePathArgNames:(NSArray<NSString *> *)filePathArgNames;

@end

// MARK: - NodeExecutionResult

/// Result of executing a single node
/// Mirrors Rust: pub struct NodeExecutionResult
@interface CSNodeExecutionResult : NSObject

/// The node that was executed
@property (nonatomic, copy) CSNodeId nodeId;

/// Whether execution succeeded
@property (nonatomic, assign) BOOL success;

/// Binary output data (if any)
@property (nonatomic, strong, nullable) NSData *binaryOutput;

/// Text/JSON output (if any)
@property (nonatomic, copy, nullable) NSString *textOutput;

/// Error message if execution failed
@property (nonatomic, copy, nullable) NSString *error;

/// Execution duration in milliseconds
@property (nonatomic, assign) uint64_t durationMs;

@end

// MARK: - CapChainExecutionResult

/// Overall result of executing a cap chain
/// Mirrors Rust: pub struct CapChainExecutionResult
@interface CSCapChainExecutionResult : NSObject

/// Whether the entire chain executed successfully
@property (nonatomic, assign) BOOL success;

/// Results from each node
@property (nonatomic, strong) NSArray<CSNodeExecutionResult *> *nodeResults;

/// Final output from the chain
@property (nonatomic, strong, nullable) NSData *finalOutput;

/// Error message if chain failed
@property (nonatomic, copy, nullable) NSString *error;

/// Total execution time in milliseconds
@property (nonatomic, assign) uint64_t totalDurationMs;

@end

NS_ASSUME_NONNULL_END

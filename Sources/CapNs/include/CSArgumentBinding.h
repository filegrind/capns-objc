//
//  CSArgumentBinding.h
//  CapNs
//
//  Argument Binding for Cap Execution
//  Mirrors Rust: src/planner/argument_binding.rs
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// MARK: - SourceEntityType

/// Type of source entity (for internal tracking, not exposed to caps)
/// Mirrors Rust: pub enum SourceEntityType
typedef NS_ENUM(NSInteger, CSSourceEntityType) {
    CSSourceEntityTypeListing,
    CSSourceEntityTypeChip,
    CSSourceEntityTypeBlock,
    CSSourceEntityTypeCapOutput,
    CSSourceEntityTypeTemporary
};

// MARK: - CapFileMetadata

/// Metadata about a cap input file
/// Mirrors Rust: pub struct CapFileMetadata
@interface CSCapFileMetadata : NSObject

/// File name (without path)
@property (nonatomic, copy, nullable) NSString *filename;

/// File size in bytes
@property (nonatomic, strong, nullable) NSNumber *sizeBytes;

/// MIME type if known
@property (nonatomic, copy, nullable) NSString *mimeType;

/// Additional metadata as JSON
@property (nonatomic, strong, nullable) NSDictionary *extra;

@end

// MARK: - CapInputFile

/// A file presented to a cap for processing.
/// This is the uniform interface caps see - they never see listings, chips, or blocks directly.
/// Mirrors Rust: pub struct CapInputFile
@interface CSCapInputFile : NSObject

/// Actual filesystem path to the file
@property (nonatomic, copy) NSString *filePath;

/// Media URN describing the file type (e.g., "media:pdf")
@property (nonatomic, copy) NSString *mediaUrn;

/// Optional file metadata
@property (nonatomic, strong, nullable) CSCapFileMetadata *metadata;

/// Original source entity ID (for traceability, not passed to cap)
@property (nonatomic, copy, nullable) NSString *sourceId;

/// Type of source entity
@property (nonatomic, assign) CSSourceEntityType sourceType;

/// Tracked file ID for file lifecycle management with plugins.
@property (nonatomic, copy, nullable) NSString *trackedFileId;

/// Security bookmark for accessing the file from the sandboxed plugin (macOS only)
@property (nonatomic, strong, nullable) NSData *securityBookmark;

/// Original file path before container path resolution.
@property (nonatomic, copy, nullable) NSString *originalPath;

/// Create a basic input file
+ (instancetype)withFilePath:(NSString *)filePath mediaUrn:(NSString *)mediaUrn;

/// Create from listing
+ (instancetype)fromListingId:(NSString *)listingId filePath:(NSString *)filePath mediaUrn:(NSString *)mediaUrn;

/// Create from chip
+ (instancetype)fromChipId:(NSString *)chipId cachePath:(NSString *)cachePath mediaUrn:(NSString *)mediaUrn;

/// Create from cap output
+ (instancetype)fromCapOutput:(NSString *)outputPath mediaUrn:(NSString *)mediaUrn;

/// Add metadata
- (instancetype)withMetadata:(CSCapFileMetadata *)metadata;

/// Add file reference info
- (instancetype)withFileReference:(NSString *)trackedFileId
                  securityBookmark:(NSData *)securityBookmark
                      originalPath:(NSString *)originalPath;

/// Get filename from path
- (nullable NSString *)filename;

/// Check if has file reference
- (BOOL)hasFileReference;

@end

// MARK: - ArgumentSource

/// Source of a resolved argument value
/// Mirrors Rust: pub enum ArgumentSource
typedef NS_ENUM(NSInteger, CSArgumentSource) {
    CSArgumentSourceInputFile,
    CSArgumentSourcePreviousOutput,
    CSArgumentSourceCapDefault,
    CSArgumentSourceCapSetting,
    CSArgumentSourceLiteral,
    CSArgumentSourceSlot,
    CSArgumentSourcePlanMetadata
};

// MARK: - ArgumentBinding

/// How to resolve an argument value for cap execution.
/// Mirrors Rust: pub enum ArgumentBinding
@interface CSArgumentBinding : NSObject

/// Input file by index
+ (instancetype)inputFileAtIndex:(NSUInteger)index;

/// Input file path (current file)
+ (instancetype)inputFilePath;

/// Input media URN (current file)
+ (instancetype)inputMediaUrn;

/// Previous output from a node
+ (instancetype)previousOutputFromNode:(NSString *)nodeId outputField:(nullable NSString *)outputField;

/// Cap default value
+ (instancetype)capDefault;

/// Cap setting
+ (instancetype)capSetting:(NSString *)settingUrn;

/// Literal string value
+ (instancetype)literalString:(NSString *)value;

/// Literal number value
+ (instancetype)literalNumber:(NSInteger)value;

/// Literal boolean value
+ (instancetype)literalBool:(BOOL)value;

/// Literal JSON value
+ (instancetype)literalJson:(id)value;

/// Slot (requires user input)
+ (instancetype)slotNamed:(NSString *)name schema:(nullable NSDictionary *)schema;

/// Plan metadata
+ (instancetype)planMetadata:(NSString *)key;

/// Check if requires user input
- (BOOL)requiresInput;

/// Check if references previous node
- (BOOL)referencesPrevious;

@end

// MARK: - ResolvedArgument

/// A resolved argument ready for cap execution.
/// Mirrors Rust: pub struct ResolvedArgument
@interface CSResolvedArgument : NSObject

/// Argument name
@property (nonatomic, copy) NSString *name;

/// Argument value as bytes
@property (nonatomic, strong) NSData *value;

/// Source of the value
@property (nonatomic, assign) CSArgumentSource source;

+ (instancetype)withName:(NSString *)name value:(NSData *)value source:(CSArgumentSource)source;

@end

// MARK: - ArgumentResolutionContext

/// Context for resolving argument bindings during execution.
/// Mirrors Rust: pub struct ArgumentResolutionContext
@interface CSArgumentResolutionContext : NSObject

/// Input files
@property (nonatomic, copy) NSArray<CSCapInputFile *> *inputFiles;

/// Current file index
@property (nonatomic, assign) NSUInteger currentFileIndex;

/// Previous outputs (node_id -> JSON value)
@property (nonatomic, strong) NSDictionary<NSString *, id> *previousOutputs;

/// Plan metadata (key -> JSON value)
@property (nonatomic, strong, nullable) NSDictionary<NSString *, id> *planMetadata;

/// Cap settings (cap_urn -> setting_urn -> value)
@property (nonatomic, strong, nullable) NSDictionary<NSString *, NSDictionary<NSString *, id> *> *capSettings;

/// Slot values (slot_name -> bytes)
@property (nonatomic, strong, nullable) NSDictionary<NSString *, NSData *> *slotValues;

/// Create with input files
+ (instancetype)withInputFiles:(NSArray<CSCapInputFile *> *)inputFiles;

/// Get current file
- (nullable CSCapInputFile *)currentFile;

@end

/// Resolve an argument binding to raw bytes.
/// Mirrors Rust: pub fn resolve_binding
NSError *_Nullable CSResolveArgumentBinding(
    CSArgumentBinding *binding,
    CSArgumentResolutionContext *context,
    NSString *capUrn,
    id _Nullable defaultValue,
    BOOL isRequired,
    CSResolvedArgument *_Nullable *_Nullable outResolved
);

NS_ASSUME_NONNULL_END

//
//  CSMediaUrn.h
//  CapNs
//
//  Media URN - a TaggedUrn with required "media:" prefix
//  Exactly mirrors Rust MediaUrn struct (src/urn/media_urn.rs)
//

#import <Foundation/Foundation.h>

@class CSTaggedUrn;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const CSMediaUrnErrorDomain;

typedef NS_ERROR_ENUM(CSMediaUrnErrorDomain, CSMediaUrnError) {
    CSMediaUrnErrorInvalidPrefix = 1,
    CSMediaUrnErrorParse = 2
};

/// Media URN - a TaggedUrn with required "media:" prefix
/// Mirrors Rust: pub struct MediaUrn(TaggedUrn)
@interface CSMediaUrn : NSObject

/// The required prefix for all media URNs
@property (class, nonatomic, readonly) NSString *PREFIX;

/// The underlying TaggedUrn
@property (nonatomic, strong, readonly) CSTaggedUrn *inner;

/// Create a MediaUrn from a TaggedUrn
/// Returns nil if the TaggedUrn doesn't have the "media" prefix
/// Mirrors Rust: impl TryFrom<TaggedUrn> for MediaUrn
+ (nullable instancetype)fromTaggedUrn:(CSTaggedUrn *)urn error:(NSError **)error;

/// Create a MediaUrn from a string representation
/// The string must be a valid tagged URN with the "media" prefix
/// Mirrors Rust: impl FromStr for MediaUrn
+ (nullable instancetype)fromString:(NSString *)string error:(NSError **)error;

/// Get a tag value
/// Mirrors Rust: pub fn get_tag(&self, key: &str) -> Option<&str>
- (nullable NSString *)getTag:(NSString *)key;

/// Get all tags as a dictionary
- (NSDictionary<NSString *, NSString *> *)tags;

/// Convert to canonical string representation
/// Mirrors Rust: impl Display for MediaUrn
- (NSString *)toString;

/// Check if this instance conforms to (can be handled by) the given pattern.
/// Equivalent to `pattern.accepts(self)`.
/// Mirrors Rust: pub fn conforms_to(&self, pattern: &MediaUrn) -> Result<bool, MediaUrnError>
- (BOOL)conformsTo:(CSMediaUrn *)pattern error:(NSError **)error;

/// Check if this pattern accepts the given instance.
/// Equivalent to `instance.conformsTo(self)`.
/// Mirrors Rust: pub fn accepts(&self, instance: &MediaUrn) -> Result<bool, MediaUrnError>
- (BOOL)accepts:(CSMediaUrn *)instance error:(NSError **)error;

// MARK: - Predicates (mirror Rust MediaUrn predicates)

/// Check if this represents binary data (bytes marker tag present).
/// Mirrors Rust: pub fn is_binary(&self) -> bool
- (BOOL)isBinary;

/// Check if this represents a map/object form (form=map).
/// Mirrors Rust: pub fn is_map(&self) -> bool
- (BOOL)isMap;

/// Check if this represents a scalar form (form=scalar).
/// Mirrors Rust: pub fn is_scalar(&self) -> bool
- (BOOL)isScalar;

/// Check if this represents a list form (form=list).
/// Mirrors Rust: pub fn is_list(&self) -> bool
- (BOOL)isList;

/// Check if this represents structured data (map or list).
/// Mirrors Rust: pub fn is_structured(&self) -> bool
- (BOOL)isStructured;

/// Check if this represents JSON data (json marker tag present).
/// Mirrors Rust: pub fn is_json(&self) -> bool
- (BOOL)isJson;

/// Check if this represents text data (textable marker tag present).
/// Mirrors Rust: pub fn is_text(&self) -> bool
- (BOOL)isText;

/// Check if this represents void (void marker tag present).
/// Mirrors Rust: pub fn is_void(&self) -> bool
- (BOOL)isVoid;

/// Check if this represents image data (image marker tag present).
/// Mirrors Rust: pub fn is_image(&self) -> bool
- (BOOL)isImage;

/// Check if this represents audio data (audio marker tag present).
/// Mirrors Rust: pub fn is_audio(&self) -> bool
- (BOOL)isAudio;

/// Check if this represents video data (video marker tag present).
/// Mirrors Rust: pub fn is_video(&self) -> bool
- (BOOL)isVideo;

/// Check if this represents numeric data (numeric marker tag present).
/// Mirrors Rust: pub fn is_numeric(&self) -> bool
- (BOOL)isNumeric;

/// Check if this represents boolean data (bool marker tag present).
/// Mirrors Rust: pub fn is_bool(&self) -> bool
- (BOOL)isBool;

/// Check if this represents a single file path (file-path marker AND NOT list).
/// Mirrors Rust: pub fn is_file_path(&self) -> bool
- (BOOL)isFilePath;

/// Check if this represents a file path array (file-path marker AND list).
/// Mirrors Rust: pub fn is_file_path_array(&self) -> bool
- (BOOL)isFilePathArray;

/// Check if this represents any file path type (single or array).
/// Mirrors Rust: pub fn is_any_file_path(&self) -> bool
- (BOOL)isAnyFilePath;

/// Check if this represents a collection type (collection marker tag present).
/// Mirrors Rust: pub fn is_collection(&self) -> bool
- (BOOL)isCollection;

@end

NS_ASSUME_NONNULL_END

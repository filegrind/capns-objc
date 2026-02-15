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

@end

NS_ASSUME_NONNULL_END

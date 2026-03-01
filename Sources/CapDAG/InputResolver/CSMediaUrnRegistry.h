//
//  CSMediaUrnRegistry.h
//  CapDAG
//
//  MediaUrnRegistry — Extension to URN mapping from bundled specs
//
//  Mirrors Rust: capdag/src/media/registry.rs
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Registry for mapping file extensions to media URNs
///
/// This registry provides extension-to-URN mapping based on the bundled
/// media spec definitions (from capdag-dot-com/standard/media/*.toml).
///
/// The registry is used by the InputResolver to determine the base URN
/// for a file, which adapters can then refine with content inspection.
@interface CSMediaUrnRegistry : NSObject

/// Shared singleton instance
+ (CSMediaUrnRegistry *)shared;

/// Get all media URNs registered for an extension
///
/// @param extension File extension (without leading dot, case-insensitive)
/// @return Array of URNs, or empty array if extension not found
- (NSArray<NSString *> *)mediaUrnsForExtension:(NSString *)extension;

/// Get the primary media URN for an extension
///
/// This returns the first (most specific) URN for the extension.
/// For extensions with content inspection adapters, this returns
/// the base URN (e.g., "media:json;textable" for .json).
///
/// @param extension File extension (without leading dot, case-insensitive)
/// @return Primary URN, or nil if extension not found
- (nullable NSString *)primaryMediaUrnForExtension:(NSString *)extension;

/// Check if an extension is registered
///
/// @param extension File extension (without leading dot, case-insensitive)
/// @return YES if the extension has registered URNs
- (BOOL)hasExtension:(NSString *)extension;

/// Get all registered extensions
- (NSArray<NSString *> *)allExtensions;

@end

NS_ASSUME_NONNULL_END

//
//  CSCollectionInput.h
//  CapNs
//
//  Collection Input Types for Cap Chain Processing
//  Mirrors Rust: src/planner/collection_input.rs
//

#import <Foundation/Foundation.h>

@class CSCapInputFile;

NS_ASSUME_NONNULL_BEGIN

// MARK: - CollectionFile

/// A file entry within a collection map.
/// Mirrors Rust: pub struct CollectionFile
@interface CSCollectionFile : NSObject

/// The listing ID from the database
@property (nonatomic, copy) NSString *listingId;

/// Full filesystem path to the file
@property (nonatomic, copy) NSString *filePath;

/// Media URN describing the file type (e.g., "media:pdf")
@property (nonatomic, copy) NSString *mediaUrn;

/// Optional human-readable title
@property (nonatomic, copy, nullable) NSString *title;

/// Security bookmark for sandboxed access (runtime-only, not serialized)
@property (nonatomic, strong, nullable) NSData *securityBookmark;

/// Create a new collection file entry
+ (instancetype)withListingId:(NSString *)listingId filePath:(NSString *)filePath mediaUrn:(NSString *)mediaUrn;

/// Set the title
- (instancetype)withTitle:(NSString *)title;

/// Set the security bookmark
- (instancetype)withSecurityBookmark:(NSData *)bookmark;

@end

// MARK: - CapInputCollection

/// A collection as structured input for capchain processing.
/// Represents a folder hierarchy with files and nested subfolders.
/// Mirrors Rust: pub struct CapInputCollection
@interface CSCapInputCollection : NSObject

/// The folder ID from the database
@property (nonatomic, copy) NSString *folderId;

/// Human-readable folder name
@property (nonatomic, copy) NSString *folderName;

/// Files directly in this folder
@property (nonatomic, strong) NSMutableArray<CSCollectionFile *> *files;

/// Nested subfolders (folder_name -> collection)
@property (nonatomic, strong) NSMutableDictionary<NSString *, CSCapInputCollection *> *folders;

/// Media URN for this collection
@property (nonatomic, copy) NSString *mediaUrn;

/// Create a new empty collection
+ (instancetype)withFolderId:(NSString *)folderId folderName:(NSString *)folderName;

/// Serialize to JSON dictionary for cap processing
- (NSDictionary *)toJSON;

/// Flatten to a list of CapInputFile for list handling.
/// Recursively collects all files from this collection and all nested subfolders.
- (NSArray<CSCapInputFile *> *)flattenToFiles;

/// Get the total number of files in this collection (including nested)
- (NSUInteger)totalFileCount;

/// Get the total number of folders in this collection (including nested)
- (NSUInteger)totalFolderCount;

/// Check if this collection is empty (no files and no subfolders)
- (BOOL)isEmpty;

@end

NS_ASSUME_NONNULL_END

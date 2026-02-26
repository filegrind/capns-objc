//
//  CSCollectionInput.m
//  CapNs
//
//  Collection Input Types for Cap Chain Processing
//  Mirrors Rust: src/planner/collection_input.rs
//

#import "CSCollectionInput.h"
#import "CSArgumentBinding.h"

/// Media URN for a collection input structure (capchain internal)
static NSString * const COLLECTION_MEDIA_URN = @"media:collection;record;textable";

// MARK: - CollectionFile

@implementation CSCollectionFile

+ (instancetype)withListingId:(NSString *)listingId filePath:(NSString *)filePath mediaUrn:(NSString *)mediaUrn {
    CSCollectionFile *file = [[CSCollectionFile alloc] init];
    file.listingId = listingId;
    file.filePath = filePath;
    file.mediaUrn = mediaUrn;
    return file;
}

- (instancetype)withTitle:(NSString *)title {
    self.title = title;
    return self;
}

- (instancetype)withSecurityBookmark:(NSData *)bookmark {
    self.securityBookmark = bookmark;
    return self;
}

@end

// MARK: - CapInputCollection

@implementation CSCapInputCollection

+ (instancetype)withFolderId:(NSString *)folderId folderName:(NSString *)folderName {
    CSCapInputCollection *collection = [[CSCapInputCollection alloc] init];
    collection.folderId = folderId;
    collection.folderName = folderName;
    collection.files = [NSMutableArray array];
    collection.folders = [NSMutableDictionary dictionary];
    collection.mediaUrn = COLLECTION_MEDIA_URN;
    return collection;
}

- (NSDictionary *)toJSON {
    NSMutableDictionary *json = [NSMutableDictionary dictionary];
    json[@"folder_id"] = self.folderId;
    json[@"folder_name"] = self.folderName;
    json[@"media_urn"] = self.mediaUrn;

    // Serialize files
    NSMutableArray *filesArray = [NSMutableArray arrayWithCapacity:self.files.count];
    for (CSCollectionFile *file in self.files) {
        NSMutableDictionary *fileDict = [NSMutableDictionary dictionary];
        fileDict[@"listing_id"] = file.listingId;
        fileDict[@"file_path"] = file.filePath;
        fileDict[@"media_urn"] = file.mediaUrn;
        if (file.title) {
            fileDict[@"title"] = file.title;
        }
        [filesArray addObject:fileDict];
    }
    json[@"files"] = filesArray;

    // Serialize folders (recursively)
    NSMutableDictionary *foldersDict = [NSMutableDictionary dictionary];
    for (NSString *folderName in self.folders) {
        CSCapInputCollection *subfolder = self.folders[folderName];
        foldersDict[folderName] = [subfolder toJSON];
    }
    json[@"folders"] = foldersDict;

    return json;
}

- (NSArray<CSCapInputFile *> *)flattenToFiles {
    NSMutableArray<CSCapInputFile *> *result = [NSMutableArray array];
    [self collectFilesRecursive:result];
    return result;
}

- (void)collectFilesRecursive:(NSMutableArray<CSCapInputFile *> *)result {
    // Add files from this folder
    for (CSCollectionFile *file in self.files) {
        CSCapInputFile *inputFile = [CSCapInputFile withFilePath:file.filePath mediaUrn:file.mediaUrn];
        inputFile.sourceId = file.listingId;
        inputFile.sourceType = CSSourceEntityTypeListing;
        if (file.securityBookmark) {
            inputFile.securityBookmark = file.securityBookmark;
        }
        [result addObject:inputFile];
    }

    // Recursively add files from subfolders
    for (CSCapInputCollection *subfolder in self.folders.allValues) {
        [subfolder collectFilesRecursive:result];
    }
}

- (NSUInteger)totalFileCount {
    NSUInteger count = self.files.count;
    for (CSCapInputCollection *subfolder in self.folders.allValues) {
        count += [subfolder totalFileCount];
    }
    return count;
}

- (NSUInteger)totalFolderCount {
    NSUInteger count = self.folders.count;
    for (CSCapInputCollection *subfolder in self.folders.allValues) {
        count += [subfolder totalFolderCount];
    }
    return count;
}

- (BOOL)isEmpty {
    return self.files.count == 0 && self.folders.count == 0;
}

@end

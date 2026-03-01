//
//  CSStdinSource.m
//  CapDAG
//
//  Implementation of stdin source types.
//

#import "CSStdinSource.h"

@interface CSStdinSource ()
@property (nonatomic, assign) CSStdinSourceKind kind;
@property (nonatomic, strong, nullable) NSData *data;
@property (nonatomic, strong, nullable) NSString *trackedFileID;
@property (nonatomic, strong, nullable) NSString *originalPath;
@property (nonatomic, strong, nullable) NSData *securityBookmark;
@property (nonatomic, strong, nullable) NSString *mediaUrn;
@end

@implementation CSStdinSource

+ (instancetype)sourceWithData:(NSData *)data {
    CSStdinSource *source = [[CSStdinSource alloc] init];
    source.kind = CSStdinSourceKindData;
    source.data = data;
    return source;
}

+ (instancetype)sourceWithFileReference:(NSString *)trackedFileID
                           originalPath:(NSString *)originalPath
                        securityBookmark:(NSData *)securityBookmark
                                mediaUrn:(NSString *)mediaUrn {
    CSStdinSource *source = [[CSStdinSource alloc] init];
    source.kind = CSStdinSourceKindFileReference;
    source.trackedFileID = trackedFileID;
    source.originalPath = originalPath;
    source.securityBookmark = securityBookmark;
    source.mediaUrn = mediaUrn;
    return source;
}

- (BOOL)isData {
    return self.kind == CSStdinSourceKindData;
}

- (BOOL)isFileReference {
    return self.kind == CSStdinSourceKindFileReference;
}

@end

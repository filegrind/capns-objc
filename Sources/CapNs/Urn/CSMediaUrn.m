//
//  CSMediaUrn.m
//  CapNs
//
//  Media URN - a TaggedUrn with required "media:" prefix
//  Exactly mirrors Rust MediaUrn struct (src/urn/media_urn.rs)
//

#import "CSMediaUrn.h"
#import "CSTaggedUrn.h"

NSErrorDomain const CSMediaUrnErrorDomain = @"CSMediaUrnErrorDomain";

@implementation CSMediaUrn

+ (NSString *)PREFIX {
    return @"media";
}

+ (nullable instancetype)fromTaggedUrn:(CSTaggedUrn *)urn error:(NSError **)error {
    if (!urn) {
        if (error) {
            *error = [NSError errorWithDomain:CSMediaUrnErrorDomain
                                         code:CSMediaUrnErrorParse
                                     userInfo:@{NSLocalizedDescriptionKey: @"TaggedUrn cannot be nil"}];
        }
        return nil;
    }

    // Validate prefix is "media" (case-insensitive, matching Rust behavior)
    if (![[urn.prefix lowercaseString] isEqualToString:@"media"]) {
        if (error) {
            *error = [NSError errorWithDomain:CSMediaUrnErrorDomain
                                         code:CSMediaUrnErrorInvalidPrefix
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Expected 'media' prefix, got '%@'", urn.prefix]}];
        }
        return nil;
    }

    CSMediaUrn *mediaUrn = [[CSMediaUrn alloc] init];
    mediaUrn->_inner = urn;
    return mediaUrn;
}

+ (nullable instancetype)fromString:(NSString *)string error:(NSError **)error {
    // Parse as TaggedUrn first (matching Rust: TaggedUrn::from_str then try_into)
    NSError *parseError = nil;
    CSTaggedUrn *urn = [CSTaggedUrn fromString:string error:&parseError];
    if (!urn) {
        if (error) {
            *error = [NSError errorWithDomain:CSMediaUrnErrorDomain
                                         code:CSMediaUrnErrorParse
                                     userInfo:@{NSLocalizedDescriptionKey: parseError.localizedDescription ?: @"Failed to parse as TaggedUrn"}];
        }
        return nil;
    }

    // Validate prefix (matching Rust: check prefix == "media")
    return [self fromTaggedUrn:urn error:error];
}

- (nullable NSString *)getTag:(NSString *)key {
    return [self.inner getTag:key];
}

- (NSDictionary<NSString *, NSString *> *)tags {
    return self.inner.tags;
}

- (NSString *)toString {
    return [self.inner toString];
}

- (NSString *)description {
    return [self toString];
}

- (BOOL)conformsTo:(CSMediaUrn *)pattern error:(NSError **)error {
    return [self.inner conformsTo:pattern.inner error:error];
}

- (BOOL)accepts:(CSMediaUrn *)instance error:(NSError **)error {
    return [self.inner accepts:instance.inner error:error];
}

- (BOOL)isEquivalentTo:(CSMediaUrn *)other {
    NSError *err = nil;
    BOOL forward = [self accepts:other error:&err];
    if (err || !forward) return NO;
    BOOL reverse = [other accepts:self error:&err];
    if (err) return NO;
    return reverse;
}

// MARK: - Builders

- (CSMediaUrn *)withTag:(NSString *)key value:(NSString *)value {
    CSTaggedUrn *modified = [self.inner withTag:key value:value];
    NSError *error;
    CSMediaUrn *result = [CSMediaUrn fromTaggedUrn:modified error:&error];
    NSAssert(result != nil, @"CSMediaUrn withTag:value: failed — inner withTag produced invalid MediaUrn: %@", error);
    return result;
}

- (CSMediaUrn *)withoutTag:(NSString *)key {
    CSTaggedUrn *modified = [self.inner withoutTag:key];
    NSError *error;
    CSMediaUrn *result = [CSMediaUrn fromTaggedUrn:modified error:&error];
    NSAssert(result != nil, @"CSMediaUrn withoutTag: failed — inner withoutTag produced invalid MediaUrn: %@", error);
    return result;
}

// MARK: - Predicates

- (BOOL)isBinary {
    return [self getTag:@"textable"] == nil;
}

- (BOOL)isMap {
    NSString *form = [self getTag:@"form"];
    return form != nil && [form isEqualToString:@"map"];
}

- (BOOL)isScalar {
    NSString *form = [self getTag:@"form"];
    return form != nil && [form isEqualToString:@"scalar"];
}

- (BOOL)isList {
    NSString *form = [self getTag:@"form"];
    return form != nil && [form isEqualToString:@"list"];
}

- (BOOL)isStructured {
    return [self isMap] || [self isList];
}

- (BOOL)isJson {
    return [self getTag:@"json"] != nil;
}

- (BOOL)isText {
    return [self getTag:@"textable"] != nil;
}

- (BOOL)isVoid {
    return [self getTag:@"void"] != nil;
}

- (BOOL)isImage {
    return [self getTag:@"image"] != nil;
}

- (BOOL)isAudio {
    return [self getTag:@"audio"] != nil;
}

- (BOOL)isVideo {
    return [self getTag:@"video"] != nil;
}

- (BOOL)isNumeric {
    return [self getTag:@"numeric"] != nil;
}

- (BOOL)isBool {
    return [self getTag:@"bool"] != nil;
}

- (BOOL)isFilePath {
    return [self getTag:@"file-path"] != nil && ![self isList];
}

- (BOOL)isFilePathArray {
    return [self getTag:@"file-path"] != nil && [self isList];
}

- (BOOL)isAnyFilePath {
    return [self isFilePath] || [self isFilePathArray];
}

- (BOOL)isCollection {
    return [self getTag:@"collection"] != nil;
}

@end

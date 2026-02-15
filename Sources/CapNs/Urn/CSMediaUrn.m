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

@end

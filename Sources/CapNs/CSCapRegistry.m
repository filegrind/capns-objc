//
//  CSCapRegistry.m
//  CapNs
//
//  Registry client for fetching canonical cap definitions from capns.org
//

#import "CSCapRegistry.h"
#import "CSCap.h"
#import "CSCapUrn.h"
#import <CommonCrypto/CommonDigest.h>

static NSString * const REGISTRY_BASE_URL = @"https://capns.org";
static const NSTimeInterval CACHE_DURATION_HOURS = 24.0;
static const NSTimeInterval HTTP_TIMEOUT_SECONDS = 10.0;

// MARK: - Cache Entry

@interface CSCacheEntry : NSObject
@property (nonatomic, strong) CSCap *definition;
@property (nonatomic) NSTimeInterval cachedAt;
@property (nonatomic) NSTimeInterval ttlHours;
- (BOOL)isExpired;
@end

@implementation CSCacheEntry

- (BOOL)isExpired {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    return now > (self.cachedAt + (self.ttlHours * 3600));
}

@end

// MARK: - CSCapRegistry

@interface CSCapRegistry ()
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSString *cacheDirectory;
@end

@implementation CSCapRegistry

- (instancetype)init {
    self = [super init];
    if (self) {
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = HTTP_TIMEOUT_SECONDS;
        config.timeoutIntervalForResource = HTTP_TIMEOUT_SECONDS;
        _session = [NSURLSession sessionWithConfiguration:config];
        
        // Setup cache directory
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        NSString *cacheDir = [paths firstObject];
        _cacheDirectory = [cacheDir stringByAppendingPathComponent:@"capns"];
        
        // Create cache directory
        [[NSFileManager defaultManager] createDirectoryAtPath:_cacheDirectory
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];
    }
    return self;
}

- (void)getCapWithUrn:(NSString *)urn completion:(void (^)(CSCap *cap, NSError *error))completion {
    // Try cache first
    CSCap *cachedCap = [self loadFromCache:urn];
    if (cachedCap) {
        completion(cachedCap, nil);
        return;
    }
    
    // Fetch from registry
    [self fetchFromRegistryWithUrn:urn completion:completion];
}

- (void)getCapsWithUrns:(NSArray<NSString *> *)urns completion:(void (^)(NSArray<CSCap *> *caps, NSError *error))completion {
    dispatch_group_t group = dispatch_group_create();
    NSMutableArray<CSCap *> *caps = [NSMutableArray array];
    __block NSError *firstError = nil;
    
    for (NSString *urn in urns) {
        dispatch_group_enter(group);
        
        [self getCapWithUrn:urn completion:^(CSCap *cap, NSError *error) {
            if (error && !firstError) {
                firstError = error;
            } else if (cap) {
                @synchronized (caps) {
                    [caps addObject:cap];
                }
            }
            dispatch_group_leave(group);
        }];
    }
    
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        if (firstError) {
            completion(nil, firstError);
        } else {
            completion([caps copy], nil);
        }
    });
}

- (void)validateCap:(CSCap *)cap completion:(void (^)(NSError *error))completion {
    NSString *urn = [cap.capUrn toString];
    [self getCapWithUrn:urn completion:^(CSCap *canonicalCap, NSError *error) {
        if (error) {
            completion(error);
            return;
        }
        
        // Validate basic properties
        if (![cap.version isEqualToString:canonicalCap.version]) {
            NSError *validationError = [NSError errorWithDomain:@"CSCapRegistryError"
                                                           code:1002
                                                       userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Version mismatch. Local: %@, Canonical: %@", cap.version, canonicalCap.version]}];
            completion(validationError);
            return;
        }
        
        if (![cap.command isEqualToString:canonicalCap.command]) {
            NSError *validationError = [NSError errorWithDomain:@"CSCapRegistryError"
                                                           code:1003
                                                       userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Command mismatch. Local: %@, Canonical: %@", cap.command, canonicalCap.command]}];
            completion(validationError);
            return;
        }
        
        if (cap.acceptsStdin != canonicalCap.acceptsStdin) {
            NSError *validationError = [NSError errorWithDomain:@"CSCapRegistryError"
                                                           code:1004
                                                       userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"accepts_stdin mismatch. Local: %@, Canonical: %@", cap.acceptsStdin ? @"YES" : @"NO", canonicalCap.acceptsStdin ? @"YES" : @"NO"]}];
            completion(validationError);
            return;
        }
        
        completion(nil); // Validation passed
    }];
}

- (BOOL)capExists:(NSString *)urn {
    // First check cache
    if ([self loadFromCache:urn]) {
        return YES;
    }
    
    // For sync check, we'd need to make synchronous request
    // This is not recommended in iOS. For now, return NO for uncached caps
    // In real implementation, you'd probably want an async version
    return NO;
}

- (void)clearCache {
    [[NSFileManager defaultManager] removeItemAtPath:self.cacheDirectory error:nil];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.cacheDirectory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
}

// MARK: - Private Methods

- (NSString *)cacheKeyForUrn:(NSString *)urn {
    NSData *data = [urn dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    
    NSMutableString *output = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        [output appendFormat:@"%02x", digest[i]];
    }
    return output;
}

- (NSString *)cacheFilePathForUrn:(NSString *)urn {
    NSString *key = [self cacheKeyForUrn:urn];
    return [self.cacheDirectory stringByAppendingPathComponent:[key stringByAppendingString:@".json"]];
}

- (CSCap *)loadFromCache:(NSString *)urn {
    NSString *cacheFile = [self cacheFilePathForUrn:urn];
    
    NSData *data = [NSData dataWithContentsOfFile:cacheFile];
    if (!data) {
        return nil;
    }
    
    NSError *error;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (!json) {
        return nil;
    }
    
    CSCacheEntry *entry = [[CSCacheEntry alloc] init];
    entry.cachedAt = [json[@"cached_at"] doubleValue];
    entry.ttlHours = [json[@"ttl_hours"] doubleValue];
    
    if ([entry isExpired]) {
        [[NSFileManager defaultManager] removeItemAtPath:cacheFile error:nil];
        return nil;
    }
    
    NSDictionary *capDict = json[@"definition"];
    CSCap *cap = [CSCap capWithDictionary:capDict error:&error];
    if (!cap) {
        return nil;
    }
    
    return cap;
}

- (void)saveToCache:(CSCap *)cap {
    NSString *urn = [cap.capUrn toString];
    NSString *cacheFile = [self cacheFilePathForUrn:urn];
    
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    
    NSDictionary *capDict = [cap toDictionary];
    
    NSDictionary *cacheEntry = @{
        @"definition": capDict,
        @"cached_at": @(now),
        @"ttl_hours": @(CACHE_DURATION_HOURS)
    };
    
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:cacheEntry options:NSJSONWritingPrettyPrinted error:&error];
    if (jsonData) {
        [jsonData writeToFile:cacheFile atomically:YES];
    }
}

- (void)fetchFromRegistryWithUrn:(NSString *)urn completion:(void (^)(CSCap *cap, NSError *error))completion {
    NSString *urlString = [NSString stringWithFormat:@"%@/%@", REGISTRY_BASE_URL, urn];
    NSURL *url = [NSURL URLWithString:urlString];
    
    NSURLSessionDataTask *task = [self.session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            completion(nil, error);
            return;
        }
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode != 200) {
            NSError *httpError = [NSError errorWithDomain:@"CSCapRegistryError"
                                                     code:httpResponse.statusCode
                                                 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Cap '%@' not found in registry (HTTP %ld)", urn, (long)httpResponse.statusCode]}];
            completion(nil, httpError);
            return;
        }
        
        NSError *parseError;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
        if (!json) {
            NSError *jsonError = [NSError errorWithDomain:@"CSCapRegistryError"
                                                     code:1001
                                                 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to parse registry response for '%@'", urn]}];
            completion(nil, jsonError);
            return;
        }
        
        CSCap *cap = [CSCap capWithDictionary:json error:&parseError];
        if (!cap) {
            NSError *capError = [NSError errorWithDomain:@"CSCapRegistryError"
                                                    code:1001
                                                userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to create cap from registry response for '%@'", urn]}];
            completion(nil, capError);
            return;
        }
        
        // Cache the result
        [self saveToCache:cap];
        
        completion(cap, nil);
    }];
    
    [task resume];
}

@end

// MARK: - Validation Functions

void CSValidateCapCanonical(CSCapRegistry *registry, CSCap *cap, void (^completion)(NSError *error)) {
    [registry validateCap:cap completion:completion];
}
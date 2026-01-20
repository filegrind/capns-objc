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
@property (nonatomic, strong) NSMutableDictionary<NSString *, CSCap *> *cachedCaps;
@property (nonatomic, strong) NSLock *cacheLock;
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
        
        // Initialize in-memory cache
        _cachedCaps = [[NSMutableDictionary alloc] init];
        _cacheLock = [[NSLock alloc] init];
        
        // Load all cached caps into memory
        [self loadAllCachedCaps];
    }
    return self;
}

- (void)getCapWithUrn:(NSString *)urn completion:(void (^)(CSCap *cap, NSError *error))completion {
    // Check in-memory cache first
    [self.cacheLock lock];
    CSCap *cachedCap = self.cachedCaps[urn];
    [self.cacheLock unlock];
    
    if (cachedCap) {
        completion(cachedCap, nil);
        return;
    }
    
    // Fetch from registry and update in-memory cache
    [self fetchFromRegistryWithUrn:urn completion:^(CSCap *cap, NSError *error) {
        if (cap) {
            [self.cacheLock lock];
            self.cachedCaps[urn] = cap;
            [self.cacheLock unlock];
        }
        completion(cap, error);
    }];
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
        
        // Validate basic properties (version validation removed as per new architecture)
        
        if (![cap.command isEqualToString:canonicalCap.command]) {
            NSError *validationError = [NSError errorWithDomain:@"CSCapRegistryError"
                                                           code:1003
                                                       userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Command mismatch. Local: %@, Canonical: %@", cap.command, canonicalCap.command]}];
            completion(validationError);
            return;
        }

        // Compare stdin - both nil or both equal strings
        BOOL stdinMatches = (cap.stdinType == nil && canonicalCap.stdinType == nil) ||
                           (cap.stdinType != nil && canonicalCap.stdinType != nil && [cap.stdinType isEqualToString:canonicalCap.stdinType]);
        if (!stdinMatches) {
            NSError *validationError = [NSError errorWithDomain:@"CSCapRegistryError"
                                                           code:1004
                                                       userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"stdin mismatch. Local: %@, Canonical: %@", cap.stdinType ?: @"(none)", canonicalCap.stdinType ?: @"(none)"]}];
            completion(validationError);
            return;
        }

        completion(nil); // Validation passed
    }];
}

- (NSArray<CSCap *> *)getCachedCaps {
    [self.cacheLock lock];
    NSArray<CSCap *> *caps = [self.cachedCaps allValues];
    [self.cacheLock unlock];
    return caps;
}

- (BOOL)capExists:(NSString *)urn {
    [self.cacheLock lock];
    BOOL exists = (self.cachedCaps[urn] != nil);
    [self.cacheLock unlock];
    return exists;
}

- (void)clearCache {
    // Clear in-memory cache
    [self.cacheLock lock];
    [self.cachedCaps removeAllObjects];
    [self.cacheLock unlock];
    
    // Clear filesystem cache
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

- (void)loadAllCachedCaps {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray *files = [fileManager contentsOfDirectoryAtPath:self.cacheDirectory error:nil];
    
    for (NSString *filename in files) {
        if (![filename hasSuffix:@".json"]) {
            continue;
        }
        
        NSString *filePath = [self.cacheDirectory stringByAppendingPathComponent:filename];
        NSData *data = [NSData dataWithContentsOfFile:filePath];
        if (!data) {
            continue;
        }
        
        NSError *error;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
        if (!json) {
            continue;
        }
        
        CSCacheEntry *entry = [[CSCacheEntry alloc] init];
        entry.cachedAt = [json[@"cached_at"] doubleValue];
        entry.ttlHours = [json[@"ttl_hours"] doubleValue];
        
        if ([entry isExpired]) {
            // Remove expired cache file
            [fileManager removeItemAtPath:filePath error:nil];
            continue;
        }
        
        NSDictionary *capDict = json[@"definition"];
        CSCap *cap = [CSCap capWithDictionary:capDict error:&error];
        if (!cap) {
            continue;
        }
        
        NSString *urn = [cap.capUrn toString];
        [self.cacheLock lock];
        self.cachedCaps[urn] = cap;
        [self.cacheLock unlock];
    }
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
    // Normalize the cap URN using the proper parser
    NSString *normalizedUrn = urn;
    NSError *parseError = nil;
    CSCapUrn *parsedUrn = [CSCapUrn fromString:urn error:&parseError];
    if (parsedUrn) {
        normalizedUrn = [parsedUrn toString];
    }

    // URL-encode only the tags part (after "cap:") while keeping "cap:" literal
    NSString *tagsPart = normalizedUrn;
    if ([normalizedUrn hasPrefix:@"cap:"]) {
        tagsPart = [normalizedUrn substringFromIndex:4];
    }
    NSString *encodedTags = [tagsPart stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet alphanumericCharacterSet]];
    NSString *urlString = [NSString stringWithFormat:@"%@/cap:%@", REGISTRY_BASE_URL, encodedTags];
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
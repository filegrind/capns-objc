//
//  CSCapHostRegistry.m
//  CapHost registry implementation
//

#import "include/CSCapHostRegistry.h"
#import "include/CSCapUrn.h"

// Error domain for capability host registry
static NSString * const CSCapHostRegistryErrorDomain = @"CSCapHostRegistryError";

/**
 * Internal capability host entry
 */
@interface CSCapHostEntry : NSObject
@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) id<CSCapHost> host;
@property (nonatomic, strong) NSArray<CSCap *> *capabilities;
@end

@implementation CSCapHostEntry
@end

/**
 * CSCapHostRegistry implementation
 */
@interface CSCapHostRegistry ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, CSCapHostEntry *> *hosts;
@end

@implementation CSCapHostRegistry

+ (instancetype)registry {
    return [[self alloc] init];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _hosts = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (BOOL)registerCapHost:(NSString *)name
                   host:(id<CSCapHost>)host
           capabilities:(NSArray<CSCap *> *)capabilities {
    return [self registerCapHost:name host:host capabilities:capabilities error:nil];
}

- (BOOL)registerCapHost:(NSString *)name
                   host:(id<CSCapHost>)host
           capabilities:(NSArray<CSCap *> *)capabilities
                  error:(NSError * _Nullable * _Nullable)error {
    
    // Validate inputs
    if (!name || name.length == 0) {
        if (error) {
            *error = [CSCapHostRegistryError registryError:@"Host name cannot be nil or empty"];
        }
        return NO;
    }
    
    if (!host) {
        if (error) {
            *error = [CSCapHostRegistryError registryError:@"CapHost cannot be nil"];
        }
        return NO;
    }
    
    if (!capabilities) {
        if (error) {
            *error = [CSCapHostRegistryError registryError:@"Capabilities array cannot be nil"];
        }
        return NO;
    }
    
    // Check if host already exists
    if (self.hosts[name]) {
        if (error) {
            *error = [CSCapHostRegistryError registryError:[NSString stringWithFormat:@"Host with name '%@' is already registered", name]];
        }
        return NO;
    }
    
    CSCapHostEntry *entry = [[CSCapHostEntry alloc] init];
    entry.name = name;
    entry.host = host;
    entry.capabilities = capabilities;
    
    self.hosts[name] = entry;
    return YES;
}

- (nullable NSArray<id<CSCapHost>> *)findCapHosts:(NSString *)requestUrn
                                            error:(NSError * _Nullable * _Nullable)error {
    
    NSError *parseError = nil;
    CSCapUrn *request = [CSCapUrn fromString:requestUrn error:&parseError];
    if (!request) {
        if (error) {
            *error = [CSCapHostRegistryError invalidUrnError:requestUrn 
                                                      reason:parseError.localizedDescription];
        }
        return nil;
    }
    
    NSMutableArray<id<CSCapHost>> *matchingHosts = [[NSMutableArray alloc] init];
    
    for (CSCapHostEntry *entry in [self.hosts allValues]) {
        for (CSCap *cap in entry.capabilities) {
            if ([cap.capUrn matches:request]) {
                [matchingHosts addObject:entry.host];
                break; // Found a matching capability for this host, no need to check others
            }
        }
    }
    
    if (matchingHosts.count == 0) {
        if (error) {
            *error = [CSCapHostRegistryError noHostsFoundErrorForCapability:requestUrn];
        }
        return nil;
    }
    
    return [matchingHosts copy];
}

- (nullable id<CSCapHost>)findBestCapHost:(NSString *)requestUrn
                                    error:(NSError * _Nullable * _Nullable)error {
    
    NSError *parseError = nil;
    CSCapUrn *request = [CSCapUrn fromString:requestUrn error:&parseError];
    if (!request) {
        if (error) {
            *error = [CSCapHostRegistryError invalidUrnError:requestUrn 
                                                      reason:parseError.localizedDescription];
        }
        return nil;
    }
    
    id<CSCapHost> bestHost = nil;
    NSInteger bestSpecificity = -1;
    
    for (CSCapHostEntry *entry in [self.hosts allValues]) {
        for (CSCap *cap in entry.capabilities) {
            if ([cap.capUrn matches:request]) {
                NSInteger specificity = [cap.capUrn specificity];
                if (bestSpecificity == -1 || specificity > bestSpecificity) {
                    bestHost = entry.host;
                    bestSpecificity = specificity;
                }
                break; // Found a matching capability for this host, check next host
            }
        }
    }
    
    if (!bestHost) {
        if (error) {
            *error = [CSCapHostRegistryError noHostsFoundErrorForCapability:requestUrn];
        }
        return nil;
    }
    
    return bestHost;
}

- (NSArray<NSString *> *)getHostNames {
    return [self.hosts allKeys];
}

- (NSArray<CSCap *> *)getAllCapabilities {
    NSMutableArray<CSCap *> *allCapabilities = [[NSMutableArray alloc] init];
    for (CSCapHostEntry *entry in [self.hosts allValues]) {
        [allCapabilities addObjectsFromArray:entry.capabilities];
    }
    return [allCapabilities copy];
}

- (BOOL)canHandle:(NSString *)requestUrn {
    NSArray<id<CSCapHost>> *hosts = [self findCapHosts:requestUrn error:nil];
    return hosts != nil && hosts.count > 0;
}

- (BOOL)unregisterCapHost:(NSString *)name {
    if (self.hosts[name]) {
        [self.hosts removeObjectForKey:name];
        return YES;
    }
    return NO;
}

- (void)clear {
    [self.hosts removeAllObjects];
}

@end

/**
 * CSCapHostRegistryError implementation
 */
@implementation CSCapHostRegistryError

+ (instancetype)noHostsFoundErrorForCapability:(NSString *)capability {
    NSString *message = [NSString stringWithFormat:@"No capability hosts found for capability: %@", capability];
    return [self errorWithDomain:CSCapHostRegistryErrorDomain
                            code:CSCapHostRegistryErrorTypeNoHostsFound
                        userInfo:@{NSLocalizedDescriptionKey: message}];
}

+ (instancetype)invalidUrnError:(NSString *)urn reason:(NSString *)reason {
    NSString *message = [NSString stringWithFormat:@"Invalid capability URN: %@: %@", urn, reason];
    return [self errorWithDomain:CSCapHostRegistryErrorDomain
                            code:CSCapHostRegistryErrorTypeInvalidUrn
                        userInfo:@{NSLocalizedDescriptionKey: message}];
}

+ (instancetype)registryError:(NSString *)message {
    NSString *fullMessage = [NSString stringWithFormat:@"Registry error: %@", message];
    return [self errorWithDomain:CSCapHostRegistryErrorDomain
                            code:CSCapHostRegistryErrorTypeRegistryError
                        userInfo:@{NSLocalizedDescriptionKey: fullMessage}];
}

@end
//
//  CSCapMatrix.m
//  CapSet registry implementation
//

#import "include/CSCapMatrix.h"
#import "include/CSCapUrn.h"

// Error domain for capability host registry
static NSString * const CSCapMatrixErrorDomain = @"CSCapMatrixError";

/**
 * Internal capability host entry
 */
@interface CSCapSetEntry : NSObject
@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) id<CSCapSet> host;
@property (nonatomic, strong) NSArray<CSCap *> *capabilities;
@end

@implementation CSCapSetEntry
@end

/**
 * CSCapMatrix implementation
 */
@interface CSCapMatrix ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, CSCapSetEntry *> *sets;
@end

@implementation CSCapMatrix

+ (instancetype)registry {
    return [[self alloc] init];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _sets = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (BOOL)registerCapSet:(NSString *)name
                   host:(id<CSCapSet>)host
           capabilities:(NSArray<CSCap *> *)capabilities {
    return [self registerCapSet:name host:host capabilities:capabilities error:nil];
}

- (BOOL)registerCapSet:(NSString *)name
                   host:(id<CSCapSet>)host
           capabilities:(NSArray<CSCap *> *)capabilities
                  error:(NSError * _Nullable * _Nullable)error {
    
    // Validate inputs
    if (!name || name.length == 0) {
        if (error) {
            *error = [CSCapMatrixError registryError:@"Host name cannot be nil or empty"];
        }
        return NO;
    }
    
    if (!host) {
        if (error) {
            *error = [CSCapMatrixError registryError:@"CapSet cannot be nil"];
        }
        return NO;
    }
    
    if (!capabilities) {
        if (error) {
            *error = [CSCapMatrixError registryError:@"Capabilities array cannot be nil"];
        }
        return NO;
    }
    
    // Check if host already exists
    if (self.sets[name]) {
        if (error) {
            *error = [CSCapMatrixError registryError:[NSString stringWithFormat:@"Host with name '%@' is already registered", name]];
        }
        return NO;
    }
    
    CSCapSetEntry *entry = [[CSCapSetEntry alloc] init];
    entry.name = name;
    entry.host = host;
    entry.capabilities = capabilities;
    
    self.sets[name] = entry;
    return YES;
}

- (nullable NSArray<id<CSCapSet>> *)findCapSets:(NSString *)requestUrn
                                            error:(NSError * _Nullable * _Nullable)error {
    
    NSError *parseError = nil;
    CSCapUrn *request = [CSCapUrn fromString:requestUrn error:&parseError];
    if (!request) {
        if (error) {
            *error = [CSCapMatrixError invalidUrnError:requestUrn 
                                                      reason:parseError.localizedDescription];
        }
        return nil;
    }
    
    NSMutableArray<id<CSCapSet>> *matchingHosts = [[NSMutableArray alloc] init];
    
    for (CSCapSetEntry *entry in [self.sets allValues]) {
        for (CSCap *cap in entry.capabilities) {
            if ([cap.capUrn matches:request]) {
                [matchingHosts addObject:entry.host];
                break; // Found a matching capability for this host, no need to check others
            }
        }
    }
    
    if (matchingHosts.count == 0) {
        if (error) {
            *error = [CSCapMatrixError noHostsFoundErrorForCapability:requestUrn];
        }
        return nil;
    }
    
    return [matchingHosts copy];
}

- (nullable id<CSCapSet>)findBestCapSet:(NSString *)requestUrn
                                    error:(NSError * _Nullable * _Nullable)error
                            capDefinition:(CSCap * _Nullable * _Nullable)capDefinition {
    
    NSError *parseError = nil;
    CSCapUrn *request = [CSCapUrn fromString:requestUrn error:&parseError];
    if (!request) {
        if (error) {
            *error = [CSCapMatrixError invalidUrnError:requestUrn 
                                                      reason:parseError.localizedDescription];
        }
        return nil;
    }
    
    id<CSCapSet> bestHost = nil;
    CSCap *bestCap = nil;
    NSInteger bestSpecificity = -1;
    
    for (CSCapSetEntry *entry in [self.sets allValues]) {
        for (CSCap *cap in entry.capabilities) {
            if ([cap.capUrn matches:request]) {
                NSInteger specificity = [cap.capUrn specificity];
                if (bestSpecificity == -1 || specificity > bestSpecificity) {
                    bestHost = entry.host;
                    bestCap = cap;
                    bestSpecificity = specificity;
                }
                break; // Found a matching capability for this host, check next host
            }
        }
    }
    
    if (!bestHost) {
        if (error) {
            *error = [CSCapMatrixError noHostsFoundErrorForCapability:requestUrn];
        }
        return nil;
    }
    
    if (capDefinition) {
        *capDefinition = bestCap;
    }
    
    return bestHost;
}

- (NSArray<NSString *> *)getHostNames {
    return [self.sets allKeys];
}

- (NSArray<CSCap *> *)getAllCapabilities {
    NSMutableArray<CSCap *> *allCapabilities = [[NSMutableArray alloc] init];
    for (CSCapSetEntry *entry in [self.sets allValues]) {
        [allCapabilities addObjectsFromArray:entry.capabilities];
    }
    return [allCapabilities copy];
}

- (BOOL)canHandle:(NSString *)requestUrn {
    NSArray<id<CSCapSet>> *sets = [self findCapSets:requestUrn error:nil];
    return sets != nil && sets.count > 0;
}

- (BOOL)unregisterCapSet:(NSString *)name {
    if (self.sets[name]) {
        [self.sets removeObjectForKey:name];
        return YES;
    }
    return NO;
}

- (void)clear {
    [self.sets removeAllObjects];
}

@end

/**
 * CSCapMatrixError implementation
 */
@implementation CSCapMatrixError

+ (instancetype)noHostsFoundErrorForCapability:(NSString *)capability {
    NSString *message = [NSString stringWithFormat:@"No cap sets found for capability: %@", capability];
    return [self errorWithDomain:CSCapMatrixErrorDomain
                            code:CSCapMatrixErrorTypeNoSetsFound
                        userInfo:@{NSLocalizedDescriptionKey: message}];
}

+ (instancetype)invalidUrnError:(NSString *)urn reason:(NSString *)reason {
    NSString *message = [NSString stringWithFormat:@"Invalid capability URN: %@: %@", urn, reason];
    return [self errorWithDomain:CSCapMatrixErrorDomain
                            code:CSCapMatrixErrorTypeInvalidUrn
                        userInfo:@{NSLocalizedDescriptionKey: message}];
}

+ (instancetype)registryError:(NSString *)message {
    NSString *fullMessage = [NSString stringWithFormat:@"Registry error: %@", message];
    return [self errorWithDomain:CSCapMatrixErrorDomain
                            code:CSCapMatrixErrorTypeRegistryError
                        userInfo:@{NSLocalizedDescriptionKey: fullMessage}];
}

@end
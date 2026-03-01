//
//  CSCapBlock.m
//  CapDAG
//
//  Composite registry implementation
//

#import "CSCapBlock.h"
#import "CSCapUrn.h"
#import "CSCapGraph.h"
#import "CSStdinSource.h"

// ============================================================================
// CSBestCapSetMatch
// ============================================================================

@implementation CSBestCapSetMatch

+ (instancetype)matchWithCap:(CSCap *)cap
                 specificity:(NSInteger)specificity
                registryName:(NSString *)registryName {
    CSBestCapSetMatch *match = [[CSBestCapSetMatch alloc] init];
    if (match) {
        match->_cap = cap;
        match->_specificity = specificity;
        match->_registryName = registryName;
    }
    return match;
}

@end

// ============================================================================
// Internal registry entry
// ============================================================================

@interface CSCapBlockEntry : NSObject
@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) CSCapMatrix *registry;
@end

@implementation CSCapBlockEntry
@end

// ============================================================================
// CSCompositeCapSet
// ============================================================================

@interface CSCompositeCapSet ()
@property (nonatomic, strong) NSArray *registries;
@end

@implementation CSCompositeCapSet

- (instancetype)initWithRegistries:(NSArray *)registries {
    self = [super init];
    if (self) {
        _registries = [registries copy];
    }
    return self;
}

- (void)executeCap:(NSString *)cap
    positionalArgs:(NSArray *)positionalArgs
         namedArgs:(NSArray *)namedArgs
       stdinSource:(CSStdinSource * _Nullable)stdinSource
        completion:(void (^)(CSResponseWrapper * _Nullable response, NSError * _Nullable error))completion {

    // Parse the request URN
    NSError *parseError = nil;
    CSCapUrn *request = [CSCapUrn fromString:cap error:&parseError];
    if (!request) {
        completion(nil, [CSCapMatrixError invalidUrnError:cap reason:parseError.localizedDescription]);
        return;
    }

    // Find the best matching CapSet across all registries
    id<CSCapSet> bestHost = nil;
    NSInteger bestSpecificity = -1;

    for (CSCapBlockEntry *entry in self.registries) {
        // Access registry's internal sets through findBestCapSet
        CSCap *capDef = nil;
        NSError *findError = nil;
        id<CSCapSet> host = [entry.registry findBestCapSet:cap error:&findError capDefinition:&capDef];

        if (host && capDef) {
            NSInteger specificity = [capDef.capUrn specificity];
            if (bestSpecificity == -1 || specificity > bestSpecificity) {
                bestHost = host;
                bestSpecificity = specificity;
            }
        }
    }

    if (!bestHost) {
        completion(nil, [CSCapMatrixError noHostsFoundErrorForCapability:cap]);
        return;
    }

    // Delegate execution to the best matching host
    [bestHost executeCap:cap
          positionalArgs:positionalArgs
               namedArgs:namedArgs
             stdinSource:stdinSource
              completion:completion];
}

- (CSCapGraph *)graph {
    CSCapGraph *graph = [CSCapGraph graph];

    for (CSCapBlockEntry *entry in self.registries) {
        NSArray<CSCap *> *capabilities = [entry.registry getAllCapabilities];
        for (CSCap *cap in capabilities) {
            [graph addCap:cap registryName:entry.name];
        }
    }

    return graph;
}

@end

// ============================================================================
// CSCapBlock
// ============================================================================

@interface CSCapBlock ()
@property (nonatomic, strong) NSMutableArray<CSCapBlockEntry *> *registries;
@end

@implementation CSCapBlock

+ (instancetype)cube {
    return [[self alloc] init];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _registries = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)addRegistry:(NSString *)name registry:(CSCapMatrix *)registry {
    @synchronized (self) {
        CSCapBlockEntry *entry = [[CSCapBlockEntry alloc] init];
        entry.name = name;
        entry.registry = registry;
        [self.registries addObject:entry];
    }
}

- (CSCapMatrix * _Nullable)removeRegistry:(NSString *)name {
    @synchronized (self) {
        for (NSUInteger i = 0; i < self.registries.count; i++) {
            CSCapBlockEntry *entry = self.registries[i];
            if ([entry.name isEqualToString:name]) {
                CSCapMatrix *removed = entry.registry;
                [self.registries removeObjectAtIndex:i];
                return removed;
            }
        }
        return nil;
    }
}

- (CSCapMatrix * _Nullable)getRegistry:(NSString *)name {
    @synchronized (self) {
        for (CSCapBlockEntry *entry in self.registries) {
            if ([entry.name isEqualToString:name]) {
                return entry.registry;
            }
        }
        return nil;
    }
}

- (NSArray<NSString *> *)getRegistryNames {
    @synchronized (self) {
        NSMutableArray<NSString *> *names = [[NSMutableArray alloc] initWithCapacity:self.registries.count];
        for (CSCapBlockEntry *entry in self.registries) {
            [names addObject:entry.name];
        }
        return [names copy];
    }
}

- (CSCapCaller * _Nullable)can:(NSString *)capUrn
                         error:(NSError * _Nullable * _Nullable)error {
    // Find the best match to get the cap definition
    CSBestCapSetMatch *bestMatch = [self findBestCapSet:capUrn error:error];
    if (!bestMatch) {
        return nil;
    }

    // Create a CompositeCapSet that will delegate execution to the right registry
    NSArray *registriesCopy;
    @synchronized (self) {
        registriesCopy = [self.registries copy];
    }

    CSCompositeCapSet *compositeHost = [[CSCompositeCapSet alloc] initWithRegistries:registriesCopy];

    return [CSCapCaller callerWithCap:capUrn
                               capSet:compositeHost
                        capDefinition:bestMatch.cap];
}

- (CSBestCapSetMatch * _Nullable)findBestCapSet:(NSString *)requestUrn
                                          error:(NSError * _Nullable * _Nullable)error {
    NSError *parseError = nil;
    CSCapUrn *request = [CSCapUrn fromString:requestUrn error:&parseError];
    if (!request) {
        if (error) {
            *error = [CSCapMatrixError invalidUrnError:requestUrn reason:parseError.localizedDescription];
        }
        return nil;
    }

    CSBestCapSetMatch *bestOverall = nil;

    @synchronized (self) {
        for (CSCapBlockEntry *entry in self.registries) {
            // Find the best match within this registry
            CSCap *capDef = nil;
            id<CSCapSet> host = [entry.registry findBestCapSet:requestUrn error:nil capDefinition:&capDef];

            if (host && capDef) {
                NSInteger specificity = [capDef.capUrn specificity];

                if (!bestOverall) {
                    bestOverall = [CSBestCapSetMatch matchWithCap:capDef
                                                     specificity:specificity
                                                    registryName:entry.name];
                } else if (specificity > bestOverall.specificity) {
                    // Only replace if strictly more specific
                    // On tie, keep the first one (priority order)
                    bestOverall = [CSBestCapSetMatch matchWithCap:capDef
                                                     specificity:specificity
                                                    registryName:entry.name];
                }
            }
        }
    }

    if (!bestOverall) {
        if (error) {
            *error = [CSCapMatrixError noHostsFoundErrorForCapability:requestUrn];
        }
        return nil;
    }

    return bestOverall;
}

- (BOOL)acceptsRequest:(NSString *)requestUrn {
    return [self findBestCapSet:requestUrn error:nil] != nil;
}

- (CSCapGraph *)graph {
    @synchronized (self) {
        CSCapGraph *graph = [CSCapGraph graph];

        for (CSCapBlockEntry *entry in self.registries) {
            NSArray<CSCap *> *capabilities = [entry.registry getAllCapabilities];
            for (CSCap *cap in capabilities) {
                [graph addCap:cap registryName:entry.name];
            }
        }

        return graph;
    }
}

@end

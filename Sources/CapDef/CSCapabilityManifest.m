//
//  CSCapabilityManifest.m
//  CapDef
//
//  Unified capability-based manifest for components (providers and plugins)
//

#import "include/CSCapabilityManifest.h"
#import "include/CSCapability.h"

@implementation CSCapabilityManifest

- (instancetype)initWithName:(NSString *)name 
                     version:(NSString *)version 
          manifestDescription:(NSString *)manifestDescription 
                capabilities:(NSArray<CSCapability *> *)capabilities {
    self = [super init];
    if (self) {
        _name = [name copy];
        _version = [version copy];
        _manifestDescription = [manifestDescription copy];
        _capabilities = [capabilities copy];
    }
    return self;
}

+ (instancetype)manifestWithName:(NSString *)name
                         version:(NSString *)version
                     description:(NSString *)description
                    capabilities:(NSArray<CSCapability *> *)capabilities {
    return [[self alloc] initWithName:name
                              version:version
                   manifestDescription:description
                         capabilities:capabilities];
}

+ (instancetype)manifestWithDictionary:(NSDictionary *)dictionary error:(NSError **)error {
    NSString *name = dictionary[@"name"];
    NSString *version = dictionary[@"version"];
    NSString *description = dictionary[@"description"];
    NSArray *capabilitiesArray = dictionary[@"capabilities"];
    
    if (!name || !version || !description || !capabilitiesArray) {
        if (error) {
            *error = [NSError errorWithDomain:@"CSCapabilityManifestError"
                                         code:1007
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing required manifest fields: name, version, description, or capabilities"}];
        }
        return nil;
    }
    
    // Parse capabilities array
    NSMutableArray<CSCapability *> *capabilities = [[NSMutableArray alloc] init];
    for (NSDictionary *capabilityDict in capabilitiesArray) {
        if (![capabilityDict isKindOfClass:[NSDictionary class]]) {
            if (error) {
                *error = [NSError errorWithDomain:@"CSCapabilityManifestError"
                                             code:1008
                                         userInfo:@{NSLocalizedDescriptionKey: @"Invalid capability format in capabilities array"}];
            }
            return nil;
        }
        
        CSCapability *capability = [CSCapability capabilityWithDictionary:capabilityDict error:error];
        if (!capability) {
            return nil;
        }
        
        [capabilities addObject:capability];
    }
    
    CSCapabilityManifest *manifest = [[self alloc] initWithName:name
                                                        version:version
                                             manifestDescription:description
                                                   capabilities:[capabilities copy]];
    
    // Optional fields
    NSString *author = dictionary[@"author"];
    if (author) {
        manifest.author = author;
    }
    
    return manifest;
}

- (CSCapabilityManifest *)withAuthor:(NSString *)author {
    self.author = [author copy];
    return self;
}

@end
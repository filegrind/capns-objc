//
//  CSCapManifest.m
//  CapNs
//
//  Unified cap-based manifest for components (providers and plugins)
//

#import "include/CSCapManifest.h"
#import "include/CSCap.h"

@implementation CSCapManifest

- (instancetype)initWithName:(NSString *)name 
                     version:(NSString *)version 
          manifestDescription:(NSString *)manifestDescription 
                caps:(NSArray<CSCap *> *)caps {
    self = [super init];
    if (self) {
        _name = [name copy];
        _version = [version copy];
        _manifestDescription = [manifestDescription copy];
        _caps = [caps copy];
    }
    return self;
}

+ (instancetype)manifestWithName:(NSString *)name
                         version:(NSString *)version
                     description:(NSString *)description
                    caps:(NSArray<CSCap *> *)caps {
    return [[self alloc] initWithName:name
                              version:version
                   manifestDescription:description
                         caps:caps];
}

+ (instancetype)manifestWithDictionary:(NSDictionary *)dictionary error:(NSError **)error {
    NSString *name = dictionary[@"name"];
    NSString *version = dictionary[@"version"];
    NSString *description = dictionary[@"description"];
    NSArray *capsArray = dictionary[@"caps"];
    
    if (!name || !version || !description || !capsArray) {
        if (error) {
            *error = [NSError errorWithDomain:@"CSCapManifestError"
                                         code:1007
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing required manifest fields: name, version, description, or caps"}];
        }
        return nil;
    }
    
    // Parse caps array
    NSMutableArray<CSCap *> *caps = [[NSMutableArray alloc] init];
    for (NSDictionary *capDict in capsArray) {
        if (![capDict isKindOfClass:[NSDictionary class]]) {
            if (error) {
                *error = [NSError errorWithDomain:@"CSCapManifestError"
                                             code:1008
                                         userInfo:@{NSLocalizedDescriptionKey: @"Invalid cap format in caps array"}];
            }
            return nil;
        }
        
        CSCap *cap = [CSCap capWithDictionary:capDict error:error];
        if (!cap) {
            return nil;
        }
        
        [caps addObject:cap];
    }
    
    CSCapManifest *manifest = [[self alloc] initWithName:name
                                                        version:version
                                             manifestDescription:description
                                                   caps:[caps copy]];
    
    // Optional fields
    NSString *author = dictionary[@"author"];
    if (author) {
        manifest.author = author;
    }
    
    return manifest;
}

- (CSCapManifest *)withAuthor:(NSString *)author {
    self.author = [author copy];
    return self;
}

@end
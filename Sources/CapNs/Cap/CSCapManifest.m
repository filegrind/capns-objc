//
//  CSCapManifest.m
//  CapNs
//
//  Unified cap-based manifest for components (providers and plugins)
//

#import "CSCapManifest.h"
#import "CSCap.h"
#import "CSCapUrn.h"
#import "CSStandardCaps.h"

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

    NSString *pageUrl = dictionary[@"page_url"];
    if (pageUrl) {
        manifest.pageUrl = pageUrl;
    }

    return manifest;
}

- (CSCapManifest *)withAuthor:(NSString *)author {
    self.author = [author copy];
    return self;
}

- (CSCapManifest *)withPageUrl:(NSString *)pageUrl {
    self.pageUrl = [pageUrl copy];
    return self;
}

- (BOOL)validate:(NSError **)error {
    // Parse CAP_IDENTITY URN
    NSError *parseError = nil;
    CSCapUrn *identityUrn = [CSCapUrn fromString:CSCapIdentity error:&parseError];
    if (!identityUrn) {
        // This should never happen - CSCapIdentity is a constant and should always be valid
        if (error) {
            *error = [NSError errorWithDomain:@"CSCapManifestError"
                                         code:1009
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"BUG: CAP_IDENTITY constant is invalid: %@", parseError.localizedDescription]}];
        }
        return NO;
    }

    // Check if any cap in the manifest matches CAP_IDENTITY (using accepts)
    BOOL hasIdentity = NO;
    for (CSCap *cap in self.caps) {
        // identityUrn.accepts(cap.capUrn) — does identity pattern accept this cap instance?
        if ([identityUrn accepts:cap.capUrn]) {
            hasIdentity = YES;
            break;
        }
    }

    if (!hasIdentity) {
        if (error) {
            *error = [NSError errorWithDomain:@"CSCapManifestError"
                                         code:1010
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Manifest missing required CAP_IDENTITY (%@)", CSCapIdentity]}];
        }
        return NO;
    }

    return YES;
}

- (CSCapManifest *)ensureIdentity {
    // Parse CAP_IDENTITY URN
    CSCapUrn *identityUrn = [CSCapUrn fromString:CSCapIdentity error:nil];
    if (!identityUrn) {
        // This should never happen - CSCapIdentity is a constant
        NSAssert(NO, @"BUG: CAP_IDENTITY constant is invalid");
        return self;
    }

    // Check if identity is already present
    BOOL hasIdentity = NO;
    for (CSCap *cap in self.caps) {
        if ([identityUrn accepts:cap.capUrn]) {
            hasIdentity = YES;
            break;
        }
    }

    if (hasIdentity) {
        return self;  // Already present, return unchanged
    }

    // Add identity cap using minimal constructor
    CSCap *identityCap = [CSCap capWithUrn:identityUrn
                                     title:@"Identity"
                                   command:@"identity"];
    NSMutableArray *newCaps = [self.caps mutableCopy];
    [newCaps addObject:identityCap];

    // Return new manifest with identity added
    return [CSCapManifest manifestWithName:self.name
                                   version:self.version
                               description:self.manifestDescription
                                      caps:[newCaps copy]];
}

@end
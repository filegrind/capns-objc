//
//  CSCapManifest.h
//  CapNs
//
//  Unified cap-based manifest for components (providers and plugins)
//

#import <Foundation/Foundation.h>

@class CSCap;

NS_ASSUME_NONNULL_BEGIN

// MARK: - Unified Cap Manifest

@interface CSCapManifest : NSObject

@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSString *version;
@property (nonatomic, strong) NSString *manifestDescription;
@property (nonatomic, strong) NSArray<CSCap *> *caps;
@property (nonatomic, strong, nullable) NSString *author;
@property (nonatomic, strong, nullable) NSString *pageUrl;

- (instancetype)initWithName:(NSString *)name 
                     version:(NSString *)version 
          manifestDescription:(NSString *)manifestDescription 
                caps:(NSArray<CSCap *> *)caps;

+ (instancetype)manifestWithName:(NSString *)name
                         version:(NSString *)version
                     description:(NSString *)description
                    caps:(NSArray<CSCap *> *)caps;

+ (instancetype)manifestWithDictionary:(NSDictionary * _Nonnull)dictionary 
                                 error:(NSError * _Nullable * _Nullable)error 
    NS_SWIFT_NAME(init(dictionary:error:));

- (CSCapManifest *)withAuthor:(NSString *)author;
- (CSCapManifest *)withPageUrl:(NSString *)pageUrl;

/**
 * Validate that CAP_IDENTITY is declared in this manifest.
 * Fails if missing — identity is mandatory in every capset.
 *
 * @param error If validation fails, contains the error description
 * @return YES if manifest contains CAP_IDENTITY, NO otherwise
 */
- (BOOL)validate:(NSError * _Nullable * _Nullable)error;

/**
 * Ensure CAP_IDENTITY is present in this manifest. Adds it if missing.
 * This method is idempotent — if identity is already present, returns self unchanged.
 *
 * @return A new manifest with CAP_IDENTITY guaranteed to be present
 */
- (CSCapManifest *)ensureIdentity;

@end

NS_ASSUME_NONNULL_END
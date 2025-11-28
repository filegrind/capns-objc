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

@end

NS_ASSUME_NONNULL_END
//
//  CSCapabilityManifest.h
//  CapDef
//
//  Unified capability-based manifest for components (providers and plugins)
//

#import <Foundation/Foundation.h>

@class CSCapability;

NS_ASSUME_NONNULL_BEGIN

// MARK: - Unified Capability Manifest

@interface CSCapabilityManifest : NSObject

@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSString *version;
@property (nonatomic, strong) NSString *manifestDescription;
@property (nonatomic, strong) NSArray<CSCapability *> *capabilities;
@property (nonatomic, strong, nullable) NSString *author;

- (instancetype)initWithName:(NSString *)name 
                     version:(NSString *)version 
          manifestDescription:(NSString *)manifestDescription 
                capabilities:(NSArray<CSCapability *> *)capabilities;

+ (instancetype)manifestWithName:(NSString *)name
                         version:(NSString *)version
                     description:(NSString *)description
                    capabilities:(NSArray<CSCapability *> *)capabilities;

+ (instancetype)manifestWithDictionary:(NSDictionary * _Nonnull)dictionary 
                                 error:(NSError * _Nullable * _Nullable)error 
    NS_SWIFT_NAME(init(dictionary:error:));

- (CSCapabilityManifest *)withAuthor:(NSString *)author;

@end

NS_ASSUME_NONNULL_END
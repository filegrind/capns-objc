//
//  CSCapabilityMatcher.m
//  Capability Matching Implementation
//

#import "CSCapabilityMatcher.h"

@implementation CSCapabilityMatcher

+ (nullable CSCapabilityId *)findBestMatchInCapabilities:(NSArray<CSCapabilityId *> *)capabilities 
                                              forRequest:(CSCapabilityId *)request {
    NSArray<CSCapabilityId *> *matches = [self findAllMatchesInCapabilities:capabilities forRequest:request];
    return matches.firstObject;
}

+ (NSArray<CSCapabilityId *> *)findAllMatchesInCapabilities:(NSArray<CSCapabilityId *> *)capabilities 
                                                  forRequest:(CSCapabilityId *)request {
    NSMutableArray<CSCapabilityId *> *matches = [NSMutableArray array];
    
    for (CSCapabilityId *capability in capabilities) {
        if ([capability canHandle:request]) {
            [matches addObject:capability];
        }
    }
    
    return [self sortCapabilitiesBySpecificity:matches];
}

+ (NSArray<CSCapabilityId *> *)sortCapabilitiesBySpecificity:(NSArray<CSCapabilityId *> *)capabilities {
    return [capabilities sortedArrayUsingComparator:^NSComparisonResult(CSCapabilityId *cap1, CSCapabilityId *cap2) {
        // Sort by specificity level first (higher specificity first)
        NSUInteger spec1 = [cap1 specificityLevel];
        NSUInteger spec2 = [cap2 specificityLevel];
        
        if (spec1 != spec2) {
            return spec1 > spec2 ? NSOrderedAscending : NSOrderedDescending;
        }
        
        // If same specificity level, sort by segment count (more segments first)
        NSUInteger count1 = cap1.segments.count;
        NSUInteger count2 = cap2.segments.count;
        
        if (count1 != count2) {
            return count1 > count2 ? NSOrderedAscending : NSOrderedDescending;
        }
        
        // If same segment count, sort alphabetically for deterministic ordering
        return [[cap1 toString] compare:[cap2 toString]];
    }];
}

+ (BOOL)capability:(CSCapabilityId *)capability 
    canHandleRequest:(CSCapabilityId *)request 
         withContext:(nullable NSDictionary<NSString *, id> *)context {
    // Basic capability matching
    if (![capability canHandle:request]) {
        return NO;
    }
    
    // If no context provided, basic matching is sufficient
    if (!context) {
        return YES;
    }
    
    // Context-based filtering could be implemented here
    // For example, checking file type compatibility, version requirements, etc.
    // This is extensible for future use cases
    
    return YES;
}

@end
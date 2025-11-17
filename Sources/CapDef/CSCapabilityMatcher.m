//
//  CSCapabilityMatcher.m
//  Capability Matching Implementation
//

#import "CSCapabilityMatcher.h"

@implementation CSCapabilityMatcher

+ (nullable CSCapabilityKey *)findBestMatchInCapabilities:(NSArray<CSCapabilityKey *> *)capabilities 
                                              forRequest:(CSCapabilityKey *)request {
    NSArray<CSCapabilityKey *> *matches = [self findAllMatchesInCapabilities:capabilities forRequest:request];
    return matches.firstObject;
}

+ (NSArray<CSCapabilityKey *> *)findAllMatchesInCapabilities:(NSArray<CSCapabilityKey *> *)capabilities 
                                                  forRequest:(CSCapabilityKey *)request {
    NSMutableArray<CSCapabilityKey *> *matches = [NSMutableArray array];
    
    for (CSCapabilityKey *capability in capabilities) {
        if ([capability canHandle:request]) {
            [matches addObject:capability];
        }
    }
    
    return [self sortCapabilitiesBySpecificity:matches];
}

+ (NSArray<CSCapabilityKey *> *)sortCapabilitiesBySpecificity:(NSArray<CSCapabilityKey *> *)capabilities {
    return [capabilities sortedArrayUsingComparator:^NSComparisonResult(CSCapabilityKey *cap1, CSCapabilityKey *cap2) {
        // Sort by specificity first (higher specificity first)
        NSUInteger spec1 = [cap1 specificity];
        NSUInteger spec2 = [cap2 specificity];
        
        if (spec1 != spec2) {
            return spec1 > spec2 ? NSOrderedAscending : NSOrderedDescending;
        }
        
        // If same specificity, sort by tag count (more tags first)
        NSUInteger count1 = cap1.tags.count;
        NSUInteger count2 = cap2.tags.count;
        
        if (count1 != count2) {
            return count1 > count2 ? NSOrderedAscending : NSOrderedDescending;
        }
        
        // If same tag count, sort alphabetically for deterministic ordering
        return [[cap1 toString] compare:[cap2 toString]];
    }];
}

+ (BOOL)capability:(CSCapabilityKey *)capability 
    canHandleRequest:(CSCapabilityKey *)request 
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
//
//  CSCapMatcher.m
//  Cap Matching Implementation
//

#import "CSCapMatcher.h"

@implementation CSCapMatcher

+ (nullable CSCapCard *)findBestMatchInCaps:(NSArray<CSCapCard *> *)caps 
                                              forRequest:(CSCapCard *)request {
    NSArray<CSCapCard *> *matches = [self findAllMatchesInCaps:caps forRequest:request];
    return matches.firstObject;
}

+ (NSArray<CSCapCard *> *)findAllMatchesInCaps:(NSArray<CSCapCard *> *)caps 
                                                  forRequest:(CSCapCard *)request {
    NSMutableArray<CSCapCard *> *matches = [NSMutableArray array];
    
    for (CSCapCard *cap in caps) {
        if ([cap canHandle:request]) {
            [matches addObject:cap];
        }
    }
    
    return [self sortCapsBySpecificity:matches];
}

+ (NSArray<CSCapCard *> *)sortCapsBySpecificity:(NSArray<CSCapCard *> *)caps {
    return [caps sortedArrayUsingComparator:^NSComparisonResult(CSCapCard *cap1, CSCapCard *cap2) {
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

+ (BOOL)cap:(CSCapCard *)cap 
    canHandleRequest:(CSCapCard *)request 
         withContext:(nullable NSDictionary<NSString *, id> *)context {
    // Basic cap matching
    if (![cap canHandle:request]) {
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
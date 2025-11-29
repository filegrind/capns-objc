//
//  CSCapRegistry.h
//  CapNs
//
//  Registry client for fetching canonical cap definitions from capns.org
//

#import <Foundation/Foundation.h>

@class CSCap, CSCapUrn;

NS_ASSUME_NONNULL_BEGIN

/**
 * CSCapRegistry provides access to canonical cap definitions from capns.org
 * with local caching for performance.
 */
@interface CSCapRegistry : NSObject

/**
 * Initialize a new registry client with default configuration
 */
- (instancetype)init;

/**
 * Get a cap from registry or cache. Never returns nil - completion called with Cap or error.
 * @param urn The cap URN to fetch
 * @param completion Completion handler with cap or error
 */
- (void)getCapWithUrn:(NSString *)urn completion:(void (^)(CSCap *cap, NSError *error))completion;

/**
 * Get multiple caps at once - fails if any cap is not available
 * @param urns Array of cap URNs to fetch
 * @param completion Completion handler with caps array or error
 */
- (void)getCapsWithUrns:(NSArray<NSString *> *)urns completion:(void (^)(NSArray<CSCap *> *caps, NSError *error))completion;

/**
 * Validate a local cap against its canonical definition
 * @param cap The cap to validate
 * @param completion Completion handler with error if validation fails, nil if valid
 */
- (void)validateCap:(CSCap *)cap completion:(void (^)(NSError * _Nullable error))completion;

/**
 * Check if a cap URN exists in registry (either cached or available online)
 * Note: This only checks cache synchronously for performance. For definitive check, use getCapWithUrn.
 * @param urn The cap URN to check
 * @return YES if cap exists in cache, NO otherwise
 */
- (BOOL)capExists:(NSString *)urn;

/**
 * Get all currently cached caps from in-memory cache
 * @return Array of all cached caps
 */
- (NSArray<CSCap *> *)getCachedCaps;

/**
 * Clear all cached registry definitions
 */
- (void)clearCache;

@end

/**
 * Validate a cap against its canonical definition (convenience function)
 * @param registry The registry to use for validation
 * @param cap The cap to validate
 * @param completion Completion handler with error if validation fails, nil if valid
 */
void CSValidateCapCanonical(CSCapRegistry *registry, CSCap *cap, void (^completion)(NSError * _Nullable error));

NS_ASSUME_NONNULL_END
//
//  CSStandardCapabilities.h
//  Standard capability definitions with arguments
//
//  This provides the standard capability definitions used across
//  all LBVR plugins, including their formal argument specifications.
//

#import <Foundation/Foundation.h>
#import "CSCapability.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Standard capability factory methods
 */
@interface CSStandardCapabilities : NSObject

/**
 * Create the standard extract-metadata capability with full argument definition
 * @return A fully configured extract-metadata capability
 */
+ (CSCapability *)extractMetadataCapability;

/**
 * Create the standard generate-thumbnail capability with full argument definition
 * @return A fully configured generate-thumbnail capability
 */
+ (CSCapability *)generateThumbnailCapability;

/**
 * Create the standard extract-outline capability with full argument definition
 * @return A fully configured extract-outline capability
 */
+ (CSCapability *)extractOutlineCapability;

/**
 * Create the standard extract-text capability with full argument definition
 * @return A fully configured extract-text capability
 */
+ (CSCapability *)extractTextCapability;

/**
 * Get all standard capabilities
 * @return An array of all standard capabilities
 */
+ (NSArray<CSCapability *> *)allStandardCapabilities;

/**
 * Get a standard capability by name
 * @param name The capability name (e.g., "extract-metadata")
 * @return The capability or nil if not found
 */
+ (nullable CSCapability *)standardCapabilityWithName:(NSString *)name;

/**
 * Get a standard capability by capability ID string
 * @param idString The capability ID string (e.g., "document:extract:metadata")
 * @return The capability or nil if not found
 */
+ (nullable CSCapability *)standardCapabilityWithId:(NSString *)idString;

@end

NS_ASSUME_NONNULL_END
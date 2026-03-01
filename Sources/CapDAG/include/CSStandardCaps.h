//
//  CSStandardCaps.h
//  CapDAG
//
//  Standard capability URN constants
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// MARK: - Standard Cap URN Constants

/**
 * Identity capability — the categorical identity morphism.
 * MANDATORY in every capset.
 * Accepts any media type as input and outputs the same media type.
 * URN: cap:in=media:;out=media:
 */
extern NSString * const CSCapIdentity;

/**
 * Discard capability — the terminal morphism.
 * Standard, but NOT mandatory.
 * Accepts any media type as input and produces void output.
 * The capdag lib MAY provide a default implementation; plugins may override.
 * URN: cap:in=media:;out=media:void
 */
extern NSString * const CSCapDiscard;

NS_ASSUME_NONNULL_END

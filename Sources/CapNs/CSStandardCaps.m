//
//  CSStandardCaps.m
//  CapNs
//
//  Standard capability URN constants
//

#import "include/CSStandardCaps.h"

// MARK: - Standard Cap URN Constants

/**
 * Identity capability — the categorical identity morphism.
 * MANDATORY in every capset.
 * Accepts any media type as input and outputs the same media type.
 */
NSString * const CSCapIdentity = @"cap:in=media:;out=media:";

/**
 * Discard capability — the terminal morphism.
 * Standard, but NOT mandatory.
 * Accepts any media type as input and produces void output.
 */
NSString * const CSCapDiscard = @"cap:in=media:;out=media:void";

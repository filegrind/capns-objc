//
//  CapDef.h
//  Capability SDK - Core capability identifier and definition system
//
//  This library provides the fundamental capability identifier system used across
//  all LBVR plugins and providers. It defines the formal structure for capability
//  identifiers with hierarchical naming, wildcard support, and specificity comparison.
//

#import <Foundation/Foundation.h>

//! Project version number for CapDef.
FOUNDATION_EXPORT double CapDefVersionNumber;

//! Project version string for CapDef.
FOUNDATION_EXPORT const unsigned char CapDefVersionString[];

#import "CSCapabilityId.h"
#import "CSCapabilityIdBuilder.h"
#import "CSCapability.h"
#import "CSCapabilityMatcher.h"
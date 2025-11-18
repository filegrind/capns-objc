//
//  CapDef.h
//  Cap SDK - Core cap identifier and definition system
//
//  This library provides the fundamental cap identifier system used across
//  all LBVR plugins and providers. It defines the formal structure for cap
//  identifiers with flat tag-based naming, wildcard support, and specificity comparison.
//

#import <Foundation/Foundation.h>

//! Project version number for CapDef.
FOUNDATION_EXPORT double CapDefVersionNumber;

//! Project version string for CapDef.
FOUNDATION_EXPORT const unsigned char CapDefVersionString[];

#import "CSCapCard.h"
#import "CSCap.h"
#import "CSCapManifest.h"
#import "CSCapMatcher.h"
#import "CSCapValidator.h"
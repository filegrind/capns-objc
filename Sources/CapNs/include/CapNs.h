//
//  CapNs.h
//  Cap SDK - Core cap URN and definition system
//
//  This library provides the fundamental cap URN system used across
//  all FGRND plugins and providers. It defines the formal structure for cap
//  identifiers with flat tag-based naming, wildcard support, and specificity comparison.
//

#import <Foundation/Foundation.h>

//! Project version number for CapNs.
FOUNDATION_EXPORT double CapNsVersionNumber;

//! Project version string for CapNs.
FOUNDATION_EXPORT const unsigned char CapNsVersionString[];

#import "CSCapUrn.h"
#import "CSCap.h"
#import "CSCapCaller.h"
#import "CSResponseWrapper.h"
#import "CSCapManifest.h"
#import "CSCapMatcher.h"
#import "CSCapValidator.h"
#import "CSSchemaValidator.h"
#import "CSCapRegistry.h"
#import "CSCapHostRegistry.h"
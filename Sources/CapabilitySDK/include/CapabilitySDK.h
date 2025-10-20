//
//  CapabilitySDK.h
//  Capability SDK - Core capability identifier and definition system
//
//  This library provides the fundamental capability identifier system used across
//  all LBVR plugins and providers. It defines the formal structure for capability
//  identifiers with hierarchical naming, wildcard support, and specificity comparison.
//

#import <Foundation/Foundation.h>

//! Project version number for CapabilitySDK.
FOUNDATION_EXPORT double CapabilitySDKVersionNumber;

//! Project version string for CapabilitySDK.
FOUNDATION_EXPORT const unsigned char CapabilitySDKVersionString[];

#import "CSCapabilityId.h"
#import "CSCapabilityIdBuilder.h"
#import "CSCapability.h"
#import "CSCapabilityMatcher.h"
#import "CSPluginCapabilities.h"
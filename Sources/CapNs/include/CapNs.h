//
//  CapNs.h
//  Cap SDK - Core cap URN and definition system
//
//  This library provides the fundamental cap URN system used across
//  all FGND plugins and providers. It defines the formal structure for cap
//  identifiers with flat tag-based naming, wildcard support, and specificity comparison.
//
//  ## Plugin Communication
//
//  The library also provides unified plugin communication infrastructure:
//
//  - **Binary Packet Framing** (`CSPacket`): Length-prefixed binary packets for stdin/stdout
//  - **Message Envelope** (`CSMessage`): JSON message types for requests/responses
//

#import <Foundation/Foundation.h>

//! Project version number for CapNs.
FOUNDATION_EXPORT double CapNsVersionNumber;

//! Project version string for CapNs.
FOUNDATION_EXPORT const unsigned char CapNsVersionString[];

// Core cap URN system
#import "CSCapUrn.h"
#import "CSCap.h"
#import "CSMediaSpec.h"
#import "CSStdinSource.h"
#import "CSCapCaller.h"
#import "CSResponseWrapper.h"
#import "CSCapManifest.h"
#import "CSCapMatcher.h"
#import "CSCapValidator.h"
#import "CSSchemaValidator.h"
#import "CSCapRegistry.h"
#import "CSCapMatrix.h"
#import "CSCapBlock.h"
#import "CSCapGraph.h"

// Plugin communication infrastructure
#import "CSPacket.h"
#import "CSMessage.h"
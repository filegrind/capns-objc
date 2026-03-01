# Cap URN - Objective-C Implementation

Objective-C implementation of Cap URN (Capability Uniform Resource Names), built on [Tagged URN](https://github.com/machinefabric/tagged-urn-objc).

## Features

- **Required Direction Specifiers** - `in`/`out` tags for input/output media types
- **Media URN Validation** - Validates direction spec values are valid Media URNs
- **Special Pattern Values** - `*` (must-have-any), `?` (unspecified), `!` (must-not-have)
- **Graded Specificity** - Exact values score higher than wildcards
- **Swift Compatible** - Full Swift interoperability via Objective-C bridge
- **NSSecureCoding** - Secure serialization support
- **Cap Definitions** - Full capability definitions with arguments, output, and metadata
- **Cap Matrix** - Registry for capability lookup and matching
- **Schema Validation** - JSON Schema validation for arguments and outputs

## Installation

### Swift Package Manager

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/machinefabric/capns-objc.git", from: "1.0.0")
]
```

### Manual

Add the `Sources/CapNs` directory to your Xcode project.

## Quick Start

### Objective-C

```objc
#import <CapNs/CSCapUrn.h>

// Parse a Cap URN
NSError *error = nil;
CSCapUrn *cap = [CSCapUrn fromString:@"cap:in=\"media:binary\";op=extract;out=\"media:object\"" error:&error];
if (cap) {
    NSLog(@"Input: %@", cap.inSpec);      // "media:binary"
    NSLog(@"Output: %@", cap.outSpec);    // "media:object"
    NSLog(@"Op: %@", [cap getTag:@"op"]); // "extract"
}

// Build a Cap URN
CSCapUrn *built = [[[[CSCapUrnBuilder builder]
    inSpec:@"media:void"]
    outSpec:@"media:object"]
    tag:@"op" value:@"generate"]
    build:&error];

// Check matching
CSCapUrn *pattern = [CSCapUrn fromString:@"cap:in=\"media:binary\";op=extract;out=\"media:object\"" error:&error];
if ([cap accepts:pattern]) {
    NSLog(@"Cap accepts pattern");
}
```

### Swift

```swift
import CapNs

// Parse a Cap URN
do {
    let cap = try CSCapUrn.fromString("cap:in=\"media:binary\";op=extract;out=\"media:object\"")
    print("Input: \(cap.inSpec)")        // "media:binary"
    print("Output: \(cap.outSpec)")      // "media:object"
    print("Op: \(cap.getTag("op") ?? "nil")") // "extract"
} catch {
    print("Parse error: \(error)")
}

// Build a Cap URN
let built = try CSCapUrnBuilder.builder()
    .inSpec("media:void")
    .outSpec("media:object")
    .tag("op", value: "generate")
    .build()

// Check matching
let pattern = try CSCapUrn.fromString("cap:in=\"media:binary\";op=extract;out=\"media:object\"")
if cap.accepts(pattern) {
    print("Cap accepts pattern")
}
```

## API Reference

### CSCapUrn

| Method | Description |
|--------|-------------|
| `+fromString:error:` | Parse Cap URN from string |
| `+fromTags:error:` | Create from tag dictionary (must include in/out) |
| `-getInSpec` | Get input media URN |
| `-getOutSpec` | Get output media URN |
| `-getTag:` | Get value for a tag key |
| `-withTag:value:` | Return new CapUrn with tag added/updated |
| `-withInSpec:` | Return new CapUrn with changed input spec |
| `-withOutSpec:` | Return new CapUrn with changed output spec |
| `-accepts:` | Check if Cap (as pattern) accepts a request |
| `-specificity` | Get graded specificity score |
| `-toString` | Get canonical string representation |

### CSCapUrnBuilder

| Method | Description |
|--------|-------------|
| `+builder` | Create a new builder |
| `-inSpec:` | Set input media URN (required) |
| `-outSpec:` | Set output media URN (required) |
| `-tag:value:` | Add or update a tag (chainable) |
| `-build:` | Build the CapUrn (returns nil on error) |

## Matching Semantics

| Pattern | Instance Missing | Instance=v | Instance=x (x≠v) |
|---------|------------------|------------|------------------|
| (missing) or `?` | Match | Match | Match |
| `K=!` | Match | No Match | No Match |
| `K=*` | No Match | Match | Match |
| `K=v` | No Match | Match | No Match |

## Graded Specificity

| Value Type | Score |
|------------|-------|
| Exact value (`K=v`) | 3 |
| Must-have-any (`K=*`) | 2 |
| Must-not-have (`K=!`) | 1 |
| Unspecified (`K=?`) or missing | 0 |

## Error Codes

| Code | Name | Description |
|------|------|-------------|
| 10 | MissingInSpec | Missing required `in` tag |
| 11 | MissingOutSpec | Missing required `out` tag |

For base Tagged URN error codes, see [Tagged URN documentation](https://github.com/machinefabric/tagged-urn-objc).

## Testing

```bash
swift test
```

## Cross-Language Compatibility

This Objective-C implementation produces identical results to:
- [Rust reference implementation](https://github.com/machinefabric/capns)
- [Go implementation](https://github.com/machinefabric/capns-go)
- [JavaScript implementation](https://github.com/machinefabric/capns-js)

All implementations follow the same rules. See:
- [Cap URN RULES.md](https://github.com/machinefabric/capns/blob/main/docs/RULES.md) - Cap-specific rules
- [Tagged URN RULES.md](https://github.com/machinefabric/tagged-urn-rs/blob/main/docs/RULES.md) - Base format rules

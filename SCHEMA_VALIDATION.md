# JSON Schema Validation for CapDAG Objective-C

This document describes the comprehensive JSON Schema validation system implemented for the CapDAG Objective-C SDK, providing validation capabilities that match the Rust and Go implementations.

## Overview

The JSON Schema validation system provides Draft-7 compliant validation for:
- **Media validation**: Validates structured input arguments (objects and arrays) against JSON schemas
- **Output validation**: Validates structured outputs against JSON schemas  
- **Schema references**: Supports both embedded schemas and external schema file references
- **Integration**: Seamlessly integrates with the existing CSCapValidator system
- **Performance**: Includes schema caching for improved validation performance

## Architecture

### Core Components

#### 1. CSJSONSchemaValidator
The main validator class that provides JSON Schema Draft-7 validation capabilities.

```objc
// Create validator with embedded schema support
CSJSONSchemaValidator *validator = [CSJSONSchemaValidator validator];

// Create validator with schema resolver for external references
CSFileSchemaResolver *resolver = [CSFileSchemaResolver resolverWithBasePath:@"/path/to/schemas"];
CSJSONSchemaValidator *validatorWithResolver = [CSJSONSchemaValidator validatorWithResolver:resolver];
```

#### 2. Schema Resolver System
Supports external schema resolution through the `CSSchemaResolver` protocol.

```objc
@protocol CSSchemaResolver <NSObject>
- (nullable NSDictionary *)resolveSchema:(NSString *)schemaRef error:(NSError **)error;
@end

// File-based resolver implementation
CSFileSchemaResolver *fileResolver = [CSFileSchemaResolver resolverWithBasePath:@"/schemas"];
```

#### 3. Enhanced Cap Types
Extended `CSCapArgument` and `CSCapOutput` with schema support.

```objc
// Enhanced CSCapArgument with schema fields
@property (nonatomic, readonly, nullable) NSString *schemaRef;
@property (nonatomic, readonly, nullable) NSDictionary *schema;

// Enhanced CSCapOutput with schema fields  
@property (nonatomic, readonly, nullable) NSString *schemaRef;
@property (nonatomic, readonly, nullable) NSDictionary *schema;
```

## Usage Examples

### 1. Embedded Schema Validation

```objc
// Define JSON schema for user data
NSDictionary *userSchema = @{
    @"type": @"object",
    @"properties": @{
        @"name": @{@"type": @"string", @"minLength": @1},
        @"age": @{@"type": @"integer", @"minimum": @0, @"maximum": @150},
        @"email": @{@"type": @"string", @"pattern": @"^[^@]+@[^@]+\\.[^@]+$"}
    },
    @"required": @[@"name", @"email"]
};

// Create argument with embedded schema
CSCapArgument *userArg = [CSCapArgument argumentWithName:@"user_data"
                                                 argType:CSArgumentTypeObject
                                           argDescription:@"User data object" 
                                                 cliFlag:@"--user"
                                                  schema:userSchema];

// Validate data against schema
NSDictionary *userData = @{@"name": @"John Doe", @"email": @"john@example.com", @"age": @30};
NSError *error = nil;
BOOL isValid = [validator validateArgument:userArg withValue:userData error:&error];
```

### 2. Schema Reference Validation

```objc
// Create argument with schema reference
CSCapArgument *configArg = [CSCapArgument argumentWithName:@"config"
                                                    argType:CSArgumentTypeObject
                                              argDescription:@"Configuration object"
                                                    cliFlag:@"--config"
                                                  schemaRef:@"config_schema"];

// Validator will resolve "config_schema.json" from resolver base path
NSError *error = nil;
BOOL isValid = [validator validateArgument:configArg withValue:configData error:&error];
```

### 3. Output Schema Validation

```objc
// Define schema for query results
NSDictionary *resultsSchema = @{
    @"type": @"array",
    @"items": @{
        @"type": @"object",
        @"properties": @{
            @"id": @{@"type": @"string"},
            @"score": @{@"type": @"number", @"minimum": @0, @"maximum": @1}
        },
        @"required": @[@"id", @"score"]
    }
};

// Create output with embedded schema
CSCapOutput *output = [CSCapOutput outputWithType:CSOutputTypeArray
                                            schema:resultsSchema
                                 outputDescription:@"Query results"];

// Validate output data
NSArray *results = @[@{@"id": @"item1", @"score": @0.95}, @{@"id": @"item2", @"score": @0.87}];
NSError *error = nil;
BOOL isValid = [validator validateOutput:output withValue:results error:&error];
```

## Integration with Existing Validation

The schema validation system seamlessly integrates with the existing `CSCapValidator` system:

```objc
// Create capability with schema-enabled arguments
CSCap *cap = [CSCap capWithUrn:urn
                       command:@"process-user"
                   description:@"Process user data"
                      metadata:@{}
                     arguments:arguments  // Contains schema-enabled arguments
                        output:output      // Contains schema-enabled output
                  acceptsStdin:NO];

// Existing validation automatically includes schema validation
NSError *error = nil;
BOOL inputValid = [CSInputValidator validateArguments:@[userData] cap:cap error:&error];
BOOL outputValid = [CSOutputValidator validateOutput:resultData cap:cap error:&error];
```

## Plugin SDK Integration

The MachineFabric Plugin SDK provides convenience methods for common document processing schemas:

```objc
// Standard document metadata schema
CSCapArgument *metadataArg = [CSCapArgument documentMetadataArgumentWithName:@"metadata"
                                                                  description:@"Document metadata"
                                                                      cliFlag:@"--metadata"
                                                                       schema:[MachFabSchemaValidationHelper standardDocumentMetadataSchema]];

// Standard file chips schema
CSCapOutput *pagesOutput = [CSCapOutput disboundPagesOutputWithSchema:[MachFabSchemaValidationHelper standardDisboundPagesSchema]
                                                          description:@"Extracted file chips"];

// Validate plugin manifest schemas
NSError *error = nil;
BOOL manifestValid = [MachFabSchemaValidationHelper validatePluginManifest:manifest error:&error];
```

## Error Handling

Comprehensive error reporting with detailed validation failure information:

```objc
NSError *error = nil;
BOOL isValid = [validator validateArgument:argument withValue:invalidData error:&error];

if (!isValid && [error isKindOfClass:[CSSchemaValidationError class]]) {
    CSSchemaValidationError *schemaError = (CSSchemaValidationError *)error;
    
    NSLog(@"Schema validation failed:");
    NSLog(@"  Type: %ld", (long)schemaError.schemaErrorType);
    NSLog(@"  Argument: %@", schemaError.argumentName);
    NSLog(@"  Errors: %@", [schemaError.validationErrors componentsJoinedByString:@", "]);
}
```

Error types include:
- `CSSchemaValidationErrorTypeMediaValidation`: Argument failed schema validation
- `CSSchemaValidationErrorTypeOutputValidation`: Output failed schema validation  
- `CSSchemaValidationErrorTypeSchemaCompilation`: Schema parsing/compilation failed
- `CSSchemaValidationErrorTypeSchemaRefNotResolved`: External schema reference not found
- `CSSchemaValidationErrorTypeInvalidJson`: Invalid JSON format

## Performance Considerations

### Schema Caching
The validator automatically caches resolved schemas to improve performance:

```objc
// First validation resolves and caches schema
[validator validateArgument:argWithSchemaRef withValue:data1 error:&error];

// Subsequent validations use cached schema (faster)
[validator validateArgument:argWithSchemaRef withValue:data2 error:&error];
```

### Validation Scope
Only structured types (objects and arrays) with schemas are validated:

```objc
// These will be schema validated (if schema is present):
CSArgumentTypeObject + schema  OK
CSArgumentTypeArray + schema   OK

// These skip schema validation:
CSArgumentTypeString          ERR (no schema needed)
CSArgumentTypeInteger         ERR (no schema needed)
CSArgumentTypeObject (no schema) ERR (no schema to validate against)
```

## JSON Schema Support

The implementation supports JSON Schema Draft-7 features including:

### Basic Types
- `string` with `minLength`, `maxLength`, `pattern`
- `integer` and `number` with `minimum`, `maximum`, `multipleOf`
- `boolean`
- `array` with `items`, `minItems`, `maxItems`
- `object` with `properties`, `required`, `additionalProperties`

### Advanced Features
- Nested object validation
- Array item validation
- Regular expression patterns
- Numeric constraints
- Required property validation
- Additional properties control

### Example Complex Schema
```objc
NSDictionary *complexSchema = @{
    @"type": @"object",
    @"properties": @{
        @"metadata": @{
            @"type": @"object", 
            @"properties": @{
                @"version": @{@"type": @"string", @"pattern": @"^\\d+\\.\\d+\\.\\d+$"}
            },
            @"required": @[@"version"]
        },
        @"items": @{
            @"type": @"array",
            @"items": @{
                @"type": @"object",
                @"properties": @{
                    @"id": @{@"type": @"integer"},
                    @"tags": @{@"type": @"array", @"items": @{@"type": @"string"}, @"maxItems": @5}
                },
                @"required": @[@"id"]
            }
        }
    },
    @"required": @[@"metadata", @"items"]
};
```

## Migration Guide

### From Basic Validation
Existing caps without schema validation continue to work unchanged:

```objc
// Existing argument (no schema) - works as before
CSCapArgument *oldArg = [CSCapArgument argumentWithName:@"data"
                                                argType:CSArgumentTypeObject
                                          argDescription:@"Data object"
                                                cliFlag:@"--data"
                                               position:nil
                                             validation:nil
                                           defaultValue:nil];
```

### Adding Schema Validation
Enhance existing arguments with schemas:

```objc
// Add schema to existing argument
CSCapArgument *enhancedArg = [CSCapArgument argumentWithName:@"data"
                                                     argType:CSArgumentTypeObject
                                               argDescription:@"Data object with validation"
                                                     cliFlag:@"--data"
                                                      schema:dataSchema];
```

## File Structure

```
capdag-objc/
├── Sources/CapDAG/
│   ├── include/
│   │   ├── CSSchemaValidator.h      # JSON schema validator interface
│   │   ├── CSCap.h                  # Enhanced with schema fields
│   │   ├── CSCapValidator.h         # Updated with schema validation
│   │   └── CapDAG.h                  # Updated to export schema validator
│   ├── CSSchemaValidator.m          # JSON schema validator implementation
│   ├── CSCap.m                      # Updated with schema support
│   └── CSCapValidator.m             # Updated with schema integration
├── Tests/CapDAGTests/
│   └── CSSchemaValidationTests.m    # Comprehensive schema validation tests
└── examples/
    └── schema_validation_example.m  # Usage examples and demonstrations
```

## Standards Compliance

- **JSON Schema Draft-7**: Full support for core validation keywords
- **RFC 3339**: Date-time format validation
- **RFC 3986**: URI format validation  
- **Unicode**: Full Unicode string support
- **IEEE 754**: Numeric validation compliance

## Best Practices

### 1. Schema Design
- Use specific types and constraints
- Include clear descriptions
- Define required fields explicitly
- Limit additional properties when appropriate

### 2. Error Handling
- Always check validation results
- Provide meaningful error messages to users
- Log schema validation failures for debugging

### 3. Performance
- Use embedded schemas for simple cases
- Use schema references for complex/shared schemas
- Consider schema complexity vs. validation performance

### 4. Testing
- Test both valid and invalid data
- Test edge cases and boundary conditions
- Test schema reference resolution
- Test integration with existing validation

This comprehensive JSON Schema validation system brings the CapDAG Objective-C SDK to feature parity with the Rust and Go implementations while maintaining backward compatibility and following Objective-C best practices.
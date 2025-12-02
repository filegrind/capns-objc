//
//  schema_validation_example.m
//  Example usage of JSON Schema validation with CapNs
//
//  Demonstrates comprehensive schema validation for both embedded schemas
//  and external schema references, integration with cap validation system,
//  and error handling.
//

#import "CapNs.h"

@interface SchemaValidationExample : NSObject
@property (nonatomic, strong) CSJSONSchemaValidator *validator;
@end

@implementation SchemaValidationExample

- (instancetype)init {
    self = [super init];
    if (self) {
        // Create validator with file resolver
        CSFileSchemaResolver *resolver = [CSFileSchemaResolver resolverWithBasePath:@"/path/to/schemas"];
        self.validator = [CSJSONSchemaValidator validatorWithResolver:resolver];
    }
    return self;
}

- (void)demonstrateEmbeddedSchemaValidation {
    NSLog(@"\n=== Embedded Schema Validation Example ===");
    
    // Create capability with embedded JSON schema
    NSDictionary *userSchema = @{
        @"type": @"object",
        @"properties": @{
            @"name": @{@"type": @"string", @"minLength": @1},
            @"age": @{@"type": @"integer", @"minimum": @0, @"maximum": @150},
            @"email": @{@"type": @"string", @"pattern": @"^[^@]+@[^@]+\\.[^@]+$"},
            @"preferences": @{
                @"type": @"object",
                @"properties": @{
                    @"notifications": @{@"type": @"boolean"},
                    @"theme": @{@"type": @"string", @"enum": @[@"light", @"dark"]}
                },
                @"additionalProperties": false
            }
        },
        @"required": @[@"name", @"email"],
        @"additionalProperties": false
    };
    
    // Create argument with embedded schema
    CSCapArgument *userArg = [CSCapArgument argumentWithName:@"user_data"
                                                     argType:CSArgumentTypeObject
                                               argDescription:@"User data with validation"
                                                     cliFlag:@"--user"
                                                      schema:userSchema];
    
    // Create output with embedded schema
    NSDictionary *responseSchema = @{
        @"type": @"object",
        @"properties": @{
            @"success": @{@"type": @"boolean"},
            @"userId": @{@"type": @"string"},
            @"message": @{@"type": @"string"}
        },
        @"required": @[@"success"],
        @"additionalProperties": false
    };
    
    CSCapOutput *output = [CSCapOutput outputWithType:CSOutputTypeObject
                                                schema:responseSchema
                                     outputDescription:@"Operation response"];
    
    // Create capability
    CSCapUrn *urn = [CSCapUrn builderWithAction:@"create"].target(@"user").build(nil);
    CSCapArguments *arguments = [CSCapArguments argumentsWithRequired:@[userArg] optional:@[]];
    
    CSCap *cap = [CSCap capWithUrn:urn
                           command:@"create-user"
                       description:@"Create a new user with validation"
                          metadata:@{}
                         arguments:arguments
                            output:output
                      acceptsStdin:NO];
    
    // Test with valid data
    NSDictionary *validUser = @{
        @"name": @"John Doe",
        @"age": @30,
        @"email": @"john@example.com",
        @"preferences": @{
            @"notifications": @YES,
            @"theme": @"dark"
        }
    };
    
    NSError *error = nil;
    BOOL result = [self.validator validateArgument:userArg withValue:validUser error:&error];
    
    if (result) {
        NSLog(@"✅ Valid user data passed schema validation");
        
        // Test integrated validation
        result = [CSInputValidator validateArguments:@[validUser] cap:cap error:&error];
        if (result) {
            NSLog(@"✅ Valid user data passed integrated validation");
        } else {
            NSLog(@"❌ Valid user data failed integrated validation: %@", error.localizedDescription);
        }
    } else {
        NSLog(@"❌ Valid user data failed schema validation: %@", error.localizedDescription);
    }
    
    // Test with invalid data
    NSDictionary *invalidUser = @{
        @"name": @"",  // Empty name (violates minLength)
        @"age": @(-5), // Negative age (violates minimum)
        @"email": @"invalid-email", // Invalid email format
        @"preferences": @{
            @"notifications": @YES,
            @"theme": @"purple", // Invalid theme (not in enum)
            @"extraField": @"not allowed" // Additional property not allowed
        }
    };
    
    error = nil;
    result = [self.validator validateArgument:userArg withValue:invalidUser error:&error];
    
    if (!result) {
        NSLog(@"✅ Invalid user data correctly failed validation");
        NSLog(@"   Error: %@", error.localizedDescription);
        
        if ([error isKindOfClass:[CSSchemaValidationError class]]) {
            CSSchemaValidationError *schemaError = (CSSchemaValidationError *)error;
            NSLog(@"   Validation errors: %@", [schemaError.validationErrors componentsJoinedByString:@", "]);
        }
    } else {
        NSLog(@"❌ Invalid user data incorrectly passed validation");
    }
}

- (void)demonstrateSchemaReferenceValidation {
    NSLog(@"\n=== Schema Reference Validation Example ===");
    
    // Create argument with schema reference
    CSCapArgument *configArg = [CSCapArgument argumentWithName:@"config"
                                                        argType:CSArgumentTypeObject
                                                  argDescription:@"Configuration object"
                                                        cliFlag:@"--config"
                                                      schemaRef:@"config_schema"];
    
    // Test validation (will fail without actual schema file)
    NSDictionary *testConfig = @{@"setting1": @"value1", @"setting2": @42};
    
    NSError *error = nil;
    BOOL result = [self.validator validateArgument:configArg withValue:testConfig error:&error];
    
    if (!result) {
        NSLog(@"✅ Schema reference correctly failed (schema file not found)");
        NSLog(@"   Error: %@", error.localizedDescription);
        
        if ([error isKindOfClass:[CSSchemaValidationError class]]) {
            CSSchemaValidationError *schemaError = (CSSchemaValidationError *)error;
            NSLog(@"   Error type: %ld", (long)schemaError.schemaErrorType);
        }
    }
}

- (void)demonstrateOutputValidation {
    NSLog(@"\n=== Output Validation Example ===");
    
    // Create output with schema
    NSDictionary *resultsSchema = @{
        @"type": @"array",
        @"items": @{
            @"type": @"object",
            @"properties": @{
                @"id": @{@"type": @"string"},
                @"score": @{@"type": @"number", @"minimum": @0, @"maximum": @1},
                @"metadata": @{
                    @"type": @"object",
                    @"additionalProperties": true
                }
            },
            @"required": @[@"id", @"score"]
        },
        @"minItems": @0
    };
    
    CSCapOutput *output = [CSCapOutput outputWithType:CSOutputTypeArray
                                                schema:resultsSchema
                                     outputDescription:@"Search results"];
    
    // Test with valid output
    NSArray *validResults = @[
        @{@"id": @"result1", @"score": @0.95, @"metadata": @{@"source": @"database"}},
        @{@"id": @"result2", @"score": @0.87},
        @{@"id": @"result3", @"score": @0.75, @"metadata": @{@"highlighted": @YES}}
    ];
    
    NSError *error = nil;
    BOOL result = [self.validator validateOutput:output withValue:validResults error:&error];
    
    if (result) {
        NSLog(@"✅ Valid output passed schema validation");
    } else {
        NSLog(@"❌ Valid output failed schema validation: %@", error.localizedDescription);
    }
    
    // Test with invalid output
    NSArray *invalidResults = @[
        @{@"id": @"result1", @"score": @1.5}, // Score > 1 (violates maximum)
        @{@"score": @0.87}, // Missing required 'id' field
        @{@"id": @"result3", @"score": @"not-a-number"} // Wrong type for score
    ];
    
    error = nil;
    result = [self.validator validateOutput:output withValue:invalidResults error:&error];
    
    if (!result) {
        NSLog(@"✅ Invalid output correctly failed validation");
        NSLog(@"   Error: %@", error.localizedDescription);
    } else {
        NSLog(@"❌ Invalid output incorrectly passed validation");
    }
}

- (void)demonstrateComplexNestedValidation {
    NSLog(@"\n=== Complex Nested Schema Validation Example ===");
    
    // Complex nested schema with multiple levels
    NSDictionary *documentSchema = @{
        @"type": @"object",
        @"properties": @{
            @"metadata": @{
                @"type": @"object",
                @"properties": @{
                    @"title": @{@"type": @"string"},
                    @"author": @{@"type": @"string"},
                    @"version": @{@"type": @"string", @"pattern": @"^\\d+\\.\\d+\\.\\d+$"},
                    @"tags": @{
                        @"type": @"array",
                        @"items": @{@"type": @"string"},
                        @"maxItems": @10
                    }
                },
                @"required": @[@"title", @"version"]
            },
            @"content": @{
                @"type": @"object",
                @"properties": @{
                    @"sections": @{
                        @"type": @"array",
                        @"items": @{
                            @"type": @"object",
                            @"properties": @{
                                @"heading": @{@"type": @"string"},
                                @"level": @{@"type": @"integer", @"minimum": @1, @"maximum": @6},
                                @"content": @{@"type": @"string"},
                                @"subsections": @{
                                    @"type": @"array",
                                    @"items": @{
                                        @"type": @"object",
                                        @"properties": @{
                                            @"heading": @{@"type": @"string"},
                                            @"content": @{@"type": @"string"}
                                        },
                                        @"required": @[@"heading", @"content"]
                                    }
                                }
                            },
                            @"required": @[@"heading", @"level", @"content"]
                        }
                    },
                    @"wordCount": @{@"type": @"integer", @"minimum": @0},
                    @"pageCount": @{@"type": @"integer", @"minimum": @1}
                },
                @"required": @[@"sections", @"wordCount", @"pageCount"]
            }
        },
        @"required": @[@"metadata", @"content"]
    };
    
    CSCapArgument *documentArg = [CSCapArgument argumentWithName:@"document"
                                                         argType:CSArgumentTypeObject
                                                   argDescription:@"Complex document structure"
                                                         cliFlag:@"--document"
                                                          schema:documentSchema];
    
    // Valid complex document
    NSDictionary *validDocument = @{
        @"metadata": @{
            @"title": @"Test Document",
            @"author": @"John Doe",
            @"version": @"1.0.0",
            @"tags": @[@"test", @"validation", @"schema"]
        },
        @"content": @{
            @"sections": @[
                @{
                    @"heading": @"Introduction",
                    @"level": @1,
                    @"content": @"This is the introduction section.",
                    @"subsections": @[
                        @{
                            @"heading": @"Overview",
                            @"content": @"Brief overview of the document."
                        }
                    ]
                },
                @{
                    @"heading": @"Main Content",
                    @"level": @1,
                    @"content": @"This is the main content section."
                }
            ],
            @"wordCount": @245,
            @"pageCount": @3
        }
    };
    
    NSError *error = nil;
    BOOL result = [self.validator validateArgument:documentArg withValue:validDocument error:&error];
    
    if (result) {
        NSLog(@"✅ Complex nested document passed schema validation");
    } else {
        NSLog(@"❌ Complex nested document failed schema validation: %@", error.localizedDescription);
    }
}

- (void)demonstratePerformanceConsiderations {
    NSLog(@"\n=== Performance Considerations Example ===");
    
    // Schema caching demonstration
    NSDictionary *simpleSchema = @{
        @"type": @"object",
        @"properties": @{
            @"id": @{@"type": @"string"},
            @"value": @{@"type": @"number"}
        },
        @"required": @[@"id", @"value"]
    };
    
    CSCapArgument *arg = [CSCapArgument argumentWithName:@"item"
                                                 argType:CSArgumentTypeObject
                                           argDescription:@"Simple item"
                                                 cliFlag:@"--item"
                                                  schema:simpleSchema];
    
    // Measure validation performance
    NSDate *startTime = [NSDate date];
    
    for (NSInteger i = 0; i < 1000; i++) {
        NSDictionary *testData = @{@"id": [NSString stringWithFormat:@"item_%ld", (long)i], @"value": @(i * 1.5)};
        NSError *error = nil;
        [self.validator validateArgument:arg withValue:testData error:&error];
    }
    
    NSTimeInterval duration = [[NSDate date] timeIntervalSinceDate:startTime];
    NSLog(@"✅ Validated 1000 objects in %.3f seconds (%.3f ms per validation)",
          duration, duration * 1000.0 / 1000.0);
}

- (void)runAllExamples {
    NSLog(@"🚀 Starting JSON Schema Validation Examples\n");
    
    [self demonstrateEmbeddedSchemaValidation];
    [self demonstrateSchemaReferenceValidation];
    [self demonstrateOutputValidation];
    [self demonstrateComplexNestedValidation];
    [self demonstratePerformanceConsiderations];
    
    NSLog(@"\n✅ All examples completed successfully!");
}

@end

// Example usage
int main(int argc, const char * argv[]) {
    @autoreleasepool {
        SchemaValidationExample *example = [[SchemaValidationExample alloc] init];
        [example runAllExamples];
    }
    return 0;
}
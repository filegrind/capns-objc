//
//  schema_validation_example.m
//  Example usage of JSON Schema validation with CapDAG
//
//  Demonstrates comprehensive schema validation with schemas stored in mediaSpecs,
//  spec ID resolution, and integration with cap validation system.
//
//  Schemas are stored in the mediaSpecs table and resolved via spec IDs.
//

#import "CapDAG.h"

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

    // Create capability with embedded JSON schema in mediaSpecs
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
                @"additionalProperties": @NO
            }
        },
        @"required": @[@"name", @"email"],
        @"additionalProperties": @NO
    };

    NSDictionary *responseSchema = @{
        @"type": @"object",
        @"properties": @{
            @"success": @{@"type": @"boolean"},
            @"userId": @{@"type": @"string"},
            @"message": @{@"type": @"string"}
        },
        @"required": @[@"success"],
        @"additionalProperties": @NO
    };

    // MediaSpecs table with schemas
    NSDictionary *mediaSpecs = @{
        @"my:user-data.v1": @{
            @"media_type": @"application/json",
            @"profile_uri": @"https://example.com/schema/user-data",
            @"schema": userSchema
        },
        @"my:create-user-response.v1": @{
            @"media_type": @"application/json",
            @"profile_uri": @"https://example.com/schema/create-user-response",
            @"schema": responseSchema
        }
    };

    // Create argument with spec ID
    CSCapArg *userArg = [CSCapArg argWithMediaUrn:@"my:user-data.v1"
                                          required:YES
                                           sources:@[[CSArgSource cliFlagSource:@"--user"]]
                                    argDescription:@"User data with validation"
                                        validation:nil
                                      defaultValue:nil];

    // Create output with spec ID
    CSCapOutput *output = [CSCapOutput outputWithMediaUrn:@"my:create-user-response.v1"
                                               validation:nil
                                        outputDescription:@"Operation response"];

    // Create capability
    CSCapUrn *urn = [[[[CSCapUrnBuilder builder] tag:@"op" value:@"create"] tag:@"target" value:@"user"] build:nil];

    CSCap *cap = [CSCap capWithUrn:urn
                             title:@"Create User"
                           command:@"create-user"
                       description:@"Create a new user with validation"
                          metadata:@{}
                        mediaSpecs:mediaSpecs
                              args:@[userArg]
                            output:output
                      metadataJSON:nil];

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
    BOOL result = [self.validator validateArgument:userArg withValue:validUser mediaSpecs:mediaSpecs error:&error];

    if (result) {
        NSLog(@"OK Valid user data passed schema validation");

        // Test integrated validation
        result = [CSInputValidator validateArguments:@[validUser] cap:cap error:&error];
        if (result) {
            NSLog(@"OK Valid user data passed integrated validation");
        } else {
            NSLog(@"ERR Valid user data failed integrated validation: %@", error.localizedDescription);
        }
    } else {
        NSLog(@"ERR Valid user data failed schema validation: %@", error.localizedDescription);
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
    result = [self.validator validateArgument:userArg withValue:invalidUser mediaSpecs:mediaSpecs error:&error];

    if (!result) {
        NSLog(@"OK Invalid user data correctly failed validation");
        NSLog(@"   Error: %@", error.localizedDescription);

        if ([error isKindOfClass:[CSSchemaValidationError class]]) {
            CSSchemaValidationError *schemaError = (CSSchemaValidationError *)error;
            NSLog(@"   Validation errors: %@", [schemaError.validationErrors componentsJoinedByString:@", "]);
        }
    } else {
        NSLog(@"ERR Invalid user data incorrectly passed validation");
    }
}

- (void)demonstrateBuiltinSpecIds {
    NSLog(@"\n=== Built-in Spec ID Validation Example ===");

    // Built-in spec IDs don't need to be declared in mediaSpecs

    CSCapArg *textArg = [CSCapArg argWithMediaUrn:CSSpecIdStr
                                          required:YES
                                           sources:@[[CSArgSource cliFlagSource:@"--text"]]
                                    argDescription:@"Text input"
                                        validation:nil
                                      defaultValue:nil];

    CSCapArg *countArg = [CSCapArg argWithMediaUrn:CSSpecIdInt
                                           required:YES
                                            sources:@[[CSArgSource cliFlagSource:@"--count"]]
                                     argDescription:@"Count value"
                                         validation:nil
                                       defaultValue:nil];

    CSCapArg *dataArg = [CSCapArg argWithMediaUrn:CSSpecIdObj
                                          required:YES
                                           sources:@[[CSArgSource cliFlagSource:@"--data"]]
                                    argDescription:@"JSON object"
                                        validation:nil
                                      defaultValue:nil];

    NSError *error = nil;

    // String validation
    BOOL result = [self.validator validateArgument:textArg withValue:@"hello world" mediaSpecs:@{} error:&error];
    if (result) {
        NSLog(@"OK Built-in str spec validated string");
    }

    // Integer validation
    result = [self.validator validateArgument:countArg withValue:@42 mediaSpecs:@{} error:&error];
    if (result) {
        NSLog(@"OK Built-in int spec validated integer");
    }

    // Object validation
    result = [self.validator validateArgument:dataArg withValue:@{@"key": @"value"} mediaSpecs:@{} error:&error];
    if (result) {
        NSLog(@"OK Built-in obj spec validated object");
    }

    // Show all built-in spec IDs
    NSLog(@"\nBuilt-in spec IDs available:");
    NSLog(@"  - %@ (string)", CSSpecIdStr);
    NSLog(@"  - %@ (integer)", CSSpecIdInt);
    NSLog(@"  - %@ (number)", CSSpecIdNum);
    NSLog(@"  - %@ (boolean)", CSSpecIdBool);
    NSLog(@"  - %@ (object)", CSSpecIdObj);
    NSLog(@"  - %@ (string array)", CSSpecIdStrArray);
    NSLog(@"  - %@ (integer array)", CSSpecIdIntArray);
    NSLog(@"  - %@ (number array)", CSSpecIdNumArray);
    NSLog(@"  - %@ (boolean array)", CSSpecIdBoolArray);
    NSLog(@"  - %@ (object array)", CSSpecIdObjArray);
    NSLog(@"  - %@ (binary)", CSSpecIdBinary);
}

- (void)demonstrateOutputValidation {
    NSLog(@"\n=== Output Validation Example ===");

    // Create output with schema in mediaSpecs
    NSDictionary *resultsSchema = @{
        @"type": @"array",
        @"items": @{
            @"type": @"object",
            @"properties": @{
                @"id": @{@"type": @"string"},
                @"score": @{@"type": @"number", @"minimum": @0, @"maximum": @1},
                @"metadata": @{
                    @"type": @"object",
                    @"additionalProperties": @YES
                }
            },
            @"required": @[@"id", @"score"]
        },
        @"minItems": @0
    };

    NSDictionary *mediaSpecs = @{
        @"my:search-results.v1": @{
            @"media_type": @"application/json",
            @"profile_uri": @"https://example.com/schema/search-results",
            @"schema": resultsSchema
        }
    };

    CSCapOutput *output = [CSCapOutput outputWithMediaSpec:@"my:search-results.v1"
                                                validation:nil
                                         outputDescription:@"Search results"];

    // Test with valid output
    NSArray *validResults = @[
        @{@"id": @"result1", @"score": @0.95, @"metadata": @{@"source": @"database"}},
        @{@"id": @"result2", @"score": @0.87},
        @{@"id": @"result3", @"score": @0.75, @"metadata": @{@"highlighted": @YES}}
    ];

    NSError *error = nil;
    BOOL result = [self.validator validateOutput:output withValue:validResults mediaSpecs:mediaSpecs error:&error];

    if (result) {
        NSLog(@"OK Valid output passed schema validation");
    } else {
        NSLog(@"ERR Valid output failed schema validation: %@", error.localizedDescription);
    }

    // Test with invalid output
    NSArray *invalidResults = @[
        @{@"id": @"result1", @"score": @1.5}, // Score > 1 (violates maximum)
        @{@"score": @0.87}, // Missing required 'id' field
        @{@"id": @"result3", @"score": @"not-a-number"} // Wrong type for score
    ];

    error = nil;
    result = [self.validator validateOutput:output withValue:invalidResults mediaSpecs:mediaSpecs error:&error];

    if (!result) {
        NSLog(@"OK Invalid output correctly failed validation");
        NSLog(@"   Error: %@", error.localizedDescription);
    } else {
        NSLog(@"ERR Invalid output incorrectly passed validation");
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

    NSDictionary *mediaSpecs = @{
        @"my:document.v1": @{
            @"media_type": @"application/json",
            @"profile_uri": @"https://example.com/schema/document",
            @"schema": documentSchema
        }
    };

    CSCapArg *documentArg = [CSCapArg argWithMediaUrn:@"my:document.v1"
                                              required:YES
                                               sources:@[[CSArgSource cliFlagSource:@"--document"]]
                                        argDescription:@"Complex document structure"
                                            validation:nil
                                          defaultValue:nil];

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
    BOOL result = [self.validator validateArgument:documentArg withValue:validDocument mediaSpecs:mediaSpecs error:&error];

    if (result) {
        NSLog(@"OK Complex nested document passed schema validation");
    } else {
        NSLog(@"ERR Complex nested document failed schema validation: %@", error.localizedDescription);
    }
}

- (void)demonstratePerformanceConsiderations {
    NSLog(@"\n=== Performance Considerations Example ===");

    // Schema in mediaSpecs
    NSDictionary *simpleSchema = @{
        @"type": @"object",
        @"properties": @{
            @"id": @{@"type": @"string"},
            @"value": @{@"type": @"number"}
        },
        @"required": @[@"id", @"value"]
    };

    NSDictionary *mediaSpecs = @{
        @"my:item.v1": @{
            @"media_type": @"application/json",
            @"profile_uri": @"https://example.com/schema/item",
            @"schema": simpleSchema
        }
    };

    CSCapArg *arg = [CSCapArg argWithMediaUrn:@"my:item.v1"
                                      required:YES
                                       sources:@[[CSArgSource cliFlagSource:@"--item"]]
                                argDescription:@"Simple item"
                                    validation:nil
                                  defaultValue:nil];

    // Measure validation performance
    NSDate *startTime = [NSDate date];

    for (NSInteger i = 0; i < 1000; i++) {
        NSDictionary *testData = @{@"id": [NSString stringWithFormat:@"item_%ld", (long)i], @"value": @(i * 1.5)};
        NSError *error = nil;
        [self.validator validateArgument:arg withValue:testData mediaSpecs:mediaSpecs error:&error];
    }

    NSTimeInterval duration = [[NSDate date] timeIntervalSinceDate:startTime];
    NSLog(@"OK Validated 1000 objects in %.3f seconds (%.3f ms per validation)",
          duration, duration * 1000.0 / 1000.0);
}

- (void)runAllExamples {
    NSLog(@" Starting JSON Schema Validation Examples\n");

    [self demonstrateEmbeddedSchemaValidation];
    [self demonstrateBuiltinSpecIds];
    [self demonstrateOutputValidation];
    [self demonstrateComplexNestedValidation];
    [self demonstratePerformanceConsiderations];

    NSLog(@"\nOK All examples completed successfully!");
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

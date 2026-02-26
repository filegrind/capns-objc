//
//  CSSchemaValidationTests.m
//  Comprehensive tests for JSON Schema validation
//
//  Tests schema validation for both arguments and outputs with schemas stored
//  in the mediaSpecs array, and integration with existing validation system.
//
//  Schemas are stored in the mediaSpecs array and resolved via URN field.
//

#import <XCTest/XCTest.h>
#import "CapNs.h"

@interface CSSchemaValidationTests : XCTestCase
@property (nonatomic, strong) CSJSONSchemaValidator *validator;
@property (nonatomic, strong) CSFileSchemaResolver *resolver;
@property (nonatomic, strong) NSString *tempDir;
@end

@implementation CSSchemaValidationTests

- (void)setUp {
    [super setUp];
    self.validator = [CSJSONSchemaValidator validator];

    // Create temporary directory for schema files
    self.tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.tempDir
                               withIntermediateDirectories:YES
                                                attributes:nil
                                                     error:nil];

    self.resolver = [CSFileSchemaResolver resolverWithBasePath:self.tempDir];
    self.validator.resolver = self.resolver;
}

- (void)tearDown {
    // Clean up temporary directory
    [[NSFileManager defaultManager] removeItemAtPath:self.tempDir error:nil];
    [super tearDown];
}

#pragma mark - Argument Schema Validation Tests

// TEST051: Test input validation succeeds with valid positional argument
- (void)testArgumentWithEmbeddedSchemaValidationSuccess {
    // Create argument with spec ID that has embedded schema in mediaSpecs
    NSDictionary *schema = @{
        @"type": @"object",
        @"properties": @{
            @"name": @{@"type": @"string"},
            @"age": @{@"type": @"integer", @"minimum": @0}
        },
        @"required": @[@"name"]
    };

    // MediaSpecs array with schema
    NSArray<NSDictionary *> *mediaSpecs = @[
        @{
            @"urn": @"my:user-data.v1;textable;record",
            @"media_type": @"application/json",
            @"profile_uri": @"https://example.com/schema/user-data",
            @"schema": schema
        }
    ];

    CSCapArg *argument = [CSCapArg argWithMediaUrn:@"my:user-data.v1;textable;record"
                                             required:YES
                                              sources:@[[CSArgSource cliFlagSource:@"--user"]]
                                       argDescription:@"User data object"
                                         defaultValue:nil];

    // Valid data that matches schema
    NSDictionary *validData = @{
        @"name": @"John Doe",
        @"age": @25
    };

    NSError *error = nil;
    BOOL result = [self.validator validateArgument:argument withValue:validData mediaSpecs:mediaSpecs error:&error];

    XCTAssertTrue(result, @"Validation should succeed for valid data");
    XCTAssertNil(error, @"Error should be nil for valid data");
}

// TEST052: Test input validation fails with MissingRequiredArgument when required arg missing
- (void)testArgumentWithEmbeddedSchemaValidationFailure {
    // Create argument with spec ID that has embedded schema in mediaSpecs
    NSDictionary *schema = @{
        @"type": @"object",
        @"properties": @{
            @"name": @{@"type": @"string"},
            @"age": @{@"type": @"integer", @"minimum": @0}
        },
        @"required": @[@"name"]
    };

    NSArray<NSDictionary *> *mediaSpecs = @[
        @{
            @"urn": @"my:user-data.v1;textable;record",
            @"media_type": @"application/json",
            @"profile_uri": @"https://example.com/schema/user-data",
            @"schema": schema
        }
    ];

    CSCapArg *argument = [CSCapArg argWithMediaUrn:@"my:user-data.v1;textable;record"
                                             required:YES
                                              sources:@[[CSArgSource cliFlagSource:@"--user"]]
                                       argDescription:@"User data object"
                                         defaultValue:nil];

    // Invalid data - missing required field
    NSDictionary *invalidData = @{
        @"age": @25
    };

    NSError *error = nil;
    BOOL result = [self.validator validateArgument:argument withValue:invalidData mediaSpecs:mediaSpecs error:&error];

    XCTAssertFalse(result, @"Validation should fail for invalid data");
    XCTAssertNotNil(error, @"Error should be present for invalid data");
    XCTAssertTrue([error isKindOfClass:[CSSchemaValidationError class]], @"Should be schema validation error");

    CSSchemaValidationError *schemaError = (CSSchemaValidationError *)error;
    XCTAssertEqual(schemaError.schemaErrorType, CSSchemaValidationErrorTypeMediaValidation);
    XCTAssertEqualObjects(schemaError.argumentName, @"my:user-data.v1;textable;record");
}

// TEST053: Test input validation fails with InvalidArgumentType when wrong type provided
- (void)testArgumentWithUnresolvableSpecIdFailsHard {
    // Create argument with non-existent spec ID
    CSCapArg *argument = [CSCapArg argWithMediaUrn:@"unknown:spec.v1"
                                             required:YES
                                              sources:@[[CSArgSource cliFlagSource:@"--data"]]
                                       argDescription:@"Some data"
                                         defaultValue:nil];

    NSDictionary *data = @{@"test": @"value"};

    NSError *error = nil;
    BOOL result = [self.validator validateArgument:argument withValue:data mediaSpecs:@[] error:&error];

    XCTAssertFalse(result, @"Validation should fail for unresolvable spec ID");
    XCTAssertNotNil(error, @"Error should be present");
    // The validator should fail hard when spec ID cannot be resolved
}

// Obj-C specific: Non-structured argument skips schema validation
- (void)testNonStructuredArgumentSkipsSchemaValidation {
    // Create string argument (no schema validation expected for non-structured types)
    // Media URNs must be defined in mediaSpecs (no built-in resolution)
    NSArray<NSDictionary *> *mediaSpecs = @[
        @{
            @"urn": CSMediaString,
            @"media_type": @"text/plain",
            @"profile_uri": @"https://capns.org/schema/string"
        }
    ];

    CSCapArg *argument = [CSCapArg argWithMediaUrn:CSMediaString
                                             required:YES
                                              sources:@[[CSArgSource cliFlagSource:@"--name"]]
                                       argDescription:@"User name"
                                         defaultValue:nil];

    NSString *value = @"test";

    NSError *error = nil;
    BOOL result = [self.validator validateArgument:argument withValue:value mediaSpecs:mediaSpecs error:&error];

    XCTAssertTrue(result, @"Non-structured types should skip schema validation");
    XCTAssertNil(error, @"Error should be nil");
}

#pragma mark - Output Schema Validation Tests

// Obj-C specific: Output validation tests
- (void)testOutputWithEmbeddedSchemaValidationSuccess {
    NSDictionary *schema = @{
        @"type": @"object",
        @"properties": @{
            @"result": @{@"type": @"string"},
            @"count": @{@"type": @"integer", @"minimum": @0},
            @"items": @{
                @"type": @"array",
                @"items": @{@"type": @"object"}
            }
        },
        @"required": @[@"result", @"count"]
    };

    NSArray<NSDictionary *> *mediaSpecs = @[
        @{
            @"urn": @"my:query-results.v1;textable;list",
            @"media_type": @"application/json",
            @"profile_uri": @"https://example.com/schema/query-results",
            @"schema": schema
        }
    ];

    CSCapOutput *output = [CSCapOutput outputWithMediaUrn:@"my:query-results.v1;textable;list"
                                         outputDescription:@"Query results"];

    // Valid output data
    NSDictionary *validData = @{
        @"result": @"success",
        @"count": @5,
        @"items": @[
            @{@"id": @1, @"name": @"item1"},
            @{@"id": @2, @"name": @"item2"}
        ]
    };

    NSError *error = nil;
    BOOL result = [self.validator validateOutput:output withValue:validData mediaSpecs:mediaSpecs error:&error];

    XCTAssertTrue(result, @"Output validation should succeed for valid data");
    XCTAssertNil(error, @"Error should be nil for valid data");
}

- (void)testOutputWithEmbeddedSchemaValidationFailure {
    NSDictionary *schema = @{
        @"type": @"object",
        @"properties": @{
            @"result": @{@"type": @"string"},
            @"count": @{@"type": @"integer", @"minimum": @0}
        },
        @"required": @[@"result", @"count"]
    };

    NSArray<NSDictionary *> *mediaSpecs = @[
        @{
            @"urn": @"my:query-results.v1;textable;list",
            @"media_type": @"application/json",
            @"profile_uri": @"https://example.com/schema/query-results",
            @"schema": schema
        }
    ];

    CSCapOutput *output = [CSCapOutput outputWithMediaUrn:@"my:query-results.v1;textable;list"
                                         outputDescription:@"Query results"];

    // Invalid data - negative count
    NSDictionary *invalidData = @{
        @"result": @"success",
        @"count": @(-1)
    };

    NSError *error = nil;
    BOOL result = [self.validator validateOutput:output withValue:invalidData mediaSpecs:mediaSpecs error:&error];

    XCTAssertFalse(result, @"Output validation should fail for invalid data");
    XCTAssertNotNil(error, @"Error should be present for invalid data");
    XCTAssertTrue([error isKindOfClass:[CSSchemaValidationError class]]);

    CSSchemaValidationError *schemaError = (CSSchemaValidationError *)error;
    XCTAssertEqual(schemaError.schemaErrorType, CSSchemaValidationErrorTypeOutputValidation);
}

#pragma mark - Integration with CSCapValidator Tests

- (void)testIntegrationWithInputValidation {
    // Create cap with schema-enabled arguments
    // Use media:record;textable instead of media:object to indicate textable object data
    CSCapUrn *urn = [[[[[[CSCapUrnBuilder builder] inSpec:@"media:void"] outSpec:@"media:record;textable"] tag:@"op" value:@"process"] tag:@"target" value:@"user"] build:nil];

    NSDictionary *userSchema = @{
        @"type": @"object",
        @"properties": @{
            @"id": @{@"type": @"integer"},
            @"name": @{@"type": @"string"},
            @"email": @{@"type": @"string", @"pattern": @"^[^@]+@[^@]+\\.[^@]+$"}
        },
        @"required": @[@"id", @"name", @"email"]
    };

    NSArray<NSDictionary *> *mediaSpecs = @[
        @{
            @"urn": @"my:user.v1;textable;record",
            @"media_type": @"application/json",
            @"profile_uri": @"https://example.com/schema/user",
            @"schema": userSchema
        }
    ];

    CSCapArg *userArg = [CSCapArg argWithMediaUrn:@"my:user.v1;textable;record"
                                            required:YES
                                             sources:@[[CSArgSource cliFlagSource:@"--user"]]
                                      argDescription:@"User object"
                                        defaultValue:nil];

    CSCap *cap = [CSCap capWithUrn:urn
                             title:@"Process User"
                           command:@"process-user"
                       description:@"Process user data"
                          metadata:@{}
                        mediaSpecs:mediaSpecs
                              args:@[userArg]
                            output:nil
                      metadataJSON:nil];

    // Valid user data
    NSDictionary *validUser = @{
        @"id": @123,
        @"name": @"John Doe",
        @"email": @"john@example.com"
    };

    NSError *error = nil;
    BOOL result = [CSInputValidator validateArguments:@[validUser] cap:cap error:&error];

    XCTAssertTrue(result, @"Input validation should succeed with valid schema data");
    XCTAssertNil(error, @"Error should be nil");

    // Invalid user data - bad email
    NSDictionary *invalidUser = @{
        @"id": @123,
        @"name": @"John Doe",
        @"email": @"invalid-email"
    };

    result = [CSInputValidator validateArguments:@[invalidUser] cap:cap error:&error];

    XCTAssertFalse(result, @"Input validation should fail with invalid schema data");
    XCTAssertNotNil(error, @"Error should be present");
    XCTAssertTrue([error isKindOfClass:[CSValidationError class]]);

    CSValidationError *validationError = (CSValidationError *)error;
    XCTAssertEqual(validationError.validationType, CSValidationErrorTypeSchemaValidationFailed);
}

- (void)testIntegrationWithOutputValidation {
    // Create cap with schema-enabled output
    // Use media:record;textable instead of media:object to indicate textable object data
    CSCapUrn *urn = [[[[[[CSCapUrnBuilder builder] inSpec:@"media:void"] outSpec:@"media:record;textable"] tag:@"op" value:@"query"] tag:@"target" value:@"data"] build:nil];

    NSDictionary *resultSchema = @{
        @"type": @"array",
        @"items": @{
            @"type": @"object",
            @"properties": @{
                @"id": @{@"type": @"string"},
                @"value": @{@"type": @"number"}
            },
            @"required": @[@"id", @"value"]
        },
        @"minItems": @0
    };

    NSArray<NSDictionary *> *mediaSpecs = @[
        @{
            @"urn": @"my:results-array.v1;textable;list",
            @"media_type": @"application/json",
            @"profile_uri": @"https://example.com/schema/results-array",
            @"schema": resultSchema
        }
    ];

    CSCapOutput *output = [CSCapOutput outputWithMediaUrn:@"my:results-array.v1;textable;list"
                                         outputDescription:@"Query results array"];

    CSCap *cap = [CSCap capWithUrn:urn
                             title:@"Query Data"
                           command:@"query-data"
                       description:@"Query data"
                          metadata:@{}
                        mediaSpecs:mediaSpecs
                              args:@[]
                            output:output
                      metadataJSON:nil];

    // Valid output
    NSArray *validOutput = @[
        @{@"id": @"item1", @"value": @42.5},
        @{@"id": @"item2", @"value": @100.0}
    ];

    NSError *error = nil;
    BOOL result = [CSOutputValidator validateOutput:validOutput cap:cap error:&error];

    XCTAssertTrue(result, @"Output validation should succeed with valid schema data");
    XCTAssertNil(error, @"Error should be nil");

    // Invalid output - missing required field
    NSArray *invalidOutput = @[
        @{@"id": @"item1"} // Missing 'value' field
    ];

    result = [CSOutputValidator validateOutput:invalidOutput cap:cap error:&error];

    XCTAssertFalse(result, @"Output validation should fail with invalid schema data");
    XCTAssertNotNil(error, @"Error should be present");
    XCTAssertTrue([error isKindOfClass:[CSValidationError class]]);

    CSValidationError *validationError = (CSValidationError *)error;
    XCTAssertEqual(validationError.validationType, CSValidationErrorTypeSchemaValidationFailed);
}

#pragma mark - Complex Schema Validation Tests

- (void)testComplexNestedSchema {
    NSDictionary *complexSchema = @{
        @"type": @"object",
        @"properties": @{
            @"metadata": @{
                @"type": @"object",
                @"properties": @{
                    @"version": @{@"type": @"string"},
                    @"timestamp": @{@"type": @"string"}
                },
                @"required": @[@"version"]
            },
            @"data": @{
                @"type": @"array",
                @"items": @{
                    @"type": @"object",
                    @"properties": @{
                        @"id": @{@"type": @"integer"},
                        @"tags": @{
                            @"type": @"array",
                            @"items": @{@"type": @"string"},
                            @"maxItems": @5
                        }
                    },
                    @"required": @[@"id"]
                }
            }
        },
        @"required": @[@"metadata", @"data"]
    };

    NSArray<NSDictionary *> *mediaSpecs = @[
        @{
            @"urn": @"my:payload.v1;textable;record",
            @"media_type": @"application/json",
            @"profile_uri": @"https://example.com/schema/payload",
            @"schema": complexSchema
        }
    ];

    CSCapArg *argument = [CSCapArg argWithMediaUrn:@"my:payload.v1;textable;record"
                                             required:YES
                                              sources:@[[CSArgSource cliFlagSource:@"--payload"]]
                                       argDescription:@"Complex payload"
                                         defaultValue:nil];

    // Valid complex data
    NSDictionary *validData = @{
        @"metadata": @{
            @"version": @"1.0",
            @"timestamp": @"2023-01-01T00:00:00Z"
        },
        @"data": @[
            @{
                @"id": @1,
                @"tags": @[@"important", @"processed"]
            },
            @{
                @"id": @2,
                @"tags": @[@"test"]
            }
        ]
    };

    NSError *error = nil;
    BOOL result = [self.validator validateArgument:argument withValue:validData mediaSpecs:mediaSpecs error:&error];

    XCTAssertTrue(result, @"Complex nested schema validation should succeed");
    XCTAssertNil(error, @"Error should be nil for valid complex data");

    // Invalid data - too many tags
    NSDictionary *invalidData = @{
        @"metadata": @{
            @"version": @"1.0"
        },
        @"data": @[
            @{
                @"id": @1,
                @"tags": @[@"tag1", @"tag2", @"tag3", @"tag4", @"tag5", @"tag6"] // Too many tags
            }
        ]
    };

    result = [self.validator validateArgument:argument withValue:invalidData mediaSpecs:mediaSpecs error:&error];

    XCTAssertFalse(result, @"Complex nested schema validation should fail for invalid data");
    XCTAssertNotNil(error, @"Error should be present for invalid complex data");
}

#pragma mark - Error Handling Tests

- (void)testSchemaValidationErrorDetails {
    NSDictionary *schema = @{
        @"type": @"object",
        @"properties": @{
            @"requiredString": @{@"type": @"string"},
            @"optionalNumber": @{@"type": @"number", @"minimum": @0}
        },
        @"required": @[@"requiredString"]
    };

    NSArray<NSDictionary *> *mediaSpecs = @[
        @{
            @"urn": @"my:test-arg.v1;textable;record",
            @"media_type": @"application/json",
            @"profile_uri": @"https://example.com/schema/test-arg",
            @"schema": schema
        }
    ];

    CSCapArg *argument = [CSCapArg argWithMediaUrn:@"my:test-arg.v1;textable;record"
                                             required:YES
                                              sources:@[[CSArgSource cliFlagSource:@"--test"]]
                                       argDescription:@"Test argument"
                                         defaultValue:nil];

    // Invalid data with multiple errors
    NSDictionary *invalidData = @{
        @"optionalNumber": @(-5) // Missing required string, negative number
    };

    NSError *error = nil;
    BOOL result = [self.validator validateArgument:argument withValue:invalidData mediaSpecs:mediaSpecs error:&error];

    XCTAssertFalse(result, @"Validation should fail");
    XCTAssertNotNil(error, @"Error should be present");
    XCTAssertTrue([error isKindOfClass:[CSSchemaValidationError class]]);

    CSSchemaValidationError *schemaError = (CSSchemaValidationError *)error;
    XCTAssertEqual(schemaError.schemaErrorType, CSSchemaValidationErrorTypeMediaValidation);
    XCTAssertEqualObjects(schemaError.argumentName, @"my:test-arg.v1;textable;record");
    XCTAssertNotNil(schemaError.validationErrors);
    XCTAssertTrue(schemaError.validationErrors.count > 0, @"Should have validation error details");
}

#pragma mark - Built-in Spec ID Tests

- (void)testBuiltinSpecIdsResolve {
    // Media URNs must be defined in mediaSpecs array (no built-in resolution)
    NSArray<NSDictionary *> *mediaSpecs = @[
        @{
            @"urn": CSMediaString,
            @"media_type": @"text/plain",
            @"profile_uri": @"https://capns.org/schema/string"
        },
        @{
            @"urn": CSMediaInteger,
            @"media_type": @"text/plain",
            @"profile_uri": @"https://capns.org/schema/integer"
        },
        @{
            @"urn": CSMediaObject,
            @"media_type": @"application/json",
            @"profile_uri": @"https://capns.org/schema/object"
        }
    ];

    CSCapArg *strArg = [CSCapArg argWithMediaUrn:CSMediaString
                                           required:YES
                                            sources:@[[CSArgSource cliFlagSource:@"--text"]]
                                     argDescription:@"Text input"
                                       defaultValue:nil];

    NSError *error = nil;
    BOOL result = [self.validator validateArgument:strArg withValue:@"hello" mediaSpecs:mediaSpecs error:&error];
    XCTAssertTrue(result, @"String spec should validate string");
    XCTAssertNil(error);

    CSCapArg *intArg = [CSCapArg argWithMediaUrn:CSMediaInteger
                                         required:YES
                                          sources:@[[CSArgSource cliFlagSource:@"--count"]]
                                   argDescription:@"Count value"
                                     defaultValue:nil];

    result = [self.validator validateArgument:intArg withValue:@42 mediaSpecs:mediaSpecs error:&error];
    XCTAssertTrue(result, @"Integer spec should validate integer");
    XCTAssertNil(error);

    CSCapArg *objArg = [CSCapArg argWithMediaUrn:CSMediaObject
                                        required:YES
                                         sources:@[[CSArgSource cliFlagSource:@"--data"]]
                                  argDescription:@"JSON data"
                                    defaultValue:nil];

    result = [self.validator validateArgument:objArg withValue:@{@"key": @"value"} mediaSpecs:mediaSpecs error:&error];
    XCTAssertTrue(result, @"Object spec should validate object");
    XCTAssertNil(error);
}

#pragma mark - MediaSpecs Without Schema Tests

- (void)testMediaSpecsWithoutSchemaSkipsValidation {
    // Test that media spec definitions without schema skip schema validation
    NSArray<NSDictionary *> *mediaSpecs = @[
        @{
            @"urn": @"my:text-input.v1;textable",
            @"media_type": @"text/plain",
            @"profile_uri": @"https://example.com/schema/text-input"
        }
    ];

    CSCapArg *argument = [CSCapArg argWithMediaUrn:@"my:text-input.v1;textable"
                                             required:YES
                                              sources:@[[CSArgSource cliFlagSource:@"--input"]]
                                       argDescription:@"Text input"
                                         defaultValue:nil];

    // Spec without schema skips schema validation
    // (schema validation is skipped when no schema is present)
    NSError *error = nil;
    BOOL result = [self.validator validateArgument:argument withValue:@"hello world" mediaSpecs:mediaSpecs error:&error];
    XCTAssertTrue(result, @"Spec without schema should pass");
    XCTAssertNil(error);
}

#pragma mark - Performance Tests

- (void)testSchemaValidationPerformance {
    // Create a large schema
    NSDictionary *schema = @{
        @"type": @"array",
        @"items": @{
            @"type": @"object",
            @"properties": @{
                @"id": @{@"type": @"string"},
                @"value": @{@"type": @"number"},
                @"metadata": @{
                    @"type": @"object",
                    @"properties": @{
                        @"created": @{@"type": @"string"},
                        @"updated": @{@"type": @"string"}
                    }
                }
            },
            @"required": @[@"id", @"value"]
        }
    };

    NSArray<NSDictionary *> *mediaSpecs = @[
        @{
            @"urn": @"my:large-data.v1;textable;record",
            @"media_type": @"application/json",
            @"profile_uri": @"https://example.com/schema/large-data",
            @"schema": schema
        }
    ];

    CSCapArg *argument = [CSCapArg argWithMediaUrn:@"my:large-data.v1;textable;record"
                                             required:YES
                                              sources:@[[CSArgSource cliFlagSource:@"--data"]]
                                       argDescription:@"Large data set"
                                         defaultValue:nil];

    // Create large valid data set
    NSMutableArray *largeDataSet = [NSMutableArray array];
    for (NSInteger i = 0; i < 1000; i++) {
        [largeDataSet addObject:@{
            @"id": [NSString stringWithFormat:@"item_%ld", (long)i],
            @"value": @(i * 1.5),
            @"metadata": @{
                @"created": @"2023-01-01",
                @"updated": @"2023-01-01"
            }
        }];
    }

    [self measureBlock:^{
        NSError *error = nil;
        BOOL result = [self.validator validateArgument:argument withValue:largeDataSet mediaSpecs:mediaSpecs error:&error];
        XCTAssertTrue(result, @"Large data set validation should succeed");
    }];
}

#pragma mark - Cap Full Validation Tests

- (void)testFullCapValidationWithMediaSpecs {
    // Test complete cap validation flow with mediaSpecs resolution
    // Use media:record;textable instead of media:object to indicate textable object data
    NSError *error = nil;
    CSCapUrn *urn = [[[[[[CSCapUrnBuilder builder] inSpec:@"media:void"] outSpec:@"media:record;textable"] tag:@"format" value:@"json"] tag:@"op" value:@"transform"] build:&error];
    XCTAssertNotNil(urn);

    NSDictionary *inputSchema = @{
        @"type": @"object",
        @"properties": @{
            @"source": @{@"type": @"string"},
            @"options": @{
                @"type": @"object",
                @"properties": @{
                    @"pretty": @{@"type": @"boolean"},
                    @"indent": @{@"type": @"integer", @"minimum": @0, @"maximum": @8}
                }
            }
        },
        @"required": @[@"source"]
    };

    NSDictionary *outputSchema = @{
        @"type": @"object",
        @"properties": @{
            @"result": @{@"type": @"string"},
            @"byteCount": @{@"type": @"integer", @"minimum": @0}
        },
        @"required": @[@"result"]
    };

    NSArray<NSDictionary *> *mediaSpecs = @[
        @{
            @"urn": @"my:transform-input.v1;textable;record",
            @"media_type": @"application/json",
            @"profile_uri": @"https://example.com/schema/transform-input",
            @"schema": inputSchema
        },
        @{
            @"urn": @"my:transform-output.v1;textable;record",
            @"media_type": @"application/json",
            @"profile_uri": @"https://example.com/schema/transform-output",
            @"schema": outputSchema
        }
    ];

    CSCapArg *inputArg = [CSCapArg argWithMediaUrn:@"my:transform-input.v1;textable;record"
                                             required:YES
                                              sources:@[[CSArgSource positionSource:0], [CSArgSource cliFlagSource:@"--input"]]
                                       argDescription:@"Transformation input"
                                         defaultValue:nil];

    CSCapOutput *output = [CSCapOutput outputWithMediaUrn:@"my:transform-output.v1;textable;record"
                                         outputDescription:@"Transformation result"];

    CSCap *cap = [CSCap capWithUrn:urn
                             title:@"Transform JSON"
                           command:@"transform-json"
                       description:@"Transform JSON data"
                          metadata:@{}
                        mediaSpecs:mediaSpecs
                              args:@[inputArg]
                            output:output
                      metadataJSON:nil];

    // Validate cap itself
    BOOL capValid = [CSCapValidator validateCap:cap error:&error];
    XCTAssertTrue(capValid, @"Cap should be valid: %@", error);

    // Test valid input
    NSDictionary *validInput = @{
        @"source": @"{\"key\": \"value\"}",
        @"options": @{
            @"pretty": @YES,
            @"indent": @2
        }
    };

    BOOL inputValid = [CSInputValidator validateArguments:@[validInput] cap:cap error:&error];
    XCTAssertTrue(inputValid, @"Valid input should pass: %@", error);

    // Test valid output
    NSDictionary *validOutputData = @{
        @"result": @"{\n  \"key\": \"value\"\n}",
        @"byteCount": @24
    };

    BOOL outputValid = [CSOutputValidator validateOutput:validOutputData cap:cap error:&error];
    XCTAssertTrue(outputValid, @"Valid output should pass: %@", error);
}

#pragma mark - XV5 Validation Tests

// TEST054: XV5 - Test inline media spec redefinition of existing registry spec is detected and rejected
- (void)testXV5InlineSpecRedefinitionDetected {
    // Try to redefine CSMediaString which exists in the registry
    // CSMediaString = @"media:textable"
    NSArray<NSDictionary *> *mediaSpecs = @[
        @{
            @"urn": CSMediaString,
            @"media_type": @"text/plain",
            @"title": @"My Custom String",
            @"description": @"Trying to redefine string"
        }
    ];

    // Mock registry lookup that returns YES for CSMediaString (it exists in registry)
    CSMediaUrnExistsInRegistryBlock mockRegistryLookup = ^BOOL(NSString *mediaUrn) {
        return [mediaUrn isEqualToString:CSMediaString];
    };

    CSXV5ValidationResult *result = [CSXV5Validator validateNoInlineMediaSpecRedefinition:mediaSpecs
                                                                        existsInRegistry:mockRegistryLookup];

    XCTAssertFalse(result.valid, @"Should fail validation when redefining registry spec");
    XCTAssertNotNil(result.error, @"Should have error message");
    XCTAssertTrue([result.error containsString:@"XV5"], @"Error should mention XV5");
    XCTAssertTrue([result.redefines containsObject:CSMediaString], @"Should identify CSMediaString as redefined");
}

// TEST055: XV5 - Test new inline media spec (not in registry) is allowed
- (void)testXV5NewInlineSpecAllowed {
    // Define a completely new media spec that doesn't exist in registry
    NSArray<NSDictionary *> *mediaSpecs = @[
        @{
            @"urn": @"media:my-unique-custom-type-xyz123",
            @"media_type": @"application/json",
            @"title": @"My Custom Output",
            @"description": @"A custom output type"
        }
    ];

    // Mock registry lookup that returns NO (spec not in registry)
    CSMediaUrnExistsInRegistryBlock mockRegistryLookup = ^BOOL(NSString *mediaUrn) {
        return NO;
    };

    CSXV5ValidationResult *result = [CSXV5Validator validateNoInlineMediaSpecRedefinition:mediaSpecs
                                                                        existsInRegistry:mockRegistryLookup];

    XCTAssertTrue(result.valid, @"Should pass validation for new spec not in registry");
    XCTAssertNil(result.error, @"Should not have error message");
}

// TEST056: XV5 - Test empty media_specs (no inline specs) passes XV5 validation
- (void)testXV5EmptyMediaSpecsAllowed {
    // Empty media_specs should pass (with or without registry lookup)
    CSXV5ValidationResult *result = [CSXV5Validator validateNoInlineMediaSpecRedefinition:@[]
                                                                        existsInRegistry:nil];
    XCTAssertTrue(result.valid, @"Empty array should pass validation");

    // Nil media_specs should pass
    result = [CSXV5Validator validateNoInlineMediaSpecRedefinition:nil
                                                  existsInRegistry:nil];
    XCTAssertTrue(result.valid, @"Nil should pass validation");

    // Graceful degradation: nil lookup function should allow
    NSArray<NSDictionary *> *mediaSpecs = @[
        @{
            @"urn": CSMediaString,
            @"media_type": @"text/plain",
        }
    ];
    result = [CSXV5Validator validateNoInlineMediaSpecRedefinition:mediaSpecs
                                                  existsInRegistry:nil];
    XCTAssertTrue(result.valid, @"Should pass when registry lookup not available (graceful degradation)");
}

@end

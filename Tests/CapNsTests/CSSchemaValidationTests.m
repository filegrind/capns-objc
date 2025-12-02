//
//  CSSchemaValidationTests.m
//  Comprehensive tests for JSON Schema validation
//
//  Tests schema validation for both arguments and outputs with embedded schemas,
//  schema references, and integration with existing validation system.
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

- (void)testArgumentWithEmbeddedSchemaValidationSuccess {
    // Create argument with embedded schema
    NSDictionary *schema = @{
        @"type": @"object",
        @"properties": @{
            @"name": @{@"type": @"string"},
            @"age": @{@"type": @"integer", @"minimum": @0}
        },
        @"required": @[@"name"]
    };
    
    CSCapArgument *argument = [CSCapArgument argumentWithName:@"user_data"
                                                      argType:CSArgumentTypeObject
                                                argDescription:@"User data object"
                                                      cliFlag:@"--user"
                                                       schema:schema];
    
    // Valid data that matches schema
    NSDictionary *validData = @{
        @"name": @"John Doe",
        @"age": @25
    };
    
    NSError *error = nil;
    BOOL result = [self.validator validateArgument:argument withValue:validData error:&error];
    
    XCTAssertTrue(result, @"Validation should succeed for valid data");
    XCTAssertNil(error, @"Error should be nil for valid data");
}

- (void)testArgumentWithEmbeddedSchemaValidationFailure {
    // Create argument with embedded schema
    NSDictionary *schema = @{
        @"type": @"object",
        @"properties": @{
            @"name": @{@"type": @"string"},
            @"age": @{@"type": @"integer", @"minimum": @0}
        },
        @"required": @[@"name"]
    };
    
    CSCapArgument *argument = [CSCapArgument argumentWithName:@"user_data"
                                                      argType:CSArgumentTypeObject
                                                argDescription:@"User data object"
                                                      cliFlag:@"--user"
                                                       schema:schema];
    
    // Invalid data - missing required field
    NSDictionary *invalidData = @{
        @"age": @25
    };
    
    NSError *error = nil;
    BOOL result = [self.validator validateArgument:argument withValue:invalidData error:&error];
    
    XCTAssertFalse(result, @"Validation should fail for invalid data");
    XCTAssertNotNil(error, @"Error should be present for invalid data");
    XCTAssertTrue([error isKindOfClass:[CSSchemaValidationError class]], @"Should be schema validation error");
    
    CSSchemaValidationError *schemaError = (CSSchemaValidationError *)error;
    XCTAssertEqual(schemaError.schemaErrorType, CSSchemaValidationErrorTypeArgumentValidation);
    XCTAssertEqualObjects(schemaError.argumentName, @"user_data");
}

- (void)testArgumentWithSchemaReference {
    // Create schema file
    NSDictionary *schema = @{
        @"type": @"array",
        @"items": @{@"type": @"string"},
        @"minItems": @1,
        @"maxItems": @10
    };
    
    NSString *schemaPath = [self.tempDir stringByAppendingPathComponent:@"string_array.json"];
    NSData *schemaData = [NSJSONSerialization dataWithJSONObject:schema options:0 error:nil];
    [schemaData writeToFile:schemaPath atomically:YES];
    
    // Create argument with schema reference
    CSCapArgument *argument = [CSCapArgument argumentWithName:@"tags"
                                                      argType:CSArgumentTypeArray
                                                argDescription:@"Array of tags"
                                                      cliFlag:@"--tags"
                                                    schemaRef:@"string_array"];
    
    // Valid data
    NSArray *validData = @[@"tag1", @"tag2", @"tag3"];
    
    NSError *error = nil;
    BOOL result = [self.validator validateArgument:argument withValue:validData error:&error];
    
    XCTAssertTrue(result, @"Validation should succeed for valid array data");
    XCTAssertNil(error, @"Error should be nil for valid data");
}

- (void)testArgumentWithInvalidSchemaReference {
    // Create argument with non-existent schema reference
    CSCapArgument *argument = [CSCapArgument argumentWithName:@"data"
                                                      argType:CSArgumentTypeObject
                                                argDescription:@"Some data"
                                                      cliFlag:@"--data"
                                                    schemaRef:@"non_existent_schema"];
    
    NSDictionary *data = @{@"test": @"value"};
    
    NSError *error = nil;
    BOOL result = [self.validator validateArgument:argument withValue:data error:&error];
    
    XCTAssertFalse(result, @"Validation should fail for non-existent schema");
    XCTAssertNotNil(error, @"Error should be present");
    XCTAssertTrue([error isKindOfClass:[CSSchemaValidationError class]]);
    
    CSSchemaValidationError *schemaError = (CSSchemaValidationError *)error;
    XCTAssertEqual(schemaError.schemaErrorType, CSSchemaValidationErrorTypeSchemaRefNotResolved);
}

- (void)testNonStructuredArgumentSkipsSchemaValidation {
    // Create string argument (no schema validation expected)
    CSCapArgument *argument = [CSCapArgument argumentWithName:@"name"
                                                      argType:CSArgumentTypeString
                                                argDescription:@"User name"
                                                      cliFlag:@"--name"
                                                    position:nil
                                                  validation:nil
                                                defaultValue:nil];
    
    NSString *value = @"test";
    
    NSError *error = nil;
    BOOL result = [self.validator validateArgument:argument withValue:value error:&error];
    
    XCTAssertTrue(result, @"Non-structured types should skip schema validation");
    XCTAssertNil(error, @"Error should be nil");
}

#pragma mark - Output Schema Validation Tests

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
    
    CSCapOutput *output = [CSCapOutput outputWithType:CSOutputTypeObject
                                                schema:schema
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
    BOOL result = [self.validator validateOutput:output withValue:validData error:&error];
    
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
    
    CSCapOutput *output = [CSCapOutput outputWithType:CSOutputTypeObject
                                                schema:schema
                                     outputDescription:@"Query results"];
    
    // Invalid data - negative count
    NSDictionary *invalidData = @{
        @"result": @"success",
        @"count": @(-1)
    };
    
    NSError *error = nil;
    BOOL result = [self.validator validateOutput:output withValue:invalidData error:&error];
    
    XCTAssertFalse(result, @"Output validation should fail for invalid data");
    XCTAssertNotNil(error, @"Error should be present for invalid data");
    XCTAssertTrue([error isKindOfClass:[CSSchemaValidationError class]]);
    
    CSSchemaValidationError *schemaError = (CSSchemaValidationError *)error;
    XCTAssertEqual(schemaError.schemaErrorType, CSSchemaValidationErrorTypeOutputValidation);
}

#pragma mark - Integration with CSCapValidator Tests

- (void)testIntegrationWithInputValidation {
    // Create cap with schema-enabled arguments
    CSCapUrn *urn = [CSCapUrn builderWithAction:@"process"].target(@"user").build(nil);
    
    NSDictionary *userSchema = @{
        @"type": @"object",
        @"properties": @{
            @"id": @{@"type": @"integer"},
            @"name": @{@"type": @"string"},
            @"email": @{@"type": @"string", @"pattern": @"^[^@]+@[^@]+\\.[^@]+$"}
        },
        @"required": @[@"id", @"name", @"email"]
    };
    
    CSCapArgument *userArg = [CSCapArgument argumentWithName:@"user"
                                                     argType:CSArgumentTypeObject
                                               argDescription:@"User object"
                                                     cliFlag:@"--user"
                                                      schema:userSchema];
    
    CSCapArguments *arguments = [CSCapArguments argumentsWithRequired:@[userArg] optional:@[]];
    CSCap *cap = [CSCap capWithUrn:urn
                           command:@"process-user"
                       description:@"Process user data"
                          metadata:@{}
                         arguments:arguments
                            output:nil
                      acceptsStdin:NO];
    
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
    CSCapUrn *urn = [CSCapUrn builderWithAction:@"query"].target(@"data").build(nil);
    
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
    
    CSCapOutput *output = [CSCapOutput outputWithType:CSOutputTypeArray
                                                schema:resultSchema
                                     outputDescription:@"Query results array"];
    
    CSCap *cap = [CSCap capWithUrn:urn
                           command:@"query-data"
                       description:@"Query data"
                          metadata:@{}
                         arguments:[CSCapArguments arguments]
                            output:output
                      acceptsStdin:NO];
    
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
    
    CSCapArgument *argument = [CSCapArgument argumentWithName:@"payload"
                                                      argType:CSArgumentTypeObject
                                                argDescription:@"Complex payload"
                                                      cliFlag:@"--payload"
                                                       schema:complexSchema];
    
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
    BOOL result = [self.validator validateArgument:argument withValue:validData error:&error];
    
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
    
    result = [self.validator validateArgument:argument withValue:invalidData error:&error];
    
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
    
    CSCapArgument *argument = [CSCapArgument argumentWithName:@"test_arg"
                                                      argType:CSArgumentTypeObject
                                                argDescription:@"Test argument"
                                                      cliFlag:@"--test"
                                                       schema:schema];
    
    // Invalid data with multiple errors
    NSDictionary *invalidData = @{
        @"optionalNumber": @(-5) // Missing required string, negative number
    };
    
    NSError *error = nil;
    BOOL result = [self.validator validateArgument:argument withValue:invalidData error:&error];
    
    XCTAssertFalse(result, @"Validation should fail");
    XCTAssertNotNil(error, @"Error should be present");
    XCTAssertTrue([error isKindOfClass:[CSSchemaValidationError class]]);
    
    CSSchemaValidationError *schemaError = (CSSchemaValidationError *)error;
    XCTAssertEqual(schemaError.schemaErrorType, CSSchemaValidationErrorTypeArgumentValidation);
    XCTAssertEqualObjects(schemaError.argumentName, @"test_arg");
    XCTAssertNotNil(schemaError.validationErrors);
    XCTAssertTrue(schemaError.validationErrors.count > 0, @"Should have validation error details");
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
    
    CSCapArgument *argument = [CSCapArgument argumentWithName:@"large_data"
                                                      argType:CSArgumentTypeArray
                                                argDescription:@"Large data set"
                                                      cliFlag:@"--data"
                                                       schema:schema];
    
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
        BOOL result = [self.validator validateArgument:argument withValue:largeDataSet error:&error];
        XCTAssertTrue(result, @"Large data set validation should succeed");
    }];
}

@end
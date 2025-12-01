//
//  CSResponseWrapper.m
//  Response wrapper for unified plugin output handling with validation
//

#import "include/CSResponseWrapper.h"

@interface CSResponseWrapper ()
@property (nonatomic, strong) NSData *rawBytes;
@property (nonatomic, assign) CSResponseContentType contentType;
@end

@implementation CSResponseWrapper

+ (instancetype)responseWithData:(NSData *)data {
    // Try to detect content type from data
    CSResponseContentType type = CSResponseContentTypeText;
    
    // Check if it's valid JSON
    NSError *jsonError = nil;
    [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
    if (!jsonError) {
        type = CSResponseContentTypeJson;
    } else {
        // Check if it's valid UTF-8 text
        NSString *testString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (!testString) {
            type = CSResponseContentTypeBinary;
        }
    }
    
    CSResponseWrapper *wrapper = [[CSResponseWrapper alloc] init];
    wrapper.rawBytes = [data copy];
    wrapper.contentType = type;
    return wrapper;
}

+ (instancetype)jsonResponseWithData:(NSData *)data {
    CSResponseWrapper *wrapper = [[CSResponseWrapper alloc] init];
    wrapper.rawBytes = [data copy];
    wrapper.contentType = CSResponseContentTypeJson;
    return wrapper;
}

+ (instancetype)textResponseWithData:(NSData *)data {
    CSResponseWrapper *wrapper = [[CSResponseWrapper alloc] init];
    wrapper.rawBytes = [data copy];
    wrapper.contentType = CSResponseContentTypeText;
    return wrapper;
}

+ (instancetype)binaryResponseWithData:(NSData *)data {
    CSResponseWrapper *wrapper = [[CSResponseWrapper alloc] init];
    wrapper.rawBytes = [data copy];
    wrapper.contentType = CSResponseContentTypeBinary;
    return wrapper;
}

- (NSString * _Nullable)asStringWithError:(NSError * _Nullable * _Nullable)error {
    NSString *result = [[NSString alloc] initWithData:self.rawBytes encoding:NSUTF8StringEncoding];
    if (!result && error) {
        *error = [NSError errorWithDomain:@"CSResponseWrapper"
                                     code:1001
                                 userInfo:@{NSLocalizedDescriptionKey: @"Failed to convert response data to UTF-8 string"}];
    }
    return result;
}

- (NSData *)asBytes {
    return self.rawBytes;
}

- (NSUInteger)size {
    return self.rawBytes.length;
}

- (BOOL)validateAgainstCap:(CSCap *)cap error:(NSError * _Nullable * _Nullable)error {
    // For binary outputs, check type compatibility
    if (self.contentType == CSResponseContentTypeBinary) {
        CSCapOutput *output = [cap getOutput];
        if (output && output.outputType != CSOutputTypeBinary) {
            if (error) {
                NSString *message = [NSString stringWithFormat:@"Cap %@ expects %@ output but received binary data",
                                   [cap urnString], [self outputTypeToString:output.outputType]];
                *error = [NSError errorWithDomain:@"CSResponseWrapper"
                                             code:1002
                                         userInfo:@{NSLocalizedDescriptionKey: message}];
            }
            return NO;
        }
        return YES;
    }
    
    // For text/JSON outputs, validate the content
    NSError *stringError = nil;
    NSString *text = [self asStringWithError:&stringError];
    if (stringError) {
        if (error) *error = stringError;
        return NO;
    }
    
    if (self.contentType == CSResponseContentTypeJson) {
        // Parse as JSON and validate structure
        NSError *jsonError = nil;
        id jsonObject = [NSJSONSerialization JSONObjectWithData:self.rawBytes options:0 error:&jsonError];
        if (jsonError) {
            if (error) {
                NSString *message = [NSString stringWithFormat:@"Output is not valid JSON for cap %@: %@",
                                   [cap urnString], jsonError.localizedDescription];
                *error = [NSError errorWithDomain:@"CSResponseWrapper"
                                             code:1003
                                         userInfo:@{NSLocalizedDescriptionKey: message}];
            }
            return NO;
        }
        
        // TODO: Add JSON schema validation against cap output definition
        // This would involve checking the JSON structure against cap.output
    }
    
    // TODO: Add comprehensive output validation
    // This would validate the output against the capability's output definition
    
    return YES;
}

- (NSString *)getContentTypeString {
    switch (self.contentType) {
        case CSResponseContentTypeJson:
            return @"application/json";
        case CSResponseContentTypeText:
            return @"text/plain";
        case CSResponseContentTypeBinary:
            return @"application/octet-stream";
    }
}

- (BOOL)matchesOutputTypeForCap:(CSCap *)cap {
    CSCapOutput *outputDef = [cap getOutput];
    if (!outputDef) {
        return NO;
    }
    
    switch (self.contentType) {
        case CSResponseContentTypeJson:
            return (outputDef.outputType == CSOutputTypeObject ||
                   outputDef.outputType == CSOutputTypeArray ||
                   outputDef.outputType == CSOutputTypeString ||
                   outputDef.outputType == CSOutputTypeInteger ||
                   outputDef.outputType == CSOutputTypeNumber ||
                   outputDef.outputType == CSOutputTypeBoolean);
            
        case CSResponseContentTypeText:
            return outputDef.outputType == CSOutputTypeString;
            
        case CSResponseContentTypeBinary:
            return outputDef.outputType == CSOutputTypeBinary;
    }
}

#pragma mark - Helper Methods

- (NSString *)outputTypeToString:(CSOutputType)outputType {
    switch (outputType) {
        case CSOutputTypeString: return @"string";
        case CSOutputTypeInteger: return @"integer";
        case CSOutputTypeNumber: return @"number";
        case CSOutputTypeBoolean: return @"boolean";
        case CSOutputTypeArray: return @"array";
        case CSOutputTypeObject: return @"object";
        case CSOutputTypeBinary: return @"binary";
    }
}

@end
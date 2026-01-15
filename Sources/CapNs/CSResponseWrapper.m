//
//  CSResponseWrapper.m
//  Response wrapper for unified plugin output handling with validation
//
//  NOTE: Validation now uses mediaSpec -> spec ID resolution.
//

#import "include/CSResponseWrapper.h"
#import "include/CSMediaSpec.h"

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
    CSCapOutput *output = [cap getOutput];
    if (!output || !output.mediaSpec) {
        // No output definition, validation passes
        return YES;
    }

    // Resolve the mediaSpec to determine expected type
    NSError *resolveError = nil;
    CSMediaSpec *mediaSpec = CSResolveMediaUrn(output.mediaSpec, cap.mediaSpecs, &resolveError);
    if (!mediaSpec) {
        // FAIL HARD on unresolvable spec ID
        if (error) {
            NSString *message = [NSString stringWithFormat:@"Cannot resolve spec ID '%@' for output: %@",
                               output.mediaSpec, resolveError.localizedDescription];
            *error = [NSError errorWithDomain:@"CSResponseWrapper"
                                         code:1004
                                     userInfo:@{NSLocalizedDescriptionKey: message}];
        }
        return NO;
    }

    // For binary outputs, check type compatibility
    if (self.contentType == CSResponseContentTypeBinary) {
        if (![mediaSpec isBinary]) {
            if (error) {
                NSString *message = [NSString stringWithFormat:@"Cap %@ expects %@ output but received binary data",
                                   [cap urnString], output.mediaSpec];
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

        // If the media spec has a schema, validate against it
        if (mediaSpec.schema) {
            // Schema validation would go here
            // For now, skip detailed schema validation
        }
    }

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

/// Checks if the response matches the expected output type based on the cap's output spec.
/// Returns error if the output spec cannot be resolved - no fallbacks.
- (BOOL)matchesOutputTypeForCap:(CSCap *)cap error:(NSError **)error {
    CSCapOutput *outputDef = [cap getOutput];
    if (!outputDef || !outputDef.mediaSpec) {
        if (error) {
            NSString *message = [NSString stringWithFormat:@"Cap '%@' has no output definition", [cap urnString]];
            *error = [NSError errorWithDomain:@"CSResponseWrapper"
                                         code:1005
                                     userInfo:@{NSLocalizedDescriptionKey: message}];
        }
        return NO;
    }

    // Resolve the mediaSpec - fail hard if resolution fails
    NSError *resolveError = nil;
    CSMediaSpec *mediaSpec = CSResolveMediaUrn(outputDef.mediaSpec, cap.mediaSpecs, &resolveError);
    if (!mediaSpec) {
        if (error) {
            NSString *message = [NSString stringWithFormat:@"Failed to resolve output spec ID '%@' for cap '%@': %@",
                               outputDef.mediaSpec, [cap urnString], resolveError.localizedDescription];
            *error = [NSError errorWithDomain:@"CSResponseWrapper"
                                         code:1006
                                     userInfo:@{NSLocalizedDescriptionKey: message}];
        }
        return NO;
    }

    switch (self.contentType) {
        case CSResponseContentTypeJson:
            return [mediaSpec isJSON];

        case CSResponseContentTypeText:
            return [mediaSpec isText];

        case CSResponseContentTypeBinary:
            return [mediaSpec isBinary];
    }
}

@end

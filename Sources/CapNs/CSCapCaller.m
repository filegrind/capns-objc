//
//  CSCapCaller.m
//  Pure cap-based execution with strict input validation
//
//  NOTE: Type validation now uses mediaSpec -> spec ID resolution.
//

#import "include/CSCapCaller.h"
#import "include/CSMediaSpec.h"
#import "include/CSStdinSource.h"

@interface CSCapCaller ()
@property (nonatomic, strong) NSString *cap;
@property (nonatomic, strong) id<CSCapSet> capSet;
@property (nonatomic, strong) CSCap *capDefinition;
@end

@implementation CSCapCaller

+ (instancetype)callerWithCap:(NSString *)cap
                      capSet:(id<CSCapSet>)capSet
                capDefinition:(CSCap *)capDefinition {
    CSCapCaller *caller = [[CSCapCaller alloc] init];
    caller.cap = cap;
    caller.capSet = capSet;
    caller.capDefinition = capDefinition;
    return caller;
}

- (void)callWithPositionalArgs:(NSArray *)positionalArgs
                     namedArgs:(NSArray *)namedArgs
                   stdinSource:(CSStdinSource * _Nullable)stdinSource
                    completion:(void (^)(CSResponseWrapper * _Nullable response, NSError * _Nullable error))completion {

    // Validate inputs against cap definition
    NSError *validationError = nil;
    if (![self validateInputs:positionalArgs namedArgs:namedArgs error:&validationError]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(nil, validationError);
        });
        return;
    }

    // Execute via cap host
    [self.capSet executeCap:self.cap
              positionalArgs:positionalArgs
                   namedArgs:namedArgs
                 stdinSource:stdinSource
                  completion:^(CSResponseWrapper * _Nullable response, NSError * _Nullable error) {

        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, error);
            });
            return;
        }

        if (!response) {
            NSError *noOutputError = [NSError errorWithDomain:@"CSCapCaller"
                                                          code:1001
                                                      userInfo:@{NSLocalizedDescriptionKey: @"Cap returned no output"}];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, noOutputError);
            });
            return;
        }

        // Validate output against cap definition
        NSError *outputValidationError = nil;
        if (![self validateOutput:response error:&outputValidationError]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, outputValidationError);
            });
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            completion(response, nil);
        });
    }];
}

#pragma mark - Validation

- (BOOL)validateInputs:(NSArray *)positionalArgs
             namedArgs:(NSArray *)namedArgs
                 error:(NSError * _Nullable * _Nullable)error {

    NSArray<CSCapArg *> *requiredArgs = [self.capDefinition getRequiredArgs];

    // Check if we have enough positional arguments for required arguments
    if (positionalArgs.count < requiredArgs.count) {
        if (error) {
            NSString *message = [NSString stringWithFormat:@"Cap '%@' expects at least %lu arguments but received %lu",
                               self.cap, (unsigned long)requiredArgs.count, (unsigned long)positionalArgs.count];
            *error = [NSError errorWithDomain:@"CSCapCaller"
                                         code:1002
                                     userInfo:@{NSLocalizedDescriptionKey: message}];
        }
        return NO;
    }

    // Validate each positional argument
    for (NSUInteger i = 0; i < positionalArgs.count && i < requiredArgs.count; i++) {
        CSCapArg *argDef = requiredArgs[i];
        id value = positionalArgs[i];

        if (![self validateArgumentValue:value againstDefinition:argDef error:error]) {
            return NO;
        }
    }

    return YES;
}

- (BOOL)validateArgumentValue:(id)value
            againstDefinition:(CSCapArg *)argDef
                        error:(NSError * _Nullable * _Nullable)error {

    // Resolve the mediaUrn to determine expected type
    NSString *specId = argDef.mediaUrn;
    if (!specId) {
        // No mediaSpec, skip type validation
        return YES;
    }

    NSError *resolveError = nil;
    CSMediaSpec *mediaSpec = CSResolveMediaUrn(specId, self.capDefinition.mediaSpecs, &resolveError);
    if (!mediaSpec) {
        // FAIL HARD on unresolvable spec ID
        if (error) {
            NSString *message = [NSString stringWithFormat:@"Cannot resolve spec ID '%@' for argument '%@': %@",
                               specId, argDef.mediaUrn, resolveError.localizedDescription];
            *error = [NSError errorWithDomain:@"CSCapCaller"
                                         code:1010
                                     userInfo:@{NSLocalizedDescriptionKey: message}];
        }
        return NO;
    }

    // Determine expected type from profile
    NSString *profile = mediaSpec.profile;
    if (!profile) {
        // No profile, skip type validation
        return YES;
    }

    // Validate based on profile URL
    if ([profile containsString:@"/schema/str"]) {
        if (![value isKindOfClass:[NSString class]]) {
            if (error) {
                NSString *message = [NSString stringWithFormat:@"Argument '%@' expects string but received %@",
                                   argDef.mediaUrn, NSStringFromClass([value class])];
                *error = [NSError errorWithDomain:@"CSCapCaller"
                                             code:1003
                                         userInfo:@{NSLocalizedDescriptionKey: message}];
            }
            return NO;
        }
    } else if ([profile containsString:@"/schema/int"]) {
        if (![value isKindOfClass:[NSNumber class]] || ![self isInteger:(NSNumber *)value]) {
            if (error) {
                NSString *message = [NSString stringWithFormat:@"Argument '%@' expects integer but received %@",
                                   argDef.mediaUrn, NSStringFromClass([value class])];
                *error = [NSError errorWithDomain:@"CSCapCaller"
                                             code:1004
                                         userInfo:@{NSLocalizedDescriptionKey: message}];
            }
            return NO;
        }
    } else if ([profile containsString:@"/schema/num"]) {
        if (![value isKindOfClass:[NSNumber class]]) {
            if (error) {
                NSString *message = [NSString stringWithFormat:@"Argument '%@' expects number but received %@",
                                   argDef.mediaUrn, NSStringFromClass([value class])];
                *error = [NSError errorWithDomain:@"CSCapCaller"
                                             code:1005
                                         userInfo:@{NSLocalizedDescriptionKey: message}];
            }
            return NO;
        }
    } else if ([profile containsString:@"/schema/bool"]) {
        if (![value isKindOfClass:[NSNumber class]]) {
            if (error) {
                NSString *message = [NSString stringWithFormat:@"Argument '%@' expects boolean but received %@",
                                   argDef.mediaUrn, NSStringFromClass([value class])];
                *error = [NSError errorWithDomain:@"CSCapCaller"
                                             code:1006
                                         userInfo:@{NSLocalizedDescriptionKey: message}];
            }
            return NO;
        }
    } else if ([profile containsString:@"/schema/obj"]) {
        // Check for obj-array first
        if ([profile containsString:@"-array"]) {
            if (![value isKindOfClass:[NSArray class]]) {
                if (error) {
                    NSString *message = [NSString stringWithFormat:@"Argument '%@' expects array but received %@",
                                       argDef.mediaUrn, NSStringFromClass([value class])];
                    *error = [NSError errorWithDomain:@"CSCapCaller"
                                                 code:1007
                                             userInfo:@{NSLocalizedDescriptionKey: message}];
                }
                return NO;
            }
        } else {
            if (![value isKindOfClass:[NSDictionary class]]) {
                if (error) {
                    NSString *message = [NSString stringWithFormat:@"Argument '%@' expects object but received %@",
                                       argDef.mediaUrn, NSStringFromClass([value class])];
                    *error = [NSError errorWithDomain:@"CSCapCaller"
                                                 code:1008
                                             userInfo:@{NSLocalizedDescriptionKey: message}];
                }
                return NO;
            }
        }
    } else if ([profile containsString:@"-array"]) {
        // Any array type
        if (![value isKindOfClass:[NSArray class]]) {
            if (error) {
                NSString *message = [NSString stringWithFormat:@"Argument '%@' expects array but received %@",
                                   argDef.mediaUrn, NSStringFromClass([value class])];
                *error = [NSError errorWithDomain:@"CSCapCaller"
                                             code:1007
                                         userInfo:@{NSLocalizedDescriptionKey: message}];
            }
            return NO;
        }
    }

    // Check for binary based on media type
    if ([mediaSpec isBinary]) {
        if (![value isKindOfClass:[NSData class]] && ![value isKindOfClass:[NSString class]]) {
            if (error) {
                NSString *message = [NSString stringWithFormat:@"Argument '%@' expects binary data but received %@",
                                   argDef.mediaUrn, NSStringFromClass([value class])];
                *error = [NSError errorWithDomain:@"CSCapCaller"
                                             code:1009
                                         userInfo:@{NSLocalizedDescriptionKey: message}];
            }
            return NO;
        }
    }

    return YES;
}

- (BOOL)validateOutput:(CSResponseWrapper *)response
                 error:(NSError * _Nullable * _Nullable)error {

    return [response validateAgainstCap:self.capDefinition error:error];
}

#pragma mark - Helper Methods

- (BOOL)isInteger:(NSNumber *)number {
    return strcmp([number objCType], @encode(int)) == 0 ||
           strcmp([number objCType], @encode(long)) == 0 ||
           strcmp([number objCType], @encode(long long)) == 0;
}

/// Resolves the output spec from the cap URN's 'out' tag.
/// Fails hard if the cap URN has no 'out' tag or the spec ID cannot be resolved.
- (nullable CSMediaSpec *)resolveOutputSpecWithError:(NSError **)error {
    CSCapUrn *capUrn = self.capDefinition.capUrn;

    // Get the 'out' tag which contains the spec ID
    NSString *specId = [capUrn getTag:@"out"];
    if (!specId) {
        if (error) {
            NSString *message = [NSString stringWithFormat:@"Cap URN '%@' is missing required 'out' tag - caps must declare their output type", self.cap];
            *error = [NSError errorWithDomain:@"CSCapCaller"
                                         code:1011
                                     userInfo:@{NSLocalizedDescriptionKey: message}];
        }
        return nil;
    }

    // Resolve the spec ID - fail hard if resolution fails
    NSError *resolveError = nil;
    CSMediaSpec *mediaSpec = CSResolveMediaUrn(specId, self.capDefinition.mediaSpecs, &resolveError);
    if (!mediaSpec) {
        if (error) {
            NSString *message = [NSString stringWithFormat:@"Failed to resolve output spec ID '%@' for cap '%@': %@ - check that media_specs contains this spec ID or it is a built-in",
                               specId, self.cap, resolveError.localizedDescription];
            *error = [NSError errorWithDomain:@"CSCapCaller"
                                         code:1012
                                     userInfo:@{NSLocalizedDescriptionKey: message}];
        }
        return nil;
    }

    return mediaSpec;
}

/// Checks if this cap produces binary output based on media_spec.
/// Returns error if the spec ID cannot be resolved - no fallbacks.
- (BOOL)isBinaryCapWithError:(NSError **)error {
    CSMediaSpec *mediaSpec = [self resolveOutputSpecWithError:error];
    if (!mediaSpec) {
        return NO;
    }
    return [mediaSpec isBinary];
}

/// Checks if this cap produces JSON output based on media_spec.
/// Returns error if the spec ID cannot be resolved - no fallbacks.
- (BOOL)isJsonCapWithError:(NSError **)error {
    CSMediaSpec *mediaSpec = [self resolveOutputSpecWithError:error];
    if (!mediaSpec) {
        return NO;
    }
    return [mediaSpec isJSON];
}

@end

//
//  CSCapCaller.m
//  Pure cap-based execution with strict input validation
//

#import "include/CSCapCaller.h"

@interface CSCapCaller ()
@property (nonatomic, strong) NSString *cap;
@property (nonatomic, strong) id<CSCapHost> capHost;
@property (nonatomic, strong) CSCap *capDefinition;
@end

@implementation CSCapCaller

+ (instancetype)callerWithCap:(NSString *)cap
                      capHost:(id<CSCapHost>)capHost
                capDefinition:(CSCap *)capDefinition {
    CSCapCaller *caller = [[CSCapCaller alloc] init];
    caller.cap = cap;
    caller.capHost = capHost;
    caller.capDefinition = capDefinition;
    return caller;
}

- (void)callWithPositionalArgs:(NSArray *)positionalArgs
                     namedArgs:(NSArray *)namedArgs
                     stdinData:(NSData * _Nullable)stdinData
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
    [self.capHost executeCap:self.cap
              positionalArgs:positionalArgs
                   namedArgs:namedArgs
                   stdinData:stdinData
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
    
    // For now, we'll validate positional args since that's what most caps use
    // Named args validation can be added later when we have caps that use them
    
    CSCapArguments *arguments = [self.capDefinition getArguments];
    NSArray<CSCapArgument *> *requiredArgs = arguments.required;
    
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
        CSCapArgument *argDef = requiredArgs[i];
        id value = positionalArgs[i];
        
        if (![self validateArgumentValue:value againstDefinition:argDef error:error]) {
            return NO;
        }
    }
    
    return YES;
}

- (BOOL)validateArgumentValue:(id)value
            againstDefinition:(CSCapArgument *)argDef
                        error:(NSError * _Nullable * _Nullable)error {
    
    // Basic type checking
    switch (argDef.argType) {
        case CSArgumentTypeString:
            if (![value isKindOfClass:[NSString class]]) {
                if (error) {
                    NSString *message = [NSString stringWithFormat:@"Argument '%@' expects string but received %@",
                                       argDef.name, NSStringFromClass([value class])];
                    *error = [NSError errorWithDomain:@"CSCapCaller"
                                                 code:1003
                                             userInfo:@{NSLocalizedDescriptionKey: message}];
                }
                return NO;
            }
            break;
            
        case CSArgumentTypeInteger:
            if (![value isKindOfClass:[NSNumber class]] || ![self isInteger:(NSNumber *)value]) {
                if (error) {
                    NSString *message = [NSString stringWithFormat:@"Argument '%@' expects integer but received %@",
                                       argDef.name, NSStringFromClass([value class])];
                    *error = [NSError errorWithDomain:@"CSCapCaller"
                                                 code:1004
                                             userInfo:@{NSLocalizedDescriptionKey: message}];
                }
                return NO;
            }
            break;
            
        case CSArgumentTypeNumber:
            if (![value isKindOfClass:[NSNumber class]]) {
                if (error) {
                    NSString *message = [NSString stringWithFormat:@"Argument '%@' expects number but received %@",
                                       argDef.name, NSStringFromClass([value class])];
                    *error = [NSError errorWithDomain:@"CSCapCaller"
                                                 code:1005
                                             userInfo:@{NSLocalizedDescriptionKey: message}];
                }
                return NO;
            }
            break;
            
        case CSArgumentTypeBoolean:
            if (![value isKindOfClass:[NSNumber class]]) {
                if (error) {
                    NSString *message = [NSString stringWithFormat:@"Argument '%@' expects boolean but received %@",
                                       argDef.name, NSStringFromClass([value class])];
                    *error = [NSError errorWithDomain:@"CSCapCaller"
                                                 code:1006
                                             userInfo:@{NSLocalizedDescriptionKey: message}];
                }
                return NO;
            }
            break;
            
        case CSArgumentTypeArray:
            if (![value isKindOfClass:[NSArray class]]) {
                if (error) {
                    NSString *message = [NSString stringWithFormat:@"Argument '%@' expects array but received %@",
                                       argDef.name, NSStringFromClass([value class])];
                    *error = [NSError errorWithDomain:@"CSCapCaller"
                                                 code:1007
                                             userInfo:@{NSLocalizedDescriptionKey: message}];
                }
                return NO;
            }
            break;
            
        case CSArgumentTypeObject:
            if (![value isKindOfClass:[NSDictionary class]]) {
                if (error) {
                    NSString *message = [NSString stringWithFormat:@"Argument '%@' expects object but received %@",
                                       argDef.name, NSStringFromClass([value class])];
                    *error = [NSError errorWithDomain:@"CSCapCaller"
                                                 code:1008
                                             userInfo:@{NSLocalizedDescriptionKey: message}];
                }
                return NO;
            }
            break;
            
        case CSArgumentTypeBinary:
            if (![value isKindOfClass:[NSData class]]) {
                if (error) {
                    NSString *message = [NSString stringWithFormat:@"Argument '%@' expects binary data but received %@",
                                       argDef.name, NSStringFromClass([value class])];
                    *error = [NSError errorWithDomain:@"CSCapCaller"
                                                 code:1009
                                             userInfo:@{NSLocalizedDescriptionKey: message}];
                }
                return NO;
            }
            break;
    }
    
    // TODO: Add validation rules checking (min/max, length, pattern, etc.)
    // This would involve checking argDef.validation and applying the rules
    
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

- (BOOL)isJsonCap {
    CSCapUrn *capUrn = self.capDefinition.capUrn;
    NSString *output = [capUrn getTag:@"output"];
    return output && (![output isEqualToString:@"binary"]);
}

@end
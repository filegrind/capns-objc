//
//  CSCapCaller.h
//  Pure cap-based execution with strict input validation
//
//  Cap caller that executes via XPC service with strict validation
//

#import <Foundation/Foundation.h>
#import "CSCap.h"
#import "CSResponseWrapper.h"

NS_ASSUME_NONNULL_BEGIN

@protocol CSCapSet <NSObject>

/**
 * Execute a capability with arguments and optional stdin data
 * @param cap The capability URN string
 * @param positionalArgs Array of positional arguments
 * @param namedArgs Array of named arguments
 * @param stdinData Optional stdin data
 * @param completion Completion handler with response or error
 */
- (void)executeCap:(NSString *)cap
    positionalArgs:(NSArray *)positionalArgs
         namedArgs:(NSArray *)namedArgs
         stdinData:(NSData * _Nullable)stdinData
        completion:(void (^)(CSResponseWrapper * _Nullable response, NSError * _Nullable error))completion;

@end

/**
 * Cap caller that executes via XPC service with strict validation
 */
@interface CSCapCaller : NSObject

@property (nonatomic, readonly) NSString *cap;
@property (nonatomic, readonly) id<CSCapSet> capSet;
@property (nonatomic, readonly) CSCap *capDefinition;

/**
 * Create a new cap caller with validation
 * @param cap The capability URN string
 * @param capSet The cap host for execution
 * @param capDefinition The capability definition for validation
 * @return A new CSCapCaller instance
 */
+ (instancetype)callerWithCap:(NSString *)cap
                      capSet:(id<CSCapSet>)capSet
                capDefinition:(CSCap *)capDefinition;

/**
 * Call the cap with structured arguments and optional stdin data
 * Validates inputs against cap definition before execution
 * @param positionalArgs Array of positional arguments
 * @param namedArgs Array of named arguments  
 * @param stdinData Optional stdin data
 * @param completion Completion handler with validated response or error
 */
- (void)callWithPositionalArgs:(NSArray *)positionalArgs
                     namedArgs:(NSArray *)namedArgs
                     stdinData:(NSData * _Nullable)stdinData
                    completion:(void (^)(CSResponseWrapper * _Nullable response, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
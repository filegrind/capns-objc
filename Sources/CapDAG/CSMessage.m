//
//  CSMessage.m
//  Message Envelope Types for Plugin Communication
//

#import "CSMessage.h"

/// Error domain for message operations
NSString * const CSMessageErrorDomain = @"CSMessageErrorDomain";

#pragma mark - CSMessage

@implementation CSMessage {
    NSString *_messageId;
    CSMessageType _messageType;
    NSString *_cap;
    NSDictionary *_payload;
}

- (instancetype)initWithId:(NSString *)messageId
               messageType:(CSMessageType)messageType
                       cap:(nullable NSString *)cap
                   payload:(NSDictionary *)payload {
    self = [super init];
    if (self) {
        _messageId = [messageId copy];
        _messageType = messageType;
        _cap = [cap copy];
        _payload = [payload copy] ?: @{};
    }
    return self;
}

#pragma mark - Properties

- (NSString *)messageId {
    return _messageId;
}

- (CSMessageType)messageType {
    return _messageType;
}

- (nullable NSString *)cap {
    return _cap;
}

- (NSDictionary *)payload {
    return _payload;
}

#pragma mark - Factory Methods

+ (instancetype)capRequestWithUrn:(NSString *)capUrn payload:(NSDictionary *)payload {
    NSString *messageId = [[NSUUID UUID] UUIDString];
    return [[CSMessage alloc] initWithId:messageId
                             messageType:CSMessageTypeCapRequest
                                     cap:capUrn
                                 payload:payload];
}

+ (instancetype)capRequestWithId:(NSString *)messageId capUrn:(NSString *)capUrn payload:(NSDictionary *)payload {
    return [[CSMessage alloc] initWithId:messageId
                             messageType:CSMessageTypeCapRequest
                                     cap:capUrn
                                 payload:payload];
}

+ (instancetype)capResponseWithRequestId:(NSString *)requestId payload:(NSDictionary *)payload {
    return [[CSMessage alloc] initWithId:requestId
                             messageType:CSMessageTypeCapResponse
                                     cap:nil
                                 payload:payload];
}

+ (instancetype)streamChunkWithRequestId:(NSString *)requestId payload:(NSDictionary *)payload {
    return [[CSMessage alloc] initWithId:requestId
                             messageType:CSMessageTypeStreamChunk
                                     cap:nil
                                 payload:payload];
}

+ (instancetype)streamEndWithRequestId:(NSString *)requestId payload:(NSDictionary *)payload {
    return [[CSMessage alloc] initWithId:requestId
                             messageType:CSMessageTypeStreamEnd
                                     cap:nil
                                 payload:payload];
}

+ (instancetype)errorWithRequestId:(NSString *)requestId code:(NSString *)code message:(NSString *)message {
    NSDictionary *payload = @{
        @"code": code ?: @"UNKNOWN",
        @"message": message ?: @"Unknown error"
    };
    return [[CSMessage alloc] initWithId:requestId
                             messageType:CSMessageTypeError
                                     cap:nil
                                 payload:payload];
}

+ (instancetype)ackWithRequestId:(NSString *)requestId {
    return [[CSMessage alloc] initWithId:requestId
                             messageType:CSMessageTypeAck
                                     cap:nil
                                 payload:@{}];
}

+ (instancetype)progressWithRequestId:(NSString *)requestId
                                stage:(NSString *)stage
                              percent:(nullable NSNumber *)percent
                              message:(nullable NSString *)message {
    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    payload[@"stage"] = stage ?: @"processing";
    if (percent) {
        payload[@"percent"] = percent;
    }
    if (message) {
        payload[@"message"] = message;
    }
    return [[CSMessage alloc] initWithId:requestId
                             messageType:CSMessageTypeProgress
                                     cap:nil
                                 payload:[payload copy]];
}

+ (instancetype)idle {
    return [[CSMessage alloc] initWithId:@""
                             messageType:CSMessageTypeIdle
                                     cap:nil
                                 payload:@{}];
}

#pragma mark - Serialization

- (nullable NSData *)toDataWithError:(NSError * _Nullable * _Nullable)error {
    NSDictionary *dictionary = [self toDictionary];
    return [NSJSONSerialization dataWithJSONObject:dictionary options:0 error:error];
}

- (NSDictionary *)toDictionary {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"id"] = _messageId;
    dict[@"type"] = [self messageTypeString];
    if (_cap) {
        dict[@"cap"] = _cap;
    }
    dict[@"payload"] = _payload ?: @{};
    return [dict copy];
}

+ (nullable instancetype)messageFromData:(NSData *)data error:(NSError * _Nullable * _Nullable)error {
    NSDictionary *dictionary = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (!dictionary) {
        return nil;
    }
    return [self messageFromDictionary:dictionary error:error];
}

+ (nullable instancetype)messageFromDictionary:(NSDictionary *)dictionary error:(NSError * _Nullable * _Nullable)error {
    // Validate required fields
    NSString *messageId = dictionary[@"id"];
    if (!messageId || ![messageId isKindOfClass:[NSString class]]) {
        if (error) {
            *error = [NSError errorWithDomain:CSMessageErrorDomain
                                         code:CSMessageErrorCodeMissingField
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing required field: id"}];
        }
        return nil;
    }

    NSString *typeString = dictionary[@"type"];
    if (!typeString || ![typeString isKindOfClass:[NSString class]]) {
        if (error) {
            *error = [NSError errorWithDomain:CSMessageErrorDomain
                                         code:CSMessageErrorCodeMissingField
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing required field: type"}];
        }
        return nil;
    }

    CSMessageType messageType = [self messageTypeFromString:typeString];

    NSString *cap = dictionary[@"cap"];
    if (cap && ![cap isKindOfClass:[NSString class]]) {
        cap = nil;
    }

    NSDictionary *payload = dictionary[@"payload"];
    if (!payload || ![payload isKindOfClass:[NSDictionary class]]) {
        payload = @{};
    }

    return [[CSMessage alloc] initWithId:messageId
                             messageType:messageType
                                     cap:cap
                                 payload:payload];
}

#pragma mark - Type Checking

- (BOOL)isRequest {
    return _messageType == CSMessageTypeCapRequest;
}

- (BOOL)isResponse {
    return _messageType == CSMessageTypeAck ||
           _messageType == CSMessageTypeProgress ||
           _messageType == CSMessageTypeCapResponse ||
           _messageType == CSMessageTypeStreamChunk ||
           _messageType == CSMessageTypeStreamEnd ||
           _messageType == CSMessageTypeIdle;
}

- (BOOL)isError {
    return _messageType == CSMessageTypeError;
}

- (BOOL)isStreaming {
    return _messageType == CSMessageTypeStreamChunk ||
           _messageType == CSMessageTypeStreamEnd;
}

- (BOOL)isStreamEnd {
    return _messageType == CSMessageTypeStreamEnd;
}

- (BOOL)isAck {
    return _messageType == CSMessageTypeAck;
}

- (BOOL)isProgress {
    return _messageType == CSMessageTypeProgress;
}

- (BOOL)isIdle {
    return _messageType == CSMessageTypeIdle;
}

#pragma mark - Convenience

- (NSString *)messageTypeString {
    switch (_messageType) {
        case CSMessageTypeCapRequest:
            return @"cap_request";
        case CSMessageTypeAck:
            return @"ack";
        case CSMessageTypeProgress:
            return @"progress";
        case CSMessageTypeCapResponse:
            return @"cap_response";
        case CSMessageTypeStreamChunk:
            return @"stream_chunk";
        case CSMessageTypeStreamEnd:
            return @"stream_end";
        case CSMessageTypeIdle:
            return @"idle";
        case CSMessageTypeError:
            return @"error";
    }
    return @"error";
}

+ (CSMessageType)messageTypeFromString:(NSString *)typeString {
    static NSDictionary<NSString *, NSNumber *> *typeMap = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        typeMap = @{
            @"cap_request": @(CSMessageTypeCapRequest),
            @"ack": @(CSMessageTypeAck),
            @"progress": @(CSMessageTypeProgress),
            @"cap_response": @(CSMessageTypeCapResponse),
            @"stream_chunk": @(CSMessageTypeStreamChunk),
            @"stream_end": @(CSMessageTypeStreamEnd),
            @"idle": @(CSMessageTypeIdle),
            @"error": @(CSMessageTypeError),
        };
    });

    NSNumber *value = typeMap[typeString];
    if (value) {
        return (CSMessageType)value.integerValue;
    }
    return CSMessageTypeError;
}

#pragma mark - NSCopying

- (id)copyWithZone:(nullable NSZone *)zone {
    return [[CSMessage alloc] initWithId:_messageId
                             messageType:_messageType
                                     cap:_cap
                                 payload:_payload];
}

@end

#pragma mark - CSErrorPayload

@implementation CSErrorPayload {
    NSString *_code;
    NSString *_message;
    NSDictionary *_details;
}

- (instancetype)initWithCode:(NSString *)code message:(NSString *)message details:(nullable NSDictionary *)details {
    self = [super init];
    if (self) {
        _code = [code copy];
        _message = [message copy];
        _details = [details copy];
    }
    return self;
}

- (NSString *)code {
    return _code;
}

- (NSString *)message {
    return _message;
}

- (nullable NSDictionary *)details {
    return _details;
}

+ (instancetype)errorWithCode:(NSString *)code message:(NSString *)message {
    return [[CSErrorPayload alloc] initWithCode:code message:message details:nil];
}

+ (instancetype)errorWithCode:(NSString *)code message:(NSString *)message details:(nullable NSDictionary *)details {
    return [[CSErrorPayload alloc] initWithCode:code message:message details:details];
}

- (NSDictionary *)toDictionary {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"code"] = _code;
    dict[@"message"] = _message;
    if (_details) {
        dict[@"details"] = _details;
    }
    return [dict copy];
}

@end

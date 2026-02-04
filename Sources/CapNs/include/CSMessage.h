//
//  CSMessage.h
//  Message Envelope Types for Plugin Communication
//
//  Messages are JSON envelopes that travel inside binary packets.
//  They provide routing (cap URN), correlation (request ID), and typing.
//
//  Message flow:
//  Host → Plugin:  CapRequest  (invoke a cap)
//  Plugin → Host:  CapResponse (single response) or StreamChunk (streaming)
//  Either → Either: Error (error condition)
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Message types for the envelope
typedef NS_ENUM(NSInteger, CSMessageType) {
    /// Request to invoke a cap (host → plugin)
    CSMessageTypeCapRequest,
    /// Acknowledge request received, processing started (plugin → host)
    CSMessageTypeAck,
    /// Progress update during processing (plugin → host)
    CSMessageTypeProgress,
    /// Single complete response (plugin → host)
    CSMessageTypeCapResponse,
    /// Streaming chunk (plugin → host)
    CSMessageTypeStreamChunk,
    /// Stream complete marker (plugin → host)
    CSMessageTypeStreamEnd,
    /// Plugin is idle, ready for next request (plugin → host)
    CSMessageTypeIdle,
    /// Error message (either direction)
    CSMessageTypeError,
};

/// Error domain for message operations
extern NSString * const CSMessageErrorDomain;

/// Message error codes
typedef NS_ENUM(NSInteger, CSMessageErrorCode) {
    CSMessageErrorCodeJSONError = 1,
    CSMessageErrorCodeMissingField = 2,
    CSMessageErrorCodeInvalidType = 3,
};

#pragma mark - CSMessage

/**
 * The message envelope that wraps all plugin communication.
 * This is serialized as JSON inside binary packets.
 */
@interface CSMessage : NSObject <NSCopying>

/// Unique message ID for correlation
@property (nonatomic, readonly) NSString *messageId;

/// Message type
@property (nonatomic, readonly) CSMessageType messageType;

/// Cap URN being invoked (for requests) or responded to (for responses)
@property (nonatomic, readonly, nullable) NSString *cap;

/// The actual payload data (request args, response data, etc.)
/// Interpretation depends on messageType and cap's media specs
@property (nonatomic, readonly) NSDictionary *payload;

#pragma mark - Factory Methods

/**
 * Create a new cap request message.
 * @param capUrn The cap URN to invoke
 * @param payload The request payload
 * @return A new CSMessage instance
 */
+ (instancetype)capRequestWithUrn:(NSString *)capUrn payload:(NSDictionary *)payload;

/**
 * Create a new cap request with a specific ID.
 * @param messageId The message ID for correlation
 * @param capUrn The cap URN to invoke
 * @param payload The request payload
 * @return A new CSMessage instance
 */
+ (instancetype)capRequestWithId:(NSString *)messageId capUrn:(NSString *)capUrn payload:(NSDictionary *)payload;

/**
 * Create a response message.
 * @param requestId The request ID this is responding to
 * @param payload The response payload
 * @return A new CSMessage instance
 */
+ (instancetype)capResponseWithRequestId:(NSString *)requestId payload:(NSDictionary *)payload;

/**
 * Create a streaming chunk message.
 * @param requestId The request ID this chunk belongs to
 * @param payload The chunk payload
 * @return A new CSMessage instance
 */
+ (instancetype)streamChunkWithRequestId:(NSString *)requestId payload:(NSDictionary *)payload;

/**
 * Create a stream end marker.
 * @param requestId The request ID this ends
 * @param payload The final payload
 * @return A new CSMessage instance
 */
+ (instancetype)streamEndWithRequestId:(NSString *)requestId payload:(NSDictionary *)payload;

/**
 * Create an error message.
 * @param requestId The request ID this error is for
 * @param code Error code
 * @param message Error message
 * @return A new CSMessage instance
 */
+ (instancetype)errorWithRequestId:(NSString *)requestId code:(NSString *)code message:(NSString *)message;

/**
 * Create an acknowledgment message.
 * @param requestId The request ID being acknowledged
 * @return A new CSMessage instance
 */
+ (instancetype)ackWithRequestId:(NSString *)requestId;

/**
 * Create a progress message.
 * @param requestId The request ID this progress is for
 * @param stage Current processing stage
 * @param percent Optional progress percentage (0-100)
 * @param message Optional progress message
 * @return A new CSMessage instance
 */
+ (instancetype)progressWithRequestId:(NSString *)requestId
                                stage:(NSString *)stage
                              percent:(nullable NSNumber *)percent
                              message:(nullable NSString *)message;

/**
 * Create an idle message (plugin ready for next request).
 * @return A new CSMessage instance
 */
+ (instancetype)idle;

#pragma mark - Serialization

/**
 * Serialize to JSON data (bytes).
 * @param error Error pointer for serialization errors
 * @return JSON data, or nil on error
 */
- (nullable NSData *)toDataWithError:(NSError * _Nullable * _Nullable)error;

/**
 * Serialize to JSON dictionary.
 * @return Dictionary representation of the message
 */
- (NSDictionary *)toDictionary;

/**
 * Deserialize from JSON data (bytes).
 * @param data JSON data
 * @param error Error pointer for parsing errors
 * @return A new CSMessage instance, or nil on error
 */
+ (nullable instancetype)messageFromData:(NSData *)data error:(NSError * _Nullable * _Nullable)error;

/**
 * Deserialize from JSON dictionary.
 * @param dictionary JSON dictionary
 * @param error Error pointer for parsing errors
 * @return A new CSMessage instance, or nil on error
 */
+ (nullable instancetype)messageFromDictionary:(NSDictionary *)dictionary error:(NSError * _Nullable * _Nullable)error;

#pragma mark - Type Checking

/**
 * Check if this is a request message.
 */
- (BOOL)isRequest;

/**
 * Check if this is a response message (complete or streaming).
 */
- (BOOL)isResponse;

/**
 * Check if this is an error message.
 */
- (BOOL)isError;

/**
 * Check if this is a streaming message.
 */
- (BOOL)isStreaming;

/**
 * Check if this is an acknowledgment message.
 */
- (BOOL)isAck;

/**
 * Check if this is a progress message.
 */
- (BOOL)isProgress;

/**
 * Check if this is an idle message.
 */
- (BOOL)isIdle;

/**
 * Check if this is a stream end marker.
 */
- (BOOL)isStreamEnd;

#pragma mark - Convenience

/**
 * Get the message type as a string (for JSON serialization).
 */
- (NSString *)messageTypeString;

/**
 * Get a message type from its string representation.
 * @param typeString The type string (e.g., "cap_request")
 * @return The message type, or CSMessageTypeError if unknown
 */
+ (CSMessageType)messageTypeFromString:(NSString *)typeString;

@end

#pragma mark - CSErrorPayload

/**
 * Helper struct for error payloads
 */
@interface CSErrorPayload : NSObject

@property (nonatomic, readonly) NSString *code;
@property (nonatomic, readonly) NSString *message;
@property (nonatomic, readonly, nullable) NSDictionary *details;

/**
 * Create an error payload.
 * @param code Error code
 * @param message Error message
 * @return A new CSErrorPayload instance
 */
+ (instancetype)errorWithCode:(NSString *)code message:(NSString *)message;

/**
 * Create an error payload with details.
 * @param code Error code
 * @param message Error message
 * @param details Additional details
 * @return A new CSErrorPayload instance
 */
+ (instancetype)errorWithCode:(NSString *)code message:(NSString *)message details:(nullable NSDictionary *)details;

/**
 * Convert to dictionary representation.
 * @return Dictionary representation of the error
 */
- (NSDictionary *)toDictionary;

@end

NS_ASSUME_NONNULL_END

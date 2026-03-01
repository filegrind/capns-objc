//
//  CSArgumentBinding.m
//  CapDAG
//
//  Argument Binding for Cap Execution
//  Mirrors Rust: src/planner/argument_binding.rs
//

#import "CSArgumentBinding.h"

// MARK: - CapFileMetadata

@implementation CSCapFileMetadata
@end

// MARK: - CapInputFile

@implementation CSCapInputFile

+ (instancetype)withFilePath:(NSString *)filePath mediaUrn:(NSString *)mediaUrn {
    CSCapInputFile *file = [[CSCapInputFile alloc] init];
    file.filePath = filePath;
    file.mediaUrn = mediaUrn;
    return file;
}

+ (instancetype)fromListingId:(NSString *)listingId filePath:(NSString *)filePath mediaUrn:(NSString *)mediaUrn {
    CSCapInputFile *file = [[CSCapInputFile alloc] init];
    file.filePath = filePath;
    file.mediaUrn = mediaUrn;
    file.sourceId = listingId;
    file.sourceType = CSSourceEntityTypeListing;
    return file;
}

+ (instancetype)fromChipId:(NSString *)chipId cachePath:(NSString *)cachePath mediaUrn:(NSString *)mediaUrn {
    CSCapInputFile *file = [[CSCapInputFile alloc] init];
    file.filePath = cachePath;
    file.mediaUrn = mediaUrn;
    file.sourceId = chipId;
    file.sourceType = CSSourceEntityTypeChip;
    return file;
}

+ (instancetype)fromCapOutput:(NSString *)outputPath mediaUrn:(NSString *)mediaUrn {
    CSCapInputFile *file = [[CSCapInputFile alloc] init];
    file.filePath = outputPath;
    file.mediaUrn = mediaUrn;
    file.sourceType = CSSourceEntityTypeCapOutput;
    return file;
}

- (instancetype)withMetadata:(CSCapFileMetadata *)metadata {
    self.metadata = metadata;
    return self;
}

- (instancetype)withFileReference:(NSString *)trackedFileId
                  securityBookmark:(NSData *)securityBookmark
                      originalPath:(NSString *)originalPath {
    self.trackedFileId = trackedFileId;
    self.securityBookmark = securityBookmark;
    self.originalPath = originalPath;
    return self;
}

- (nullable NSString *)filename {
    return [self.filePath lastPathComponent];
}

- (BOOL)hasFileReference {
    return self.trackedFileId != nil && self.securityBookmark != nil;
}

@end

// MARK: - ArgumentBinding

@interface CSArgumentBinding ()
@property (nonatomic, assign) NSInteger bindingType;
@property (nonatomic, assign) NSUInteger inputFileIndex;
@property (nonatomic, copy, nullable) NSString *nodeId;
@property (nonatomic, copy, nullable) NSString *outputField;
@property (nonatomic, copy, nullable) NSString *settingUrn;
@property (nonatomic, strong, nullable) id literalValue;
@property (nonatomic, copy, nullable) NSString *slotName;
@property (nonatomic, strong, nullable) NSDictionary *slotSchema;
@property (nonatomic, copy, nullable) NSString *metadataKey;
@end

typedef NS_ENUM(NSInteger, CSArgumentBindingType) {
    CSArgumentBindingTypeInputFileIndex,
    CSArgumentBindingTypeInputFilePath,
    CSArgumentBindingTypeInputMediaUrn,
    CSArgumentBindingTypePreviousOutput,
    CSArgumentBindingTypeCapDefault,
    CSArgumentBindingTypeCapSetting,
    CSArgumentBindingTypeLiteral,
    CSArgumentBindingTypeSlot,
    CSArgumentBindingTypePlanMetadata
};

@implementation CSArgumentBinding

+ (instancetype)inputFileAtIndex:(NSUInteger)index {
    CSArgumentBinding *binding = [[CSArgumentBinding alloc] init];
    binding.bindingType = CSArgumentBindingTypeInputFileIndex;
    binding.inputFileIndex = index;
    return binding;
}

+ (instancetype)inputFilePath {
    CSArgumentBinding *binding = [[CSArgumentBinding alloc] init];
    binding.bindingType = CSArgumentBindingTypeInputFilePath;
    return binding;
}

+ (instancetype)inputMediaUrn {
    CSArgumentBinding *binding = [[CSArgumentBinding alloc] init];
    binding.bindingType = CSArgumentBindingTypeInputMediaUrn;
    return binding;
}

+ (instancetype)previousOutputFromNode:(NSString *)nodeId outputField:(nullable NSString *)outputField {
    CSArgumentBinding *binding = [[CSArgumentBinding alloc] init];
    binding.bindingType = CSArgumentBindingTypePreviousOutput;
    binding.nodeId = nodeId;
    binding.outputField = outputField;
    return binding;
}

+ (instancetype)capDefault {
    CSArgumentBinding *binding = [[CSArgumentBinding alloc] init];
    binding.bindingType = CSArgumentBindingTypeCapDefault;
    return binding;
}

+ (instancetype)capSetting:(NSString *)settingUrn {
    CSArgumentBinding *binding = [[CSArgumentBinding alloc] init];
    binding.bindingType = CSArgumentBindingTypeCapSetting;
    binding.settingUrn = settingUrn;
    return binding;
}

+ (instancetype)literalString:(NSString *)value {
    CSArgumentBinding *binding = [[CSArgumentBinding alloc] init];
    binding.bindingType = CSArgumentBindingTypeLiteral;
    binding.literalValue = value;
    return binding;
}

+ (instancetype)literalNumber:(NSInteger)value {
    CSArgumentBinding *binding = [[CSArgumentBinding alloc] init];
    binding.bindingType = CSArgumentBindingTypeLiteral;
    binding.literalValue = @(value);
    return binding;
}

+ (instancetype)literalBool:(BOOL)value {
    CSArgumentBinding *binding = [[CSArgumentBinding alloc] init];
    binding.bindingType = CSArgumentBindingTypeLiteral;
    binding.literalValue = @(value);
    return binding;
}

+ (instancetype)literalJson:(id)value {
    CSArgumentBinding *binding = [[CSArgumentBinding alloc] init];
    binding.bindingType = CSArgumentBindingTypeLiteral;
    binding.literalValue = value;
    return binding;
}

+ (instancetype)slotNamed:(NSString *)name schema:(nullable NSDictionary *)schema {
    CSArgumentBinding *binding = [[CSArgumentBinding alloc] init];
    binding.bindingType = CSArgumentBindingTypeSlot;
    binding.slotName = name;
    binding.slotSchema = schema;
    return binding;
}

+ (instancetype)planMetadata:(NSString *)key {
    CSArgumentBinding *binding = [[CSArgumentBinding alloc] init];
    binding.bindingType = CSArgumentBindingTypePlanMetadata;
    binding.metadataKey = key;
    return binding;
}

- (BOOL)requiresInput {
    return self.bindingType == CSArgumentBindingTypeSlot;
}

- (BOOL)referencesPrevious {
    return self.bindingType == CSArgumentBindingTypePreviousOutput;
}

@end

// MARK: - ResolvedArgument

@implementation CSResolvedArgument

+ (instancetype)withName:(NSString *)name value:(NSData *)value source:(CSArgumentSource)source {
    CSResolvedArgument *arg = [[CSResolvedArgument alloc] init];
    arg.name = name;
    arg.value = value;
    arg.source = source;
    return arg;
}

@end

// MARK: - ArgumentResolutionContext

@implementation CSArgumentResolutionContext

+ (instancetype)withInputFiles:(NSArray<CSCapInputFile *> *)inputFiles {
    CSArgumentResolutionContext *ctx = [[CSArgumentResolutionContext alloc] init];
    ctx.inputFiles = inputFiles;
    ctx.currentFileIndex = 0;
    ctx.previousOutputs = @{};
    return ctx;
}

- (nullable CSCapInputFile *)currentFile {
    if (self.currentFileIndex < self.inputFiles.count) {
        return self.inputFiles[self.currentFileIndex];
    }
    return nil;
}

@end

// MARK: - Helper: JSON value to bytes

static NSData *JSONValueToBytes(id value) {
    if ([value isKindOfClass:[NSString class]]) {
        return [(NSString *)value dataUsingEncoding:NSUTF8StringEncoding];
    }

    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:value options:0 error:&error];
    if (error) {
        return [NSData data];
    }
    return data;
}

// MARK: - Resolve Binding

NSError *_Nullable CSResolveArgumentBinding(
    CSArgumentBinding *binding,
    CSArgumentResolutionContext *context,
    NSString *capUrn,
    id _Nullable defaultValue,
    BOOL isRequired,
    CSResolvedArgument *_Nullable *_Nullable outResolved
) {
    NSData *value = nil;
    CSArgumentSource source = CSArgumentSourceInputFile;

    switch (binding.bindingType) {
        case CSArgumentBindingTypeInputFileIndex: {
            if (binding.inputFileIndex >= context.inputFiles.count) {
                return [NSError errorWithDomain:@"CSPlannerError"
                                           code:1
                                       userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:
                                           @"Input file index %lu out of bounds (have %lu files)",
                                           (unsigned long)binding.inputFileIndex,
                                           (unsigned long)context.inputFiles.count]}];
            }
            CSCapInputFile *file = context.inputFiles[binding.inputFileIndex];
            value = [file.filePath dataUsingEncoding:NSUTF8StringEncoding];
            source = CSArgumentSourceInputFile;
            break;
        }

        case CSArgumentBindingTypeInputFilePath: {
            CSCapInputFile *file = [context currentFile];
            if (!file) {
                return [NSError errorWithDomain:@"CSPlannerError"
                                           code:1
                                       userInfo:@{NSLocalizedDescriptionKey: @"No current input file available"}];
            }
            value = [file.filePath dataUsingEncoding:NSUTF8StringEncoding];
            source = CSArgumentSourceInputFile;
            break;
        }

        case CSArgumentBindingTypeInputMediaUrn: {
            CSCapInputFile *file = [context currentFile];
            if (!file) {
                return [NSError errorWithDomain:@"CSPlannerError"
                                           code:1
                                       userInfo:@{NSLocalizedDescriptionKey: @"No current input file available"}];
            }
            value = [file.mediaUrn dataUsingEncoding:NSUTF8StringEncoding];
            source = CSArgumentSourceInputFile;
            break;
        }

        case CSArgumentBindingTypePreviousOutput: {
            id output = context.previousOutputs[binding.nodeId];
            if (!output) {
                return [NSError errorWithDomain:@"CSPlannerError"
                                           code:1
                                       userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:
                                           @"No output from node '%@'", binding.nodeId]}];
            }

            id jsonValue = output;
            if (binding.outputField) {
                if ([output isKindOfClass:[NSDictionary class]]) {
                    jsonValue = output[binding.outputField];
                    if (!jsonValue) {
                        return [NSError errorWithDomain:@"CSPlannerError"
                                                   code:1
                                               userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:
                                                   @"Field '%@' not found in output from node '%@'",
                                                   binding.outputField, binding.nodeId]}];
                    }
                } else {
                    return [NSError errorWithDomain:@"CSPlannerError"
                                               code:1
                                           userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:
                                               @"Cannot extract field '%@' from non-dictionary output",
                                               binding.outputField]}];
                }
            }

            value = JSONValueToBytes(jsonValue);
            source = CSArgumentSourcePreviousOutput;
            break;
        }

        case CSArgumentBindingTypeCapDefault: {
            if (!defaultValue) {
                return [NSError errorWithDomain:@"CSPlannerError"
                                           code:1
                                       userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:
                                           @"Cap '%@' has no default value for argument", capUrn]}];
            }
            value = JSONValueToBytes(defaultValue);
            source = CSArgumentSourceCapDefault;
            break;
        }

        case CSArgumentBindingTypeCapSetting: {
            if (!context.capSettings) {
                return [NSError errorWithDomain:@"CSPlannerError"
                                           code:1
                                       userInfo:@{NSLocalizedDescriptionKey: @"No cap settings available"}];
            }

            NSDictionary *settings = context.capSettings[capUrn];
            if (!settings) {
                return [NSError errorWithDomain:@"CSPlannerError"
                                           code:1
                                       userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:
                                           @"No settings for cap '%@'", capUrn]}];
            }

            id settingValue = settings[binding.settingUrn];
            if (!settingValue) {
                return [NSError errorWithDomain:@"CSPlannerError"
                                           code:1
                                       userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:
                                           @"Setting '%@' not found for cap '%@'",
                                           binding.settingUrn, capUrn]}];
            }

            value = JSONValueToBytes(settingValue);
            source = CSArgumentSourceCapSetting;
            break;
        }

        case CSArgumentBindingTypeLiteral: {
            value = JSONValueToBytes(binding.literalValue);
            source = CSArgumentSourceLiteral;
            break;
        }

        case CSArgumentBindingTypeSlot: {
            NSString *slotKey = [NSString stringWithFormat:@"%@:%@", capUrn, binding.slotName];

            // Check slot values first
            if (context.slotValues && context.slotValues[slotKey]) {
                value = context.slotValues[slotKey];
                source = CSArgumentSourceSlot;
                break;
            }

            // Check cap settings
            if (context.capSettings && context.capSettings[capUrn]) {
                id settingValue = context.capSettings[capUrn][binding.slotName];
                if (settingValue) {
                    value = JSONValueToBytes(settingValue);
                    source = CSArgumentSourceCapSetting;
                    break;
                }
            }

            // Check default
            if (defaultValue) {
                value = JSONValueToBytes(defaultValue);
                source = CSArgumentSourceCapDefault;
                break;
            }

            // Required but missing
            if (isRequired) {
                return [NSError errorWithDomain:@"CSPlannerError"
                                           code:1
                                       userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:
                                           @"Missing required argument '%@': no value in slot_values (key: %@), settings, or default",
                                           binding.slotName, slotKey]}];
            } else {
                // Optional and missing - return nil
                if (outResolved) {
                    *outResolved = nil;
                }
                return nil;
            }
        }

        case CSArgumentBindingTypePlanMetadata: {
            if (!context.planMetadata) {
                return [NSError errorWithDomain:@"CSPlannerError"
                                           code:1
                                       userInfo:@{NSLocalizedDescriptionKey: @"No plan metadata available"}];
            }

            id metadataValue = context.planMetadata[binding.metadataKey];
            if (!metadataValue) {
                return [NSError errorWithDomain:@"CSPlannerError"
                                           code:1
                                       userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:
                                           @"Key '%@' not found in plan metadata", binding.metadataKey]}];
            }

            value = JSONValueToBytes(metadataValue);
            source = CSArgumentSourcePlanMetadata;
            break;
        }
    }

    if (outResolved) {
        *outResolved = [CSResolvedArgument withName:@"" value:value source:source];
    }

    return nil;
}

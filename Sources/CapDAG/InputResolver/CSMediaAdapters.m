//
//  CSMediaAdapters.m
//  CapDAG
//
//  Media adapter implementations
//

#import "CSMediaAdapters.h"

#pragma mark - Helper Functions

/// Check if data starts with the given bytes
static BOOL _dataStartsWith(NSData *data, const uint8_t *bytes, NSUInteger length) {
    if (data.length < length) return NO;
    return memcmp(data.bytes, bytes, length) == 0;
}

/// Check if data contains the given bytes at offset
static BOOL _dataContainsAt(NSData *data, NSUInteger offset, const uint8_t *bytes, NSUInteger length) {
    if (data.length < offset + length) return NO;
    return memcmp((const uint8_t *)data.bytes + offset, bytes, length) == 0;
}

/// Convert data to UTF8 string (returns nil if not valid UTF8)
static NSString * _Nullable _dataToUTF8(NSData *data) {
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

/// Trim whitespace from string
static NSString *_trimWhitespace(NSString *str) {
    return [str stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

#pragma mark - CSBaseAdapter Implementation

@implementation CSBaseAdapter {
    NSString *_name;
}

- (instancetype)initWithName:(NSString *)name
                  extensions:(NSArray<NSString *> *)extensions
               magicPatterns:(NSArray<NSData *> *)magicPatterns
                mediaUrnBase:(NSString *)mediaUrnBase
          requiresInspection:(BOOL)requiresInspection
            defaultStructure:(CSContentStructure)defaultStructure {
    self = [super init];
    if (self) {
        _name = [name copy];
        _extensions = [extensions copy];
        _magicPatterns = [magicPatterns copy];
        _mediaUrnBase = [mediaUrnBase copy];
        _requiresInspection = requiresInspection;
        _defaultStructure = defaultStructure;
    }
    return self;
}

- (NSString *)name {
    return _name;
}

- (BOOL)matchesExtension:(NSString *)extension {
    NSString *ext = [extension lowercaseString];
    return [_extensions containsObject:ext];
}

- (BOOL)matchesMagicBytes:(NSData *)bytes {
    for (NSData *pattern in _magicPatterns) {
        if (_dataStartsWith(bytes, pattern.bytes, pattern.length)) {
            return YES;
        }
    }
    return NO;
}

- (nullable NSString *)detectMediaUrn:(NSString *)path
                              content:(NSData *)content
                            structure:(CSContentStructure *)structure
                                error:(NSError **)error {
    if (structure) {
        *structure = _defaultStructure;
    }
    return [self buildMediaUrnWithStructure:_defaultStructure];
}

- (NSString *)buildMediaUrnWithStructure:(CSContentStructure)structure {
    NSMutableString *urn = [NSMutableString stringWithString:_mediaUrnBase];

    // Add list marker if needed
    if (structure == CSContentStructureListOpaque || structure == CSContentStructureListRecord) {
        if (![urn containsString:@";list"]) {
            [urn appendString:@";list"];
        }
    }

    // Add record marker if needed
    if (structure == CSContentStructureScalarRecord || structure == CSContentStructureListRecord) {
        if (![urn containsString:@";record"]) {
            [urn appendString:@";record"];
        }
    }

    return urn;
}

@end

#pragma mark - Document Adapters

@implementation CSPdfAdapter

- (instancetype)init {
    uint8_t magic[] = {0x25, 0x50, 0x44, 0x46}; // %PDF
    return [super initWithName:@"pdf"
                    extensions:@[@"pdf"]
                 magicPatterns:@[[NSData dataWithBytes:magic length:4]]
                  mediaUrnBase:@"media:pdf"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

@end

@implementation CSEpubAdapter

- (instancetype)init {
    return [super initWithName:@"epub"
                    extensions:@[@"epub"]
                 magicPatterns:@[]
                  mediaUrnBase:@"media:epub"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

- (BOOL)matchesMagicBytes:(NSData *)bytes {
    // EPUB is a ZIP file starting with PK
    uint8_t pk[] = {0x50, 0x4B, 0x03, 0x04};
    if (!_dataStartsWith(bytes, pk, 4)) return NO;

    // Check for mimetype file containing "application/epub+zip"
    NSString *content = _dataToUTF8(bytes);
    return content && [content containsString:@"application/epub+zip"];
}

@end

@implementation CSDocxAdapter

- (instancetype)init {
    return [super initWithName:@"docx"
                    extensions:@[@"docx"]
                 magicPatterns:@[]
                  mediaUrnBase:@"media:docx"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

- (BOOL)matchesMagicBytes:(NSData *)bytes {
    // DOCX is a ZIP file
    uint8_t pk[] = {0x50, 0x4B, 0x03, 0x04};
    return _dataStartsWith(bytes, pk, 4);
}

@end

@implementation CSXlsxAdapter

- (instancetype)init {
    return [super initWithName:@"xlsx"
                    extensions:@[@"xlsx"]
                 magicPatterns:@[]
                  mediaUrnBase:@"media:xlsx"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

@end

@implementation CSPptxAdapter

- (instancetype)init {
    return [super initWithName:@"pptx"
                    extensions:@[@"pptx"]
                 magicPatterns:@[]
                  mediaUrnBase:@"media:pptx"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

@end

@implementation CSOdtAdapter

- (instancetype)init {
    return [super initWithName:@"odt"
                    extensions:@[@"odt", @"ods", @"odp"]
                 magicPatterns:@[]
                  mediaUrnBase:@"media:odt"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

@end

@implementation CSRtfAdapter

- (instancetype)init {
    uint8_t magic[] = {0x7B, 0x5C, 0x72, 0x74, 0x66}; // {\rtf
    return [super initWithName:@"rtf"
                    extensions:@[@"rtf"]
                 magicPatterns:@[[NSData dataWithBytes:magic length:5]]
                  mediaUrnBase:@"media:rtf;textable"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

@end

#pragma mark - Image Adapters

@implementation CSPngAdapter

- (instancetype)init {
    uint8_t magic[] = {0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A};
    return [super initWithName:@"png"
                    extensions:@[@"png"]
                 magicPatterns:@[[NSData dataWithBytes:magic length:8]]
                  mediaUrnBase:@"media:png;image"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

@end

@implementation CSJpegAdapter

- (instancetype)init {
    uint8_t magic[] = {0xFF, 0xD8, 0xFF};
    return [super initWithName:@"jpeg"
                    extensions:@[@"jpg", @"jpeg", @"jpe", @"jfif"]
                 magicPatterns:@[[NSData dataWithBytes:magic length:3]]
                  mediaUrnBase:@"media:jpeg;image"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

@end

@implementation CSGifAdapter

- (instancetype)init {
    uint8_t magic87[] = {0x47, 0x49, 0x46, 0x38, 0x37, 0x61}; // GIF87a
    uint8_t magic89[] = {0x47, 0x49, 0x46, 0x38, 0x39, 0x61}; // GIF89a
    return [super initWithName:@"gif"
                    extensions:@[@"gif"]
                 magicPatterns:@[
                     [NSData dataWithBytes:magic87 length:6],
                     [NSData dataWithBytes:magic89 length:6]
                 ]
                  mediaUrnBase:@"media:gif;image"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

@end

@implementation CSWebpAdapter

- (instancetype)init {
    return [super initWithName:@"webp"
                    extensions:@[@"webp"]
                 magicPatterns:@[]
                  mediaUrnBase:@"media:webp;image"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

- (BOOL)matchesMagicBytes:(NSData *)bytes {
    // RIFF....WEBP
    uint8_t riff[] = {0x52, 0x49, 0x46, 0x46};
    uint8_t webp[] = {0x57, 0x45, 0x42, 0x50};
    return _dataStartsWith(bytes, riff, 4) && _dataContainsAt(bytes, 8, webp, 4);
}

@end

@implementation CSSvgAdapter

- (instancetype)init {
    return [super initWithName:@"svg"
                    extensions:@[@"svg", @"svgz"]
                 magicPatterns:@[]
                  mediaUrnBase:@"media:svg;image;textable"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

- (BOOL)matchesMagicBytes:(NSData *)bytes {
    NSString *content = _dataToUTF8(bytes);
    return content && ([content containsString:@"<svg"] || [content containsString:@"<!DOCTYPE svg"]);
}

@end

@implementation CSTiffAdapter

- (instancetype)init {
    uint8_t magicII[] = {0x49, 0x49, 0x2A, 0x00}; // Little endian
    uint8_t magicMM[] = {0x4D, 0x4D, 0x00, 0x2A}; // Big endian
    return [super initWithName:@"tiff"
                    extensions:@[@"tiff", @"tif"]
                 magicPatterns:@[
                     [NSData dataWithBytes:magicII length:4],
                     [NSData dataWithBytes:magicMM length:4]
                 ]
                  mediaUrnBase:@"media:tiff;image"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

@end

@implementation CSBmpAdapter

- (instancetype)init {
    uint8_t magic[] = {0x42, 0x4D}; // BM
    return [super initWithName:@"bmp"
                    extensions:@[@"bmp", @"dib"]
                 magicPatterns:@[[NSData dataWithBytes:magic length:2]]
                  mediaUrnBase:@"media:bmp;image"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

@end

@implementation CSHeicAdapter

- (instancetype)init {
    return [super initWithName:@"heic"
                    extensions:@[@"heic", @"heif"]
                 magicPatterns:@[]
                  mediaUrnBase:@"media:heic;image"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

- (BOOL)matchesMagicBytes:(NSData *)bytes {
    // ftyp box at offset 4 with heic/heif brand
    if (bytes.length < 12) return NO;
    uint8_t ftyp[] = {0x66, 0x74, 0x79, 0x70};
    if (!_dataContainsAt(bytes, 4, ftyp, 4)) return NO;

    NSString *brand = [[NSString alloc] initWithData:[bytes subdataWithRange:NSMakeRange(8, 4)]
                                            encoding:NSASCIIStringEncoding];
    return [brand hasPrefix:@"heic"] || [brand hasPrefix:@"heif"] || [brand hasPrefix:@"mif1"];
}

@end

@implementation CSAvifAdapter

- (instancetype)init {
    return [super initWithName:@"avif"
                    extensions:@[@"avif"]
                 magicPatterns:@[]
                  mediaUrnBase:@"media:avif;image"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

- (BOOL)matchesMagicBytes:(NSData *)bytes {
    if (bytes.length < 12) return NO;
    uint8_t ftyp[] = {0x66, 0x74, 0x79, 0x70};
    if (!_dataContainsAt(bytes, 4, ftyp, 4)) return NO;

    NSString *brand = [[NSString alloc] initWithData:[bytes subdataWithRange:NSMakeRange(8, 4)]
                                            encoding:NSASCIIStringEncoding];
    return [brand hasPrefix:@"avif"];
}

@end

@implementation CSIcoAdapter

- (instancetype)init {
    uint8_t magic[] = {0x00, 0x00, 0x01, 0x00};
    return [super initWithName:@"ico"
                    extensions:@[@"ico"]
                 magicPatterns:@[[NSData dataWithBytes:magic length:4]]
                  mediaUrnBase:@"media:ico;image"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

@end

@implementation CSPsdAdapter

- (instancetype)init {
    uint8_t magic[] = {0x38, 0x42, 0x50, 0x53}; // 8BPS
    return [super initWithName:@"psd"
                    extensions:@[@"psd", @"psb"]
                 magicPatterns:@[[NSData dataWithBytes:magic length:4]]
                  mediaUrnBase:@"media:psd;image"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

@end

@implementation CSRawImageAdapter

- (instancetype)init {
    return [super initWithName:@"raw"
                    extensions:@[@"raw", @"cr2", @"cr3", @"nef", @"arw", @"dng", @"orf", @"rw2"]
                 magicPatterns:@[]
                  mediaUrnBase:@"media:raw;image"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

@end

#pragma mark - Audio Adapters

@implementation CSWavAdapter

- (instancetype)init {
    return [super initWithName:@"wav"
                    extensions:@[@"wav", @"wave"]
                 magicPatterns:@[]
                  mediaUrnBase:@"media:wav;audio"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

- (BOOL)matchesMagicBytes:(NSData *)bytes {
    uint8_t riff[] = {0x52, 0x49, 0x46, 0x46};
    uint8_t wave[] = {0x57, 0x41, 0x56, 0x45};
    return _dataStartsWith(bytes, riff, 4) && _dataContainsAt(bytes, 8, wave, 4);
}

@end

@implementation CSMp3Adapter

- (instancetype)init {
    uint8_t magic1[] = {0xFF, 0xFB}; // MPEG audio frame sync
    uint8_t magic2[] = {0xFF, 0xFA};
    uint8_t magic3[] = {0xFF, 0xF3};
    uint8_t magic4[] = {0xFF, 0xF2};
    uint8_t id3[] = {0x49, 0x44, 0x33}; // ID3
    return [super initWithName:@"mp3"
                    extensions:@[@"mp3"]
                 magicPatterns:@[
                     [NSData dataWithBytes:magic1 length:2],
                     [NSData dataWithBytes:magic2 length:2],
                     [NSData dataWithBytes:magic3 length:2],
                     [NSData dataWithBytes:magic4 length:2],
                     [NSData dataWithBytes:id3 length:3]
                 ]
                  mediaUrnBase:@"media:mp3;audio"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

@end

@implementation CSFlacAdapter

- (instancetype)init {
    uint8_t magic[] = {0x66, 0x4C, 0x61, 0x43}; // fLaC
    return [super initWithName:@"flac"
                    extensions:@[@"flac"]
                 magicPatterns:@[[NSData dataWithBytes:magic length:4]]
                  mediaUrnBase:@"media:flac;audio"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

@end

@implementation CSAacAdapter

- (instancetype)init {
    return [super initWithName:@"aac"
                    extensions:@[@"aac"]
                 magicPatterns:@[]
                  mediaUrnBase:@"media:aac;audio"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

@end

@implementation CSOggAdapter

- (instancetype)init {
    uint8_t magic[] = {0x4F, 0x67, 0x67, 0x53}; // OggS
    return [super initWithName:@"ogg"
                    extensions:@[@"ogg", @"oga", @"ogx"]
                 magicPatterns:@[[NSData dataWithBytes:magic length:4]]
                  mediaUrnBase:@"media:ogg;audio"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

@end

@implementation CSAiffAdapter

- (instancetype)init {
    return [super initWithName:@"aiff"
                    extensions:@[@"aiff", @"aif", @"aifc"]
                 magicPatterns:@[]
                  mediaUrnBase:@"media:aiff;audio"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

- (BOOL)matchesMagicBytes:(NSData *)bytes {
    uint8_t form[] = {0x46, 0x4F, 0x52, 0x4D};
    uint8_t aiff[] = {0x41, 0x49, 0x46, 0x46};
    uint8_t aifc[] = {0x41, 0x49, 0x46, 0x43};
    return _dataStartsWith(bytes, form, 4) &&
           (_dataContainsAt(bytes, 8, aiff, 4) || _dataContainsAt(bytes, 8, aifc, 4));
}

@end

@implementation CSM4aAdapter

- (instancetype)init {
    return [super initWithName:@"m4a"
                    extensions:@[@"m4a", @"m4b", @"m4p"]
                 magicPatterns:@[]
                  mediaUrnBase:@"media:m4a;audio"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

- (BOOL)matchesMagicBytes:(NSData *)bytes {
    if (bytes.length < 12) return NO;
    uint8_t ftyp[] = {0x66, 0x74, 0x79, 0x70};
    if (!_dataContainsAt(bytes, 4, ftyp, 4)) return NO;

    NSString *brand = [[NSString alloc] initWithData:[bytes subdataWithRange:NSMakeRange(8, 4)]
                                            encoding:NSASCIIStringEncoding];
    return [brand hasPrefix:@"M4A"] || [brand hasPrefix:@"M4B"];
}

@end

@implementation CSOpusAdapter

- (instancetype)init {
    return [super initWithName:@"opus"
                    extensions:@[@"opus"]
                 magicPatterns:@[]
                  mediaUrnBase:@"media:opus;audio"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

@end

@implementation CSMidiAdapter

- (instancetype)init {
    uint8_t magic[] = {0x4D, 0x54, 0x68, 0x64}; // MThd
    return [super initWithName:@"midi"
                    extensions:@[@"mid", @"midi"]
                 magicPatterns:@[[NSData dataWithBytes:magic length:4]]
                  mediaUrnBase:@"media:midi;audio"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

@end

@implementation CSCafAdapter

- (instancetype)init {
    uint8_t magic[] = {0x63, 0x61, 0x66, 0x66}; // caff
    return [super initWithName:@"caf"
                    extensions:@[@"caf"]
                 magicPatterns:@[[NSData dataWithBytes:magic length:4]]
                  mediaUrnBase:@"media:caf;audio"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

@end

@implementation CSWmaAdapter

- (instancetype)init {
    uint8_t magic[] = {0x30, 0x26, 0xB2, 0x75}; // ASF header
    return [super initWithName:@"wma"
                    extensions:@[@"wma"]
                 magicPatterns:@[[NSData dataWithBytes:magic length:4]]
                  mediaUrnBase:@"media:wma;audio"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

@end

#pragma mark - Video Adapters

@implementation CSMp4Adapter

- (instancetype)init {
    return [super initWithName:@"mp4"
                    extensions:@[@"mp4", @"m4v"]
                 magicPatterns:@[]
                  mediaUrnBase:@"media:mp4;video"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

- (BOOL)matchesMagicBytes:(NSData *)bytes {
    if (bytes.length < 12) return NO;
    uint8_t ftyp[] = {0x66, 0x74, 0x79, 0x70};
    if (!_dataContainsAt(bytes, 4, ftyp, 4)) return NO;

    NSString *brand = [[NSString alloc] initWithData:[bytes subdataWithRange:NSMakeRange(8, 4)]
                                            encoding:NSASCIIStringEncoding];
    return [brand hasPrefix:@"mp4"] || [brand hasPrefix:@"isom"] || [brand hasPrefix:@"avc1"];
}

@end

@implementation CSWebmAdapter

- (instancetype)init {
    uint8_t magic[] = {0x1A, 0x45, 0xDF, 0xA3}; // EBML
    return [super initWithName:@"webm"
                    extensions:@[@"webm"]
                 magicPatterns:@[[NSData dataWithBytes:magic length:4]]
                  mediaUrnBase:@"media:webm;video"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

@end

@implementation CSMkvAdapter

- (instancetype)init {
    uint8_t magic[] = {0x1A, 0x45, 0xDF, 0xA3}; // EBML (same as WebM)
    return [super initWithName:@"mkv"
                    extensions:@[@"mkv", @"mka", @"mks"]
                 magicPatterns:@[[NSData dataWithBytes:magic length:4]]
                  mediaUrnBase:@"media:mkv;video"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

@end

@implementation CSMovAdapter

- (instancetype)init {
    return [super initWithName:@"mov"
                    extensions:@[@"mov", @"qt"]
                 magicPatterns:@[]
                  mediaUrnBase:@"media:mov;video"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

- (BOOL)matchesMagicBytes:(NSData *)bytes {
    if (bytes.length < 12) return NO;
    uint8_t ftyp[] = {0x66, 0x74, 0x79, 0x70};
    if (!_dataContainsAt(bytes, 4, ftyp, 4)) return NO;

    NSString *brand = [[NSString alloc] initWithData:[bytes subdataWithRange:NSMakeRange(8, 4)]
                                            encoding:NSASCIIStringEncoding];
    return [brand hasPrefix:@"qt"] || [brand isEqualToString:@"moov"];
}

@end

@implementation CSAviAdapter

- (instancetype)init {
    return [super initWithName:@"avi"
                    extensions:@[@"avi"]
                 magicPatterns:@[]
                  mediaUrnBase:@"media:avi;video"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

- (BOOL)matchesMagicBytes:(NSData *)bytes {
    uint8_t riff[] = {0x52, 0x49, 0x46, 0x46};
    uint8_t avi[] = {0x41, 0x56, 0x49, 0x20};
    return _dataStartsWith(bytes, riff, 4) && _dataContainsAt(bytes, 8, avi, 4);
}

@end

@implementation CSMpegAdapter

- (instancetype)init {
    uint8_t magic[] = {0x00, 0x00, 0x01, 0xBA}; // MPEG-PS
    return [super initWithName:@"mpeg"
                    extensions:@[@"mpeg", @"mpg", @"mpe", @"m1v", @"m2v"]
                 magicPatterns:@[[NSData dataWithBytes:magic length:4]]
                  mediaUrnBase:@"media:mpeg;video"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

@end

@implementation CSTsAdapter

- (instancetype)init {
    uint8_t magic[] = {0x47}; // TS sync byte
    return [super initWithName:@"ts"
                    extensions:@[@"ts", @"mts", @"m2ts"]
                 magicPatterns:@[[NSData dataWithBytes:magic length:1]]
                  mediaUrnBase:@"media:ts;video"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

@end

@implementation CSFlvAdapter

- (instancetype)init {
    uint8_t magic[] = {0x46, 0x4C, 0x56}; // FLV
    return [super initWithName:@"flv"
                    extensions:@[@"flv"]
                 magicPatterns:@[[NSData dataWithBytes:magic length:3]]
                  mediaUrnBase:@"media:flv;video"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

@end

@implementation CSWmvAdapter

- (instancetype)init {
    uint8_t magic[] = {0x30, 0x26, 0xB2, 0x75}; // ASF header
    return [super initWithName:@"wmv"
                    extensions:@[@"wmv", @"asf"]
                 magicPatterns:@[[NSData dataWithBytes:magic length:4]]
                  mediaUrnBase:@"media:wmv;video"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

@end

@implementation CSOgvAdapter

- (instancetype)init {
    uint8_t magic[] = {0x4F, 0x67, 0x67, 0x53}; // OggS
    return [super initWithName:@"ogv"
                    extensions:@[@"ogv"]
                 magicPatterns:@[[NSData dataWithBytes:magic length:4]]
                  mediaUrnBase:@"media:ogv;video"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

@end

@implementation CS3gpAdapter

- (instancetype)init {
    return [super initWithName:@"3gp"
                    extensions:@[@"3gp", @"3g2"]
                 magicPatterns:@[]
                  mediaUrnBase:@"media:3gp;video"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

- (BOOL)matchesMagicBytes:(NSData *)bytes {
    if (bytes.length < 12) return NO;
    uint8_t ftyp[] = {0x66, 0x74, 0x79, 0x70};
    if (!_dataContainsAt(bytes, 4, ftyp, 4)) return NO;

    NSString *brand = [[NSString alloc] initWithData:[bytes subdataWithRange:NSMakeRange(8, 4)]
                                            encoding:NSASCIIStringEncoding];
    return [brand hasPrefix:@"3gp"] || [brand hasPrefix:@"3g2"];
}

@end

#pragma mark - Data Interchange Adapters

@implementation CSJsonAdapter

- (instancetype)init {
    return [super initWithName:@"json"
                    extensions:@[@"json", @"geojson", @"topojson"]
                 magicPatterns:@[]
                  mediaUrnBase:@"media:json;textable"
            requiresInspection:YES
              defaultStructure:CSContentStructureScalarOpaque];
}

- (nullable NSString *)detectMediaUrn:(NSString *)path
                              content:(NSData *)content
                            structure:(CSContentStructure *)structure
                                error:(NSError **)error {
    NSString *text = _dataToUTF8(content);
    if (!text) {
        if (structure) *structure = CSContentStructureScalarOpaque;
        return @"media:json;textable";
    }

    text = _trimWhitespace(text);

    // Detect structure based on first non-whitespace character
    if (text.length == 0) {
        if (structure) *structure = CSContentStructureScalarOpaque;
        return @"media:json;textable";
    }

    unichar firstChar = [text characterAtIndex:0];

    if (firstChar == '{') {
        // Object - record, no list
        if (structure) *structure = CSContentStructureScalarRecord;
        return @"media:json;record;textable";
    } else if (firstChar == '[') {
        // Array - check first element
        NSError *parseError = nil;
        id parsed = [NSJSONSerialization JSONObjectWithData:content options:0 error:&parseError];
        if (!parseError && [parsed isKindOfClass:[NSArray class]]) {
            NSArray *arr = (NSArray *)parsed;
            if (arr.count == 0) {
                // Empty array
                if (structure) *structure = CSContentStructureListOpaque;
                return @"media:json;list;textable";
            }
            // Check first element
            id first = arr[0];
            if ([first isKindOfClass:[NSDictionary class]]) {
                // Array of objects
                if (structure) *structure = CSContentStructureListRecord;
                return @"media:json;list;record;textable";
            } else {
                // Array of primitives
                if (structure) *structure = CSContentStructureListOpaque;
                return @"media:json;list;textable";
            }
        } else {
            // Parse failed, assume list of primitives
            if (structure) *structure = CSContentStructureListOpaque;
            return @"media:json;list;textable";
        }
    } else {
        // Primitive value
        if (structure) *structure = CSContentStructureScalarOpaque;
        return @"media:json;textable";
    }
}

@end

@implementation CSNdjsonAdapter

- (instancetype)init {
    return [super initWithName:@"ndjson"
                    extensions:@[@"ndjson", @"jsonl"]
                 magicPatterns:@[]
                  mediaUrnBase:@"media:ndjson;textable"
            requiresInspection:YES
              defaultStructure:CSContentStructureListOpaque];
}

- (nullable NSString *)detectMediaUrn:(NSString *)path
                              content:(NSData *)content
                            structure:(CSContentStructure *)structure
                                error:(NSError **)error {
    NSString *text = _dataToUTF8(content);
    if (!text) {
        if (structure) *structure = CSContentStructureListOpaque;
        return @"media:ndjson;list;textable";
    }

    // Check if any line is an object
    NSArray<NSString *> *lines = [text componentsSeparatedByCharactersInSet:
                                  [NSCharacterSet newlineCharacterSet]];

    BOOL hasObject = NO;
    NSUInteger lineCount = 0;

    for (NSString *line in lines) {
        NSString *trimmed = _trimWhitespace(line);
        if (trimmed.length == 0) continue;

        lineCount++;
        if (lineCount > 10) break; // Only check first 10 lines

        if ([trimmed hasPrefix:@"{"]) {
            hasObject = YES;
            break;
        }
    }

    if (hasObject) {
        if (structure) *structure = CSContentStructureListRecord;
        return @"media:ndjson;list;record;textable";
    } else {
        if (structure) *structure = CSContentStructureListOpaque;
        return @"media:ndjson;list;textable";
    }
}

@end

@implementation CSCsvAdapter

- (instancetype)init {
    return [super initWithName:@"csv"
                    extensions:@[@"csv"]
                 magicPatterns:@[]
                  mediaUrnBase:@"media:csv;textable"
            requiresInspection:YES
              defaultStructure:CSContentStructureListOpaque];
}

- (nullable NSString *)detectMediaUrn:(NSString *)path
                              content:(NSData *)content
                            structure:(CSContentStructure *)structure
                                error:(NSError **)error {
    NSString *text = _dataToUTF8(content);
    if (!text) {
        if (structure) *structure = CSContentStructureListOpaque;
        return @"media:csv;list;textable";
    }

    // Get first line and count columns
    NSString *firstLine = [[text componentsSeparatedByCharactersInSet:
                            [NSCharacterSet newlineCharacterSet]] firstObject];
    if (!firstLine || firstLine.length == 0) {
        if (structure) *structure = CSContentStructureListOpaque;
        return @"media:csv;list;textable";
    }

    // Count commas (simple heuristic, doesn't handle quoted fields perfectly)
    NSUInteger commaCount = [[firstLine componentsSeparatedByString:@","] count] - 1;

    if (commaCount > 0) {
        // Multiple columns - record
        if (structure) *structure = CSContentStructureListRecord;
        return @"media:csv;list;record;textable";
    } else {
        // Single column
        if (structure) *structure = CSContentStructureListOpaque;
        return @"media:csv;list;textable";
    }
}

@end

@implementation CSTsvAdapter

- (instancetype)init {
    return [super initWithName:@"tsv"
                    extensions:@[@"tsv"]
                 magicPatterns:@[]
                  mediaUrnBase:@"media:tsv;textable"
            requiresInspection:YES
              defaultStructure:CSContentStructureListOpaque];
}

- (nullable NSString *)detectMediaUrn:(NSString *)path
                              content:(NSData *)content
                            structure:(CSContentStructure *)structure
                                error:(NSError **)error {
    NSString *text = _dataToUTF8(content);
    if (!text) {
        if (structure) *structure = CSContentStructureListOpaque;
        return @"media:tsv;list;textable";
    }

    // Get first line and count tabs
    NSString *firstLine = [[text componentsSeparatedByCharactersInSet:
                            [NSCharacterSet newlineCharacterSet]] firstObject];
    if (!firstLine || firstLine.length == 0) {
        if (structure) *structure = CSContentStructureListOpaque;
        return @"media:tsv;list;textable";
    }

    NSUInteger tabCount = [[firstLine componentsSeparatedByString:@"\t"] count] - 1;

    if (tabCount > 0) {
        if (structure) *structure = CSContentStructureListRecord;
        return @"media:tsv;list;record;textable";
    } else {
        if (structure) *structure = CSContentStructureListOpaque;
        return @"media:tsv;list;textable";
    }
}

@end

@implementation CSYamlAdapter

- (instancetype)init {
    return [super initWithName:@"yaml"
                    extensions:@[@"yaml", @"yml"]
                 magicPatterns:@[]
                  mediaUrnBase:@"media:yaml;textable"
            requiresInspection:YES
              defaultStructure:CSContentStructureScalarOpaque];
}

- (nullable NSString *)detectMediaUrn:(NSString *)path
                              content:(NSData *)content
                            structure:(CSContentStructure *)structure
                                error:(NSError **)error {
    NSString *text = _dataToUTF8(content);
    if (!text) {
        if (structure) *structure = CSContentStructureScalarOpaque;
        return @"media:yaml;textable";
    }

    text = _trimWhitespace(text);

    // Simple YAML structure detection
    // Check for document separator (multi-doc)
    if ([text containsString:@"\n---"]) {
        // Multi-document - always list
        // Check if first doc is a mapping
        if ([text hasPrefix:@"---\n-"] || [text hasPrefix:@"- "]) {
            if (structure) *structure = CSContentStructureListOpaque;
            return @"media:yaml;list;textable";
        } else {
            if (structure) *structure = CSContentStructureListRecord;
            return @"media:yaml;list;record;textable";
        }
    }

    // Check for sequence (starts with -)
    if ([text hasPrefix:@"- "] || [text hasPrefix:@"-\n"]) {
        // Check if items are mappings
        NSArray<NSString *> *lines = [text componentsSeparatedByCharactersInSet:
                                      [NSCharacterSet newlineCharacterSet]];
        for (NSString *line in lines) {
            if ([line hasPrefix:@"- "] && [line containsString:@": "]) {
                // Sequence of mappings
                if (structure) *structure = CSContentStructureListRecord;
                return @"media:yaml;list;record;textable";
            }
        }
        // Sequence of scalars
        if (structure) *structure = CSContentStructureListOpaque;
        return @"media:yaml;list;textable";
    }

    // Check for mapping (contains : )
    if ([text containsString:@": "]) {
        if (structure) *structure = CSContentStructureScalarRecord;
        return @"media:yaml;record;textable";
    }

    // Scalar
    if (structure) *structure = CSContentStructureScalarOpaque;
    return @"media:yaml;textable";
}

@end

@implementation CSTomlAdapter

- (instancetype)init {
    return [super initWithName:@"toml"
                    extensions:@[@"toml"]
                 magicPatterns:@[]
                  mediaUrnBase:@"media:toml;record;textable"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarRecord];
}

@end

@implementation CSIniAdapter

- (instancetype)init {
    return [super initWithName:@"ini"
                    extensions:@[@"ini", @"cfg", @"conf"]
                 magicPatterns:@[]
                  mediaUrnBase:@"media:ini;record;textable"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarRecord];
}

@end

@implementation CSXmlAdapter

- (instancetype)init {
    return [super initWithName:@"xml"
                    extensions:@[@"xml", @"xsd", @"xsl", @"xslt"]
                 magicPatterns:@[]
                  mediaUrnBase:@"media:xml;textable"
            requiresInspection:YES
              defaultStructure:CSContentStructureScalarOpaque];
}

- (BOOL)matchesMagicBytes:(NSData *)bytes {
    NSString *content = _dataToUTF8(bytes);
    return content && ([content hasPrefix:@"<?xml"] || [content hasPrefix:@"<!"]);
}

- (nullable NSString *)detectMediaUrn:(NSString *)path
                              content:(NSData *)content
                            structure:(CSContentStructure *)structure
                                error:(NSError **)error {
    // Simple heuristic: if contains repeated elements, it's a list
    NSString *text = _dataToUTF8(content);
    if (!text) {
        if (structure) *structure = CSContentStructureScalarOpaque;
        return @"media:xml;textable";
    }

    // Try to find repeated element patterns
    // This is a simple heuristic, not full XML parsing
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"<([a-zA-Z][a-zA-Z0-9]*)[^>]*>"
                                                                           options:0
                                                                             error:nil];
    NSMutableDictionary<NSString *, NSNumber *> *tagCounts = [NSMutableDictionary dictionary];

    [regex enumerateMatchesInString:text options:0 range:NSMakeRange(0, MIN(text.length, 10000))
                         usingBlock:^(NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop) {
        NSString *tag = [text substringWithRange:[result rangeAtIndex:1]];
        tagCounts[tag] = @([tagCounts[tag] integerValue] + 1);
    }];

    // If any tag appears more than twice, assume list structure
    for (NSNumber *count in tagCounts.allValues) {
        if (count.integerValue > 2) {
            if (structure) *structure = CSContentStructureListRecord;
            return @"media:xml;list;record;textable";
        }
    }

    if (structure) *structure = CSContentStructureScalarRecord;
    return @"media:xml;record;textable";
}

@end

@implementation CSPlistAdapter

- (instancetype)init {
    return [super initWithName:@"plist"
                    extensions:@[@"plist"]
                 magicPatterns:@[]
                  mediaUrnBase:@"media:plist;record"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarRecord];
}

- (BOOL)matchesMagicBytes:(NSData *)bytes {
    // Binary plist magic: bplist
    uint8_t magic[] = {0x62, 0x70, 0x6C, 0x69, 0x73, 0x74};
    if (_dataStartsWith(bytes, magic, 6)) return YES;

    // XML plist
    NSString *content = _dataToUTF8(bytes);
    return content && [content containsString:@"<!DOCTYPE plist"];
}

@end

#pragma mark - Plain Text Adapters

@implementation CSPlainTextAdapter

- (instancetype)init {
    return [super initWithName:@"txt"
                    extensions:@[@"txt", @"text"]
                 magicPatterns:@[]
                  mediaUrnBase:@"media:txt;textable"
            requiresInspection:YES
              defaultStructure:CSContentStructureScalarOpaque];
}

- (nullable NSString *)detectMediaUrn:(NSString *)path
                              content:(NSData *)content
                            structure:(CSContentStructure *)structure
                                error:(NSError **)error {
    NSString *text = _dataToUTF8(content);
    if (!text) {
        if (structure) *structure = CSContentStructureScalarOpaque;
        return @"media:txt;textable";
    }

    // Count lines
    NSArray<NSString *> *lines = [text componentsSeparatedByCharactersInSet:
                                  [NSCharacterSet newlineCharacterSet]];
    NSUInteger nonEmptyLines = 0;
    for (NSString *line in lines) {
        if (_trimWhitespace(line).length > 0) nonEmptyLines++;
    }

    if (nonEmptyLines > 1) {
        if (structure) *structure = CSContentStructureListOpaque;
        return @"media:txt;list;textable";
    } else {
        if (structure) *structure = CSContentStructureScalarOpaque;
        return @"media:txt;textable";
    }
}

@end

@implementation CSMarkdownAdapter

- (instancetype)init {
    return [super initWithName:@"md"
                    extensions:@[@"md", @"markdown", @"mdown", @"mkd"]
                 magicPatterns:@[]
                  mediaUrnBase:@"media:md;textable"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

@end

@implementation CSLogAdapter

- (instancetype)init {
    return [super initWithName:@"log"
                    extensions:@[@"log", @"out"]
                 magicPatterns:@[]
                  mediaUrnBase:@"media:log;list;textable"
            requiresInspection:NO
              defaultStructure:CSContentStructureListOpaque];
}

@end

@implementation CSRstAdapter

- (instancetype)init {
    return [super initWithName:@"rst"
                    extensions:@[@"rst", @"rest"]
                 magicPatterns:@[]
                  mediaUrnBase:@"media:rst;textable"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

@end

@implementation CSLatexAdapter

- (instancetype)init {
    return [super initWithName:@"tex"
                    extensions:@[@"tex", @"latex", @"ltx"]
                 magicPatterns:@[]
                  mediaUrnBase:@"media:tex;textable"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

@end

@implementation CSOrgAdapter

- (instancetype)init {
    return [super initWithName:@"org"
                    extensions:@[@"org"]
                 magicPatterns:@[]
                  mediaUrnBase:@"media:org;textable"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

@end

@implementation CSHtmlAdapter

- (instancetype)init {
    return [super initWithName:@"html"
                    extensions:@[@"html", @"htm", @"xhtml"]
                 magicPatterns:@[]
                  mediaUrnBase:@"media:html;textable"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

- (BOOL)matchesMagicBytes:(NSData *)bytes {
    NSString *content = _dataToUTF8(bytes);
    return content && ([content containsString:@"<html"] ||
                       [content containsString:@"<!DOCTYPE html"] ||
                       [content containsString:@"<!doctype html"]);
}

@end

@implementation CSCssAdapter

- (instancetype)init {
    return [super initWithName:@"css"
                    extensions:@[@"css", @"scss", @"sass", @"less"]
                 magicPatterns:@[]
                  mediaUrnBase:@"media:css;textable"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

@end

#pragma mark - Source Code Adapters

// Macro for simple code adapters
#define DEFINE_CODE_ADAPTER(ClassName, AdapterName, Extensions, MediaBase) \
@implementation ClassName \
- (instancetype)init { \
    return [super initWithName:@AdapterName \
                    extensions:Extensions \
                 magicPatterns:@[] \
                  mediaUrnBase:@MediaBase \
            requiresInspection:NO \
              defaultStructure:CSContentStructureScalarOpaque]; \
} \
@end

DEFINE_CODE_ADAPTER(CSRustAdapter, "rust", (@[@"rs"]), "media:rust;textable;code")
DEFINE_CODE_ADAPTER(CSPythonAdapter, "python", (@[@"py", @"pyw", @"pyi"]), "media:python;textable;code")
DEFINE_CODE_ADAPTER(CSJavaScriptAdapter, "javascript", (@[@"js", @"mjs", @"cjs"]), "media:javascript;textable;code")
DEFINE_CODE_ADAPTER(CSTypeScriptAdapter, "typescript", (@[@"ts", @"tsx", @"mts", @"cts"]), "media:typescript;textable;code")
DEFINE_CODE_ADAPTER(CSGoAdapter, "go", (@[@"go"]), "media:go;textable;code")
DEFINE_CODE_ADAPTER(CSJavaAdapter, "java", (@[@"java"]), "media:java;textable;code")
DEFINE_CODE_ADAPTER(CSCAdapter, "c", (@[@"c", @"h"]), "media:c;textable;code")
DEFINE_CODE_ADAPTER(CSCppAdapter, "cpp", (@[@"cpp", @"cc", @"cxx", @"hpp", @"hh", @"hxx"]), "media:cpp;textable;code")
DEFINE_CODE_ADAPTER(CSSwiftAdapter, "swift", (@[@"swift"]), "media:swift;textable;code")
DEFINE_CODE_ADAPTER(CSObjCAdapter, "objc", (@[@"m", @"mm"]), "media:objc;textable;code")
DEFINE_CODE_ADAPTER(CSRubyAdapter, "ruby", (@[@"rb", @"rake", @"gemspec"]), "media:ruby;textable;code")
DEFINE_CODE_ADAPTER(CSPhpAdapter, "php", (@[@"php", @"phtml", @"php3", @"php4", @"php5"]), "media:php;textable;code")
DEFINE_CODE_ADAPTER(CSShellAdapter, "shell", (@[@"sh", @"bash", @"zsh", @"fish"]), "media:shell;textable;code")
DEFINE_CODE_ADAPTER(CSSqlAdapter, "sql", (@[@"sql"]), "media:sql;textable;code")
DEFINE_CODE_ADAPTER(CSKotlinAdapter, "kotlin", (@[@"kt", @"kts"]), "media:kotlin;textable;code")
DEFINE_CODE_ADAPTER(CSScalaAdapter, "scala", (@[@"scala", @"sc"]), "media:scala;textable;code")
DEFINE_CODE_ADAPTER(CSCSharpAdapter, "csharp", (@[@"cs"]), "media:csharp;textable;code")
DEFINE_CODE_ADAPTER(CSHaskellAdapter, "haskell", (@[@"hs", @"lhs"]), "media:haskell;textable;code")
DEFINE_CODE_ADAPTER(CSElixirAdapter, "elixir", (@[@"ex", @"exs"]), "media:elixir;textable;code")
DEFINE_CODE_ADAPTER(CSLuaAdapter, "lua", (@[@"lua"]), "media:lua;textable;code")
DEFINE_CODE_ADAPTER(CSPerlAdapter, "perl", (@[@"pl", @"pm", @"t"]), "media:perl;textable;code")
DEFINE_CODE_ADAPTER(CSRLangAdapter, "r", (@[@"r", @"R"]), "media:r;textable;code")
DEFINE_CODE_ADAPTER(CSJuliaAdapter, "julia", (@[@"jl"]), "media:julia;textable;code")
DEFINE_CODE_ADAPTER(CSZigAdapter, "zig", (@[@"zig"]), "media:zig;textable;code")
DEFINE_CODE_ADAPTER(CSNimAdapter, "nim", (@[@"nim", @"nims"]), "media:nim;textable;code")
DEFINE_CODE_ADAPTER(CSDartAdapter, "dart", (@[@"dart"]), "media:dart;textable;code")
DEFINE_CODE_ADAPTER(CSVueAdapter, "vue", (@[@"vue"]), "media:vue;textable;code")
DEFINE_CODE_ADAPTER(CSSvelteAdapter, "svelte", (@[@"svelte"]), "media:svelte;textable;code")

@implementation CSMakefileAdapter

- (instancetype)init {
    return [super initWithName:@"makefile"
                    extensions:@[@"makefile", @"mk"]
                 magicPatterns:@[]
                  mediaUrnBase:@"media:makefile;textable"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

- (BOOL)matchesExtension:(NSString *)extension {
    // Special handling for files without extension named "Makefile" or "GNUmakefile"
    return [super matchesExtension:extension];
}

@end

@implementation CSDockerfileAdapter

- (instancetype)init {
    return [super initWithName:@"dockerfile"
                    extensions:@[@"dockerfile"]
                 magicPatterns:@[]
                  mediaUrnBase:@"media:dockerfile;textable"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

@end

@implementation CSIgnoreFileAdapter

- (instancetype)init {
    return [super initWithName:@"ignore"
                    extensions:@[@"gitignore", @"dockerignore", @"npmignore", @"hgignore"]
                 magicPatterns:@[]
                  mediaUrnBase:@"media:gitignore;list;textable"
            requiresInspection:NO
              defaultStructure:CSContentStructureListOpaque];
}

@end

@implementation CSRequirementsAdapter

- (instancetype)init {
    return [super initWithName:@"requirements"
                    extensions:@[@"requirements"]
                 magicPatterns:@[]
                  mediaUrnBase:@"media:requirements;list;textable"
            requiresInspection:NO
              defaultStructure:CSContentStructureListOpaque];
}

@end

#pragma mark - Archive Adapters

@implementation CSZipAdapter

- (instancetype)init {
    uint8_t magic[] = {0x50, 0x4B, 0x03, 0x04};
    return [super initWithName:@"zip"
                    extensions:@[@"zip"]
                 magicPatterns:@[[NSData dataWithBytes:magic length:4]]
                  mediaUrnBase:@"media:zip;archive"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

@end

@implementation CSTarAdapter

- (instancetype)init {
    return [super initWithName:@"tar"
                    extensions:@[@"tar"]
                 magicPatterns:@[]
                  mediaUrnBase:@"media:tar;archive"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

- (BOOL)matchesMagicBytes:(NSData *)bytes {
    // TAR magic at offset 257: "ustar"
    uint8_t magic[] = {0x75, 0x73, 0x74, 0x61, 0x72};
    return _dataContainsAt(bytes, 257, magic, 5);
}

@end

@implementation CSGzipAdapter

- (instancetype)init {
    uint8_t magic[] = {0x1F, 0x8B};
    return [super initWithName:@"gzip"
                    extensions:@[@"gz", @"gzip", @"tgz"]
                 magicPatterns:@[[NSData dataWithBytes:magic length:2]]
                  mediaUrnBase:@"media:gzip;archive"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

@end

@implementation CSBzip2Adapter

- (instancetype)init {
    uint8_t magic[] = {0x42, 0x5A, 0x68}; // BZh
    return [super initWithName:@"bzip2"
                    extensions:@[@"bz2", @"bzip2", @"tbz2"]
                 magicPatterns:@[[NSData dataWithBytes:magic length:3]]
                  mediaUrnBase:@"media:bzip2;archive"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

@end

@implementation CSXzAdapter

- (instancetype)init {
    uint8_t magic[] = {0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00};
    return [super initWithName:@"xz"
                    extensions:@[@"xz", @"txz"]
                 magicPatterns:@[[NSData dataWithBytes:magic length:6]]
                  mediaUrnBase:@"media:xz;archive"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

@end

@implementation CSZstdAdapter

- (instancetype)init {
    uint8_t magic[] = {0x28, 0xB5, 0x2F, 0xFD};
    return [super initWithName:@"zstd"
                    extensions:@[@"zst", @"zstd"]
                 magicPatterns:@[[NSData dataWithBytes:magic length:4]]
                  mediaUrnBase:@"media:zstd;archive"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

@end

@implementation CS7zAdapter

- (instancetype)init {
    uint8_t magic[] = {0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C};
    return [super initWithName:@"7z"
                    extensions:@[@"7z"]
                 magicPatterns:@[[NSData dataWithBytes:magic length:6]]
                  mediaUrnBase:@"media:7z;archive"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

@end

@implementation CSRarAdapter

- (instancetype)init {
    uint8_t magic1[] = {0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00}; // RAR4
    uint8_t magic2[] = {0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00}; // RAR5
    return [super initWithName:@"rar"
                    extensions:@[@"rar"]
                 magicPatterns:@[
                     [NSData dataWithBytes:magic1 length:7],
                     [NSData dataWithBytes:magic2 length:8]
                 ]
                  mediaUrnBase:@"media:rar;archive"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

@end

@implementation CSJarAdapter

- (instancetype)init {
    uint8_t magic[] = {0x50, 0x4B, 0x03, 0x04};
    return [super initWithName:@"jar"
                    extensions:@[@"jar", @"war", @"ear"]
                 magicPatterns:@[[NSData dataWithBytes:magic length:4]]
                  mediaUrnBase:@"media:jar;archive"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

@end

@implementation CSDmgAdapter

- (instancetype)init {
    return [super initWithName:@"dmg"
                    extensions:@[@"dmg"]
                 magicPatterns:@[]
                  mediaUrnBase:@"media:dmg;archive"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

@end

@implementation CSIsoAdapter

- (instancetype)init {
    return [super initWithName:@"iso"
                    extensions:@[@"iso"]
                 magicPatterns:@[]
                  mediaUrnBase:@"media:iso;archive"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

- (BOOL)matchesMagicBytes:(NSData *)bytes {
    // ISO 9660 magic at offset 32769 or 34817: "CD001"
    uint8_t magic[] = {0x43, 0x44, 0x30, 0x30, 0x31};
    return _dataContainsAt(bytes, 32769, magic, 5) || _dataContainsAt(bytes, 34817, magic, 5);
}

@end

#pragma mark - Other Adapters

@implementation CSFontAdapter

- (instancetype)init {
    return [super initWithName:@"font"
                    extensions:@[@"ttf", @"otf", @"woff", @"woff2", @"eot"]
                 magicPatterns:@[]
                  mediaUrnBase:@"media:font"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

- (BOOL)matchesMagicBytes:(NSData *)bytes {
    // TTF: 00 01 00 00
    uint8_t ttf[] = {0x00, 0x01, 0x00, 0x00};
    if (_dataStartsWith(bytes, ttf, 4)) return YES;

    // OTF: OTTO
    uint8_t otf[] = {0x4F, 0x54, 0x54, 0x4F};
    if (_dataStartsWith(bytes, otf, 4)) return YES;

    // WOFF: wOFF
    uint8_t woff[] = {0x77, 0x4F, 0x46, 0x46};
    if (_dataStartsWith(bytes, woff, 4)) return YES;

    // WOFF2: wOF2
    uint8_t woff2[] = {0x77, 0x4F, 0x46, 0x32};
    if (_dataStartsWith(bytes, woff2, 4)) return YES;

    return NO;
}

@end

@implementation CSModel3DAdapter

- (instancetype)init {
    return [super initWithName:@"model3d"
                    extensions:@[@"obj", @"stl", @"fbx", @"gltf", @"glb", @"dae", @"3ds", @"ply"]
                 magicPatterns:@[]
                  mediaUrnBase:@"media:model"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

@end

@implementation CSMlModelAdapter

- (instancetype)init {
    return [super initWithName:@"mlmodel"
                    extensions:@[@"gguf", @"ggml", @"safetensors", @"pt", @"pth", @"onnx", @"mlmodel", @"mlpackage"]
                 magicPatterns:@[]
                  mediaUrnBase:@"media:mlmodel"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

- (BOOL)matchesMagicBytes:(NSData *)bytes {
    // GGUF: GGUF
    uint8_t gguf[] = {0x47, 0x47, 0x55, 0x46};
    return _dataStartsWith(bytes, gguf, 4);
}

@end

@implementation CSDatabaseAdapter

- (instancetype)init {
    return [super initWithName:@"database"
                    extensions:@[@"sqlite", @"sqlite3", @"db", @"mdb", @"accdb"]
                 magicPatterns:@[]
                  mediaUrnBase:@"media:database"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

- (BOOL)matchesMagicBytes:(NSData *)bytes {
    // SQLite: "SQLite format 3"
    uint8_t sqlite[] = {0x53, 0x51, 0x4C, 0x69, 0x74, 0x65, 0x20, 0x66, 0x6F, 0x72, 0x6D, 0x61, 0x74, 0x20, 0x33};
    return _dataStartsWith(bytes, sqlite, 15);
}

@end

@implementation CSColumnarDataAdapter

- (instancetype)init {
    return [super initWithName:@"columnar"
                    extensions:@[@"parquet", @"arrow", @"feather", @"avro", @"orc"]
                 magicPatterns:@[]
                  mediaUrnBase:@"media:columnar;list;record"
            requiresInspection:NO
              defaultStructure:CSContentStructureListRecord];
}

- (BOOL)matchesMagicBytes:(NSData *)bytes {
    // Parquet: PAR1
    uint8_t parquet[] = {0x50, 0x41, 0x52, 0x31};
    if (_dataStartsWith(bytes, parquet, 4)) return YES;

    // Arrow IPC: ARROW1
    uint8_t arrow[] = {0x41, 0x52, 0x52, 0x4F, 0x57, 0x31};
    if (_dataStartsWith(bytes, arrow, 6)) return YES;

    return NO;
}

@end

@implementation CSCertificateAdapter

- (instancetype)init {
    return [super initWithName:@"certificate"
                    extensions:@[@"pem", @"crt", @"cer", @"key", @"csr", @"p12", @"pfx"]
                 magicPatterns:@[]
                  mediaUrnBase:@"media:cert"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

- (BOOL)matchesMagicBytes:(NSData *)bytes {
    NSString *content = _dataToUTF8(bytes);
    return content && [content hasPrefix:@"-----BEGIN"];
}

@end

@implementation CSGeoAdapter

- (instancetype)init {
    return [super initWithName:@"geo"
                    extensions:@[@"kml", @"kmz", @"gpx", @"shp"]
                 magicPatterns:@[]
                  mediaUrnBase:@"media:geo"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

@end

@implementation CSSubtitleAdapter

- (instancetype)init {
    return [super initWithName:@"subtitle"
                    extensions:@[@"srt", @"vtt", @"ass", @"ssa", @"sub"]
                 magicPatterns:@[]
                  mediaUrnBase:@"media:subtitle;list;record;textable"
            requiresInspection:NO
              defaultStructure:CSContentStructureListRecord];
}

@end

@implementation CSEmailAdapter

- (instancetype)init {
    return [super initWithName:@"email"
                    extensions:@[@"eml", @"msg", @"mbox"]
                 magicPatterns:@[]
                  mediaUrnBase:@"media:email"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarRecord];
}

@end

@implementation CSJupyterAdapter

- (instancetype)init {
    return [super initWithName:@"jupyter"
                    extensions:@[@"ipynb"]
                 magicPatterns:@[]
                  mediaUrnBase:@"media:jupyter;record;textable"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarRecord];
}

@end

@implementation CSWasmAdapter

- (instancetype)init {
    uint8_t magic[] = {0x00, 0x61, 0x73, 0x6D}; // \0asm
    return [super initWithName:@"wasm"
                    extensions:@[@"wasm", @"wat"]
                 magicPatterns:@[[NSData dataWithBytes:magic length:4]]
                  mediaUrnBase:@"media:wasm"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

@end

@implementation CSDotAdapter

- (instancetype)init {
    return [super initWithName:@"dot"
                    extensions:@[@"dot", @"gv"]
                 magicPatterns:@[]
                  mediaUrnBase:@"media:dot;textable"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

- (BOOL)matchesMagicBytes:(NSData *)bytes {
    NSString *content = _dataToUTF8(bytes);
    return content && ([content containsString:@"digraph"] || [content containsString:@"graph"]);
}

@end

#pragma mark - Fallback Adapter

@implementation CSFallbackAdapter

- (instancetype)init {
    return [super initWithName:@"fallback"
                    extensions:@[]
                 magicPatterns:@[]
                  mediaUrnBase:@"media:"
            requiresInspection:NO
              defaultStructure:CSContentStructureScalarOpaque];
}

- (BOOL)matchesExtension:(NSString *)extension {
    // Fallback matches everything
    return YES;
}

- (BOOL)matchesMagicBytes:(NSData *)bytes {
    // Never match on magic bytes - only use as last resort
    return NO;
}

@end

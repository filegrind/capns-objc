//
//  CSMediaAdapters.h
//  CapDAG
//
//  Forward declarations for all media adapter classes
//

#import <Foundation/Foundation.h>
#import "CSInputResolver.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Base Adapter

/// Base adapter implementation with common functionality
@interface CSBaseAdapter : NSObject <CSMediaAdapter>

/// Extensions this adapter handles (lowercase, without dot)
@property (nonatomic, readonly) NSArray<NSString *> *extensions;

/// Magic bytes patterns this adapter recognizes
@property (nonatomic, readonly) NSArray<NSData *> *magicPatterns;

/// Default media URN base (without markers)
@property (nonatomic, readonly) NSString *mediaUrnBase;

/// Whether this adapter requires content inspection
@property (nonatomic, readonly) BOOL requiresInspection;

/// Default content structure if no inspection needed
@property (nonatomic, readonly) CSContentStructure defaultStructure;

/// Initialize with configuration
- (instancetype)initWithName:(NSString *)name
                  extensions:(NSArray<NSString *> *)extensions
               magicPatterns:(NSArray<NSData *> *)magicPatterns
                mediaUrnBase:(NSString *)mediaUrnBase
          requiresInspection:(BOOL)requiresInspection
            defaultStructure:(CSContentStructure)defaultStructure;

/// Build media URN with appropriate markers
- (NSString *)buildMediaUrnWithStructure:(CSContentStructure)structure;

@end

#pragma mark - Document Adapters

@interface CSPdfAdapter : CSBaseAdapter
@end

@interface CSEpubAdapter : CSBaseAdapter
@end

@interface CSDocxAdapter : CSBaseAdapter
@end

@interface CSXlsxAdapter : CSBaseAdapter
@end

@interface CSPptxAdapter : CSBaseAdapter
@end

@interface CSOdtAdapter : CSBaseAdapter
@end

@interface CSRtfAdapter : CSBaseAdapter
@end

#pragma mark - Image Adapters

@interface CSPngAdapter : CSBaseAdapter
@end

@interface CSJpegAdapter : CSBaseAdapter
@end

@interface CSGifAdapter : CSBaseAdapter
@end

@interface CSWebpAdapter : CSBaseAdapter
@end

@interface CSSvgAdapter : CSBaseAdapter
@end

@interface CSTiffAdapter : CSBaseAdapter
@end

@interface CSBmpAdapter : CSBaseAdapter
@end

@interface CSHeicAdapter : CSBaseAdapter
@end

@interface CSAvifAdapter : CSBaseAdapter
@end

@interface CSIcoAdapter : CSBaseAdapter
@end

@interface CSPsdAdapter : CSBaseAdapter
@end

@interface CSRawImageAdapter : CSBaseAdapter
@end

#pragma mark - Audio Adapters

@interface CSWavAdapter : CSBaseAdapter
@end

@interface CSMp3Adapter : CSBaseAdapter
@end

@interface CSFlacAdapter : CSBaseAdapter
@end

@interface CSAacAdapter : CSBaseAdapter
@end

@interface CSOggAdapter : CSBaseAdapter
@end

@interface CSAiffAdapter : CSBaseAdapter
@end

@interface CSM4aAdapter : CSBaseAdapter
@end

@interface CSOpusAdapter : CSBaseAdapter
@end

@interface CSMidiAdapter : CSBaseAdapter
@end

@interface CSCafAdapter : CSBaseAdapter
@end

@interface CSWmaAdapter : CSBaseAdapter
@end

#pragma mark - Video Adapters

@interface CSMp4Adapter : CSBaseAdapter
@end

@interface CSWebmAdapter : CSBaseAdapter
@end

@interface CSMkvAdapter : CSBaseAdapter
@end

@interface CSMovAdapter : CSBaseAdapter
@end

@interface CSAviAdapter : CSBaseAdapter
@end

@interface CSMpegAdapter : CSBaseAdapter
@end

@interface CSTsAdapter : CSBaseAdapter
@end

@interface CSFlvAdapter : CSBaseAdapter
@end

@interface CSWmvAdapter : CSBaseAdapter
@end

@interface CSOgvAdapter : CSBaseAdapter
@end

@interface CS3gpAdapter : CSBaseAdapter
@end

#pragma mark - Data Interchange Adapters (Require Content Inspection)

@interface CSJsonAdapter : CSBaseAdapter
@end

@interface CSNdjsonAdapter : CSBaseAdapter
@end

@interface CSCsvAdapter : CSBaseAdapter
@end

@interface CSTsvAdapter : CSBaseAdapter
@end

@interface CSYamlAdapter : CSBaseAdapter
@end

@interface CSTomlAdapter : CSBaseAdapter
@end

@interface CSIniAdapter : CSBaseAdapter
@end

@interface CSXmlAdapter : CSBaseAdapter
@end

@interface CSPlistAdapter : CSBaseAdapter
@end

#pragma mark - Plain Text Adapters

@interface CSPlainTextAdapter : CSBaseAdapter
@end

@interface CSMarkdownAdapter : CSBaseAdapter
@end

@interface CSLogAdapter : CSBaseAdapter
@end

@interface CSRstAdapter : CSBaseAdapter
@end

@interface CSLatexAdapter : CSBaseAdapter
@end

@interface CSOrgAdapter : CSBaseAdapter
@end

@interface CSHtmlAdapter : CSBaseAdapter
@end

@interface CSCssAdapter : CSBaseAdapter
@end

#pragma mark - Source Code Adapters

@interface CSRustAdapter : CSBaseAdapter
@end

@interface CSPythonAdapter : CSBaseAdapter
@end

@interface CSJavaScriptAdapter : CSBaseAdapter
@end

@interface CSTypeScriptAdapter : CSBaseAdapter
@end

@interface CSGoAdapter : CSBaseAdapter
@end

@interface CSJavaAdapter : CSBaseAdapter
@end

@interface CSCAdapter : CSBaseAdapter
@end

@interface CSCppAdapter : CSBaseAdapter
@end

@interface CSSwiftAdapter : CSBaseAdapter
@end

@interface CSObjCAdapter : CSBaseAdapter
@end

@interface CSRubyAdapter : CSBaseAdapter
@end

@interface CSPhpAdapter : CSBaseAdapter
@end

@interface CSShellAdapter : CSBaseAdapter
@end

@interface CSSqlAdapter : CSBaseAdapter
@end

@interface CSKotlinAdapter : CSBaseAdapter
@end

@interface CSScalaAdapter : CSBaseAdapter
@end

@interface CSCSharpAdapter : CSBaseAdapter
@end

@interface CSHaskellAdapter : CSBaseAdapter
@end

@interface CSElixirAdapter : CSBaseAdapter
@end

@interface CSLuaAdapter : CSBaseAdapter
@end

@interface CSPerlAdapter : CSBaseAdapter
@end

@interface CSRLangAdapter : CSBaseAdapter
@end

@interface CSJuliaAdapter : CSBaseAdapter
@end

@interface CSZigAdapter : CSBaseAdapter
@end

@interface CSNimAdapter : CSBaseAdapter
@end

@interface CSDartAdapter : CSBaseAdapter
@end

@interface CSVueAdapter : CSBaseAdapter
@end

@interface CSSvelteAdapter : CSBaseAdapter
@end

@interface CSMakefileAdapter : CSBaseAdapter
@end

@interface CSDockerfileAdapter : CSBaseAdapter
@end

@interface CSIgnoreFileAdapter : CSBaseAdapter
@end

@interface CSRequirementsAdapter : CSBaseAdapter
@end

#pragma mark - Archive Adapters

@interface CSZipAdapter : CSBaseAdapter
@end

@interface CSTarAdapter : CSBaseAdapter
@end

@interface CSGzipAdapter : CSBaseAdapter
@end

@interface CSBzip2Adapter : CSBaseAdapter
@end

@interface CSXzAdapter : CSBaseAdapter
@end

@interface CSZstdAdapter : CSBaseAdapter
@end

@interface CS7zAdapter : CSBaseAdapter
@end

@interface CSRarAdapter : CSBaseAdapter
@end

@interface CSJarAdapter : CSBaseAdapter
@end

@interface CSDmgAdapter : CSBaseAdapter
@end

@interface CSIsoAdapter : CSBaseAdapter
@end

#pragma mark - Other Adapters

@interface CSFontAdapter : CSBaseAdapter
@end

@interface CSModel3DAdapter : CSBaseAdapter
@end

@interface CSMlModelAdapter : CSBaseAdapter
@end

@interface CSDatabaseAdapter : CSBaseAdapter
@end

@interface CSColumnarDataAdapter : CSBaseAdapter
@end

@interface CSCertificateAdapter : CSBaseAdapter
@end

@interface CSGeoAdapter : CSBaseAdapter
@end

@interface CSSubtitleAdapter : CSBaseAdapter
@end

@interface CSEmailAdapter : CSBaseAdapter
@end

@interface CSJupyterAdapter : CSBaseAdapter
@end

@interface CSWasmAdapter : CSBaseAdapter
@end

@interface CSDotAdapter : CSBaseAdapter
@end

#pragma mark - Fallback Adapter

@interface CSFallbackAdapter : CSBaseAdapter
@end

NS_ASSUME_NONNULL_END

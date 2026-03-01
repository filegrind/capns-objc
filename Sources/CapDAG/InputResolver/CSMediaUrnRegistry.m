//
//  CSMediaUrnRegistry.m
//  CapDAG
//
//  MediaUrnRegistry — Extension to URN mapping from bundled specs
//
//  This mirrors the extension index from Rust's MediaUrnRegistry.
//  The mappings are compiled from the TOML specs in capdag-dot-com/standard/media/
//

#import "CSMediaUrnRegistry.h"

@implementation CSMediaUrnRegistry {
    /// Extension to URNs mapping (lowercase extension -> array of URNs)
    NSDictionary<NSString *, NSArray<NSString *> *> *_extensionIndex;
}

+ (CSMediaUrnRegistry *)shared {
    static CSMediaUrnRegistry *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[CSMediaUrnRegistry alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self _buildExtensionIndex];
    }
    return self;
}

/// Build extension index from compiled-in mappings
/// These mappings mirror the TOML specs in capdag-dot-com/standard/media/
- (void)_buildExtensionIndex {
    // This index is generated from the standard media specs
    // Each extension maps to an array of URNs (some extensions have multiple)
    _extensionIndex = @{
        // Documents
        @"pdf": @[@"media:pdf"],
        @"epub": @[@"media:epub"],
        @"mobi": @[@"media:mobi"],
        @"djvu": @[@"media:djvu"],
        @"doc": @[@"media:doc"],
        @"docx": @[@"media:docx"],
        @"xls": @[@"media:xls"],
        @"xlsx": @[@"media:xlsx"],
        @"ppt": @[@"media:ppt"],
        @"pptx": @[@"media:pptx"],
        @"odt": @[@"media:odt"],
        @"ods": @[@"media:ods"],
        @"odp": @[@"media:odp"],
        @"rtf": @[@"media:rtf"],
        @"pages": @[@"media:pages"],
        @"numbers": @[@"media:numbers"],
        @"keynote": @[@"media:keynote"],

        // Images
        @"png": @[@"media:png;image"],
        @"jpg": @[@"media:jpeg;image"],
        @"jpeg": @[@"media:jpeg;image"],
        @"gif": @[@"media:gif;image"],
        @"webp": @[@"media:webp;image"],
        @"svg": @[@"media:svg;image"],
        @"tiff": @[@"media:tiff;image"],
        @"tif": @[@"media:tiff;image"],
        @"bmp": @[@"media:bmp;image"],
        @"heic": @[@"media:heic;image"],
        @"heif": @[@"media:heic;image"],
        @"avif": @[@"media:avif;image"],
        @"ico": @[@"media:ico;image"],
        @"psd": @[@"media:psd;image"],
        @"raw": @[@"media:raw;image"],
        @"cr2": @[@"media:raw;image"],
        @"nef": @[@"media:raw;image"],
        @"arw": @[@"media:raw;image"],
        @"dng": @[@"media:raw;image"],
        @"exr": @[@"media:exr;image"],
        @"hdr": @[@"media:hdr;image"],
        @"icns": @[@"media:icns;image"],

        // Audio
        @"wav": @[@"media:wav;audio"],
        @"mp3": @[@"media:mp3;audio"],
        @"flac": @[@"media:flac;audio"],
        @"aac": @[@"media:aac;audio"],
        @"ogg": @[@"media:ogg;audio"],
        @"m4a": @[@"media:m4a;audio"],
        @"aiff": @[@"media:aiff;audio"],
        @"aif": @[@"media:aiff;audio"],
        @"opus": @[@"media:opus;audio"],
        @"wma": @[@"media:wma;audio"],
        @"caf": @[@"media:caf;audio"],
        @"mid": @[@"media:midi;audio"],
        @"midi": @[@"media:midi;audio"],

        // Video
        @"mp4": @[@"media:mp4;video"],
        @"webm": @[@"media:webm;video"],
        @"mkv": @[@"media:mkv;video"],
        @"mov": @[@"media:mov;video"],
        @"avi": @[@"media:avi;video"],
        @"mpeg": @[@"media:mpeg;video"],
        @"mpg": @[@"media:mpeg;video"],
        @"mts": @[@"media:ts;video"],
        @"m2ts": @[@"media:ts;video"],
        @"flv": @[@"media:flv;video"],
        @"wmv": @[@"media:wmv;video"],
        @"ogv": @[@"media:ogv;video"],
        @"3gp": @[@"media:3gp;video"],

        // Data interchange (require content inspection)
        @"json": @[@"media:json;textable"],
        @"ndjson": @[@"media:ndjson;list;textable"],
        @"jsonl": @[@"media:ndjson;list;textable"],
        @"csv": @[@"media:csv;list;textable"],
        @"tsv": @[@"media:tsv;list;textable"],
        @"psv": @[@"media:psv;list;textable"],
        @"yaml": @[@"media:yaml;textable"],
        @"yml": @[@"media:yaml;textable"],
        @"toml": @[@"media:toml;record;textable"],
        @"ini": @[@"media:ini;record;textable"],
        @"cfg": @[@"media:conf;record;textable"],
        @"conf": @[@"media:conf;record;textable"],
        @"config": @[@"media:conf;record;textable"],
        @"properties": @[@"media:properties;record;textable"],
        @"env": @[@"media:env;record;textable"],
        @"xml": @[@"media:xml;textable"],
        @"plist": @[@"media:plist;record"],

        // Text files
        @"txt": @[@"media:txt;textable"],
        @"text": @[@"media:txt;textable"],
        @"md": @[@"media:md;textable"],
        @"markdown": @[@"media:md;textable"],
        @"mdown": @[@"media:md;textable"],
        @"mkd": @[@"media:md;textable"],
        @"log": @[@"media:log;list;textable"],
        @"out": @[@"media:log;list;textable"],
        @"rst": @[@"media:rst;textable"],
        @"rest": @[@"media:rst;textable"],
        @"adoc": @[@"media:asciidoc;textable"],
        @"asciidoc": @[@"media:asciidoc;textable"],
        @"tex": @[@"media:latex;textable"],
        @"latex": @[@"media:latex;textable"],
        @"ltx": @[@"media:latex;textable"],
        @"org": @[@"media:org;textable"],
        @"html": @[@"media:html;textable"],
        @"htm": @[@"media:html;textable"],
        @"xhtml": @[@"media:html;textable"],
        @"css": @[@"media:css;textable"],
        @"scss": @[@"media:scss;textable"],
        @"sass": @[@"media:scss;textable"],
        @"less": @[@"media:less;textable"],

        // Source code
        @"rs": @[@"media:rust;textable;code"],
        @"py": @[@"media:python;textable;code"],
        @"pyw": @[@"media:python;textable;code"],
        @"pyi": @[@"media:python;textable;code"],
        @"js": @[@"media:javascript;textable;code"],
        @"mjs": @[@"media:javascript;textable;code"],
        @"cjs": @[@"media:javascript;textable;code"],
        @"jsx": @[@"media:jsx;textable;code"],
        @"ts": @[@"media:typescript;textable;code"],
        @"tsx": @[@"media:tsx;textable;code"],
        @"mts": @[@"media:typescript;textable;code"],
        @"cts": @[@"media:typescript;textable;code"],
        @"go": @[@"media:go;textable;code"],
        @"java": @[@"media:java;textable;code"],
        @"c": @[@"media:c;textable;code"],
        @"h": @[@"media:c-header;textable;code"],
        @"cpp": @[@"media:cpp;textable;code"],
        @"cc": @[@"media:cpp;textable;code"],
        @"cxx": @[@"media:cpp;textable;code"],
        @"hpp": @[@"media:cpp-header;textable;code"],
        @"hh": @[@"media:cpp-header;textable;code"],
        @"swift": @[@"media:swift;textable;code"],
        @"m": @[@"media:objc;textable;code"],
        @"mm": @[@"media:objcpp;textable;code"],
        @"rb": @[@"media:ruby;textable;code"],
        @"php": @[@"media:php;textable;code"],
        @"sh": @[@"media:shell;textable;code"],
        @"bash": @[@"media:shell;textable;code"],
        @"zsh": @[@"media:zsh;textable;code"],
        @"fish": @[@"media:fish;textable;code"],
        @"sql": @[@"media:sql;textable;code"],
        @"kt": @[@"media:kotlin;textable;code"],
        @"kts": @[@"media:kotlin;textable;code"],
        @"scala": @[@"media:scala;textable;code"],
        @"sc": @[@"media:scala;textable;code"],
        @"cs": @[@"media:csharp;textable;code"],
        @"fs": @[@"media:fsharp;textable;code"],
        @"fsx": @[@"media:fsharp;textable;code"],
        @"hs": @[@"media:haskell;textable;code"],
        @"lhs": @[@"media:haskell;textable;code"],
        @"ex": @[@"media:elixir;textable;code"],
        @"exs": @[@"media:elixir;textable;code"],
        @"erl": @[@"media:erlang;textable;code"],
        @"hrl": @[@"media:erlang;textable;code"],
        @"lua": @[@"media:lua;textable;code"],
        @"pl": @[@"media:perl;textable;code"],
        @"pm": @[@"media:perl;textable;code"],
        @"r": @[@"media:r;textable;code"],
        @"jl": @[@"media:julia;textable;code"],
        @"zig": @[@"media:zig;textable;code"],
        @"nim": @[@"media:nim;textable;code"],
        @"dart": @[@"media:dart;textable;code"],
        @"vue": @[@"media:vue;textable;code"],
        @"svelte": @[@"media:svelte;textable;code"],
        @"astro": @[@"media:astro;textable;code"],
        @"clj": @[@"media:clojure;textable;code"],
        @"cljs": @[@"media:clojure;textable;code"],
        @"cljc": @[@"media:clojure;textable;code"],
        @"lisp": @[@"media:lisp;textable;code"],
        @"scm": @[@"media:scheme;textable;code"],
        @"ml": @[@"media:ocaml;textable;code"],
        @"mli": @[@"media:ocaml;textable;code"],
        @"vb": @[@"media:vb;textable;code"],

        // Build and config files
        @"makefile": @[@"media:makefile;textable"],
        @"cmake": @[@"media:cmake;textable"],
        @"dockerfile": @[@"media:dockerfile;textable"],
        @"gitignore": @[@"media:gitignore;list;textable"],
        @"dockerignore": @[@"media:dockerignore;list;textable"],
        @"editorconfig": @[@"media:editorconfig;textable"],

        // Archives
        @"zip": @[@"media:zip;archive"],
        @"tar": @[@"media:tar;archive"],
        @"gz": @[@"media:gzip;archive"],
        @"tgz": @[@"media:targz;archive"],
        @"bz2": @[@"media:bzip2;archive"],
        @"xz": @[@"media:xz;archive"],
        @"zst": @[@"media:zstd;archive"],
        @"zstd": @[@"media:zstd;archive"],
        @"7z": @[@"media:7z;archive"],
        @"rar": @[@"media:rar;archive"],
        @"jar": @[@"media:jar;archive"],
        @"war": @[@"media:war;archive"],
        @"dmg": @[@"media:dmg;archive"],
        @"iso": @[@"media:iso;archive"],
        @"deb": @[@"media:deb;archive"],
        @"rpm": @[@"media:rpm;archive"],
        @"pkg": @[@"media:pkg;archive"],
        @"apk": @[@"media:apk;archive"],
        @"ipa": @[@"media:ipa;archive"],
        @"lzma": @[@"media:lzma;archive"],

        // Fonts
        @"ttf": @[@"media:ttf;font"],
        @"otf": @[@"media:otf;font"],
        @"woff": @[@"media:woff;font"],
        @"woff2": @[@"media:woff2;font"],

        // 3D Models
        @"obj": @[@"media:obj;model3d"],
        @"stl": @[@"media:stl;model3d"],
        @"fbx": @[@"media:fbx;model3d"],
        @"gltf": @[@"media:gltf;model3d"],
        @"glb": @[@"media:glb;model3d"],

        // ML Models
        @"onnx": @[@"media:onnx;mlmodel"],
        @"safetensors": @[@"media:safetensors;mlmodel"],
        @"gguf": @[@"media:gguf;mlmodel"],
        @"mlmodel": @[@"media:coreml;mlmodel"],
        @"pt": @[@"media:pytorch;mlmodel"],
        @"pth": @[@"media:pytorch;mlmodel"],
        @"h5": @[@"media:hdf5;mlmodel"],
        @"hdf5": @[@"media:hdf5;mlmodel"],

        // Data formats
        @"sqlite": @[@"media:sqlite;database"],
        @"db": @[@"media:sqlite;database"],
        @"sqlite3": @[@"media:sqlite;database"],
        @"parquet": @[@"media:parquet;columnar"],
        @"arrow": @[@"media:arrow;columnar"],
        @"avro": @[@"media:avro;columnar"],
        @"npy": @[@"media:numpy;data"],
        @"npz": @[@"media:numpy;data"],
        @"msgpack": @[@"media:msgpack;binary"],
        @"cbor": @[@"media:cbor;binary"],
        @"protobuf": @[@"media:protobuf;binary"],
        @"proto": @[@"media:protobuf;textable"],

        // Certificates
        @"pem": @[@"media:pem;certificate"],
        @"crt": @[@"media:pem;certificate"],
        @"cer": @[@"media:pem;certificate"],
        @"p12": @[@"media:pkcs12;certificate"],
        @"pfx": @[@"media:pkcs12;certificate"],

        // Geo
        @"geojson": @[@"media:geojson;record;textable"],
        @"gpx": @[@"media:gpx;record;textable"],
        @"kml": @[@"media:kml;record;textable"],

        // Subtitles
        @"srt": @[@"media:srt;list;textable"],
        @"vtt": @[@"media:vtt;list;textable"],
        @"ass": @[@"media:ass;textable"],

        // Email
        @"eml": @[@"media:eml;email"],
        @"mbox": @[@"media:mbox;email"],

        // Notebooks
        @"ipynb": @[@"media:jupyter;notebook"],

        // WebAssembly
        @"wasm": @[@"media:wasm;binary"],
        @"wat": @[@"media:wat;textable"],

        // Diagrams
        @"dot": @[@"media:dot;textable"],
        @"mermaid": @[@"media:mermaid;textable"],

        // Calendar
        @"ics": @[@"media:ics;textable"],
        @"vcf": @[@"media:vcf;textable"],

        // Requirements
        @"requirements": @[@"media:requirements;list;textable"],
    };
}

- (NSArray<NSString *> *)mediaUrnsForExtension:(NSString *)extension {
    NSString *ext = [extension lowercaseString];
    NSArray<NSString *> *urns = _extensionIndex[ext];
    return urns ?: @[];
}

- (nullable NSString *)primaryMediaUrnForExtension:(NSString *)extension {
    NSArray<NSString *> *urns = [self mediaUrnsForExtension:extension];
    return urns.firstObject;
}

- (BOOL)hasExtension:(NSString *)extension {
    NSString *ext = [extension lowercaseString];
    return _extensionIndex[ext] != nil;
}

- (NSArray<NSString *> *)allExtensions {
    return [_extensionIndex allKeys];
}

@end

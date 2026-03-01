//
//  CSInputResolverTests.m
//  CapDAG
//
//  Tests for CSInputResolver module
//  Test numbers match capdag Rust tests (TEST1000-TEST1099)
//

#import <XCTest/XCTest.h>
#import "CSInputResolver.h"

@interface CSInputResolverTests : XCTestCase
@property (nonatomic, strong) NSString *testDir;
@property (nonatomic, strong) NSFileManager *fm;
@end

@implementation CSInputResolverTests

- (void)setUp {
    [super setUp];
    self.fm = [NSFileManager defaultManager];

    // Create temp directory for test files
    NSString *tempDir = NSTemporaryDirectory();
    self.testDir = [tempDir stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [self.fm createDirectoryAtPath:self.testDir withIntermediateDirectories:YES attributes:nil error:nil];
}

- (void)tearDown {
    // Clean up test directory
    [self.fm removeItemAtPath:self.testDir error:nil];
    [super tearDown];
}

#pragma mark - Helper Methods

- (NSString *)createTestFile:(NSString *)name content:(NSString *)content {
    NSString *path = [self.testDir stringByAppendingPathComponent:name];
    [content writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    return path;
}

- (NSString *)createTestDir:(NSString *)name {
    NSString *path = [self.testDir stringByAppendingPathComponent:name];
    [self.fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    return path;
}

#pragma mark - OS File Filter Tests (TEST1020-TEST1029)

- (void)test1020_macos_ds_store {
    // TEST1020: macOS .DS_Store should be excluded
    XCTAssertTrue(CSInputResolverShouldExcludeFile(@"/path/.DS_Store"));
    XCTAssertTrue(CSInputResolverShouldExcludeFile(@".DS_Store"));
}

- (void)test1021_windows_thumbs_db {
    // TEST1021: Windows Thumbs.db should be excluded
    XCTAssertTrue(CSInputResolverShouldExcludeFile(@"/path/Thumbs.db"));
    XCTAssertTrue(CSInputResolverShouldExcludeFile(@"Thumbs.db"));
}

- (void)test1022_macos_resource_fork {
    // TEST1022: macOS resource fork (._*) should be excluded
    XCTAssertTrue(CSInputResolverShouldExcludeFile(@"/path/._file"));
    XCTAssertTrue(CSInputResolverShouldExcludeFile(@"._document.pdf"));
}

- (void)test1023_office_lock_file {
    // TEST1023: Office lock file (~$*) should be excluded
    XCTAssertTrue(CSInputResolverShouldExcludeFile(@"/path/~$document.docx"));
    XCTAssertTrue(CSInputResolverShouldExcludeFile(@"~$file.xlsx"));
}

- (void)test1024_git_directory {
    // TEST1024: .git directory should be excluded
    XCTAssertTrue(CSInputResolverShouldExcludeDirectory(@"/path/.git"));
    XCTAssertTrue(CSInputResolverShouldExcludeDirectory(@".git"));
}

- (void)test1025_macosx_archive {
    // TEST1025: __MACOSX archive artifact should be excluded
    XCTAssertTrue(CSInputResolverShouldExcludeDirectory(@"/path/__MACOSX"));
    XCTAssertTrue(CSInputResolverShouldExcludeDirectory(@"__MACOSX"));
}

- (void)test1026_temp_files {
    // TEST1026: Temp files should be excluded
    XCTAssertTrue(CSInputResolverShouldExcludeFile(@"/path/file.tmp"));
    XCTAssertTrue(CSInputResolverShouldExcludeFile(@"document.temp"));
}

- (void)test1027_localized {
    // TEST1027: .localized should be excluded
    XCTAssertTrue(CSInputResolverShouldExcludeFile(@"/path/.localized"));
}

- (void)test1028_desktop_ini {
    // TEST1028: desktop.ini should be excluded
    XCTAssertTrue(CSInputResolverShouldExcludeFile(@"/path/desktop.ini"));
}

- (void)test1029_content_files_not_excluded {
    // TEST1029: Content files should NOT be excluded
    XCTAssertFalse(CSInputResolverShouldExcludeFile(@"/path/file.json"));
    XCTAssertFalse(CSInputResolverShouldExcludeFile(@"/path/file.txt"));
    XCTAssertFalse(CSInputResolverShouldExcludeFile(@"/path/file.pdf"));
    XCTAssertFalse(CSInputResolverShouldExcludeFile(@"/path/file.log"));
    XCTAssertFalse(CSInputResolverShouldExcludeFile(@"/path/file.md"));
}

#pragma mark - JSON Detection Tests (TEST1030-TEST1044)

- (void)test1030_json_empty_object {
    // TEST1030: Empty object should be ScalarRecord
    NSString *path = [self createTestFile:@"test.json" content:@"{}"];
    CSContentStructure structure;
    NSError *error;

    NSString *mediaUrn = CSInputResolverDetectFile(path, &structure, &error);

    XCTAssertNil(error);
    XCTAssertEqualObjects(mediaUrn, @"media:json;record;textable");
    XCTAssertEqual(structure, CSContentStructureScalarRecord);
}

- (void)test1031_json_simple_object {
    // TEST1031: Simple object should be ScalarRecord
    NSString *path = [self createTestFile:@"test.json" content:@"{\"a\":1}"];
    CSContentStructure structure;
    NSError *error;

    NSString *mediaUrn = CSInputResolverDetectFile(path, &structure, &error);

    XCTAssertNil(error);
    XCTAssertEqualObjects(mediaUrn, @"media:json;record;textable");
    XCTAssertEqual(structure, CSContentStructureScalarRecord);
}

- (void)test1033_json_empty_array {
    // TEST1033: Empty array should be ListOpaque
    NSString *path = [self createTestFile:@"test.json" content:@"[]"];
    CSContentStructure structure;
    NSError *error;

    NSString *mediaUrn = CSInputResolverDetectFile(path, &structure, &error);

    XCTAssertNil(error);
    XCTAssertEqualObjects(mediaUrn, @"media:json;list;textable");
    XCTAssertEqual(structure, CSContentStructureListOpaque);
}

- (void)test1034_json_array_of_primitives {
    // TEST1034: Array of primitives should be ListOpaque
    NSString *path = [self createTestFile:@"test.json" content:@"[1,2,3]"];
    CSContentStructure structure;
    NSError *error;

    NSString *mediaUrn = CSInputResolverDetectFile(path, &structure, &error);

    XCTAssertNil(error);
    XCTAssertEqualObjects(mediaUrn, @"media:json;list;textable");
    XCTAssertEqual(structure, CSContentStructureListOpaque);
}

- (void)test1035_json_array_of_strings {
    // TEST1035: Array of strings should be ListOpaque
    NSString *path = [self createTestFile:@"test.json" content:@"[\"a\",\"b\"]"];
    CSContentStructure structure;
    NSError *error;

    NSString *mediaUrn = CSInputResolverDetectFile(path, &structure, &error);

    XCTAssertNil(error);
    XCTAssertEqualObjects(mediaUrn, @"media:json;list;textable");
    XCTAssertEqual(structure, CSContentStructureListOpaque);
}

- (void)test1036_json_array_of_objects {
    // TEST1036: Array of objects should be ListRecord
    NSString *path = [self createTestFile:@"test.json" content:@"[{\"a\":1}]"];
    CSContentStructure structure;
    NSError *error;

    NSString *mediaUrn = CSInputResolverDetectFile(path, &structure, &error);

    XCTAssertNil(error);
    XCTAssertEqualObjects(mediaUrn, @"media:json;list;record;textable");
    XCTAssertEqual(structure, CSContentStructureListRecord);
}

- (void)test1038_json_string_primitive {
    // TEST1038: String primitive should be ScalarOpaque
    NSString *path = [self createTestFile:@"test.json" content:@"\"hello\""];
    CSContentStructure structure;
    NSError *error;

    NSString *mediaUrn = CSInputResolverDetectFile(path, &structure, &error);

    XCTAssertNil(error);
    XCTAssertEqualObjects(mediaUrn, @"media:json;textable");
    XCTAssertEqual(structure, CSContentStructureScalarOpaque);
}

- (void)test1039_json_number_primitive {
    // TEST1039: Number primitive should be ScalarOpaque
    NSString *path = [self createTestFile:@"test.json" content:@"42"];
    CSContentStructure structure;
    NSError *error;

    NSString *mediaUrn = CSInputResolverDetectFile(path, &structure, &error);

    XCTAssertNil(error);
    XCTAssertEqualObjects(mediaUrn, @"media:json;textable");
    XCTAssertEqual(structure, CSContentStructureScalarOpaque);
}

- (void)test1040_json_boolean_true {
    // TEST1040: Boolean true should be ScalarOpaque
    NSString *path = [self createTestFile:@"test.json" content:@"true"];
    CSContentStructure structure;
    NSError *error;

    NSString *mediaUrn = CSInputResolverDetectFile(path, &structure, &error);

    XCTAssertNil(error);
    XCTAssertEqualObjects(mediaUrn, @"media:json;textable");
    XCTAssertEqual(structure, CSContentStructureScalarOpaque);
}

- (void)test1042_json_null {
    // TEST1042: Null should be ScalarOpaque
    NSString *path = [self createTestFile:@"test.json" content:@"null"];
    CSContentStructure structure;
    NSError *error;

    NSString *mediaUrn = CSInputResolverDetectFile(path, &structure, &error);

    XCTAssertNil(error);
    XCTAssertEqualObjects(mediaUrn, @"media:json;textable");
    XCTAssertEqual(structure, CSContentStructureScalarOpaque);
}

#pragma mark - NDJSON Detection Tests (TEST1045-TEST1054)

- (void)test1045_ndjson_objects_only {
    // TEST1045: NDJSON with objects should be ListRecord
    NSString *path = [self createTestFile:@"test.ndjson" content:@"{\"a\":1}\n{\"b\":2}"];
    CSContentStructure structure;
    NSError *error;

    NSString *mediaUrn = CSInputResolverDetectFile(path, &structure, &error);

    XCTAssertNil(error);
    XCTAssertEqualObjects(mediaUrn, @"media:ndjson;list;record;textable");
    XCTAssertEqual(structure, CSContentStructureListRecord);
}

- (void)test1046_ndjson_single_object {
    // TEST1046: Single object NDJSON should be ListRecord
    NSString *path = [self createTestFile:@"test.ndjson" content:@"{\"a\":1}"];
    CSContentStructure structure;
    NSError *error;

    NSString *mediaUrn = CSInputResolverDetectFile(path, &structure, &error);

    XCTAssertNil(error);
    XCTAssertEqualObjects(mediaUrn, @"media:ndjson;list;record;textable");
    XCTAssertEqual(structure, CSContentStructureListRecord);
}

- (void)test1047_ndjson_primitives_only {
    // TEST1047: NDJSON with primitives should be ListOpaque
    NSString *path = [self createTestFile:@"test.ndjson" content:@"1\n2\n3"];
    CSContentStructure structure;
    NSError *error;

    NSString *mediaUrn = CSInputResolverDetectFile(path, &structure, &error);

    XCTAssertNil(error);
    XCTAssertEqualObjects(mediaUrn, @"media:ndjson;list;textable");
    XCTAssertEqual(structure, CSContentStructureListOpaque);
}

#pragma mark - CSV Detection Tests (TEST1055-TEST1064)

- (void)test1055_csv_multi_column {
    // TEST1055: Multi-column CSV should be ListRecord
    NSString *path = [self createTestFile:@"test.csv" content:@"a,b\n1,2"];
    CSContentStructure structure;
    NSError *error;

    NSString *mediaUrn = CSInputResolverDetectFile(path, &structure, &error);

    XCTAssertNil(error);
    XCTAssertEqualObjects(mediaUrn, @"media:csv;list;record;textable");
    XCTAssertEqual(structure, CSContentStructureListRecord);
}

- (void)test1056_csv_single_column {
    // TEST1056: Single column CSV should be ListOpaque
    NSString *path = [self createTestFile:@"test.csv" content:@"value\n1\n2"];
    CSContentStructure structure;
    NSError *error;

    NSString *mediaUrn = CSInputResolverDetectFile(path, &structure, &error);

    XCTAssertNil(error);
    XCTAssertEqualObjects(mediaUrn, @"media:csv;list;textable");
    XCTAssertEqual(structure, CSContentStructureListOpaque);
}

#pragma mark - YAML Detection Tests (TEST1065-TEST1074)

- (void)test1065_yaml_simple_mapping {
    // TEST1065: Simple YAML mapping should be ScalarRecord
    NSString *path = [self createTestFile:@"test.yaml" content:@"a: 1"];
    CSContentStructure structure;
    NSError *error;

    NSString *mediaUrn = CSInputResolverDetectFile(path, &structure, &error);

    XCTAssertNil(error);
    XCTAssertEqualObjects(mediaUrn, @"media:yaml;record;textable");
    XCTAssertEqual(structure, CSContentStructureScalarRecord);
}

- (void)test1067_yaml_sequence_of_scalars {
    // TEST1067: YAML sequence of scalars should be ListOpaque
    NSString *path = [self createTestFile:@"test.yaml" content:@"- a\n- b"];
    CSContentStructure structure;
    NSError *error;

    NSString *mediaUrn = CSInputResolverDetectFile(path, &structure, &error);

    XCTAssertNil(error);
    XCTAssertEqualObjects(mediaUrn, @"media:yaml;list;textable");
    XCTAssertEqual(structure, CSContentStructureListOpaque);
}

- (void)test1068_yaml_sequence_of_mappings {
    // TEST1068: YAML sequence of mappings should be ListRecord
    NSString *path = [self createTestFile:@"test.yaml" content:@"- a: 1\n- b: 2"];
    CSContentStructure structure;
    NSError *error;

    NSString *mediaUrn = CSInputResolverDetectFile(path, &structure, &error);

    XCTAssertNil(error);
    XCTAssertEqualObjects(mediaUrn, @"media:yaml;list;record;textable");
    XCTAssertEqual(structure, CSContentStructureListRecord);
}

#pragma mark - Extension Mapping Tests (TEST1080-TEST1089)

- (void)test1080_pdf_extension {
    // TEST1080: PDF extension should map to media:pdf
    // Create minimal PDF-like file (we can't test magic bytes easily in CI)
    NSString *path = [self createTestFile:@"test.pdf" content:@"%PDF-1.4"];
    CSContentStructure structure;
    NSError *error;

    NSString *mediaUrn = CSInputResolverDetectFile(path, &structure, &error);

    XCTAssertNil(error);
    XCTAssertEqualObjects(mediaUrn, @"media:pdf");
    XCTAssertEqual(structure, CSContentStructureScalarOpaque);
}

- (void)test1081_png_extension {
    // TEST1081: PNG extension should map to media:png;image
    NSString *path = [self createTestFile:@"test.png" content:@""];
    CSContentStructure structure;
    NSError *error;

    NSString *mediaUrn = CSInputResolverDetectFile(path, &structure, &error);

    XCTAssertNil(error);
    XCTAssertEqualObjects(mediaUrn, @"media:png;image");
    XCTAssertEqual(structure, CSContentStructureScalarOpaque);
}

- (void)test1082_mp3_extension {
    // TEST1082: MP3 extension should map to media:mp3;audio
    NSString *path = [self createTestFile:@"test.mp3" content:@""];
    CSContentStructure structure;
    NSError *error;

    NSString *mediaUrn = CSInputResolverDetectFile(path, &structure, &error);

    XCTAssertNil(error);
    XCTAssertEqualObjects(mediaUrn, @"media:mp3;audio");
    XCTAssertEqual(structure, CSContentStructureScalarOpaque);
}

- (void)test1083_mp4_extension {
    // TEST1083: MP4 extension should map to media:mp4;video
    NSString *path = [self createTestFile:@"test.mp4" content:@""];
    CSContentStructure structure;
    NSError *error;

    NSString *mediaUrn = CSInputResolverDetectFile(path, &structure, &error);

    XCTAssertNil(error);
    XCTAssertEqualObjects(mediaUrn, @"media:mp4;video");
    XCTAssertEqual(structure, CSContentStructureScalarOpaque);
}

- (void)test1084_rust_extension {
    // TEST1084: Rust extension should map to media:rust;textable;code
    NSString *path = [self createTestFile:@"test.rs" content:@"fn main() {}"];
    CSContentStructure structure;
    NSError *error;

    NSString *mediaUrn = CSInputResolverDetectFile(path, &structure, &error);

    XCTAssertNil(error);
    XCTAssertEqualObjects(mediaUrn, @"media:rust;textable;code");
    XCTAssertEqual(structure, CSContentStructureScalarOpaque);
}

- (void)test1085_python_extension {
    // TEST1085: Python extension should map to media:python;textable;code
    NSString *path = [self createTestFile:@"test.py" content:@"print('hello')"];
    CSContentStructure structure;
    NSError *error;

    NSString *mediaUrn = CSInputResolverDetectFile(path, &structure, &error);

    XCTAssertNil(error);
    XCTAssertEqualObjects(mediaUrn, @"media:python;textable;code");
    XCTAssertEqual(structure, CSContentStructureScalarOpaque);
}

- (void)test1086_markdown_extension {
    // TEST1086: Markdown extension should map to media:md;textable
    NSString *path = [self createTestFile:@"test.md" content:@"# Hello"];
    CSContentStructure structure;
    NSError *error;

    NSString *mediaUrn = CSInputResolverDetectFile(path, &structure, &error);

    XCTAssertNil(error);
    XCTAssertEqualObjects(mediaUrn, @"media:md;textable");
    XCTAssertEqual(structure, CSContentStructureScalarOpaque);
}

- (void)test1087_toml_always_record {
    // TEST1087: TOML is always record
    NSString *path = [self createTestFile:@"test.toml" content:@"key = \"value\""];
    CSContentStructure structure;
    NSError *error;

    NSString *mediaUrn = CSInputResolverDetectFile(path, &structure, &error);

    XCTAssertNil(error);
    XCTAssertEqualObjects(mediaUrn, @"media:toml;record;textable");
    XCTAssertEqual(structure, CSContentStructureScalarRecord);
}

- (void)test1088_log_file_is_list {
    // TEST1088: Log file is always list
    NSString *path = [self createTestFile:@"test.log" content:@"line1\nline2"];
    CSContentStructure structure;
    NSError *error;

    NSString *mediaUrn = CSInputResolverDetectFile(path, &structure, &error);

    XCTAssertNil(error);
    XCTAssertEqualObjects(mediaUrn, @"media:log;list;textable");
    XCTAssertEqual(structure, CSContentStructureListOpaque);
}

- (void)test1089_unknown_extension {
    // TEST1089: Unknown extension should fallback
    NSString *path = [self createTestFile:@"test.xyz" content:@"unknown content"];
    CSContentStructure structure;
    NSError *error;

    NSString *mediaUrn = CSInputResolverDetectFile(path, &structure, &error);

    XCTAssertNil(error);
    XCTAssertEqualObjects(mediaUrn, @"media:");
    XCTAssertEqual(structure, CSContentStructureScalarOpaque);
}

#pragma mark - Path Resolution Tests (TEST1000-TEST1019)

- (void)test1000_single_existing_file {
    // TEST1000: Single existing file should resolve
    NSString *path = [self createTestFile:@"test.txt" content:@"hello"];
    NSError *error;

    CSResolvedInputSet *result = CSInputResolverResolvePath(path, &error);

    XCTAssertNil(error);
    XCTAssertNotNil(result);
    XCTAssertEqual(result.files.count, 1);
    XCTAssertEqualObjects(result.files[0].path, path);
}

- (void)test1001_single_nonexistent_file {
    // TEST1001: Non-existent file should error
    NSString *path = [self.testDir stringByAppendingPathComponent:@"missing.txt"];
    NSError *error;

    CSResolvedInputSet *result = CSInputResolverResolvePath(path, &error);

    XCTAssertNotNil(error);
    XCTAssertNil(result);
    XCTAssertEqual(error.code, CSInputResolverErrorNotFound);
}

- (void)test1002_empty_directory {
    // TEST1002: Empty directory should error with NoFilesResolved
    NSString *dir = [self createTestDir:@"empty"];
    NSError *error;

    CSResolvedInputSet *result = CSInputResolverResolvePath(dir, &error);

    XCTAssertNotNil(error);
    XCTAssertNil(result);
    XCTAssertEqual(error.code, CSInputResolverErrorNoFilesResolved);
}

- (void)test1003_directory_with_files {
    // TEST1003: Directory with files should resolve
    NSString *dir = [self createTestDir:@"docs"];
    [self createTestFile:@"docs/file1.txt" content:@"one"];
    [self createTestFile:@"docs/file2.txt" content:@"two"];
    NSError *error;

    CSResolvedInputSet *result = CSInputResolverResolvePath(dir, &error);

    XCTAssertNil(error);
    XCTAssertNotNil(result);
    XCTAssertEqual(result.files.count, 2);
    XCTAssertEqual(result.cardinality, CSInputCardinalitySequence);
}

- (void)test1010_duplicate_paths {
    // TEST1010: Duplicate paths should be deduplicated
    NSString *path = [self createTestFile:@"test.txt" content:@"hello"];
    NSError *error;

    CSResolvedInputSet *result = CSInputResolverResolvePaths(@[path, path], &error);

    XCTAssertNil(error);
    XCTAssertNotNil(result);
    XCTAssertEqual(result.files.count, 1);
}

- (void)test1013_empty_input_array {
    // TEST1013: Empty input should error
    NSError *error;

    CSResolvedInputSet *result = CSInputResolverResolvePaths(@[], &error);

    XCTAssertNotNil(error);
    XCTAssertNil(result);
    XCTAssertEqual(error.code, CSInputResolverErrorEmptyInput);
}

#pragma mark - Aggregate Cardinality Tests (TEST1090-TEST1099)

- (void)test1090_single_file_scalar {
    // TEST1090: Single file with scalar content should be Single
    NSString *path = [self createTestFile:@"test.pdf" content:@"%PDF-1.4"];
    NSError *error;

    CSResolvedInputSet *result = CSInputResolverResolvePath(path, &error);

    XCTAssertNil(error);
    XCTAssertNotNil(result);
    XCTAssertEqual(result.cardinality, CSInputCardinalitySingle);
}

- (void)test1091_single_file_list_content {
    // TEST1091: Single file with list content should be Sequence
    NSString *path = [self createTestFile:@"test.csv" content:@"a,b\n1,2\n3,4"];
    NSError *error;

    CSResolvedInputSet *result = CSInputResolverResolvePath(path, &error);

    XCTAssertNil(error);
    XCTAssertNotNil(result);
    XCTAssertEqual(result.cardinality, CSInputCardinalitySequence);
}

- (void)test1092_two_files {
    // TEST1092: Two files should be Sequence
    [self createTestFile:@"file1.txt" content:@"one"];
    NSString *path2 = [self createTestFile:@"file2.txt" content:@"two"];
    NSString *path1 = [self.testDir stringByAppendingPathComponent:@"file1.txt"];
    NSError *error;

    CSResolvedInputSet *result = CSInputResolverResolvePaths(@[path1, path2], &error);

    XCTAssertNil(error);
    XCTAssertNotNil(result);
    XCTAssertEqual(result.files.count, 2);
    XCTAssertEqual(result.cardinality, CSInputCardinalitySequence);
}

- (void)test1093_dir_single_file {
    // TEST1093: Directory with 1 file should be Single
    NSString *dir = [self createTestDir:@"single"];
    [self createTestFile:@"single/only.pdf" content:@"%PDF"];
    NSError *error;

    CSResolvedInputSet *result = CSInputResolverResolvePath(dir, &error);

    XCTAssertNil(error);
    XCTAssertNotNil(result);
    XCTAssertEqual(result.files.count, 1);
    XCTAssertEqual(result.cardinality, CSInputCardinalitySingle);
}

- (void)test1094_dir_multiple_files {
    // TEST1094: Directory with 3 files should be Sequence
    NSString *dir = [self createTestDir:@"multi"];
    [self createTestFile:@"multi/a.txt" content:@"a"];
    [self createTestFile:@"multi/b.txt" content:@"b"];
    [self createTestFile:@"multi/c.txt" content:@"c"];
    NSError *error;

    CSResolvedInputSet *result = CSInputResolverResolvePath(dir, &error);

    XCTAssertNil(error);
    XCTAssertNotNil(result);
    XCTAssertEqual(result.files.count, 3);
    XCTAssertEqual(result.cardinality, CSInputCardinalitySequence);
}

- (void)test1098_common_media {
    // TEST1098: All same media type should have commonMedia
    NSString *dir = [self createTestDir:@"pdfs"];
    [self createTestFile:@"pdfs/a.pdf" content:@"%PDF"];
    [self createTestFile:@"pdfs/b.pdf" content:@"%PDF"];
    NSError *error;

    CSResolvedInputSet *result = CSInputResolverResolvePath(dir, &error);

    XCTAssertNil(error);
    XCTAssertNotNil(result);
    XCTAssertEqualObjects(result.commonMedia, @"media:pdf");
    XCTAssertTrue([result isHomogeneous]);
}

- (void)test1099_heterogeneous {
    // TEST1099: Mixed media types should not have commonMedia
    NSString *dir = [self createTestDir:@"mixed"];
    [self createTestFile:@"mixed/doc.pdf" content:@"%PDF"];
    [self createTestFile:@"mixed/image.png" content:@""];
    NSError *error;

    CSResolvedInputSet *result = CSInputResolverResolvePath(dir, &error);

    XCTAssertNil(error);
    XCTAssertNotNil(result);
    XCTAssertNil(result.commonMedia);
    XCTAssertFalse([result isHomogeneous]);
}

#pragma mark - Glob Pattern Tests

- (void)test_glob_pattern_detection {
    // Test glob pattern detection
    XCTAssertTrue(CSInputResolverIsGlobPattern(@"*.txt"));
    XCTAssertTrue(CSInputResolverIsGlobPattern(@"file?.pdf"));
    XCTAssertTrue(CSInputResolverIsGlobPattern(@"doc[1-3].txt"));
    XCTAssertFalse(CSInputResolverIsGlobPattern(@"/path/to/file.txt"));
    XCTAssertFalse(CSInputResolverIsGlobPattern(@"regular_file.pdf"));
}

#pragma mark - CSResolvedFile Tests

- (void)test_resolved_file_properties {
    CSResolvedFile *file = [CSResolvedFile fileWithPath:@"/test.csv"
                                               mediaUrn:@"media:csv;list;record;textable"
                                              sizeBytes:1024
                                       contentStructure:CSContentStructureListRecord];

    XCTAssertTrue([file isList]);
    XCTAssertTrue([file isRecord]);
    XCTAssertEqualObjects(file.path, @"/test.csv");
    XCTAssertEqual(file.sizeBytes, 1024);
}

- (void)test_resolved_file_scalar_opaque {
    CSResolvedFile *file = [CSResolvedFile fileWithPath:@"/test.pdf"
                                               mediaUrn:@"media:pdf"
                                              sizeBytes:2048
                                       contentStructure:CSContentStructureScalarOpaque];

    XCTAssertFalse([file isList]);
    XCTAssertFalse([file isRecord]);
}

#pragma mark - CSResolvedInputSet Tests

- (void)test_resolved_input_set_total_size {
    CSResolvedFile *file1 = [CSResolvedFile fileWithPath:@"/a.txt"
                                                mediaUrn:@"media:txt"
                                               sizeBytes:100
                                        contentStructure:CSContentStructureScalarOpaque];
    CSResolvedFile *file2 = [CSResolvedFile fileWithPath:@"/b.txt"
                                                mediaUrn:@"media:txt"
                                               sizeBytes:200
                                        contentStructure:CSContentStructureScalarOpaque];

    CSResolvedInputSet *set = [CSResolvedInputSet setWithFiles:@[file1, file2]
                                                   cardinality:CSInputCardinalitySequence
                                                   commonMedia:@"media:txt"];

    XCTAssertEqual([set totalSize], 300);
    XCTAssertTrue([set isHomogeneous]);
}

@end

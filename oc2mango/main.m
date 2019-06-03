//
//  main.m
//  oc2mango
//
//  Created by Jiang on 2019/4/10.
//  Copyright © 2019年 SilverFruity. All rights reserved.
//
#import <Foundation/Foundation.h>
#import <oc2mangoLib/oc2mangoLib.h>
#import "NSArray+Functional.h"
void recursiveLookupCompileFiles(NSString *path,NSMutableArray *dirs,NSMutableArray *files){
    BOOL isDir;
    if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir]) {
        if ([@[@"h",@"m",@"preprocesser"] containsObject:path.pathExtension.lowercaseString]) {
            if (files) {
                [files addObject:path];
            }
        }else if (isDir) {
            if (dirs) {
                [dirs addObject:path];
            }
            NSError *error;
            NSArray <NSString *> *filenames = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:path error:&error];
            for (NSString *filename in filenames) {
                recursiveLookupCompileFiles([path stringByAppendingPathComponent:filename],dirs,files);
            }
            return;
        }
    }
}

@interface FileProcesssManager:NSObject
@property (nonatomic,copy) NSString *root;
@property (nonatomic,strong) NSMutableArray *dirs;
@property (nonatomic,strong) NSMutableArray *files;
@property (nonatomic,strong) NSMutableArray *implementationFiles;
@property (nonatomic,copy) NSString *preprocesserResultRoot;
@end

@implementation FileProcesssManager
- (instancetype)initWithRootDir:(NSString *)dir{
    self = [super init];
    self.root = dir;
    self.dirs = [NSMutableArray array];
    self.files = [NSMutableArray array];
    return self;
}
- (void)recursiveLookupRootDir{
    recursiveLookupCompileFiles(self.root, self.dirs, self.files);
}
- (NSString *)preprocesserResultRoot{
    if (!_preprocesserResultRoot) {
        _preprocesserResultRoot = [NSString stringWithFormat:@"%@/preprocesser",self.root];
        [[NSFileManager defaultManager] createDirectoryAtPath:_preprocesserResultRoot withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return _preprocesserResultRoot;
}
- (void)preprocessor{
    NSString *dirPaths = [self.dirs reduce:@"" map:^id(id object1, id object2) {
        return [NSString stringWithFormat:@"%@ -I%@",object1,object2];
    }];
    for (NSString *file in self.implementationFiles) {
        NSString *filename = [[file lastPathComponent] componentsSeparatedByString:@"."].firstObject;
        filename = [NSString stringWithFormat:@"%@.preprocesser",filename];
        NSString *output = [self.preprocesserResultRoot stringByAppendingPathComponent:filename];
        if ([[NSFileManager defaultManager] fileExistsAtPath:output]) {
            continue;
        }
        NSString *command = [NSString stringWithFormat:@"clang -E %@ %@ -o %@",file,dirPaths,output];
        [self shellCommand:command];
    }
}

- (void)convert:(NSMutableArray *)files{
    NSMutableArray *failedFiles = [NSMutableArray array];
    for (NSString *path in files) {
        NSData *data = [NSData dataWithContentsOfFile:path];
        [OCParser parseSource:[[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding]];
        if (!OCParser.isSuccess) {
            [failedFiles addObject:path];
        }
    }
    if (OCParser.isSuccess) {
        return;
    }
}
- (NSString *)shellCommand:(NSString *)cmd{
    // 初始化并设置shell路径
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath: @"/bin/bash"];
    // -c 用来执行string-commands（命令字符串），也就说不管后面的字符串里是什么都会被当做shellcode来执行
    NSArray *arguments = [NSArray arrayWithObjects: @"-c", cmd, nil];
    [task setArguments: arguments];
    
    // 新建输出管道作为Task的输出
    NSPipe *pipe = [NSPipe pipe];
    [task setStandardOutput: pipe];
    
    // 开始task
    NSFileHandle *file = [pipe fileHandleForReading];
    [task launch];
    
    // 获取运行结果
    NSData *data = [file readDataToEndOfFile];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}
- (NSMutableArray *)implementationFiles{
    if (!_implementationFiles) {
        _implementationFiles =  [_files filter:^BOOL(NSUInteger index, NSString *path) {
            return [path.pathExtension.lowercaseString isEqualToString:@"m"];
        }];
    }
    return _implementationFiles;
}
@end






int main(int argc, const char * argv[]) {
    NSString *path  = [NSString stringWithUTF8String:argv[1]];
    FileProcesssManager *manager = [[FileProcesssManager alloc] initWithRootDir:path];
    [manager recursiveLookupRootDir];
    [manager preprocessor];
    NSMutableArray *precessorfiles = [NSMutableArray array];
    recursiveLookupCompileFiles(manager.preprocesserResultRoot, nil, precessorfiles);
    [manager convert:precessorfiles];
    if (!OCParser.isSuccess) {
        return 0;
    }
    return 1;
}



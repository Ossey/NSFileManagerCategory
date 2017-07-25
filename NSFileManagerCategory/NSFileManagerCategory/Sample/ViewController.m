//
//  ViewController.m
//  NSFileManagerCategory
//
//  Created by xiaoyuan on 2017/7/25.
//  Copyright © 2017年 xiaoyuan. All rights reserved.
//

#import "ViewController.h"
#import "NSFileManager+FileOperationExtend.h"

static void * FileProgressObserverContext = &FileProgressObserverContext;

@interface FileAttributeItem : NSObject

@property (nonatomic, copy) NSString *fullPath;
@property (nonatomic, assign) int64_t totalFileSize;
@property (nonatomic, assign) int64_t receivedFileSize;
@property (nonatomic, assign) NSUInteger subFileCount;


- (NSProgress *)addProgress;

@end


@interface ViewController ()

@property (nonatomic, strong) NSProgress *fileProgress;
@property (nonatomic, strong) NSOperationQueue *loadFileQueue;
@property (nonatomic, strong) NSFileManager *fileManager;
@property (nonatomic, strong) NSMutableArray<FileAttributeItem *> *copyfiles;
@property (nonatomic, strong) UIProgressView *progressBar;
@property (nonatomic, strong) NSArray<FileAttributeItem *> *sourceFiles;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    _loadFileQueue = [NSOperationQueue new];
    _copyfiles = [NSMutableArray array];
    _fileProgress = [NSProgress progressWithTotalUnitCount:0];
    [_fileProgress addObserver:self
                    forKeyPath:NSStringFromSelector(@selector(fractionCompleted))
                       options:NSKeyValueObservingOptionInitial
                       context:FileProgressObserverContext];
    [self.view addSubview:self.progressBar];
    self.progressBar.translatesAutoresizingMaskIntoConstraints = NO;
    
    
    NSDictionary *viewsDictionary = @{@"progressBar": self.progressBar};
    CGFloat progressBarTopConst = 20.0;
    if (self.navigationController.isNavigationBarHidden) {
        progressBarTopConst = 64.0;
    }
    NSDictionary *metricsDictionary = @{@"progressBarTopConst" : [NSNumber numberWithFloat:progressBarTopConst]};
    [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"|[progressBar]|" options:NSLayoutFormatAlignAllLeading | NSLayoutFormatAlignAllRight metrics:nil views:viewsDictionary]];
    [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-progressBarTopConst-[progressBar]" options:kNilOptions metrics:metricsDictionary views:viewsDictionary]];

}


- (void)loadFile:(NSString *)path completion:(void (^)(NSArray<FileAttributeItem *> *files))completion {
    [_loadFileQueue addOperationWithBlock:^{
        BOOL isExist, isDirectory;
        isExist = [_fileManager fileExistsAtPath:path isDirectory:&isDirectory];
        if (!isExist || isDirectory) {
            if (completion) {
                completion(nil);
            }
            return;
        }
        NSMutableArray *array = [NSMutableArray array];
        NSError *error = nil;
        NSArray *tempFiles = [_fileManager contentsOfDirectoryAtPath:path error:&error];
        if (error) {
            NSLog(@"Error: %@", error);
        }
        NSArray *files = [self sortedFiles:tempFiles rootPath:path];
        [files enumerateObjectsUsingBlock:^(NSString * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            FileAttributeItem *model = [FileAttributeItem new];
            NSString *fullPath = [path stringByAppendingPathComponent:obj];
            model.fullPath = fullPath;
            NSError *error = nil;
            NSArray *subFiles = [_fileManager contentsOfDirectoryAtPath:fullPath error:&error];
            if (!error) {
                model.subFileCount = subFiles.count;
            }
            
            [array addObject:model];
        }];
        if (completion) {
            completion(array);
        }
    }];
}


- (IBAction)copyFile:(id)sender {
    
    [self loadFile:NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject completion:^(NSArray<FileAttributeItem *> *files) {
        
        [self copyFile:files toRootPath:NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject];
    }];
    
    
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}
////////////////////////////////////////////////////////////////////////
#pragma mark - Progress
////////////////////////////////////////////////////////////////////////

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    if (context == FileProgressObserverContext && object == self.fileProgress) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.progressBar.progress = [object fractionCompleted];
        });
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (void)copyFile:(NSArray<FileAttributeItem *> *)fileItems toRootPath:(NSString *)dstRootPath {
    
    [_copyfiles addObjectsFromArray:fileItems];
    
    [_loadFileQueue addOperationWithBlock:^{
        [self resetProgress];
        
        [fileItems enumerateObjectsUsingBlock:^(FileAttributeItem *  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            self.fileProgress.totalUnitCount++;
            [self.fileProgress becomeCurrentWithPendingUnitCount:1];
            [obj addProgress];
            /*
             obj.totalFileSize = [obj.fullPath fileSize];
             */
            NSDictionary *fileAttrs = [[NSFileManager defaultManager] attributesOfItemAtPath:obj.fullPath error:nil];
            obj.totalFileSize = [[fileAttrs objectForKey:NSFileSize] intValue];
            [self.fileProgress resignCurrent];
            
            NSString *desPath = [dstRootPath stringByAppendingPathComponent:[obj.fullPath lastPathComponent]];
            
            if ([desPath isEqualToString:obj.fullPath]) {
                NSLog(@"路径相同");
                obj.receivedFileSize = obj.totalFileSize;
                [_copyfiles removeObject:obj];
                return;
            }
            if ([_fileManager fileExistsAtPath:desPath]) {
                
                NSError *removeError = nil;
                [_fileManager removeItemAtPath:desPath error:&removeError];
                if (removeError) {
                    NSLog(@"Error: %@", removeError.localizedDescription);
                    obj.receivedFileSize = obj.totalFileSize;
                } else {
                    [_fileManager copyItemAtPath:obj.fullPath toPath:desPath handler:^(BOOL isFinishedCopy, unsigned long long receivedFileSize, NSError *error) {
                        obj.receivedFileSize = receivedFileSize;
                        if (isFinishedCopy) {
                            obj.receivedFileSize = obj.totalFileSize;
                        }
                        [_copyfiles removeObject:obj];
                    }];
                    
                }
            } else {
                [_fileManager copyItemAtPath:obj.fullPath toPath:desPath handler:^(BOOL isFinishedCopy, unsigned long long receivedFileSize, NSError *error) {
                    obj.receivedFileSize = receivedFileSize;
                    if (isFinishedCopy) {
                        obj.receivedFileSize = obj.totalFileSize;
                    }
                    [_copyfiles removeObject:obj];
                }];
            }
        }];
    }];
    
}

- (void)resetProgress {
    BOOL hasActiveFlag = [self copyfiles].count;
    if (hasActiveFlag == NO) {
        @try {
            [self.fileProgress removeObserver:self forKeyPath:NSStringFromSelector(@selector(fractionCompleted))];
        } @catch (NSException *exception) {
            NSLog(@"Error: Repeated removeObserver(keyPath = fractionCompleted)");
        } @finally {
            
        }
        
        self.fileProgress = [NSProgress progressWithTotalUnitCount:0];
        [self.fileProgress addObserver:self
                            forKeyPath:NSStringFromSelector(@selector(fractionCompleted))
                               options:NSKeyValueObservingOptionInitial
                               context:FileProgressObserverContext];
    }
}


- (UIProgressView *)progressBar {
    if (!_progressBar) {
        _progressBar = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
        _progressBar.progress = 0.0;
    }
    return _progressBar;
}

////////////////////////////////////////////////////////////////////////
#pragma mark - Sorted files
////////////////////////////////////////////////////////////////////////
- (NSArray *)sortedFiles:(NSArray *)files rootPath:(NSString *)rootPath {
    return [files sortedArrayWithOptions:NSSortConcurrent usingComparator:^NSComparisonResult(NSString* file1, NSString* file2) {
        NSString *newPath1 = [rootPath stringByAppendingPathComponent:file1];
        NSString *newPath2 = [rootPath stringByAppendingPathComponent:file2];
        
        BOOL isDirectory1, isDirectory2;
        [[NSFileManager defaultManager ] fileExistsAtPath:newPath1 isDirectory:&isDirectory1];
        [[NSFileManager defaultManager ] fileExistsAtPath:newPath2 isDirectory:&isDirectory2];
        
        if (isDirectory1 && !isDirectory2) {
            return NSOrderedAscending;
        }
        
        return  NSOrderedDescending;
    }];
}

- (void)dealloc {
    [self.fileProgress removeObserver:self forKeyPath:NSStringFromSelector(@selector(fractionCompleted))];
}
@end


@interface FileAttributeItem ()

@property (nonatomic, strong) NSProgress *progress;

@end

@implementation FileAttributeItem

- (NSProgress *)addProgress {
    if (self.progress) {
        self.progress = nil;
    }
    NSProgress *progress = [[NSProgress alloc] initWithParent:[NSProgress currentProgress]
                                                     userInfo:nil];
    progress.kind = NSProgressKindFile;
    [progress setUserInfoObject:NSProgressFileOperationKindKey
                         forKey:NSProgressFileOperationKindDownloading];
    [progress setUserInfoObject:self.fullPath forKey:@"fullPath"];
    progress.cancellable = NO;
    progress.pausable = NO;
    progress.totalUnitCount = NSURLSessionTransferSizeUnknown;
    progress.completedUnitCount = 0;
    self.progress = progress;
    return progress;
}

- (void)setTotalFileSize:(int64_t)totalFileSize {
    _totalFileSize = totalFileSize;
    if (self.progress && totalFileSize >= 0) {
        if (totalFileSize == 0) {
            self.progress.totalUnitCount = 1;
        } else {
            self.progress.totalUnitCount = totalFileSize;
        }
    }
}

- (void)setReceivedFileSize:(int64_t)receivedFileSize {
    _receivedFileSize = receivedFileSize;
    if (receivedFileSize >= 0) {
        if (self.progress && self.totalFileSize >= 0) {
            if (self.totalFileSize == 0) {
                self.progress.completedUnitCount = 1;
            } else {
                self.progress.completedUnitCount = receivedFileSize;
            }
        }
    }
    
}



@end

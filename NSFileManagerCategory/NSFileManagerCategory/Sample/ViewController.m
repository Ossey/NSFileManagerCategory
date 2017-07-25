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
@property (nonatomic, copy) NSString *rootPath;
@property (nonatomic, strong) NSMutableArray *copyfiles;
@property (nonatomic, strong) UIProgressView *progressBar;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    _copyfiles = [NSMutableArray array];
    _rootPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
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

- (IBAction)copyFile:(id)sender {
    
    
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

- (void)copyFileFromFileItems:(NSArray<FileAttributeItem *> *)fileItems {
    
    [_copyfiles addObjectsFromArray:fileItems];
    
    [_loadFileQueue addOperationWithBlock:^{
        [self resetProgress];
        
        __weak typeof(self) weakSelf = self;
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
            
            NSString *desPath = [weakSelf.rootPath stringByAppendingPathComponent:[obj.fullPath lastPathComponent]];
            
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

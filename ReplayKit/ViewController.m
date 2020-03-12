//
//  ViewController.m
//  ReplayKit
//
//  Created by ttlx on 2020/1/3.
//  Copyright © 2020 ttlx. All rights reserved.
//

#import "ViewController.h"
#import <ReplayKit/ReplayKit.h>
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>

@interface ViewController ()

@property (nonatomic, strong) UILabel *label;
@property (nonatomic, strong) NSTimer *timer;

@property (nonatomic, strong) NSString *videoPath;
@property (nonatomic, assign) BOOL hasStopped;
@property (nonatomic, assign) CFMutableArrayRef videoSampleBufferArray;

@property (nonatomic, strong) AVAssetWriter *writer;
@property (nonatomic, strong) AVAssetWriterInput *videoInput;
@property (nonatomic, strong) AVAssetWriterInput *appAudioInput;
@property (nonatomic, strong) AVAssetWriterInput *micAudioInput;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.

    _label = [[UILabel alloc] init];
    [self.view addSubview:_label];
    _label.font = [UIFont systemFontOfSize:20];
    _label.textColor = [UIColor redColor];
    _label.frame = self.view.frame;
    _label.textAlignment = NSTextAlignmentCenter;
    _label.text = @"1231";
    
    __block float count = 1.0f;
    _timer = [NSTimer timerWithTimeInterval:0.1 repeats:YES block:^(NSTimer * _Nonnull timer) {
        _label.text = [NSString stringWithFormat:@"%.2f", count];
        count = count + 0.1;
    }];
    
    [[NSRunLoop currentRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
    [_timer fire];
    
    
    UIButton *btn = [[UIButton alloc] init];
    [self.view addSubview:btn];
    [btn setTitle:@"开始录制" forState:UIControlStateNormal];
    [btn setTitle:@"结束录制" forState:UIControlStateSelected];
    btn.backgroundColor = [UIColor greenColor];
    btn.frame = CGRectMake(20, 50, 120, 50);
    [btn addTarget:self action:@selector(onRecordClick:) forControlEvents:UIControlEventTouchUpInside];

    
    [self playAudio];
  
}

- (void)onRecordClick:(UIButton *)btn
{
    if (!btn.selected) { // 开始录制
        [self startRecording:^(NSError *error) {
            btn.selected = YES;
        }];
    }
    else {
        [self stopRecording:^(NSString *filePath, NSError *error) {
            [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                
                PHAssetCreationRequest *request = [PHAssetCreationRequest creationRequestForAsset];
                
                [request addResourceWithType:PHAssetResourceTypeVideo fileURL:[NSURL fileURLWithPath:filePath] options:nil];
                
            } completionHandler:^(BOOL success, NSError * _Nullable error) {
                NSLog(@"写入相册结果, %d, %@", success, filePath);
                btn.selected = NO;
            }];
        }];
    }
}

- (void)playAudio
{
    NSString *path = [[NSBundle mainBundle] pathForResource:@"12.mp3" ofType:nil];
    static AVAudioPlayer *player = nil;
    player = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path] error:nil];
    [player play];
}

- (void)startRecording:(void (^)(NSError *error))callBack
{
    RPScreenRecorder *record = [RPScreenRecorder sharedRecorder];
    record.microphoneEnabled = YES;

    if (@available(iOS 11.0, *)) {

        _videoPath = [[self getTempDirectory] stringByAppendingFormat:@"/%@.mp4", @"replayKit"];
        NSLog(@"writer path %@", _videoPath);
        if ([[NSFileManager defaultManager] fileExistsAtPath:_videoPath]) {
            [[NSFileManager defaultManager] removeItemAtPath:_videoPath error:nil];
        }
        NSError *error = nil;
        AVAssetWriter *writer = [AVAssetWriter assetWriterWithURL:[NSURL fileURLWithPath:_videoPath] fileType:AVFileTypeMPEG4 error:&error];
        if (error) {
            NSLog(@"AVAssetWriter error %@", error.localizedDescription);
        }
        _writer = writer;

//
        if ([writer canAddInput:self.videoInput]) {
            [writer addInput:self.videoInput];
        }
        else {
            NSLog(@"添加input失败 videoInput");
        }
        if ([writer canAddInput:self.micAudioInput]) {
            [writer addInput:self.micAudioInput];
        }
        else {
            NSLog(@"添加input失败 micAudioInput");
        }
        if ([writer canAddInput:self.appAudioInput]) {
            [writer addInput:self.appAudioInput];
        }
        else {
            NSLog(@"添加input失败 appAudioInput");
        }

        BOOL resu = [writer startWriting];
        NSLog(@"resu %d, %@", resu, writer.error);

        __block BOOL hasStartSession = NO;
        _hasStopped = NO;

        __weak typeof(self) weakSelf = self;
        [record startCaptureWithHandler:^(CMSampleBufferRef  _Nonnull sampleBuffer, RPSampleBufferType bufferType, NSError * _Nullable error) {

            NSLog(@"%p %ld", sampleBuffer, (long)bufferType);
            if (weakSelf.hasStopped) return ;

            if (!hasStartSession) {

                hasStartSession = YES;
                 CMTime pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
                 [writer startSessionAtSourceTime:pts];
            }
//            // 没开始的话开始
            if (writer.status == AVAssetWriterStatusUnknown) {

                return;
            }

            if (writer.status == AVAssetWriterStatusFailed) {
                NSLog(@"An error occured: %@", writer.error);
                [self stopRecording:nil];
                return;
            }

            if (bufferType == RPSampleBufferTypeVideo) {
                CFRetain(sampleBuffer);

                if (weakSelf.videoInput.isReadyForMoreMediaData) {

                    NSLog(@"ready for weakSelf.videoInput");

                    // 将sampleBuffer添加进视频输入源
                    BOOL resu = [weakSelf.videoInput appendSampleBuffer:sampleBuffer];
                    NSAssert(resu, @"视频添加失败");
                    CFRelease(sampleBuffer);

                } else {
                    NSLog(@"Not ready for videoInput");
                }

            }
            else if (bufferType == RPSampleBufferTypeAudioApp) {

                    if (weakSelf.appAudioInput.isReadyForMoreMediaData) {
                        NSLog(@"ready for RPSampleBufferTypeAudioApp");
                        CFRetain(sampleBuffer);
                        // 将sampleBuffer添加进视频输入源
                        [weakSelf.appAudioInput appendSampleBuffer:sampleBuffer];
                        CFRelease(sampleBuffer);
                    } else {
                        NSLog(@"Not ready for _appAudioInput");
                    }


            }
            else if (bufferType == RPSampleBufferTypeAudioMic) {
                if (weakSelf.micAudioInput.isReadyForMoreMediaData) {
                    NSLog(@"ready for RPSampleBufferTypeAudioMic");
                    CFRetain(sampleBuffer);
                    // 将sampleBuffer添加进视频输入源
                    [weakSelf.micAudioInput appendSampleBuffer:sampleBuffer];
                    CFRelease(sampleBuffer);
                } else {
                    NSLog(@"Not ready for _micAudioInput");
                }
            }
//
        } completionHandler:^(NSError * _Nullable error) {
            if(callBack) {
                callBack(error);
            }
            NSLog(@"completionHandler %@", error.localizedDescription);
        }];
    } else {
    }
}

- (void)stopRecording:(void(^)(NSString *filePath, NSError *error))handler
{
    _hasStopped = YES;
    RPScreenRecorder *record = [RPScreenRecorder sharedRecorder];
    __weak typeof(self) weakSelf = self;
    if (@available(iOS 11.0, *)) {
        [record stopCaptureWithHandler:^(NSError * _Nullable error) {
              if (error) {
                NSLog(@"stopCaptureWithHandler: %@", error);
            }
            // 结束写入
            [self.writer finishWritingWithCompletionHandler:^{
                {
                    weakSelf.writer = nil;
                    weakSelf.videoInput = nil;
                    weakSelf.appAudioInput = nil;
                    weakSelf.micAudioInput = nil;
                }
                NSLog(@"屏幕录制结束，视频地址: %@", weakSelf.videoPath);
                
                if (handler) {
                    handler(weakSelf.videoPath, nil);
                }
            }];
        }];
    } else {
    }

}

#pragma mark - lazy load
- (AVAssetWriterInput *)videoInput
{
    
    if (!_videoInput) {
        NSDictionary *compressionProperties = @{
            AVVideoAverageBitRateKey : [NSNumber numberWithDouble:2000 * 1000]
        };
        
        NSDictionary *videoSettings = @{
            AVVideoCompressionPropertiesKey : compressionProperties,
            AVVideoCodecKey                 : AVVideoCodecTypeH264,
            AVVideoWidthKey                 : [NSNumber numberWithFloat:[UIScreen mainScreen].bounds.size.width],
            AVVideoHeightKey                : [NSNumber numberWithFloat:[UIScreen mainScreen].bounds.size.height]
        };
        
        _videoInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:videoSettings];
        _videoInput.expectsMediaDataInRealTime = YES;
    }
    return _videoInput;
}

- (AVAssetWriterInput *)appAudioInput
{
    if (!_appAudioInput) {
        _appAudioInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio outputSettings:[self audioSettingDict]];
        _appAudioInput.expectsMediaDataInRealTime = YES;
    }
    return _appAudioInput;
}

- (AVAssetWriterInput *)micAudioInput
{
    if (!_micAudioInput) {
        _micAudioInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio outputSettings:[self audioSettingDict]];
        _micAudioInput.expectsMediaDataInRealTime = YES;
    }
    return _micAudioInput;
}

- (NSDictionary *)audioSettingDict
{
    NSDictionary *audioInputSetting = @{ AVFormatIDKey : @(kAudioFormatMPEG4AAC),
                                         AVSampleRateKey : @(16000),
                                         AVNumberOfChannelsKey : @1,
    };
    
    
    return audioInputSetting;
}

- (NSString *)getTempDirectory
{
    NSString *ttlxDir = [[NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) firstObject] stringByAppendingPathComponent:@"replayKit"];

    if (![[NSFileManager defaultManager] fileExistsAtPath:ttlxDir]) {
        NSError *error = nil;
        [[NSFileManager defaultManager] createDirectoryAtPath:ttlxDir withIntermediateDirectories:YES attributes:nil error:&error];
    }

    return ttlxDir;
}
@end

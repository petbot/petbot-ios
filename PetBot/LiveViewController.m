//
//  ViewController.m
//  kxmovieapp
//
//  Created by Kolyvan on 11.10.12.
//  Copyright (c) 2012 Konstantin Boukreev . All rights reserved.
//
//  https://github.com/kolyvan/kxmovie
//  this file is part of KxMovie
//  KxMovie is licenced under the LGPL v3, see lgpl-3.0.txt
//
// Modified by Misko Dzamba 2014
//
//  LiveViewController.m
//

#import "LiveViewController.h"
#import <MediaPlayer/MediaPlayer.h>
#import <QuartzCore/QuartzCore.h>
#import "PetConnection.h"
#import "KxMovieDecoder.h"
#import "KxAudioManager.h"
#import "KxMovieGLView.h"
#import "KxLogger.h"

////////////////////////////////////////////////////////////////////////////////

static NSString * formatTimeInterval(CGFloat seconds, BOOL isLeft)
{
    seconds = MAX(0, seconds);
    
    NSInteger s = seconds;
    NSInteger m = s / 60;
    NSInteger h = m / 60;
    
    s = s % 60;
    m = m % 60;
    
    NSMutableString *format = [(isLeft && seconds >= 0.5 ? @"-" : @"") mutableCopy];
    if (h != 0) [format appendFormat:@"%d:%0.2d", h, m];
    else        [format appendFormat:@"%d", m];
    [format appendFormat:@":%0.2d", s];
    
    return format;
}


static NSMutableDictionary * gHistory;


@interface LiveViewController () {
    
    KxMovieDecoder      *_decoder;
    dispatch_queue_t    _dispatchQueue;
    NSMutableArray      *_videoFrames;
    NSMutableArray      *_subtitles;
    CGFloat             _moviePosition;
    BOOL                _disableUpdateHUD;
    NSTimeInterval      _tickCorrectionTime;
    NSTimeInterval      _tickCorrectionPosition;
    NSUInteger          _tickCounter;
    BOOL                _fullscreen;
    BOOL                _fitMode;
    BOOL                _infoMode;
    BOOL                _restoreIdleTimer;
    BOOL                _interrupted;
    NSString            *_path;
    
    KxMovieGLView       *_glView;
    UIImageView         *_imageView;
    UIView              *_topHUD;
    UIToolbar           *_topBar;
    UIToolbar           *_bottomBar;
    UISlider            *_progressSlider;
    
    UIBarButtonItem     *_playBtn;
    UIBarButtonItem     *_pauseBtn;
    UIBarButtonItem     *_rewindBtn;
    UIBarButtonItem     *_fforwardBtn;
    UIBarButtonItem     *_spaceItem;
    UIBarButtonItem     *_fixedSpaceItem;
    
    UIButton            *_logoutButton;
    UIButton            *_cookieButton;
    UIButton            *_soundButton;
    UILabel             *_progressLabel;
    UILabel             *_leftLabel;
    UIButton            *_infoButton;
    UIActivityIndicatorView *_activityIndicatorView;
    UILabel             *_subtitlesLabel;
    
    
#ifdef DEBUG
    UILabel             *_messageLabel;
    NSTimeInterval      _debugStartTime;
    NSUInteger          _debugAudioStatus;
    NSDate              *_debugAudioStatusTS;
#endif
    
    CGFloat             _bufferedDuration;
    CGFloat             _minBufferedDuration;
    CGFloat             _maxBufferedDuration;
    BOOL                _buffered;
    
    BOOL                _savedIdleTimer;
    double             _missed;
    double             _stream_time;
    double             _prog_time;
    
    NSDictionary        *_parameters;
}

@property (readwrite) BOOL playing;
@property (readwrite) BOOL decoding;
@property (readwrite, strong) KxArtworkFrame *artworkFrame;
@end

@implementation LiveViewController

+ (void)initialize
{
    if (!gHistory)
        gHistory = [NSMutableDictionary dictionary];
}

- (BOOL)prefersStatusBarHidden { return YES; }

+ (id) movieViewControllerWithContentPath: (NSString *) path
                               parameters: (NSDictionary *) parameters
{
    return [[LiveViewController alloc] initWithContentPath: path parameters: parameters];
}

- (id) initWithContentPath: (NSString *) path
                parameters: (NSDictionary *) parameters
{
    
    path=@"rtsp://162.243.126.214/proxyStream";
    _path = path;
    _missed=0;
    NSAssert(path.length > 0, @"empty path");
    
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _moviePosition = 0;
        //        self.wantsFullScreenLayout = YES;
        
        _parameters = parameters;
        
        __weak LiveViewController *weakSelf = self;
        
        KxMovieDecoder *decoder = [[KxMovieDecoder alloc] init];

        
        decoder.interruptCallback = ^BOOL(){
            
            __strong LiveViewController *strongSelf = weakSelf;
            return strongSelf ? [strongSelf interruptDecoder] : YES;
        };
        
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            
            NSError *error = nil;
            [decoder openFile:path error:&error];
            
            __strong LiveViewController *strongSelf = weakSelf;
            if (strongSelf) {
                
                dispatch_sync(dispatch_get_main_queue(), ^{
                    
                    [strongSelf setMovieDecoder:decoder withError:error];
                });
            }
        });
    }
    return self;
}



- (void) dealloc
{
    [self pause];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    if (_dispatchQueue) {
        _dispatchQueue = NULL;
    }
    
    LoggerStream(1, @"%@ dealloc", self);
}

-(UIColor*)colorWithHexString:(NSString*)hex
{
    NSString *cString = [[hex stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];
    
    // String should be 6 or 8 characters
    if ([cString length] < 6) return [UIColor grayColor];
    
    // strip 0X if it appears
    if ([cString hasPrefix:@"0X"]) cString = [cString substringFromIndex:2];
    
    if ([cString length] != 6) return  [UIColor grayColor];
    
    // Separate into r, g, b substrings
    NSRange range;
    range.location = 0;
    range.length = 2;
    NSString *rString = [cString substringWithRange:range];
    
    range.location = 2;
    NSString *gString = [cString substringWithRange:range];
    
    range.location = 4;
    NSString *bString = [cString substringWithRange:range];
    
    // Scan values
    unsigned int r, g, b;
    [[NSScanner scannerWithString:rString] scanHexInt:&r];
    [[NSScanner scannerWithString:gString] scanHexInt:&g];
    [[NSScanner scannerWithString:bString] scanHexInt:&b];
    
    return [UIColor colorWithRed:((float) r / 255.0f)
                           green:((float) g / 255.0f)
                            blue:((float) b / 255.0f)
                           alpha:1.0f];
}

- (void) dropCookie {
    [PetConnection cookieDrop];
}

- (void) playSound {
    [PetConnection playSound:8];
}

- (void) logout {
    [self stopStream];
    [PetConnection logout];
    [self performSegueWithIdentifier:@"logout" sender:self];
}

- (void)loadView
{
    CGRect bounds = [[UIScreen mainScreen] applicationFrame];
    
    self.view = [[UIView alloc] initWithFrame:bounds];
    self.view.backgroundColor = [UIColor blackColor];
    self.view.tintColor = [UIColor blackColor];
    
    _activityIndicatorView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle: UIActivityIndicatorViewStyleWhiteLarge];
    _activityIndicatorView.center = self.view.center;
    _activityIndicatorView.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    
    [self.view addSubview:_activityIndicatorView];
    
    CGFloat width = bounds.size.width;
    CGFloat height = bounds.size.height;
    
#ifdef DEBUG
    _messageLabel = [[UILabel alloc] initWithFrame:CGRectMake(20,40,width-40,40)];
    _messageLabel.backgroundColor = [UIColor clearColor];
    _messageLabel.textColor = [UIColor redColor];
    _messageLabel.hidden = YES;
    _messageLabel.font = [UIFont systemFontOfSize:14];
    _messageLabel.numberOfLines = 2;
    _messageLabel.textAlignment = NSTextAlignmentCenter;
    _messageLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:_messageLabel];
#endif
    
    CGFloat topH = 50;
    CGFloat botH = 50;
    
    /*_topHUD    = [[UIView alloc] initWithFrame:CGRectMake(0,height-botH,width,botH)];
    //_topBar    = [[UIToolbar alloc] initWithFrame:CGRectMake(0, height-botH, width, topH)];
    //_bottomBar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, height-botH, width, botH)];
    //_bottomBar.tintColor = [UIColor blackColor];
    
    
    _topHUD.frame = CGRectMake(0,0,width,_topBar.frame.size.height);
    
    _topHUD.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _topBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    //_bottomBar.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleWidth;
    
    //[self.view addSubview:_topBar]; //MISKO // the white background to top
    [self.view addSubview:_topHUD]; //MISKO
    [self.view addSubview:_bottomBar]; //MISKO
    */  
    
    
    // top hud
    
    /*_doneButton = [UIButton buttonWithType:UIButtonTypeCustom];
     _doneButton.frame = CGRectMake(0, 1, 50, topH);
     _doneButton.backgroundColor = [UIColor clearColor];
     //    _doneButton.backgroundColor = [UIColor redColor];
     [_doneButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
     [_doneButton setTitle:NSLocalizedString(@"OK", nil) forState:UIControlStateNormal];
     _doneButton.titleLabel.font = [UIFont systemFontOfSize:18];
     _doneButton.showsTouchWhenHighlighted = YES;
     [_doneButton addTarget:self action:@selector(doneDidTouch:)
     forControlEvents:UIControlEventTouchUpInside];
     //    [_doneButton setContentVerticalAlignment:UIControlContentVerticalAlignmentCenter];
     
     _progressLabel = [[UILabel alloc] initWithFrame:CGRectMake(46, 1, 50, topH)];
     _progressLabel.backgroundColor = [UIColor clearColor];
     _progressLabel.opaque = NO;
     _progressLabel.adjustsFontSizeToFitWidth = NO;
     _progressLabel.textAlignment = NSTextAlignmentRight;
     _progressLabel.textColor = [UIColor blackColor];
     _progressLabel.text = @"";
     _progressLabel.font = [UIFont systemFontOfSize:12];
     
     _progressSlider = [[UISlider alloc] initWithFrame:CGRectMake(100, 2, width-197, topH)];
     _progressSlider.autoresizingMask = UIViewAutoresizingFlexibleWidth;
     _progressSlider.continuous = NO;
     _progressSlider.value = 0;
     //    [_progressSlider setThumbImage:[UIImage imageNamed:@"kxmovie.bundle/sliderthumb"]
     //                          forState:UIControlStateNormal];
     
     _leftLabel = [[UILabel alloc] initWithFrame:CGRectMake(width-92, 1, 60, topH)];
     _leftLabel.backgroundColor = [UIColor clearColor];
     _leftLabel.opaque = NO;
     _leftLabel.adjustsFontSizeToFitWidth = NO;
     _leftLabel.textAlignment = NSTextAlignmentLeft;
     _leftLabel.textColor = [UIColor blackColor];
     _leftLabel.text = @"";
     _leftLabel.font = [UIFont systemFontOfSize:12];
     _leftLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
     
     _infoButton = [UIButton buttonWithType:UIButtonTypeInfoDark];
     _infoButton.frame = CGRectMake(width-31, (topH-20)/2+1, 20, 20);
     _infoButton.showsTouchWhenHighlighted = YES;
     _infoButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
     [_infoButton addTarget:self action:@selector(infoDidTouch:) forControlEvents:UIControlEventTouchUpInside];
     
     [_topHUD addSubview:_doneButton];
     [_topHUD addSubview:_progressLabel];
     [_topHUD addSubview:_progressSlider];
     [_topHUD addSubview:_leftLabel];
     [_topHUD addSubview:_infoButton];*/
    
    // bottom hud
    _cookieButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _cookieButton.frame = CGRectMake(10, height-90, MIN(width/3,200), 80);
    _cookieButton.backgroundColor = [self colorWithHexString:@"d9534f"];
    [_cookieButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [_cookieButton setTitle:NSLocalizedString(@"Cookie", nil) forState:UIControlStateNormal];
    _cookieButton.titleLabel.font = [UIFont boldSystemFontOfSize:27.0]; //[UIFont systemFontOfSize:18];
    //_doneButton.showsTouchWhenHighlighted = YES;
    [_cookieButton addTarget:self action:@selector(dropCookie)
          forControlEvents:UIControlEventTouchUpInside];
    _cookieButton.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleRightMargin;// | UIViewAutoresizingFlexibleWidth;
    _cookieButton.alpha=0.8;
    _cookieButton.layer.cornerRadius=10;
    _cookieButton.layer.masksToBounds=true;
    [[ self view] addSubview: _cookieButton];
    
    _soundButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _soundButton.frame = CGRectMake(width-MIN(width/3,200)-10, height-90, MIN(width/3,200), 80);
    _soundButton.backgroundColor = [self colorWithHexString:@"f0ad4e"];
    [_soundButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [_soundButton setTitle:NSLocalizedString(@"Sound", nil) forState:UIControlStateNormal];
    _soundButton.titleLabel.font = [UIFont boldSystemFontOfSize:27.0]; //[UIFont systemFontOfSize:18];
    //_doneButton.showsTouchWhenHighlighted = YES;
    [_soundButton addTarget:self action:@selector(playSound)
          forControlEvents:UIControlEventTouchUpInside];
    _soundButton.autoresizingMask = UIViewAutoresizingFlexibleTopMargin |  UIViewAutoresizingFlexibleLeftMargin;// | UIViewAutoresizingFlexibleWidth;
    _soundButton.alpha=0.8;
    _soundButton.layer.cornerRadius=10;
    _soundButton.layer.masksToBounds=true;
    [[ self view] addSubview: _soundButton];
    
    _logoutButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _logoutButton.frame = CGRectMake(width-MIN(width/3,200)-10, 10, MIN(width/3,200), 80);
    _logoutButton.backgroundColor = [UIColor whiteColor];
    [_logoutButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [_logoutButton setTitle:NSLocalizedString(@"Logout", nil) forState:UIControlStateNormal];
    _logoutButton.titleLabel.font = [UIFont boldSystemFontOfSize:27.0]; //[UIFont systemFontOfSize:18];
    //_doneButton.showsTouchWhenHighlighted = YES;
    [_logoutButton addTarget:self action:@selector(logout)
          forControlEvents:UIControlEventTouchUpInside];
    _logoutButton.autoresizingMask = UIViewAutoresizingFlexibleBottomMargin |  UIViewAutoresizingFlexibleLeftMargin;// | UIViewAutoresizingFlexibleWidth;
    _logoutButton.alpha=0.8;
    _logoutButton.layer.cornerRadius=10;
    _logoutButton.layer.masksToBounds=true;
    [[ self view] addSubview: _logoutButton];
    
    //[_topHUD addSubview:_doneButton];
    
    /*_spaceItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                                                               target:nil
                                                               action:nil];
    
    _fixedSpaceItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace
                                                                    target:nil
                                                                    action:nil];
    _fixedSpaceItem.width = 30;
    
    _rewindBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRewind
                                                               target:self
                                                               action:@selector(rewindDidTouch:)];
    
    
    _playBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemPlay
                                                             target:self
                                                             action:nil];
    //action:@selector(playDidTouch:)];
    _playBtn.width = 50;
    
    _pauseBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemPause
                                                              target:self
                                                              action:@selector(playDidTouch:)];
    _pauseBtn.width = 50;
    
    _fforwardBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFastForward
                                                                 target:self
                                                                 action:@selector(forwardDidTouch:)];
    
    [self updateBottomBar];*/
    
    if (_decoder) {
        
        [self setupPresentView];
        
    } else {
        
        _progressLabel.hidden = YES;
        _progressSlider.hidden = YES;
        _leftLabel.hidden = YES;
        _infoButton.hidden = YES;
    }
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    
    if (self.playing) {
        
        [self pause];
        [self freeBufferedFrames];
        
        if (_maxBufferedDuration > 0) {
            
            _minBufferedDuration = _maxBufferedDuration = 0;
            [self play];
            
            LoggerStream(0, @"didReceiveMemoryWarning, disable buffering and continue playing");
            
        } else {
            
            // force ffmpeg to free allocated memory
            [_decoder closeFile];
            [_decoder openFile:nil error:nil];
            
            [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Failure", nil)
                                        message:NSLocalizedString(@"Out of memory", nil)
                                       delegate:nil
                              cancelButtonTitle:NSLocalizedString(@"Close", nil)
                              otherButtonTitles:nil] show];
        }
        
    } else {
        
        [self freeBufferedFrames];
        [_decoder closeFile];
        [_decoder openFile:nil error:nil];
    }
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    LoggerStream(1, @"ViewDidload");
    NSString * streamURL = [PetConnection streamURL];
    if (streamURL.length>1) {
        [self initWithContentPath:streamURL parameters:nil];
    } else {
        NSLog(@"Fatal error view did load stream");
    }
}



- (void) viewDidAppear:(BOOL)animated
{
    LoggerStream(1, @"viewDidAppear");
    
    [super viewDidAppear:animated];
    
    if (self.presentingViewController)
        [self fullscreenMode:YES];
    
    /*if (_infoMode)
     [self showInfoView:NO animated:NO];*/
    
    _savedIdleTimer = [[UIApplication sharedApplication] isIdleTimerDisabled];
    
    //[self showHUD: YES];
    
    if (_decoder) {
        //NSLog(@"restore play");
        [self restorePlay];
    } else {
        //NSLog(@"start animating");
        [_activityIndicatorView startAnimating];
    }
    
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillResignActive:)
                                                 name:UIApplicationWillResignActiveNotification
                                               object:[UIApplication sharedApplication]];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidBecomeActive:)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:[UIApplication sharedApplication]];
    
    //[NSTimer scheduledTimerWithTimeInterval:5.0f
    //                                 target:self selector:@selector(pause) userInfo:nil repeats:YES];
}

- (void) viewWillDisappear:(BOOL)animated
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    [super viewWillDisappear:animated];
    
    [_activityIndicatorView stopAnimating];
    
    if (_decoder) {
        
        [self pause];
        
        if (_moviePosition == 0 || _decoder.isEOF)
            [gHistory removeObjectForKey:_decoder.path];
        else if (!_decoder.isNetwork)
            [gHistory setValue:[NSNumber numberWithFloat:_moviePosition]
                        forKey:_decoder.path];
    }
    
    if (_fullscreen)
        [self fullscreenMode:NO];
    
    [[UIApplication sharedApplication] setIdleTimerDisabled:_savedIdleTimer];
    
    [_activityIndicatorView stopAnimating];
    _buffered = NO;
    _interrupted = YES;
    
    LoggerStream(1, @"viewWillDisappear %@", self);
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return (interfaceOrientation != UIInterfaceOrientationPortraitUpsideDown);
}

- (void) applicationWillResignActive: (NSNotification *)notification
{
    //[self showHUD:YES];
    [self stopStream];
    LoggerStream(1, @"applicationWillResignActive");
}

-(void) stopStream {
    
    @synchronized(self) {
        [self pause];
        if (_dispatchQueue!=nil) {
            dispatch_sync(_dispatchQueue,^(void) {
                NSLog(@"done waiting...");
            });
            //[[NSNotificationCenter defaultCenter] removeObserver:self];
            //dispatch_suspend(_dispatchQueue);
            if (_dispatchQueue) {
                _dispatchQueue = NULL;
            }
        } else {
            NSLog(@"DISPATCH Q IS NILL");
        }
        /*if (_dispatchQueue) {
            _dispatchQueue = NULL;
        }*/
        if (_glView!=nil) {
            [_glView removeFromSuperview];
        }
        if (_decoder!=nil) {
            [_decoder closeFile];
        }
        _decoder=nil;
        _glView=nil;
    }
}

-(void) startStream {
    
    @synchronized(self) {
        NSString *streamURL = [PetConnection streamURL];
        if (streamURL.length>1) {
            [self initWithContentPath:streamURL parameters:nil];
            if (_decoder) {
                //NSLog(@"restore play");
                [self restorePlay];
                
            } else {
                //NSLog(@"start animating");
                [_activityIndicatorView startAnimating];
            }
        } else {
            NSLog(@"Fatal error in start stream");
        }
    }
}

-(void) restartStream {
        NSLog(@"SSSSTARRTTTTT");
        [self stopStream];
        [self startStream];
        
        NSLog(@"FINIHSSHSHSHSH");
}

- (void) applicationDidBecomeActive: (NSNotification *)notification
{
    //[_decoder closeFile];
    /*
    [self startStream];*/
    //[self play];
    //[self play];
    //[self removeFromParentViewController];
    //[self startStream];
    [self startStream];
    LoggerStream(1, @"applicationDidBecomeActive");
}

#pragma mark - public

-(void) play
{
    if (self.playing)
        return;
    
    if (!_decoder.validVideo &&
        !_decoder.validAudio) {
        
        return;
    }
    
    if (_interrupted)
        return;
    
    self.playing = YES;
    _interrupted = NO;
    _disableUpdateHUD = NO;
    _tickCorrectionTime = 0;
    _tickCounter = 0;
    
#ifdef DEBUG
    _debugStartTime = -1;
#endif
    
    [self asyncDecodeFrames];
    //[self updatePlayButton];
    
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, 0.1 * NSEC_PER_SEC);
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
        [self tick];
    });
    
    /*if (_decoder.validAudio)
     [self enableAudio:YES];*/
    //NSLog(@"disable audio !!!!!!"); //MISKO
    //[self enableAudio:NO];
    
    LoggerStream(1, @"play movie");
}

- (void) pause
{
    if (!self.playing)
        return;
    
    self.playing = NO;
    //_interrupted = YES;
    //[self enableAudio:NO];
    //[self updatePlayButton];
    LoggerStream(1, @"pause movie");
}

- (void) setMoviePosition: (CGFloat) position
{
    BOOL playMode = self.playing;
    
    self.playing = NO;
    _disableUpdateHUD = YES;
    //[self enableAudio:NO];
    
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, 0.1 * NSEC_PER_SEC);
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
        
        [self updatePosition:position playMode:playMode];
    });
}

#pragma mark - private

- (void) setMovieDecoder: (KxMovieDecoder *) decoder
               withError: (NSError *) error
{
    LoggerStream(2, @"setMovieDecoder");
    
    if (!error && decoder) {
        
        _decoder        = decoder;
        _dispatchQueue  = dispatch_queue_create("KxMovie", DISPATCH_QUEUE_SERIAL);
        _videoFrames    = [NSMutableArray array];
        //_audioFrames    = [NSMutableArray array];
        
        if (_decoder.subtitleStreamsCount) {
            _subtitles = [NSMutableArray array];
        }
        
        _minBufferedDuration = 0.0;
        
        _maxBufferedDuration = 0.0;
        
        _decoder.disableDeinterlacing = true;
        
        LoggerStream(2, @"buffered limit: %.1f - %.1f", _minBufferedDuration, _maxBufferedDuration);
        
        if (self.isViewLoaded) {
            LoggerStream(2,@"setting up VIEW");
            [self setupPresentView];
            
            _progressLabel.hidden   = NO;
            _progressSlider.hidden  = NO;
            _leftLabel.hidden       = NO;
            _infoButton.hidden      = NO;
            
            if (_activityIndicatorView.isAnimating) {
                
                [_activityIndicatorView stopAnimating];
                // if (self.view.window)
                [self restorePlay];
            }
        }
        
    } else {
        
        if (self.isViewLoaded && self.view.window) {
            
            [_activityIndicatorView stopAnimating];
            if (!_interrupted)
                [self handleDecoderMovieError: error];
        }
    }
}

- (void) restorePlay
{
    NSNumber *n = [gHistory valueForKey:_decoder.path];
    if (n)
        [self updatePosition:n.floatValue playMode:YES];
    else
        [self play];
}

- (void) setupPresentView
{
    CGRect bounds = self.view.bounds;
    
    if (_decoder.validVideo) {
    
        //[[self sbglview] initWithFrame:bounds decoder:_decoder];
        @synchronized(self) {
            if (_glView!=nil) {
                NSLog(@"NOT GOOD");
                [_glView removeFromSuperview];
                _glView=nil;
            }
            _glView = [[KxMovieGLView alloc] initWithFrame:bounds decoder:_decoder];
        }
    }
    
    /*if (!_glView) {
        
        LoggerVideo(0, @"fallback to use RGB video frame and UIKit");
        [_decoder setupVideoFrameFormat:KxVideoFrameFormatRGB];
        _imageView = [[UIImageView alloc] initWithFrame:bounds];
        _imageView.backgroundColor = [UIColor blackColor];
    }*/ //MISKO
    
    UIView *frameView = [self frameView];
    frameView.contentMode = UIViewContentModeScaleAspectFit;
    frameView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleBottomMargin;
    
    [self.view insertSubview:frameView atIndex:0];
    
    if (_decoder.validVideo) {
        
        //[self setupUserInteraction]; MISKO
        
    } else {
        
        _imageView.image = [UIImage imageNamed:@"kxmovie.bundle/music_icon.png"];
        _imageView.contentMode = UIViewContentModeCenter;
    }
    
    self.view.backgroundColor = [UIColor clearColor];
    
    if (_decoder.duration == MAXFLOAT) {
        
        _leftLabel.text = @"\u221E"; // infinity
        _leftLabel.font = [UIFont systemFontOfSize:14];
        
        CGRect frame;
        
        frame = _leftLabel.frame;
        frame.origin.x += 40;
        frame.size.width -= 40;
        _leftLabel.frame = frame;
        
        frame =_progressSlider.frame;
        frame.size.width += 40;
        _progressSlider.frame = frame;
        
    } else {
        
        [_progressSlider addTarget:self
                            action:@selector(progressDidChange:)
                  forControlEvents:UIControlEventValueChanged];
    }
    
    if (_decoder.subtitleStreamsCount) {
        
        CGSize size = self.view.bounds.size;
        
        _subtitlesLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, size.height, size.width, 0)];
        _subtitlesLabel.numberOfLines = 0;
        _subtitlesLabel.backgroundColor = [UIColor clearColor];
        _subtitlesLabel.opaque = NO;
        _subtitlesLabel.adjustsFontSizeToFitWidth = NO;
        _subtitlesLabel.textAlignment = NSTextAlignmentCenter;
        _subtitlesLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        _subtitlesLabel.textColor = [UIColor whiteColor];
        _subtitlesLabel.font = [UIFont systemFontOfSize:16];
        _subtitlesLabel.hidden = YES;
        
        [self.view addSubview:_subtitlesLabel];
    }
}

- (UIView *) frameView
{
    //return [self sbglview];
    return _glView;
    //return _glView ? _glView : _imageView;
}

- (BOOL) addFrames: (NSArray *)frames
{
    if (_decoder.validVideo) {
        
        @synchronized(_videoFrames) {
            
            for (KxMovieFrame *frame in frames)
                if (frame.type == KxMovieFrameTypeVideo) {
                    [_videoFrames addObject:frame];
                    _bufferedDuration += frame.duration;
                }
        }
    }
    
    if (_decoder.validAudio) {
        
        /*@synchronized(_audioFrames) {
         
         for (KxMovieFrame *frame in frames)
         if (frame.type == KxMovieFrameTypeAudio) {
         [_audioFrames addObject:frame];
         if (!_decoder.validVideo)
         _bufferedDuration += frame.duration;
         }
         }*/
        
        if (!_decoder.validVideo) {
            
            for (KxMovieFrame *frame in frames)
                if (frame.type == KxMovieFrameTypeArtwork)
                    self.artworkFrame = (KxArtworkFrame *)frame;
        }
    }
    
    if (_decoder.validSubtitles) {
        
        @synchronized(_subtitles) {
            
            for (KxMovieFrame *frame in frames)
                if (frame.type == KxMovieFrameTypeSubtitle) {
                    [_subtitles addObject:frame];
                }
        }
    }
    
    return self.playing && _bufferedDuration < _maxBufferedDuration;
}

- (BOOL) decodeFrames
{
    //NSAssert(dispatch_get_current_queue() == _dispatchQueue, @"bugcheck");
    
    NSArray *frames = nil;
    
    if (_decoder.validVideo ||
        _decoder.validAudio) {
        
        frames = [_decoder decodeFrames:0];
    }
    
    if (frames.count) {
        return [self addFrames: frames];
    }
    return NO;
}

- (void) asyncDecodeFrames
{
    if (self.decoding)
        return;
    
    __weak LiveViewController *weakSelf = self;
    __weak KxMovieDecoder *weakDecoder = _decoder;
    
    const CGFloat duration = _decoder.isNetwork ? .0f : 0.1f;
    
    self.decoding = YES;
    dispatch_async(_dispatchQueue, ^{
        
        {
            __strong LiveViewController *strongSelf = weakSelf;
            if (!strongSelf.playing)
                return;
        }
        
        BOOL good = YES;
        while (good) {
            
            good = NO;
            
            @autoreleasepool {
                
                __strong KxMovieDecoder *decoder = weakDecoder;
                
                if (decoder && (decoder.validVideo || decoder.validAudio)) {
                    
                    NSArray *frames = [decoder decodeFrames:duration];
                    if (frames.count) {
                        
                        __strong LiveViewController *strongSelf = weakSelf;
                        if (strongSelf)
                            good = [strongSelf addFrames:frames];
                    }
                }
            }
        }
        
        {
            __strong LiveViewController *strongSelf = weakSelf;
            if (strongSelf) strongSelf.decoding = NO;
        }
    });
}

- (void) tick
{
    
    if ((_tickCounter++ % 450)==0) {
        [PetConnection streamVideo];
    }
    //NSLog(@"tick1");
    if ((_tickCounter++ % 50)==0) {
        if (![_glView isDescendantOfView:self.view]) {
            NSLog(@"IS NOT descendant");
        }
        //NSLog(@"tick2");
        if (_moviePosition>(_decoder.startTime+6)) {
            if (_stream_time<0.0001) {
                double now = [NSDate timeIntervalSinceReferenceDate];
                _stream_time=_decoder.position;
                _prog_time=now;
                //NSLog(@"%0.2f %0.2f",_stream_time,_prog_time);
            } else {
                double now = [NSDate timeIntervalSinceReferenceDate];
                double mtime = _decoder.position;
                
                double d =(mtime - _stream_time) - (now-_prog_time);
                if (abs(d)>0.8) {
                    //NSLog(@"TIMEOUT %lf",_missed);
                    _missed+=1.1;
                    if (_missed>3) {
                        _missed=0.0;
                        _prog_time=0.0;
                        _stream_time=0.0;
                        //NSLog(@"Restart stream");
                        [self restartStream];
                    }
                } else {
                    _missed=0.0;
                }
                NSLog(@"%0.2f %0.2f %0.2f %0.2f",mtime , _moviePosition - _stream_time, now-_prog_time, (mtime - _stream_time) - (now-_prog_time));
            }
        }
    }
    if (_buffered && ((_bufferedDuration > _minBufferedDuration) || _decoder.isEOF)) {
        
        _tickCorrectionTime = 0;
        _buffered = NO;
        [_activityIndicatorView stopAnimating];
    }
    
    //NSLog(@"%d frames buffered",_videoFrames.count);
    
    CGFloat interval = 0;
    if (!_buffered)
        interval = [self presentFrame];
    
    if (self.playing) {
        const NSUInteger leftFrames =
        (_decoder.validVideo ? _videoFrames.count : 0) + 0; //MISKO
        //(_decoder.validAudio ? _audioFrames.count : 0);
        
        if (0 == leftFrames) {
            
            if (_decoder.isEOF) {
                
                [self pause];
                [self updateHUD];
                return;
            }
            
            if (_minBufferedDuration > 0 && !_buffered) {
                _buffered = YES;
                [_activityIndicatorView startAnimating];
            }
        }
        
        
        if (!leftFrames ||
            !(_bufferedDuration > _minBufferedDuration)) {
            [self asyncDecodeFrames];
        }
        
        const NSTimeInterval correction = [self tickCorrection];
        const NSTimeInterval time = MAX(interval + correction, 0.01);
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, time * NSEC_PER_SEC);
        dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
            [self tick];
        });
    }
    _tickCounter++;
    //if ((_tickCounter++ % 3) == 0) {
    //    [self updateHUD];
    //}
}

- (CGFloat) tickCorrection
{
    if (_buffered)
        return 0;
    
    const NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    
    if (!_tickCorrectionTime) {
        
        _tickCorrectionTime = now;
        _tickCorrectionPosition = _moviePosition;
        return 0;
    }
    
    NSTimeInterval dPosition = _moviePosition - _tickCorrectionPosition;
    NSTimeInterval dTime = now - _tickCorrectionTime;
    NSTimeInterval correction = dPosition - dTime;
    /*if (dPosition<1e-10) {
        _missed+=dTime;
        if (_missed>1.5 && !_activityIndicatorView.isAnimating) {
            UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"BUFFRED2", nil)
                                                                message:@"BUFFER2"
                                                               delegate:nil
                                                      cancelButtonTitle:NSLocalizedString(@"Close", nil)
                                                      otherButtonTitles:nil];
            
            [alertView show];
            [_activityIndicatorView startAnimating];
        }
    } else {
        _missed=0.0;
        if (_activityIndicatorView.isAnimating) {
            [_activityIndicatorView stopAnimating];
        }
    }*/
    //NSLog(@"%0.4f %0.4f %0.4f %0.4f",dPosition,dTime,correction,_decoder.position);
    //if ((_tickCounter % 200) == 0)
    //    LoggerStream(1, @"tick correction %.4f", correction);
    
    if (correction > 1.f || correction < -1.f) {
        LoggerStream(1, @"tick correction reset %.2f", correction);
        correction = 0;
        _tickCorrectionTime = 0;
    }
    
    return correction;
}

- (CGFloat) presentFrame
{
    CGFloat interval = 0;
    
    if (_decoder.validVideo) {
        
        KxVideoFrame *frame;
        
        @synchronized(_videoFrames) {
            
            if (_videoFrames.count > 0) {
                //NSLog(@"have %d frames",_videoFrames.count);
                frame = _videoFrames[0];
                [_videoFrames removeObjectAtIndex:0];
                _bufferedDuration -= frame.duration;
            }
        }
        
        if (frame)
            interval = [self presentVideoFrame:frame];
        
    }
    
    /*else if (_decoder.validAudio) {
        
        //interval = _bufferedDuration * 0.5;
        
        if (self.artworkFrame) {
            
            _imageView.image = [self.artworkFrame asImage];
            self.artworkFrame = nil;
        }
    }*/
    
    //if (_decoder.validSubtitles)
    //    [self presentSubtitles];
    
#ifdef DEBUG
    if (self.playing && _debugStartTime < 0)
        _debugStartTime = [NSDate timeIntervalSinceReferenceDate] - _moviePosition;
#endif
    
    return interval;
}

- (CGFloat) presentVideoFrame: (KxVideoFrame *) frame
{
    [_glView render:frame];
    
    //[[self sbglview] render:frame];
    /*if (_glView) {
        
        [_glView render:frame];
        
    } else {
        
        KxVideoFrameRGB *rgbFrame = (KxVideoFrameRGB *)frame;
        _imageView.image = [rgbFrame asImage];
    }*/
    
    _moviePosition = frame.position;
    //NSLog(@"%.2f",frame.duration);
    return frame.duration;
}

- (void) presentSubtitles
{
    NSArray *actual, *outdated;
    
    if ([self subtitleForPosition:_moviePosition
                           actual:&actual
                         outdated:&outdated]){
        
        if (outdated.count) {
            @synchronized(_subtitles) {
                [_subtitles removeObjectsInArray:outdated];
            }
        }
        
        if (actual.count) {
            
            NSMutableString *ms = [NSMutableString string];
            for (KxSubtitleFrame *subtitle in actual.reverseObjectEnumerator) {
                if (ms.length) [ms appendString:@"\n"];
                [ms appendString:subtitle.text];
            }
            
            if (![_subtitlesLabel.text isEqualToString:ms]) {
                
                CGSize viewSize = self.view.bounds.size;
                CGSize size = [ms sizeWithFont:_subtitlesLabel.font
                             constrainedToSize:CGSizeMake(viewSize.width, viewSize.height * 0.5)
                                 lineBreakMode:NSLineBreakByTruncatingTail];
                _subtitlesLabel.text = ms;
                _subtitlesLabel.frame = CGRectMake(0, viewSize.height - size.height - 10,
                                                   viewSize.width, size.height);
                _subtitlesLabel.hidden = NO;
            }
            
        } else {
            
            _subtitlesLabel.text = nil;
            _subtitlesLabel.hidden = YES;
        }
    }
}

- (BOOL) subtitleForPosition: (CGFloat) position
                      actual: (NSArray **) pActual
                    outdated: (NSArray **) pOutdated
{
    if (!_subtitles.count)
        return NO;
    
    NSMutableArray *actual = nil;
    NSMutableArray *outdated = nil;
    
    for (KxSubtitleFrame *subtitle in _subtitles) {
        
        if (position < subtitle.position) {
            
            break; // assume what subtitles sorted by position
            
        } else if (position >= (subtitle.position + subtitle.duration)) {
            
            if (pOutdated) {
                if (!outdated)
                    outdated = [NSMutableArray array];
                [outdated addObject:subtitle];
            }
            
        } else {
            
            if (pActual) {
                if (!actual)
                    actual = [NSMutableArray array];
                [actual addObject:subtitle];
            }
        }
    }
    
    if (pActual) *pActual = actual;
    if (pOutdated) *pOutdated = outdated;
    
    return actual.count || outdated.count;
}

/*- (void) updateBottomBar
{
    UIBarButtonItem *playPauseBtn = self.playing ? _pauseBtn : _playBtn;
    [_bottomBar setItems:@[_spaceItem, _rewindBtn, _fixedSpaceItem, playPauseBtn,
                           _fixedSpaceItem, _fforwardBtn, _spaceItem] animated:NO];
}

- (void) updatePlayButton
{
    [self updateBottomBar];
}*/

- (void) updateHUD
{
    if (_disableUpdateHUD)
        return;
    
    const CGFloat duration = _decoder.duration;
    const CGFloat position = _moviePosition -_decoder.startTime;
    
    if (_progressSlider.state == UIControlStateNormal)
        _progressSlider.value = position / duration;
    _progressLabel.text = formatTimeInterval(position, NO);
    
    if (_decoder.duration != MAXFLOAT)
        _leftLabel.text = formatTimeInterval(duration - position, YES);
    
#ifdef DEBUG
    /*const NSTimeInterval timeSinceStart = [NSDate timeIntervalSinceReferenceDate] - _debugStartTime;
     NSString *subinfo = _decoder.validSubtitles ? [NSString stringWithFormat: @" %d",_subtitles.count] : @"";
     
     NSString *audioStatus;
     
     if (_debugAudioStatus) {
     
     if (NSOrderedAscending == [_debugAudioStatusTS compare: [NSDate dateWithTimeIntervalSinceNow:-0.5]]) {
     _debugAudioStatus = 0;
     }
     }
     
     if      (_debugAudioStatus == 1) audioStatus = @"\n(audio outrun)";
     else if (_debugAudioStatus == 2) audioStatus = @"\n(audio lags)";
     else if (_debugAudioStatus == 3) audioStatus = @"\n(audio silence)";
     else audioStatus = @"";
     
     _messageLabel.text = [NSString stringWithFormat:@"%d %d%@ %c - %@ %@ %@\n%@",
     _videoFrames.count,
     _audioFrames.count,
     subinfo,
     self.decoding ? 'D' : ' ',
     formatTimeInterval(timeSinceStart, NO),
     //timeSinceStart > _moviePosition + 0.5 ? @" (lags)" : @"",
     _decoder.isEOF ? @"- END" : @"",
     audioStatus,
     _buffered ? [NSString stringWithFormat:@"buffering %.1f%%", _bufferedDuration / _minBufferedDuration * 100] : @""];*/
#endif
}

- (void) showHUD: (BOOL) show
{
    //_hiddenHUD = !show;
    //_panGestureRecognizer.enabled = _hiddenHUD;
    
    //[[UIApplication sharedApplication] setIdleTimerDisabled:_hiddenHUD];
    
    [UIView animateWithDuration:0.2
                          delay:0.0
                        options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionTransitionNone
                     animations:^{
                         
                         //CGFloat alpha = _hiddenHUD ? 0 : 1;
                         CGFloat alpha = 1;
                         _topBar.alpha = alpha;
                         _topHUD.alpha = alpha;
                         _bottomBar.alpha = alpha;
                     }
                     completion:nil];
    
}

- (void) fullscreenMode: (BOOL) on
{
    _fullscreen = on;
    UIApplication *app = [UIApplication sharedApplication];
    [app setStatusBarHidden:on withAnimation:UIStatusBarAnimationNone];
    // if (!self.presentingViewController) {
    //[self.navigationController setNavigationBarHidden:on animated:YES];
    //[self.tabBarController setTabBarHidden:on animated:YES];
    // }
}

- (void) setMoviePositionFromDecoder
{
    //[_decoder resyncStream];

    NSLog(@"%0.2f %0.2f %0.2f %0.2f %0.2f" , _moviePosition, _decoder.position, [_decoder position], [_decoder duration],
_bufferedDuration);
    if ([self playing]) {
        [self pause];
    }else {
        [self play];
    }
    //_moviePosition = _decoder.position;
    //[self freeBufferedFrames];
    //[_decoder resyncStream];
    //[self freeBufferedFrames];
    //NSLog(@"%0.2f %0.2f %0.2f" , _moviePosition, _decoder.position, _decoder.duration);
}

- (void) setDecoderPosition: (CGFloat) position
{
    _decoder.position = position;
}

- (void) enableUpdateHUD
{
    _disableUpdateHUD = NO;
}

- (void) updatePosition: (CGFloat) position
               playMode: (BOOL) playMode
{
    [self freeBufferedFrames];
    
    position = MIN(_decoder.duration - 1, MAX(0, position));
    
    __weak LiveViewController *weakSelf = self;
    
    dispatch_async(_dispatchQueue, ^{
        
        if (playMode) {
            
            {
                __strong LiveViewController *strongSelf = weakSelf;
                if (!strongSelf) return;
                [strongSelf setDecoderPosition: position];
            }
            
            dispatch_async(dispatch_get_main_queue(), ^{
                
                __strong LiveViewController *strongSelf = weakSelf;
                if (strongSelf) {
                    [strongSelf setMoviePositionFromDecoder];
                    [strongSelf play];
                }
            });
            
        } else {
            
            {
                __strong LiveViewController *strongSelf = weakSelf;
                if (!strongSelf) return;
                [strongSelf setDecoderPosition: position];
                [strongSelf decodeFrames];
            }
            
            dispatch_async(dispatch_get_main_queue(), ^{
                
                __strong LiveViewController *strongSelf = weakSelf;
                if (strongSelf) {
                    
                    //[strongSelf enableUpdateHUD];
                    [strongSelf setMoviePositionFromDecoder];
                    [strongSelf presentFrame];
                    //[strongSelf updateHUD];
                }
            });
        }
    });
}

- (void) freeBufferedFrames
{
    @synchronized(_videoFrames) {
        [_videoFrames removeAllObjects];
    }
    
    /*@synchronized(_audioFrames) {
     
     [_audioFrames removeAllObjects];
     _currentAudioFrame = nil;
     }*/
    
    if (_subtitles) {
        @synchronized(_subtitles) {
            [_subtitles removeAllObjects];
        }
    }
    
    _bufferedDuration = 0;
}

- (void) handleDecoderMovieError: (NSError *) error
{
    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Failure", nil)
                                                        message:[error localizedDescription]
                                                       delegate:nil
                                              cancelButtonTitle:NSLocalizedString(@"Close", nil)
                                              otherButtonTitles:nil];
    
    [alertView show];
}

- (BOOL) interruptDecoder
{
    //if (!_decoder)
    //    return NO;
    return _interrupted;
}

@end


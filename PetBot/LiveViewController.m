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
#import "GCDAsyncUdpSocket.h"
#import "STUNClient.h"

#import <MessageUI/MFMailComposeViewController.h>
#import <Social/Social.h>
#import <MobileCoreServices/MobileCoreServices.h>

////////////////////////////////////////////////////////////////////////////////




static NSMutableDictionary * gHistory;
static dispatch_queue_t _streamVideoDispatchQueue;


@interface LiveViewController () {
    
    BOOL _decodeFramesRunning;
    BOOL _drawFramesRunning;
    
    
    KxMovieDecoder      *_decoder;
    dispatch_queue_t    _dispatchQueue;
    dispatch_queue_t    _drawDispatchQueue;
    dispatch_semaphore_t _frameSemaphore;
    dispatch_semaphore_t _decodeSemaphore;
    dispatch_semaphore_t _drawSemaphore;
    
    //dispatch_semaphore_t _frameMutex;
    NSLock *_frameMutex;
    
    NSArray             *_quotes;
    
    NSMutableArray      *_videoFrames;
    CGFloat             _moviePosition;
    BOOL                _fitMode;
    BOOL                _infoMode;
    BOOL                _restoreIdleTimer;
    BOOL                _interrupted;
    BOOL                _shutdown;
    NSString            *_path;
    
    NSInteger           _state;
    
    BOOL                _takeSnapshot;
    BOOL                _wantRotate;
    
    
    NSInteger           _missed_rtsp_key;
    BOOL                _frameDecode;
    
    NSTimer * streamVideoTimer;
    
    KxMovieGLView       *_glView;
    UIImageView         *_imageView;
    UIView              *_topHUD;
    UIToolbar           *_topBar;
    UIToolbar           *_bottomBar;
    UISlider            *_progressSlider;
    
    
    UIButton            *_logoutButton;
    UIButton            *_snapButton;
    UIButton            *_cookieButton;
    UIButton            *_soundButton;
    UIActivityIndicatorView *_activityIndicatorView;
    
    NSInteger           _local_port;
    NSInteger            _advertised_port;
    GCDAsyncUdpSocket *udpSocket;
    
    
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
@property (readwrite, strong) KxArtworkFrame *artworkFrame;

@end

NSString            *_segueMutex =@"mutex";

@implementation LiveViewController

-(void)didReceivePublicIPandPort:(NSDictionary *) data{
    NSLog(@"Public IP=%@, public Port=%@ ", [data objectForKey:publicIPKey],
          [data objectForKey:publicPortKey]);
    NSNumber * nat_port =[data objectForKey:publicPortKey];
    [udpSocket close];
    _advertised_port=[nat_port integerValue];
    _state=3;
    [self finishInit];
}


-(void)streamVideoTimerF: (NSTimer *)timer {
    @autoreleasepool {
        
        NSDictionary * d = [PetConnection streamVideo];
        if ([d objectForKey:@"rtsp"]==nil) {
            _missed_rtsp_key++;
            NSLog(@"Missing RTSP KEY");
            if (_missed_rtsp_key>2) {
                NSLog(@"missed rtsp key too many times");
                NSDictionary *userInfo = @{NSLocalizedDescriptionKey: NSLocalizedString(@"Cannot connect to PetBot Video.", nil)};
                NSError *error = [NSError errorWithDomain:@"PetBot.ca"
                                                     code:-57
                                                 userInfo:userInfo];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self handleDecoderMovieError:error];
                });
                [timer invalidate];
            }
            //NSLog(@"NO RTSP STREAM AVAILABLE");
        } else {
            NSLog(@" RTSP STREAM AVAILABLE %@" , [d objectForKey:@"rtsp"]);
            if (_path==nil) { //TODO check if path changed?
                _path=[d objectForKey:@"rtsp"];
                _state=2;
                [self initWithContent];
            }
        }
        d=nil;
    }
}

+ (void)initialize
{
    if (!gHistory)
        gHistory = [NSMutableDictionary dictionary];
}

- (BOOL)prefersStatusBarHidden { return YES; }


- (void) finishInit {
    NSLog(@"setting advertised to %d and local to %d", _advertised_port,_local_port);
    
    _moviePosition = 0;
    //        self.wantsFullScreenLayout = YES;
    
    
    __weak LiveViewController *weakSelf = self;
    
    
    
    KxMovieDecoder *decoder = [[KxMovieDecoder alloc] init];
    
    decoder.local_port=_local_port;
    decoder.advertised_port=_advertised_port;
    
    decoder.interruptCallback = ^BOOL(){
        
        __strong LiveViewController *strongSelf = weakSelf;
        return strongSelf ? [strongSelf interruptDecoder] : YES;
    };
    
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        
        NSError *error = nil;
        [decoder openFile:_path error:&error ];
        
        if (error) {
            NSLog(@"something bad happened should probably stop and kill it");
        }
        
        __strong LiveViewController *strongSelf = weakSelf;
        if (strongSelf) {
            
            dispatch_sync(dispatch_get_main_queue(), ^{
                
                [strongSelf setMovieDecoder:decoder withError:error];
            });
        }
    });
}

- (id) initWithContent
{
    self = [super init];
    udpSocket = [[GCDAsyncUdpSocket alloc] initWithDelegate:self delegateQueue:dispatch_get_main_queue()];
    
    _frameSemaphore =  dispatch_semaphore_create( 0 ); //semaphore for frames
    _drawSemaphore = dispatch_semaphore_create( 0 ); //semaphore for kill draw thread
    _decodeSemaphore = dispatch_semaphore_create( 0 ); //semaphore for kill decode thread
    _frameMutex = [[NSLock alloc] init]; //dispatch_semaphore_create(1);
    //dispatch_semaphore_signal(_frameMutex);
    
    STUNClient *stunClient = [[STUNClient alloc] init];
    [stunClient requestPublicIPandPortWithUDPSocket:udpSocket delegate:self];
    NSLog(@"Local port %d", [udpSocket localPort_IPv4]);
    _local_port=[udpSocket localPort_IPv4];
    
    /*path=@"rtsp://162.243.126.214/proxyStream?max_port=19091&min_port=19092"*/
    _missed=0;
    NSAssert(_path.length > 0, @"empty path");
    
    self = [super initWithNibName:nil bundle:nil];
    return self;
}



- (void) dealloc
{
    [self pause];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    
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

-(void)getQuotes {
    _quotes = [PetConnection get_quotes];
}

- (void) dropCookie {
    dispatch_async(dispatch_get_main_queue(), ^{
        [PetConnection cookieDrop];
    });
}

- (void) playSound {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self performSegueWithIdentifier:@"toSoundPicker" sender:self];
        //[PetConnection playSound:8];
    });
}

- (void) logout {
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self stopStream]) {
            [PetConnection logout];
            
            @synchronized(_segueMutex) {
                NSLog(@"logging out");
                //[self performSegueWithIdentifier:@"logout" sender:self];
                _state=-1;
                [streamVideoTimer invalidate];
                [self dismissViewControllerAnimated:true completion:nil];
            }
        }
    });
    
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
    _activityIndicatorView.transform = CGAffineTransformMakeScale(2, 2);
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
    
    UIColor * c = [UIColor colorWithRed:0.469124 green:0.789775 blue:0.891733 alpha:1];
    
    // bottom hud
    _cookieButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _cookieButton.frame = CGRectMake(10, height-55, MIN(width/3,200), 45);
    _cookieButton.backgroundColor = c;
    [_cookieButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [_cookieButton setTitle:NSLocalizedString(@"Cookie", nil) forState:UIControlStateNormal];
    _cookieButton.titleLabel.font = [UIFont boldSystemFontOfSize:27.0]; //[UIFont systemFontOfSize:18];
    _cookieButton.showsTouchWhenHighlighted = YES;
    [_cookieButton addTarget:self action:@selector(dropCookie)
            forControlEvents:UIControlEventTouchUpInside];
    _cookieButton.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleRightMargin;// | UIViewAutoresizingFlexibleWidth;
    _cookieButton.alpha=0.8;
    _cookieButton.layer.cornerRadius=10;
    _cookieButton.layer.masksToBounds=true;
    [[ self view] addSubview: _cookieButton];
    
    _soundButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _soundButton.frame = CGRectMake(width-MIN(width/3,200)-10, height-55, MIN(width/3,200), 45);
    _soundButton.backgroundColor = c;
    [_soundButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [_soundButton setTitle:NSLocalizedString(@"Sound", nil) forState:UIControlStateNormal];
    _soundButton.titleLabel.font = [UIFont boldSystemFontOfSize:27.0]; //[UIFont systemFontOfSize:18];
    _soundButton.showsTouchWhenHighlighted = YES;
    [_soundButton addTarget:self action:@selector(playSound)
           forControlEvents:UIControlEventTouchUpInside];
    _soundButton.autoresizingMask = UIViewAutoresizingFlexibleTopMargin |  UIViewAutoresizingFlexibleLeftMargin;// | UIViewAutoresizingFlexibleWidth;
    _soundButton.alpha=0.8;
    _soundButton.layer.cornerRadius=10;
    _soundButton.layer.masksToBounds=true;
    [[ self view] addSubview: _soundButton];
    
    _logoutButton = [UIButton buttonWithType:UIButtonTypeCustom];
    
    _logoutButton.frame = CGRectMake(width-MIN(width/3,200)-10, 10, MIN(width/3,200), 45);
    _logoutButton.backgroundColor = c;
    [_logoutButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [_logoutButton setTitle:NSLocalizedString(@"Logout", nil) forState:UIControlStateNormal];
    _logoutButton.titleLabel.font = [UIFont boldSystemFontOfSize:27.0]; //[UIFont systemFontOfSize:18];
    _logoutButton.showsTouchWhenHighlighted = YES;
    [_logoutButton addTarget:self action:@selector(logout)
            forControlEvents:UIControlEventTouchUpInside];
    _logoutButton.autoresizingMask = UIViewAutoresizingFlexibleBottomMargin |   UIViewAutoresizingFlexibleLeftMargin;// | UIViewAutoresizingFlexibleWidth;
    _logoutButton.alpha=0.8;
    _logoutButton.layer.cornerRadius=10;
    _logoutButton.layer.masksToBounds=true;
    [[ self view] addSubview: _logoutButton];
    
    _snapButton = [UIButton buttonWithType:UIButtonTypeCustom];
    //_cookieButton.frame = CGRectMake(10, height-90, MIN(width/3,200), 80);
    _snapButton.frame = CGRectMake(10, 10, MIN(width/3,200), 45);
    _snapButton.backgroundColor = c;
    [_snapButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [_snapButton setTitle:NSLocalizedString(@"Share", nil) forState:UIControlStateNormal];
    _snapButton.titleLabel.font = [UIFont boldSystemFontOfSize:27.0]; //[UIFont systemFontOfSize:18];
    _snapButton.showsTouchWhenHighlighted = YES;
    [_snapButton addTarget:self action:@selector(snapshot)
          forControlEvents:UIControlEventTouchUpInside];
    _snapButton.autoresizingMask = UIViewAutoresizingFlexibleBottomMargin |  UIViewAutoresizingFlexibleRightMargin;// | UIViewAutoresizingFlexibleWidth;
    _snapButton.alpha=0.8;
    _snapButton.layer.cornerRadius=10;
    _snapButton.layer.masksToBounds=true;
    [[ self view] addSubview: _snapButton];
    
    
    
    
    
    
    if (_decoder) {
        [self setupPresentView];
    }
}

- (UIImage *)imageWithImage:(UIImage *)image scaled:(float)scale {
    //UIGraphicsBeginImageContext(newSize);
    // In next line, pass 0.0 to use the current device's pixel scaling factor (and thus account for Retina resolution).
    // Pass 1.0 to force exact pixel size.
    CGSize newSize = CGSizeMake(image.size.width*scale,image.size.height*scale);
    UIGraphicsBeginImageContextWithOptions(newSize, NO, 0.0);
    [image drawInRect:CGRectMake(0, 0, newSize.width, newSize.height)];
    UIImage *newImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return newImage;
}

- (UIImage*) maskImage:(UIImage *)image {
    UIImage *maskImage = [self imageWithImage:[UIImage imageNamed:@"logo_smaller.png"] scaled:0.2];
    
    
    
    //CGImageRef maskRef = maskImage.CGImage;
    
    
    UIImage *backgroundImage = image;
    UIImage *watermarkImage = maskImage;
    
    UIGraphicsBeginImageContext(backgroundImage.size);
    [backgroundImage drawInRect:CGRectMake(0, 0, backgroundImage.size.width, backgroundImage.size.height)];
    [watermarkImage drawInRect:CGRectMake(backgroundImage.size.width - watermarkImage.size.width, backgroundImage.size.height - watermarkImage.size.height, watermarkImage.size.width, watermarkImage.size.height)];
    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

-(void)suspendQs {
    dispatch_suspend(_dispatchQueue); //TODO can probably let network one work
    dispatch_suspend(_drawDispatchQueue);
}

-(void)resumeQs {
    dispatch_resume(_dispatchQueue);
    dispatch_resume(_drawDispatchQueue);
}

-(BOOL)snapshotWithImg:(UIImage *)img {
    //dispatch_semaphore_wait(_frameMutex, DISPATCH_TIME_FOREVER);
    //[_frameMutex lock]; //have this lock going in!
    //img= [self maskImage:[_decoder currentImage] ];
    //dispatch_semaphore_signal(_frameMutex);
    //[_frameMutex unlock];
    NSMutableArray *sharingItems = [NSMutableArray new];
    
    
    NSString * quote;
    if (_quotes==nil) {
        NSArray *quotes; //TODO download more quotes
        quotes = [NSArray arrayWithObjects:
                  @"Another awesome PetSelfie! #petbot",
                  @"Where my treats at dawg? #petbot",
                  @"Who let the dog out? #petbot",
                  @"My best puppy face. #petbot",
                  @"What I do when you're not here. #petbot",
                  nil];
        uint32_t rnd = arc4random_uniform([quotes count]);
        quote = [quotes objectAtIndex:rnd];
    } else {
        NSLog(@"have quotes from server");
        uint32_t rnd = arc4random_uniform([_quotes count]);
        quote = [_quotes objectAtIndex:rnd];
    }
    
    [sharingItems addObject:quote];
    [sharingItems addObject:img];
    //[sharingItems addObject:url];
    
    UIActivityViewController *activityController = [[UIActivityViewController alloc] initWithActivityItems:sharingItems applicationActivities:nil];
    [self presentViewController:activityController animated:YES completion:nil];
    //[_glView captureToPhotoAlbum];
    return true;
}

-(BOOL)snapshot {
    if (_takeSnapshot==false) {
        _takeSnapshot=true;
        return true;
    }
    return false;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    
    if (self.playing) {
        
        LoggerStream(0, @"didReceiveMemoryWarning, disable buffering and continue playing");
        
    } else {
        
        [_decoder closeFile];
        //[_decoder openFile:nil error:nil];
    }
}



- (void)viewDidLoad
{
    [super viewDidLoad];
    NSLog(@"ViewDidLoad state is %ul",_state);
    @synchronized(self) {
        if (_state==0) {
            _state=1;
            NSLog(@"ViewDidLoad state is %ul",_state);
            _missed_rtsp_key=0;
            streamVideoTimer = [NSTimer scheduledTimerWithTimeInterval:1.0f
                                                                target:self selector:@selector(streamVideoTimerF:) userInfo:nil repeats:YES];
            dispatch_async(dispatch_get_main_queue(),^(void){
                [self getQuotes];
            });
            
        }
    }
    LoggerStream(1, @"ViewDidload");
}



- (void) viewDidAppear:(BOOL)animated
{
    
    @synchronized(_segueMutex) {
        LoggerStream(1, @"viewDidAppear");
        
        [super viewDidAppear:animated];
        
        
        _savedIdleTimer = [[UIApplication sharedApplication] isIdleTimerDisabled];
        
        if (_decoder) {
            NSLog(@"starting play");
            //[self restorePlay];
        } else {
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
    }
}

- (void) viewWillDisappear:(BOOL)animated
{
    NSLog(@"View will disappear");
    //[self stopStream];
    /*[[NSNotificationCenter defaultCenter] removeObserver:self];
     
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
     _interrupted = YES;*/
    
    LoggerStream(1, @"viewWillDisappear %@", self);
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return (interfaceOrientation != UIInterfaceOrientationPortraitUpsideDown);
}

- (void) applicationWillResignActive: (NSNotification *)notification
{
    LoggerStream(1, @"applicationWillResignActive");
}

-(BOOL) stopStream {
    if (!_shutdown) {
        @synchronized(self) {
            _state=-1;
            _shutdown=true;
            NSLog(@"Waiting to kill decode thread");
            //TODO should set timeout on av_read_frame?
            if (_decodeFramesRunning) {
                dispatch_semaphore_wait(_decodeSemaphore,DISPATCH_TIME_FOREVER);
            }
            NSLog(@"decode thread is dead");
            if (_drawFramesRunning) {
                dispatch_semaphore_signal(_frameSemaphore); //just in case need to signal
                dispatch_semaphore_wait(_drawSemaphore,DISPATCH_TIME_FOREVER);
            }
            NSLog(@"draw thread is dead");
            [_decoder closeFile];
            //[_decoder openFile:nil error:nil];
            NSLog(@"decoder closed");
            if ([streamVideoTimer isValid]) {
                [streamVideoTimer invalidate];
            }
            [_glView removeFromSuperview];
            _glView=nil;
            _decoder=nil;
            _dispatchQueue=nil;
            _drawDispatchQueue=nil;
            _imageView=nil;
            udpSocket=nil;
            _videoFrames=nil;
            _parameters=nil;
            NSLog(@"All good can exit now");
            
        }
        return true;
    } else {
        return false;
    }
    
    
}

-(void) startStream {
    @synchronized(self) {
        //start the stream pulse
        if ([streamVideoTimer isValid]) {
            [streamVideoTimer invalidate];
        }
        if (_state<0) { //should probably check this better
            return;
        }
        streamVideoTimer = [NSTimer scheduledTimerWithTimeInterval:4.0f
                                                            target:self selector:@selector(streamVideoTimerF:) userInfo:nil repeats:YES];
        
        _decodeFramesRunning = true;
        [self asyncDecodeFrames];
        
        //start the drawing thread
        _drawFramesRunning = true;
        
        _drawDispatchQueue  = dispatch_queue_create("draw", DISPATCH_QUEUE_SERIAL);
        dispatch_async(_drawDispatchQueue,^(void){
            [self tick];
        });
    }
}


- (void) applicationDidBecomeActive: (NSNotification *)notification
{
    //[self startStream];
    LoggerStream(1, @"applicationDidBecomeActive");
}

#pragma mark - public

-(void) play
{
    
    
    self.playing = YES;
    _interrupted = NO;
    
    [self startStream];
    
    LoggerStream(1, @"play movie");
}

- (void) pause
{
    if (!self.playing)
        return;
    
    self.playing = NO;
    //Stop streaming, give error and go to login?
    //try to reconnect, give error and go to login
    
    LoggerStream(1, @"pause movie");
}

- (void) setMoviePosition: (CGFloat) position
{
    BOOL playMode = self.playing;
    
    self.playing = NO;
    
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
        
        
        _minBufferedDuration = 0.0;
        
        _maxBufferedDuration = 0.0;
        
        _decoder.disableDeinterlacing = true;
        
        LoggerStream(2, @"buffered limit: %.1f - %.1f", _minBufferedDuration, _maxBufferedDuration);
        
        if (self.isViewLoaded) {
            LoggerStream(2,@"setting up VIEW");
            [self setupPresentView];
            
            
            if (_activityIndicatorView.isAnimating) {
                
                //[_activityIndicatorView stopAnimating];
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
    
    UIView *frameView = [self frameView];
    frameView.contentMode = UIViewContentModeScaleAspectFit;
    frameView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleBottomMargin;
    
    [self.view insertSubview:frameView atIndex:0];
    
    if (!_decoder.validVideo) {
        _imageView.image = [UIImage imageNamed:@"kxmovie.bundle/music_icon.png"];
        _imageView.contentMode = UIViewContentModeCenter;
    }
    
    self.view.backgroundColor = [UIColor clearColor];
    
}

- (UIView *) frameView
{
    return _glView;
}


- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration {
    //dispatch_semaphore_wait(_frameMutex, DISPATCH_TIME_FOREVER);
    _wantRotate=true;
    [_frameMutex lock];
    _wantRotate=false;
    //[self suspendQs];
    //[_glView removeFromSuperview];
    //_glView=nil;
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation {
    //CGRect bounds = self.view.bounds;
    //_glView = [[KxMovieGLView alloc] initWithFrame:bounds decoder:_decoder];
    //dispatch_semaphore_signal(_frameMutex);
    [_frameMutex unlock];
    //[self resumeQs];
}

- (void) asyncDecodeFrames
{
    
    __weak KxMovieDecoder *weakDecoder = _decoder;
    
    dispatch_async(_dispatchQueue, ^{ //TODO make this higher priority queue?
        
        
        int nil_frames=0;
        BOOL good=true;
        while (good) { //TODO test on some sort of play condition?
            
            @autoreleasepool {
                
                __strong KxMovieDecoder *decoder = weakDecoder;
                if (decoder && decoder.validVideo) {
                    
                    KxVideoFrame * kf=nil;
                    kf = [_decoder decodeFrame];
                    if (kf==nil) {
                        nil_frames++;
                    }
                    if (nil_frames>30) {
                        NSLog(@"Killing decode thread - nil frames");
                        NSDictionary *userInfo = @{
                                                   NSLocalizedDescriptionKey: NSLocalizedString(@"Lost connection to PetBot.", nil)
                                                   };
                        NSError *error = [NSError errorWithDomain:@"PetBot.ca"
                                                             code:-57
                                                         userInfo:userInfo];
                        _decodeFramesRunning=false;
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [self handleDecoderMovieError:error];
                        });
                        dispatch_semaphore_signal(_frameSemaphore);
                        return;
                    } else if (_shutdown) {
                        NSLog(@"Killing decode thread - shutdown");
                        _decodeFramesRunning=false;
                        dispatch_semaphore_signal(_frameSemaphore);
                        dispatch_semaphore_signal(_decodeSemaphore);
                        return;
                        //good=false;
                    } else if (kf!=nil) {
                        nil_frames-=10;
                        @synchronized(_videoFrames) {
                            if (kf.type == KxMovieFrameTypeVideo) {
                                [_videoFrames addObject:kf];
                                dispatch_semaphore_signal(_frameSemaphore);
                                //NSLog(@"Have %lu frames buffered",(unsigned long)[_videoFrames count]);
                            }
                        }
                    }
                }
            }
        }
        return;
    });
}


-(BOOL) tickHelper {
    dispatch_semaphore_wait(_frameSemaphore,DISPATCH_TIME_FOREVER);
    //have a frame! or need to exit
    if (_shutdown) {
        //shut it down
        NSLog(@"Killing draw thread");
        _drawFramesRunning=false;
        dispatch_semaphore_signal(_drawSemaphore);
        return false;
    } else {
        //draw the frame
        [self presentFrame];
    }
    return true;
}


- (void) tick
{
    BOOL good=true;
    while (good) {
        [_frameMutex lock];
        @autoreleasepool {
            for (int i=0; i<5 && good; i++ ) {
                good=[self tickHelper];
                if (_takeSnapshot) {
                    //make a new tick instance, will wait on lock while we grab snapshot
                    dispatch_async(_drawDispatchQueue,^(void){
                        [self tick];
                    });
                    //grab snapshot
                    UIImage * img= [self maskImage:[_decoder currentImage] ];
                    //let the new tick instance run
                    [_frameMutex unlock];
                    //process the snapshot
                    [self snapshotWithImg:[img copy]];
                    _takeSnapshot=false;
                    return;
                } else if (_wantRotate) {
                    //first unlock to let rotate get a good chance to grab lock
                    //then restart ourselves
                    [_frameMutex unlock];
                    dispatch_async(_drawDispatchQueue,^(void){
                        [self tick];
                    });
                    return;
                }
            }
        }
        [_frameMutex unlock];
        if ([_activityIndicatorView isAnimating]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [_activityIndicatorView stopAnimating];
            });
        }
    }
    return;
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
    
    return interval;
}

- (CGFloat) presentVideoFrame: (KxVideoFrame *) frame
{
    [_glView render:frame];
    
    _moviePosition = frame.position;
    
    return frame.duration;
}



- (void) setMoviePositionFromDecoder
{
    
    NSLog(@"%0.2f %0.2f %0.2f %0.2f %0.2f" , _moviePosition, _decoder.position, [_decoder position], [_decoder duration],
          _bufferedDuration);
    if ([self playing]) {
        [self pause];
    }else {
        [self play];
    }
}

- (void) setDecoderPosition: (CGFloat) position
{
    _decoder.position = position;
}


- (void) updatePosition: (CGFloat) position
               playMode: (BOOL) playMode
{
    
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
                //[strongSelf decodeFrames]; MISKO!!
            }
            
            dispatch_async(dispatch_get_main_queue(), ^{
                
                __strong LiveViewController *strongSelf = weakSelf;
                if (strongSelf) {
                    
                    [strongSelf setMoviePositionFromDecoder];
                    [strongSelf presentFrame];
                }
            });
        }
    });
}


- (void) handleDecoderMovieError: (NSError *) error
{
    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Failure", nil)
                                                        message:[error localizedDescription]
                                                       delegate:nil
                                              cancelButtonTitle:NSLocalizedString(@"Close", nil)
                                              otherButtonTitles:nil];
    
    [alertView show];
    
    //logout properly
    if ([self stopStream]) {
        [PetConnection logout];
        
        @synchronized(_segueMutex) {
            NSLog(@"Logging out x2");
            //[self performSegueWithIdentifier:@"logout" sender:self];
            _state=-1;
            [streamVideoTimer invalidate];
            [self dismissViewControllerAnimated:true completion:nil];
        }
    }
}

- (BOOL) interruptDecoder
{
    return _interrupted;
}

@end


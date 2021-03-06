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
    NSLock *_videoMutex;
    
    NSArray             *_quotes;
    
    NSMutableArray      *_videoFrames;
    CGFloat             _moviePosition;
    BOOL                _fitMode;
    BOOL                _infoMode;
    BOOL                _restoreIdleTimer;
    BOOL                _interrupted;
    BOOL                _shutdown;
    NSString            *_path;
    NSString            *_altPath;
    
    NSInteger           _state;
    
    BOOL                _takeSnapshot;
    BOOL                _wantRotate;
    
    long long           _frames;
    long long           _interrupts_on_same_frame;
    unsigned long long  _interrupts;
    double                _effective_fps;
    long long           _last_frame;
    double              _last_frame_time;
    
    
    NSInteger           _missed_rtsp_key;
    NSInteger           _stun_timeout;
    BOOL                _frameDecode;
    BOOL                _useUDP;
    
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
    double             _stream_time;
    double             _prog_time;
    
    NSDictionary        *_parameters;
}

@property (readwrite) BOOL playing;
@property (readwrite, strong) KxArtworkFrame *artworkFrame;

@end

NSString            *_segueMutex =@"mutex";
NSString            *_openMutex =@"mutex";

@implementation LiveViewController

-(void)didReceivePublicIPandPort:(NSDictionary *) data{
    NSLog(@"Public IP=%@, public Port=%@ ", [data objectForKey:publicIPKey],
          [data objectForKey:publicPortKey]);
    @synchronized(_openMutex) {
        if (_state<3) {
            NSNumber * nat_port =[data objectForKey:publicPortKey];
            [udpSocket close];
            _advertised_port=[nat_port integerValue];
            _state=3;
            [self openStream];
            //[_decoder closeFile];
            //_altPath=@"rtmp://petbot.ca/rtmp/000000002fb9a0bb";
            //[self openStream];
        }
    }
}



-(void)streamVideoTimerF: (NSTimer *)timer {
    @autoreleasepool {
        if (_state<3) {
            _stun_timeout++;
        }
        //NSDictionary * d = [PetConnection streamVideo];
        [PetConnection streamVideoWithCallBack:^(NSDictionary * d) {
            if ([d objectForKey:@"rtmp"]!=nil) {
                _altPath=[d objectForKey:@"rtmp"];
            }
            
            if (_useUDP) {
                if ([d objectForKey:@"rtsp"]==nil) {
                    _missed_rtsp_key++;
                    NSLog(@"Missing RTSP KEY");
                    if (_missed_rtsp_key>4) {
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
                } else {
                    if (_path==nil) {
                        _path=[d objectForKey:@"rtsp"];
                        _state=2;
                        //[self initWithContent];
                        [self querySTUN];
                    }
                }
            }
            
            
            if ((_stun_timeout>3 || _missed_rtsp_key>3) && [d objectForKey:@"rtmp"]!=nil) {
                NSLog(@"TIME OUT");
                _useUDP=false;
            }
            @synchronized(_openMutex) {
                //if we timed out on stun the lets go to RTMP
                if (_state<3 && !_useUDP)  {
                    _path=[d objectForKey:@"rtmp"];
                    _state=3;
                    [self openStream];
                }
            }
        }];

    }
}

+ (void)initialize
{
    if (!gHistory)
        gHistory = [NSMutableDictionary dictionary];
}

- (BOOL)prefersStatusBarHidden { return YES; }



- (void) openStream {
    _frameSemaphore =  dispatch_semaphore_create( 0 ); //semaphore for frames
    _drawSemaphore = dispatch_semaphore_create( 0 ); //semaphore for kill draw thread
    _decodeSemaphore = dispatch_semaphore_create( 0 ); //semaphore for kill decode thread
    _frameMutex = [[NSLock alloc] init]; //dispatch_semaphore_create(1);
    _videoMutex =[[NSLock alloc] init];
    
    NSLog(@"setting advertised to %ld and local to %ld", _advertised_port,_local_port);
    
    _moviePosition = 0;
    
    __weak LiveViewController *weakSelf = self;
    
    KxMovieDecoder *decoder = [[KxMovieDecoder alloc] init];
    
    decoder.local_port=_local_port;
    decoder.advertised_port=_advertised_port;
    
    decoder.interruptCallback = ^BOOL(){
        _interrupts++;
        if ((_interrupts%50)==0 && _last_frame==_frames ) {
                //TODO need to do time, interrupts not reliable on time spacing!
                _interrupts_on_same_frame++;
            if (_last_frame_time>0) {
                double time_on_last_frame = CFAbsoluteTimeGetCurrent()-_last_frame_time;
                if (_last_frame>30) {
                    //already started streaming
                    if (time_on_last_frame>6) {
                        _interrupted=YES;
                    }
                } else {
                    //have not started streaming give it some more time
                    if (time_on_last_frame>30) {
                        _interrupted=YES;
                    }
                }
                //NSLog(@"%lf" , time_on_last_frame);
            } else {
                _last_frame_time=CFAbsoluteTimeGetCurrent();
            }
            //NSLog(@"interrupt callback %lld %lld",_interrupts_on_same_frame,_last_frame);
        }
        if (_last_frame!=_frames) {
            _last_frame_time=CFAbsoluteTimeGetCurrent();
            _last_frame=_frames;
            _interrupts_on_same_frame=0;
        }
        //__strong LiveViewController *strongSelf = weakSelf;
        return _interrupted;
        //return strongSelf ? [strongSelf interruptDecoder] : YES;
    };
    
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        
        NSError *error = nil;
        [decoder openFile:_path altFile:_altPath error:&error ];
        //NSLog(@"RTMP ONLY!!!");
        //[decoder openFile:_altPath altFile:_path error:&error ];
        //[decoder openFile:@"http://testthis.com" altFile:@"http://testthis.com" error:&error ];
        
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


- (id) querySTUN
{
    //self = [super init];
    udpSocket = [[GCDAsyncUdpSocket alloc] initWithDelegate:self delegateQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH,0)];
    
    STUNClient *stunClient = [[STUNClient alloc] init];
    
    [stunClient requestPublicIPandPortWithUDPSocket:udpSocket delegate:self];
    NSLog(@"Local port %d", [udpSocket localPort_IPv4]);
    _local_port=[udpSocket localPort_IPv4];
    
    NSAssert(_path.length > 0, @"empty path");
    
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
    [PetConnection getQuotesWithCallBack:^(NSArray * d) {
        if (d==nil) {
            //there has been an error : TODO
        } else {
            _quotes=d;
        }
    }];
}

- (void) dropCookie {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW,0), ^{
        [PetConnection cookieDropWithCallBack:^(BOOL dropped) {
            if (dropped) {
                //TODO should do something
            } else {
                //TODO should do something else?
                //try again?
                //depends on what failed? no treats or error?
            }
        }];
    });
}

- (void) playSound {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW,0), ^{
        [self performSegueWithIdentifier:@"toSoundPicker" sender:self];
    });
}

- (void) logout {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH,0), ^{
        if ([self shutdownVideo]) {
            [PetConnection logoutWithCallBack:^(BOOL logged_out) {
                //TODO should try again if fail?
                @synchronized(_segueMutex) {
                    NSLog(@"logging out");
                    //[self performSegueWithIdentifier:@"logout" sender:self];
                    _state=-1;
                    [streamVideoTimer invalidate];
                    [self dismissViewControllerAnimated:true completion:nil];
                }
            }];
            
            
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

    if (floor(NSFoundationVersionNumber) > NSFoundationVersionNumber_iOS_6_1) {
        activityController.excludedActivityTypes = @[UIActivityTypeAirDrop];
    }
    
    activityController.popoverPresentationController.sourceView = self.view;
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
    NSLog(@"ViewDidLoad state is %ld",_state);
    _frames=0;
    _interrupts_on_same_frame=0;
    _last_frame_time=0;
    _last_frame=0;
    _interrupts=0;
    _effective_fps=25;
    @synchronized(self) {
        if (_state==0) {
            _state=1;
            NSLog(@"ViewDidLoad state is %ld",_state);
            _missed_rtsp_key=0;
            _stun_timeout=0;
            _useUDP=true;
            streamVideoTimer = [NSTimer scheduledTimerWithTimeInterval:1.0f
                                                                target:self selector:@selector(streamVideoTimerF:) userInfo:nil repeats:YES];
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW,0),^(void){
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
    [super viewWillDisappear:animated];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return (interfaceOrientation != UIInterfaceOrientationPortraitUpsideDown);
}

- (void) applicationWillResignActive: (NSNotification *)notification
{
    LoggerStream(1, @"applicationWillResignActive");
}



-(BOOL) shutdownVideo {
    if (!_shutdown) {
        @synchronized(self) {
            _state=-1;
            _interrupted=YES;
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
    
    @synchronized(self) {
        //start the stream pulse
        if ([streamVideoTimer isValid]) {
            [streamVideoTimer invalidate];
        }
        if (_state<0) { //should probably check this better
            return;
        }
        _missed_rtsp_key=0;
        _stun_timeout=0;
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
                
                [_activityIndicatorView stopAnimating];
                // if (self.view.window)
                //[self restorePlay];
                [self play];
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

/*- (void) restorePlay
{
    NSNumber *n = [gHistory valueForKey:_decoder.path];
    if (n)
        [self updatePosition:n.floatValue playMode:YES];
    else
        [self play];
}*/

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
                    if (nil_frames>20) {
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
                        nil_frames=MAX(0,nil_frames-10);
                        
                        
                            if (kf.type == KxMovieFrameTypeVideo) {
                                [_videoMutex lock];
                                [_videoFrames addObject:kf];
                                [_videoMutex unlock];
                                dispatch_semaphore_signal(_frameSemaphore);
                                kf=nil;
                                //NSLog(@"Have %lu frames buffered",(unsigned long)[_videoFrames count]);
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
        _frames++;
        if (_frames%1000==0) {
            NSDate* date = [NSDate date];
            
            //Create the dateformatter object
            NSDateFormatter* formatter = [[NSDateFormatter alloc] init] ;
            
            //Set the required date format
            [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
            
            //Get the string date
            NSString* str = [formatter stringFromDate:date];
            
            //Display on the console
            NSLog(@"%@ %lld", str, _frames);
        }
        
            if (_decoder.validVideo) {
                KxVideoFrame *frame;
                
                NSInteger frames = _videoFrames.count;
                if (frames > 0) {
                    //NSLog(@"have %ld frames",_videoFrames.count);
                        [_videoMutex lock];
                        frame = _videoFrames[0];
                        [_videoFrames removeObjectAtIndex:0];
                        [_videoMutex unlock];
                }
                
                //_bufferedDuration -= frame.duration;
                if (frame) {
                    [_glView render:frame];
                    
                    _moviePosition = frame.position;
                    if (frames<=_effective_fps/2) {
                        //NSLog(@"Not enough frames!!!");
                        _effective_fps-=0.3;
                    } else if (frames>_effective_fps) { //means we have 1 second buffered?
                        _effective_fps+=0.05*(frames/_effective_fps);
                        //NSLog(@"WAy too many frames!!!");
                    } else if (frames>_effective_fps/2) { //means we have half second buffered
                        //NSLog(@"too many frames!!!");
                        _effective_fps+=0.05;
                    }
                    //NSLog(@"%lf fps", _effective_fps);
                    usleep(1000000/_effective_fps);
                    
                }
                
            }
        
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
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0), ^{
                [_activityIndicatorView stopAnimating];
            });
        }
    }
    return;
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




- (void) handleDecoderMovieError: (NSError *) error
{
    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Failure", nil)
                                                        message:[error localizedDescription]
                                                       delegate:nil
                                              cancelButtonTitle:NSLocalizedString(@"Close", nil)
                                              otherButtonTitles:nil];
    
    [alertView show];
    
    //logout properly
    if ([self shutdownVideo]) {
        [PetConnection logoutWithCallBack:^(BOOL logged_out) {
            @synchronized(_segueMutex) {
                NSLog(@"Logging out x2");
                //[self performSegueWithIdentifier:@"logout" sender:self];
                _state=-1;
                [streamVideoTimer invalidate];
                [self dismissViewControllerAnimated:true completion:nil];
            }
        }];
        
        
    }
}


@end


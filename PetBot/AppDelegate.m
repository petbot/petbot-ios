//
//  AppDelegate.m
//  PetView
//
//  Created by Misko Dzamba on 2014-06-06.
//  Copyright (c) 2014 PetBot. All rights reserved.
//

#import "AppDelegate.h"
#import "LiveViewController.h"
#import "KxMovieDecoder.h"


@implementation AppDelegate

- (void) methodB:(NSTimer *)timer
{
    //Do calculations.
    //NSLog(@"TESTXXXX");
    //[vc setMoviePositionFromDecoder];
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    //[KxMovieDecoder setLogLevel:0];
    // Override point for customization after application launch.
    /*NSLog(@"PRESSED BUTTON");
    NSString *path = @"rtmp://162.243.126.214/rtmp/000000007221d3e3";
    
    vc = [LiveViewController movieViewControllerWithContentPath:path parameters:nil];
    
    
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.rootViewController = vc;
    [self.window makeKeyAndVisible];*/
    /*[NSTimer scheduledTimerWithTimeInterval:15.0f
                                     target:self selector:@selector(methodB:) userInfo:nil repeats:YES];*/
    return YES;
}
							
- (void)applicationWillResignActive:(UIApplication *)application
{
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
    
    NSLog(@"active ");
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later. 
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    
    NSLog(@"enter background");
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
    NSLog(@"foreground");
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    
    NSLog(@"background");
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}

@end

//
//  LiveViewController.h
//  PetView
//
//  Created by Misko Dzamba on 2014-06-07.
//  Copyright (c) 2014 PetBot. All rights reserved.
//

#import <UIKit/UIKit.h>

#import "KxMovieGLView.h"
@class KxMovieDecoder;

@interface LiveViewController : UIViewController
+ (id) movieViewControllerWithContentPath: (NSString *) path
                               parameters: (NSDictionary *) parameters;
@property (readonly) BOOL playing;

- (void) play;
- (void) pause;
- (void) setMoviePositionFromDecoder;
@end



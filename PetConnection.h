//
//  PetConnection.h
//  PetView
//
//  Created by Misko Dzamba on 2014-06-07.
//  Copyright (c) 2014 PetBot. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
enum {
    CONNECTION_ERROR,
    CONNECTION_FAILED_CONNECT,
    CONNECTION_BAD_PASSWORD,
    CONNECTION_OK
};


@interface PetConnection : NSObject

+(PetConnection*)getInstance;
+(void)loginUsername:(NSString *)username password:(NSString *)password withCallBack:(void (^)(NSInteger))cb;
+(void)playSound:(NSInteger)index withCallBack:(void (^)(BOOL played))cb;
+(void)playSoundfile:(NSString *)soundfile withCallBack:(void (^)(BOOL played))cb;
+(void)listSoundsWithCallBack:(void (^)(NSArray *))cb;
+(void)streamVideoWithCallBack:(void (^)(NSDictionary *))cb;
+(NSString*)streamURL;
+(void) removeSoundfile:(NSString * )soundfile withCallBack:(void (^)(BOOL ok))cb;
+(NSString*) soundURLFromFilename:(NSString* )soundfile;
+(void) uploadSoundURL:(NSURL *) soundfile withFilename:(NSString *)filename withCallBack:(void (^)(BOOL ok))cb;
+(void)getQuotesWithCallBack:(void (^)(NSArray *))cb;
+(void)mobileVersionSupportedWithCallBack:(void (^)(NSArray *))cb;
+ (void)logoutWithCallBack:(void (^)(BOOL logged_out))cb;

+ (void)cookieDropWithCallBack:(void (^)(BOOL dropped))cb;

@end


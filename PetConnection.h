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
+(void)loginUsername:(NSString *)username password:(NSString *)password;
+(NSData *)getUrl:(NSString*)urlString;
+(void)postDataToUrl:(NSString*)urlString jsonData:(NSData*)jsonData;
+(BOOL)cookieDrop;
+(BOOL)logout;
+(BOOL)playSound:(NSInteger)index;
+(BOOL)playSoundfile:(NSString *)soundfile;
+(NSArray *)listSounds;
+(NSDictionary*)streamVideo;
+(NSString*)streamURL;
+(BOOL) removeSoundfile:(NSString * )soundfile;
+(NSString*) soundURLFromFilename:(NSString* )soundfile;
+(BOOL) uploadSoundURL:(NSURL *) soundfile withFilename:(NSString *)filename;
+(NSArray *)get_quotes;
+(BOOL)mobile_version_supported;
@end


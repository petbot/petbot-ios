//
//  PetConnection.h
//  PetView
//
//  Created by Misko Dzamba on 2014-06-07.
//  Copyright (c) 2014 PetBot. All rights reserved.
//

#import <Foundation/Foundation.h>

enum {
    CONNECTION_ERROR,
    CONNECTION_FAILED_CONNECT,
    CONNECTION_BAD_PASSWORD,
    CONNECTION_OK
};


@interface PetConnection : NSObject
+(PetConnection*)getInstance;
+(NSInteger)loginUsername:(NSString *)username password:(NSString *)password;
+(NSData *)getUrl:(NSString*)urlString;
+(NSData *)postDataToUrl:(NSString*)urlString jsonData:(NSData*)jsonData;
+(BOOL)cookieDrop;
+(BOOL)logout;
+(BOOL)playSound:(NSInteger)index;
+(NSDictionary*)streamVideo;
+(NSString*)streamURL;

@end


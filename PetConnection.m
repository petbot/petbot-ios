//
//  PetConnection.m
//  PetView
//
//  Created by Misko Dzamba on 2014-06-07.
//  Copyright (c) 2014 PetBot. All rights reserved.
//

#import "PetConnection.h"
#import "WPXMLRPCEncoder.h"
#import "WPXMLRPCDecoder.h"


@implementation PetConnection


AVAudioPlayer *player;
static PetConnection *instance = nil;
static NSTimer * streamVideoTimer=nil;

//Dev settings
/*static NSString *baseUrl=@"http://petbot.ca:5100/";
static NSString *session=@"";
static NSString *loginUrl=@"http://petbot.ca:5100/login";
static NSString *relayUrl=@"http://petbot.ca:5100/relay";
static NSString *logoutUrl=@"http://petbot.ca:5100/logout";
static NSString *streamUrl=@"";*/

//Release settings
/*
static NSString *baseUrl=@"https://petbot.ca/";
static NSString *session=@"";
static NSString *loginUrl=@"https://petbot.ca/login";
static NSString *relayUrl=@"https://petbot.ca/relay";
static NSString *logoutUrl=@"https://petbot.ca/logout";
static NSString *streamUrl=@"";*/

//dev2 settings

static NSString *baseUrl=@"http://petbot.ca:1010/";
static NSString *session=@"";
static NSString *loginUrl=@"http://petbot.ca:1010/login";
static NSString *relayUrl=@"http://petbot.ca:1010/relay";
static NSString *logoutUrl=@"http://petbot.ca:1010/logout";
static NSString *streamUrl=@"";



+(PetConnection *)getInstance
{
    @synchronized(self)
    {
        if(instance==nil)
        {
            instance= [PetConnection new];
            
        }
    }
    return instance;
}

+(void)loginUsername:(NSString *)username password:(NSString *)password withCallBack:(void (^)(NSInteger error_no))cb
{
    //[PetConnection logout];
    NSDictionary *tmp = [[NSDictionary alloc] initWithObjectsAndKeys:
                         username, @"email",
                         password, @"password",
                         nil];
    NSError * error;
    NSData *postdata = [NSJSONSerialization dataWithJSONObject:tmp options:0 error:&error];
    if (error) {
        cb(CONNECTION_ERROR);
        return;
    }
    
    //first try to always log out
    [self logoutWithCallBack:^(BOOL b ) {
        //then try to login
        [PetConnection postDataToUrl:loginUrl jsonData:postdata withCallBack:^(NSURLResponse *response, NSData *data, NSError *error) {
            NSLog(@"%@", [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding]);
            if (data==nil) {
                cb(CONNECTION_FAILED_CONNECT);
                return;
            }
            NSDictionary* dictionary = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&error];
            if (dictionary==nil) {
                cb(CONNECTION_FAILED_CONNECT);
                return;
            }
            if ([ dictionary valueForKey:@"meta" ]!=nil) {
                NSDictionary* rsp=[ dictionary valueForKey:@"meta" ];
                if ([[rsp valueForKey:@"code"] integerValue]!=200) {
                    cb(CONNECTION_BAD_PASSWORD);
                    return;
                } else {
                    //logged in
                    cb(CONNECTION_OK);
                    return;
                }
            }
        }];
    }];


}


+(void) checkHeadersFromResponse:(NSURLResponse *)response withData:(NSData *)data andError:(NSError *)error andCB:(void (^)(NSURLResponse *, NSData *, NSError *))cb {
    if (error) {
        cb(response, data, error);
        return;
    }
    NSDictionary* headers = [(NSHTTPURLResponse *)response allHeaderFields];
    if ([headers valueForKey:@"Set-Cookie"]) {
        //session =[headers valueForKey:@"Set-Cookie"];
    }
    cb(response, data, error);
    return;
}

+(void)postDataToUrl:(NSString*)urlString jsonData:(NSData*)jsonData withCallBack:(void (^)(NSURLResponse *, NSData *, NSError *))cb
{
    NSURL *url=[NSURL URLWithString:[urlString stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    NSLog(@"POSTDATATOURL: %@", [[NSString alloc] initWithData:jsonData encoding:NSASCIIStringEncoding]);
    //responseData = [NSMutableData data] ;
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:url];
    
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    if (jsonData!=nil) {
        [request setValue:[NSString stringWithFormat:@"%lu", [jsonData length]] forHTTPHeaderField:@"Content-Length"];
        [request setHTTPBody:jsonData];
    }
    
    [NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue mainQueue] completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
        [PetConnection checkHeadersFromResponse:response withData:data andError:error andCB:cb];
    }];

}

+(NSString*)streamURL {
    return streamUrl;
}

+ (void)streamVideoWithCallBack:(void (^)(NSDictionary * ))cb {
        NSMutableURLRequest * request = [self makeXMLRequestMethod:@"streamVideo" Parameters:@[]];
        [NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue mainQueue] completionHandler:^(NSURLResponse * response, NSData * data, NSError * error ) {
            if (data==nil || error) {
                //something went wrong // TODO handle better
                cb(nil);
                return;
            } else if (cb==nil) {
                NSLog(@"fail stream vide o 2");
                return;
            } else {
                //otherwise lets get the current streams that we can connect to
                WPXMLRPCDecoder *decoder = [[WPXMLRPCDecoder alloc] initWithData:data];
                NSString * type =NSStringFromClass([[decoder object] class]);
                if (![type isEqualToString:@"__NSArrayM"]) {
                    //NSLog(@"failed in streamVideo call");
                    decoder=nil;
                    cb(nil);
                    return;
                }
                NSArray *parsedResult = [[decoder object] copy];
                //if petbot is offline this next line will segfault
                //NSLog(@"parsed results has %lu entries",(unsigned long)[parsedResult count]);
                if (parsedResult!=nil && [parsedResult count]>0) {
                    NSDictionary * streams = [parsedResult objectAtIndex:1];
                    cb(streams);
                }
                decoder=nil;
            }
        }];
}

+(NSMutableURLRequest *)makeRequest:(NSString *)url withCookie:(BOOL)with_cookie withPost:(BOOL)with_post {
    NSURL *URL = [NSURL URLWithString:url];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:URL];
    if (with_cookie) {
        //[self setSessionCookie:request];
    }
    if (with_post) {
        [request setHTTPMethod:@"POST"];
    }
    return request;
}

+(NSMutableURLRequest *)setSessionCookie:(NSMutableURLRequest *)request {
    //[request setValue:session forHTTPHeaderField:@"Cookie"];
    return request;
}

+(NSMutableURLRequest *)makeXMLRequestMethod:(NSString *)method_name Parameters:(NSArray *)parameters {
    NSMutableURLRequest * request = [self makeRequest:relayUrl withCookie:true withPost:true];
    WPXMLRPCEncoder *encoder = [[WPXMLRPCEncoder alloc] initWithMethod:method_name andParameters:parameters];
    [request setHTTPBody:encoder.body];
    [request setValue:@"text/xml" forHTTPHeaderField:@"Content-Type"];
    return request;
}


+ (void)cookieDropWithCallBack:(void (^)(BOOL dropped))cb {
    NSMutableURLRequest * request = [self makeXMLRequestMethod:@"sendCookie" Parameters:@[]];
    [NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue mainQueue] completionHandler:^(NSURLResponse * response, NSData * data, NSError * error ) {
        if (data==nil || error) {
            cb(false);
        } else {
            cb(true); //TODO should really check to make sure that TRUE was returned!
        }
    }];
}

+ (void)logoutWithCallBack:(void (^)(BOOL logged_out))cb {
    NSMutableURLRequest *request = [self makeRequest:logoutUrl withCookie:true withPost:false];
    
    [NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue mainQueue] completionHandler:^(NSURLResponse * response, NSData * data, NSError * error ) {
        //NSLog(@"%@", [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding]);
        //clear the cookies
        NSHTTPCookieStorage *cookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
        for (NSHTTPCookie *each in cookieStorage.cookies) {
            [cookieStorage deleteCookie:each];
        }
        if (data==nil || error) {
            session = nil;
            NSLog(@"logout fail");
            cb(false);
        } else {
            session = nil;
            NSLog(@"Logout ok");
            cb(true); //TODO should really check to make sure that TRUE was returned!
        }
    }];
}


+(void)playSound:(NSInteger)index withCallBack:(void (^)(BOOL player))cb {
    NSMutableURLRequest *request = [self makeXMLRequestMethod:@"playSound" Parameters:[[NSArray alloc] initWithObjects:[[NSNumber alloc] initWithInteger:index], nil]];
    [NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue mainQueue] completionHandler:^(NSURLResponse * response, NSData * data, NSError * error ) {
        if (data==nil || error) {
            cb(false);
        } else {
            cb(true); //TODO should really check to make sure that TRUE was returned!
        }
    }];
}


+(void)getJSONURL:(NSString *)url withKey:(NSString *)key withCallBack:(void (^)(NSArray * d))cb {
    [PetConnection postDataToUrl:url jsonData:nil withCallBack:^(NSURLResponse * response, NSData * data, NSError * error) {
        if (error) {
            cb(nil);
            return;
        }
        if (data==nil) {
            cb(nil);
            return;
        }
        NSDictionary* dictionary = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&error];
        NSLog(@"array : %@",dictionary);
        if ([dictionary valueForKey:@"result"]!=nil) {
            NSDictionary * d = [dictionary valueForKey:@"result"];
            NSArray * a = [d valueForKey:key];
            cb(a);
            return;
        }
        cb(nil);
        return;
    }];
    return;
}


+(void) listSoundsWithCallBack:(void (^)(NSArray *))cb {
    NSString * url =[NSString stringWithFormat:@"%@%@", baseUrl , @"list_sounds"];
    [PetConnection getJSONURL:url withKey:@"sounds" withCallBack:cb];
}

+(void)getQuotesWithCallBack:(void (^)(NSArray *))cb {
    NSString * url =[NSString stringWithFormat:@"%@%@", baseUrl , @"get_quotes"];
    [PetConnection getJSONURL:url withKey:@"quotes" withCallBack:cb];

}

+(void)mobileVersionSupportedWithCallBack:(void (^)(NSArray *))cb {
    NSString * url = [NSString stringWithFormat:@"%@%@", baseUrl , @"mobile_app_supported"];
    [PetConnection postDataToUrl:url jsonData:nil withCallBack:^(NSURLResponse * response, NSData * data, NSError * error) {
        if (data==nil) {
            cb(nil);
            return;
        }
        
        NSDictionary* dictionary = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&error];
        NSLog(@"array : %@",dictionary);
        if ([dictionary valueForKey:@"result"]!=nil) {
            NSDictionary * d = [dictionary valueForKey:@"result"];
            NSLog(@"Mobile version %@",[d valueForKey:@"version"]);
            NSNumber * num = [d valueForKey:@"version"];
            NSArray * a = [NSArray arrayWithObjects:[NSNumber numberWithInt:[num intValue]],nil];
            cb(a);
            return;
        }
        cb(nil);
        return;
    }];
    

}


+(NSString*) soundURLFromFilename:(NSString* )soundfile {
    return [NSString stringWithFormat:@"%@get_sound/%@",baseUrl,soundfile];
}



+(void) playSoundfile:(NSString * )soundfile withCallBack:(void (^)(BOOL played))cb {
    NSMutableURLRequest *request = [self makeXMLRequestMethod:@"playSound" Parameters:[[NSArray alloc] initWithObjects:[self soundURLFromFilename:soundfile], nil]];
    [NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue mainQueue] completionHandler:^(NSURLResponse * response, NSData * data, NSError * error ) {
        if (data==nil || error) {
            cb(false);
        } else {
            cb(true); //TODO should really check to make sure that TRUE was returned!
        }
    }];

    //play sound locally
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayback error:nil];
    
    NSURL *mp3URL = [NSURL URLWithString:[PetConnection soundURLFromFilename:soundfile]];
    NSLog(@"url used is %@",[PetConnection soundURLFromFilename:soundfile]);
    NSData *audioData = [NSData dataWithContentsOfURL:mp3URL];
    //dispatch_async(dispatch_get_main_queue(), ^{
    NSError* error;
    player = [[AVAudioPlayer alloc] initWithData:audioData error:&error];
    NSLog(@"%@", error);
    player.volume=1;
    [player setDelegate:self];
    [player prepareToPlay];
    [player play];
}


+(void) removeSoundfile:(NSString * )soundfile withCallBack:(void (^)(BOOL ok))cb {
    NSString * url = [NSString stringWithFormat:@"%@%@/%@", baseUrl , @"remove_sound",soundfile] ;
    [PetConnection postDataToUrl:url jsonData:nil withCallBack:^(NSURLResponse * response, NSData * data, NSError * error) {
        if (data==nil || error ) {
            cb(false);
        } else {
            cb(true);
        }
        return;
    }];
}

+(void) uploadSoundURL:(NSURL *) soundfile withFilename:(NSString *)filename  withCallBack:(void (^)(BOOL ok))cb {
    NSString *urlString = [NSString stringWithFormat:@"%@post_sound",baseUrl];
    NSMutableURLRequest * request= [[NSMutableURLRequest alloc] init];
    [request setURL:[NSURL URLWithString:urlString]];
    [request setHTTPMethod:@"POST"];
    NSString *boundary = @"---------------------------14737809831466499882746641449";
    NSString *contentType = [NSString stringWithFormat:@"multipart/form-data; boundary=%@",boundary];
    [request addValue:contentType forHTTPHeaderField: @"Content-Type"];
    NSMutableData *postbody = [NSMutableData data];
    [postbody appendData:[[NSString stringWithFormat:@"\r\n--%@\r\n",boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [postbody appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"file\"; filename=\"%@.m4a\"\r\n", filename] dataUsingEncoding:NSUTF8StringEncoding]];
    [postbody appendData:[@"Content-Type: application/octet-stream\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    NSData *data = [[NSData alloc] initWithContentsOfURL:soundfile];
    [postbody appendData:[NSData dataWithData:data]];
    [postbody appendData:[[NSString stringWithFormat:@"\r\n--%@--\r\n",boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [request setHTTPBody:postbody];
    
    
    
    [NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue mainQueue] completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
        NSString * returnString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        NSLog(@"filename is %@",filename);
        NSLog(@"%@", returnString);
        if(data==nil || error) {
            cb(false);
        } else {
            cb(true);
        }
    }];
    
    //NSData *returnData = [NSURLConnection sendSynchronousRequest:request returningResponse:nil error:nil];

    return ;
}

@end





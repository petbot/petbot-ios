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
static NSString *baseUrl=@"https://petbot.ca/";
static NSString *session=@"";
static NSString *loginUrl=@"https://petbot.ca/login";
static NSString *relayUrl=@"https://petbot.ca/relay";
static NSString *logoutUrl=@"https://petbot.ca/logout";
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

+(NSInteger)loginUsername:(NSString *)username password:(NSString *)password
{
    [PetConnection logout];
    NSDictionary *tmp = [[NSDictionary alloc] initWithObjectsAndKeys:
                         username, @"email",
                         password, @"password",
                         nil];
    NSError * error;
    NSData *postdata = [NSJSONSerialization dataWithJSONObject:tmp options:0 error:&error];
    if (error) {
        return CONNECTION_FAILED_CONNECT;
    }
    
    NSData * responseData = [PetConnection postDataToUrl:loginUrl jsonData:postdata];
    if (responseData==nil) {
        return CONNECTION_FAILED_CONNECT;
    }
    NSDictionary* dictionary = [NSJSONSerialization JSONObjectWithData:responseData options:kNilOptions error:&error];
    NSLog(@"array : %@",dictionary);
    
    
    if ([ dictionary valueForKey:@"meta" ]!=nil) {
        NSDictionary* rsp=[ dictionary valueForKey:@"meta" ];
        if ([[rsp valueForKey:@"code"] integerValue]!=200) {
            //not logged in
            //NSLog(@"array : %@",[rsp valueForKey:@"code"]);
            NSLog(@"not logged in");
            return CONNECTION_BAD_PASSWORD;
        } else {
            //logged in
            NSLog(@"logged in");
            return CONNECTION_OK;
        }
    }
    
    return CONNECTION_ERROR;
}

+(NSData *)getUrl:(NSString*)urlString
{
    NSData* responseData = nil;
    NSURL *url=[NSURL URLWithString:[urlString stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    //responseData = [NSMutableData data] ;
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:url];
    
    NSURLResponse* response;
    NSError* error = nil;
    responseData = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
    //NSString *responseString = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding];
    
    //NSHTTPURLResponse *HTTPResponse = (NSHTTPURLResponse *)response;
   // NSDictionary *fields = [HTTPResponse allHeaderFields];
    
    //NSLog(@"array : %@",fields);
    //NSLog(@"the final output is:%@",responseString);
    
    return responseData;
}


+(NSData *)postDataToUrl:(NSString*)urlString jsonData:(NSData*)jsonData
{
    NSData* responseData = nil;
    NSURL *url=[NSURL URLWithString:[urlString stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    //responseData = [NSMutableData data] ;
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:url];
    
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    if (jsonData!=nil) {
        [request setValue:[NSString stringWithFormat:@"%d", [jsonData length]] forHTTPHeaderField:@"Content-Length"];
        [request setHTTPBody:jsonData];
    }
    NSURLResponse* response;
    NSError* error = nil;
    responseData = [NSURLConnection sendSynchronousRequest:request     returningResponse:&response error:&error];
    if (error) {
        NSLog(@"Error in conection");
        return nil;
    }
    NSDictionary* headers = [(NSHTTPURLResponse *)response allHeaderFields];
    NSLog(@"array w : %@",headers);
    
    if ([headers valueForKey:@"Set-Cookie"]) {
        //PetConnection *obj=[PetConnection getInstance];
        session =[headers valueForKey:@"Set-Cookie"];
        NSLog(@"set cookie");
    }
    NSString *responseString = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding];
    
    NSHTTPURLResponse *HTTPResponse = (NSHTTPURLResponse *)response;
    NSDictionary *fields = [HTTPResponse allHeaderFields];
    
    NSLog(@"array : %@",fields);
    NSLog(@"the final output is:%@",responseString);
    
    return responseData;
}

+(NSString*)streamURL {
    return streamUrl;
}

+ (NSDictionary*)streamVideo {
    NSDictionary * streams;
    @autoreleasepool {
        
        NSURL *URL = [NSURL URLWithString:relayUrl];
        NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:URL];
        [request setHTTPMethod:@"POST"];
        [request setValue:session forHTTPHeaderField:@"Cookie"];
        WPXMLRPCEncoder *encoder = [[WPXMLRPCEncoder alloc] initWithMethod:@"streamVideo" andParameters:@[]];
        [request setHTTPBody:encoder.body];
        [request setValue:@"text/xml" forHTTPHeaderField:@"Content-Type"];
        NSURLResponse* response;
        NSData* responseData = nil;
        NSError* error = nil;
        responseData = [NSURLConnection sendSynchronousRequest:request     returningResponse:&response error:&error];
        //NSString *responseString = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding];
        //NSLog(@"the final output is:%@",responseString);
        if (error){
            return false;
        }
        WPXMLRPCDecoder *decoder = [[WPXMLRPCDecoder alloc] initWithData:responseData];
        //NSLog(@"object is type %@",NSStringFromClass([[decoder object] class]));
        NSString * type =NSStringFromClass([[decoder object] class]);
        if (![type isEqualToString:@"__NSArrayM"]) {
            //NSLog(@"failed in streamVideo call");
            return nil;
        }
        NSArray *parsedResult = [[decoder object] copy];
        //if petbot is offline this next line will segfault
        //NSLog(@"parsed results has %lu entries",(unsigned long)[parsedResult count]);
        streams = [parsedResult objectAtIndex:1];
        encoder=nil;
        decoder=nil;
        //streamUrl = [parsedResult objectAtIndex:1];
        
        //NSLog(@"startStream %@",parsedResult);
    }
    
    return streams;
}


+ (BOOL)cookieDrop {
    NSURL *URL = [NSURL URLWithString:relayUrl];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:URL];
    [request setHTTPMethod:@"POST"];
    [request setValue:session forHTTPHeaderField:@"Cookie"];
    WPXMLRPCEncoder *encoder = [[WPXMLRPCEncoder alloc] initWithMethod:@"sendCookie" andParameters:@[]];
    [request setHTTPBody:encoder.body];
    [request setValue:@"text/xml" forHTTPHeaderField:@"Content-Type"];
    NSURLResponse* response;
    NSError* error = nil;
    [NSURLConnection sendSynchronousRequest:request     returningResponse:&response error:&error];
    if (error){
        return false;
    }
    //NSLog(@"drop treat");
    return true;
}

+ (BOOL)logout {
    session = nil;
    NSURL *URL = [NSURL URLWithString:logoutUrl];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:URL];
    [request setValue:session forHTTPHeaderField:@"Cookie"];
    NSURLResponse* response;
    NSData* responseData = nil;
    NSError* error = nil;
    responseData = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
    NSString *responseString = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding];
    if (error){
         NSLog(@"the final output is:%@",responseString);
        return false;
    }
    //NSLog(@"the final output is:%@",responseString);
    //NSLog(@"loggedout");
    return true;
}


+(BOOL)playSound:(NSInteger)index {
    NSURL *URL = [NSURL URLWithString:relayUrl];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:URL];
    [request setHTTPMethod:@"POST"];
    [request setValue:session forHTTPHeaderField:@"Cookie"];
    
    WPXMLRPCEncoder *encoder = [[WPXMLRPCEncoder alloc] initWithMethod:@"playSound" andParameters:[[NSArray alloc] initWithObjects:[[NSNumber alloc] initWithInteger:index], nil]];
    [request setHTTPBody:encoder.body];
    [request setValue:@"text/xml" forHTTPHeaderField:@"Content-Type"];
    NSURLResponse* response;
    NSError* error = nil;
    [NSURLConnection sendSynchronousRequest:request     returningResponse:&response error:&error];
                                //[[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding];
                                
                                //NSLog(@"the final output is:%@",responseString);
                                if (error){
        return false;
    }
    NSLog(@"play sound");
    return true;
}


+(NSArray *) listSounds {
        NSData * responseData = [PetConnection postDataToUrl:[NSString stringWithFormat:@"%@%@", baseUrl , @"list_sounds"] jsonData:nil];
        if (responseData==nil) {
            return nil;
        }
    
        NSError* error = nil;
    
        NSDictionary* dictionary = [NSJSONSerialization JSONObjectWithData:responseData options:kNilOptions error:&error];
        NSLog(@"array : %@",dictionary);
    if ([dictionary valueForKey:@"result"]!=nil) {
        NSDictionary * d = [dictionary valueForKey:@"result"];
        NSArray * a = [d valueForKey:@"sounds"];
        return a;
    }
    return nil;
}

+(NSArray *)get_quotes {
    NSData * responseData = [PetConnection postDataToUrl:[NSString stringWithFormat:@"%@%@", baseUrl , @"get_quotes"] jsonData:nil];
    if (responseData==nil) {
        return nil;
    }
    
    NSError* error = nil;
    
    NSDictionary* dictionary = [NSJSONSerialization JSONObjectWithData:responseData options:kNilOptions error:&error];
    NSLog(@"array : %@",dictionary);
    if ([dictionary valueForKey:@"result"]!=nil) {
        NSDictionary * d = [dictionary valueForKey:@"result"];
        NSArray * a = [d valueForKey:@"quotes"];
        return a;
    }
    return nil;
}


+(BOOL)mobile_version_supported {
    NSData * responseData = [PetConnection postDataToUrl:[NSString stringWithFormat:@"%@%@", baseUrl , @"mobile_app_supported"] jsonData:nil];
    if (responseData==nil) {
        return false;
    }
    
    NSError* error = nil;
    
    
    NSDictionary* dictionary = [NSJSONSerialization JSONObjectWithData:responseData options:kNilOptions error:&error];
    NSLog(@"array : %@",dictionary);
    if ([dictionary valueForKey:@"result"]!=nil) {
        NSDictionary * d = [dictionary valueForKey:@"result"];
        NSLog(@"Mobile version %@",[d valueForKey:@"version"]);
        NSNumber * num = [d valueForKey:@"version"];
        BOOL b = [num boolValue];
        return b;
    }
    return false;
}


+(NSString*) soundURLFromFilename:(NSString* )soundfile {
    return [NSString stringWithFormat:@"%@get_sound/%@",baseUrl,soundfile];
}



+(BOOL) playSoundfile:(NSString * )soundfile {
    NSURL *URL = [NSURL URLWithString:relayUrl];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:URL];
    [request setHTTPMethod:@"POST"];
    [request setValue:session forHTTPHeaderField:@"Cookie"];
    
    WPXMLRPCEncoder *encoder = [[WPXMLRPCEncoder alloc] initWithMethod:@"playSound" andParameters:[[NSArray alloc] initWithObjects:[self soundURLFromFilename:soundfile], nil]];
    [request setHTTPBody:encoder.body];
    [request setValue:@"text/xml" forHTTPHeaderField:@"Content-Type"];
    NSURLResponse* response;
    NSError* error = nil;
    [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
    //[[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding];
    
    //NSLog(@"the final output is:%@",responseString);
    if (error){
        return false;
    }
    
    //play sound locally
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayback error:nil];
    
    NSURL *mp3URL = [NSURL URLWithString:[PetConnection soundURLFromFilename:soundfile]];
    NSData *audioData = [NSData dataWithContentsOfURL:mp3URL];
    //dispatch_async(dispatch_get_main_queue(), ^{
    error = nil;
    player = [[AVAudioPlayer alloc] initWithData:audioData error:&error];
    NSLog(@"%@", error);
    player.volume=1;
    [player setDelegate:self];
    [player prepareToPlay];
    [player play];
    return true;
}


+(BOOL) removeSoundfile:(NSString * )soundfile {
    NSData * responseData = [PetConnection postDataToUrl:[NSString stringWithFormat:@"%@%@/%@", baseUrl , @"remove_sound",soundfile] jsonData:nil];
    if (responseData==nil) {
        return false;
    }
    return true;
}

+(BOOL) uploadSoundURL:(NSURL *) soundfile withFilename:(NSString *)filename {
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
    [postbody appendData:[[NSString stringWithString:@"Content-Type: application/octet-stream\r\n\r\n"] dataUsingEncoding:NSUTF8StringEncoding]];
    NSData *data = [[NSData alloc] initWithContentsOfURL:soundfile];
    [postbody appendData:[NSData dataWithData:data]];
    [postbody appendData:[[NSString stringWithFormat:@"\r\n--%@--\r\n",boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [request setHTTPBody:postbody];
    
    NSData *returnData = [NSURLConnection sendSynchronousRequest:request returningResponse:nil error:nil];
    NSString * returnString = [[NSString alloc] initWithData:returnData encoding:NSUTF8StringEncoding];
    NSLog(@"filename is %@",filename);
    NSLog(@"%@", returnString);
    return true;
}

@end





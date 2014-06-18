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


static PetConnection *instance = nil;
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
    NSDictionary* dictionary = [NSJSONSerialization JSONObjectWithData:responseData options:kNilOptions error:&error];
    //NSLog(@"array : %@",dictionary);
    
    
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
    responseData = [NSMutableData data] ;
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:url];
    
    NSURLResponse* response;
    NSError* error = nil;
    responseData = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
    NSString *responseString = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding];
    
    NSHTTPURLResponse *HTTPResponse = (NSHTTPURLResponse *)response;
    NSDictionary *fields = [HTTPResponse allHeaderFields];
    
    //NSLog(@"array : %@",fields);
    //NSLog(@"the final output is:%@",responseString);
    
    return responseData;
}


+(NSData *)postDataToUrl:(NSString*)urlString jsonData:(NSData*)jsonData
{
    NSData* responseData = nil;
    NSURL *url=[NSURL URLWithString:[urlString stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    responseData = [NSMutableData data] ;
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:url];
    
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:[NSString stringWithFormat:@"%d", [jsonData length]] forHTTPHeaderField:@"Content-Length"];
    [request setHTTPBody:jsonData];
    NSURLResponse* response;
    NSError* error = nil;
    responseData = [NSURLConnection sendSynchronousRequest:request     returningResponse:&response error:&error];
    if (error) {
        NSLog(@"Error in conection");
        return nil;
    }
    NSDictionary* headers = [(NSHTTPURLResponse *)response allHeaderFields];
    //NSLog(@"array w : %@",headers);
    
    if ([headers valueForKey:@"Set-Cookie"]) {
        //PetConnection *obj=[PetConnection getInstance];
        session =[headers valueForKey:@"Set-Cookie"];
        NSLog(@"set cookie");
    }
    NSString *responseString = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding];
    
    NSHTTPURLResponse *HTTPResponse = (NSHTTPURLResponse *)response;
    NSDictionary *fields = [HTTPResponse allHeaderFields];
    
    // NSLog(@"array : %@",fields);
    //NSLog(@"the final output is:%@",responseString);
    
    return responseData;
}

+(NSString*)streamURL {
    return streamUrl;
}

+ (BOOL)streamVideo {
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
    NSString *responseString = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding];
    //NSLog(@"the final output is:%@",responseString);
    if (error){
        return false;
    }
    WPXMLRPCDecoder *decoder = [[WPXMLRPCDecoder alloc] initWithData:responseData];
    NSArray *parsedResult = [decoder object];
    streamUrl = [parsedResult objectAtIndex:1];
    
    //NSLog(@"startStream %@",parsedResult);
    
    return true;
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
    NSData* responseData = nil;
    NSError* error = nil;
    responseData = [NSURLConnection sendSynchronousRequest:request     returningResponse:&response error:&error];
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
    NSData* responseData = nil;
    NSError* error = nil;
    responseData = [NSURLConnection sendSynchronousRequest:request     returningResponse:&response error:&error];
                                
                                NSString *responseString = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding];
                                
                                //NSLog(@"the final output is:%@",responseString);
                                if (error){
        return false;
    }
    NSLog(@"play sound");
    return true;
}
@end





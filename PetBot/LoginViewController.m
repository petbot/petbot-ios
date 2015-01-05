//
//  LoginViewController.m
//  PetView
//
//  Created by Misko Dzamba on 2014-06-07.
//  Copyright (c) 2014 PetBot. All rights reserved.
//

#import "LoginViewController.h"
#import "PetConnection.h"
#import "JNKeychain.h"

@interface LoginViewController () {
    BOOL passwordEdited;
    BOOL usernameEdited;
    __weak IBOutlet UIButton *loginButton;
    __weak IBOutlet UISwitch *rememberSwitch;
    dispatch_semaphore_t _login_action;
    dispatch_semaphore_t _logged_in;
}

@end

@implementation LoginViewController
- (IBAction)remeberSwitched:(id)sender {
    if (rememberSwitch.isOn) {
        
    } else {
        [self forgetLogin];
    }
}



//   JNKeychain interface for saving / loading
- (IBAction)rememberSwitched:(id)sender {
    NSLog(@"remember save: %@",[NSNumber numberWithBool:rememberSwitch.isOn]);
    [JNKeychain saveValue:[NSNumber numberWithBool:rememberSwitch.isOn] forKey:@"remember"];
}

-(void) forgetLogin {
    [self saveLogin:@"" password:@""];
}
-(void) saveLogin:(NSString *)username password:(NSString*)password {
    [JNKeychain saveValue:password forKey:@"password"];
    [JNKeychain saveValue:username forKey:@"username"];
}
-(NSString *) loadUsername {
    return [JNKeychain loadValueForKey:@"username"];
}
-(NSString *) loadPassword {
    return [JNKeychain loadValueForKey:@"password"];
}





- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

-(void)viewDidAppear:(BOOL)animated {
    passwordEdited=false;
    usernameEdited=false;
    
    NSString * saved_username = [self loadUsername];
    if (saved_username.length>0) {
        self.username.text=saved_username;
        usernameEdited=true;
    }
    NSString * saved_password = [self loadPassword];
    if (saved_password.length>0) {
        self.password.text=saved_password;
        passwordEdited=true;
    }
    
    //reset the locks
    long acquired = dispatch_semaphore_wait(_logged_in, DISPATCH_TIME_NOW);
    if (acquired!=0) {
        NSLog(@"Releasing lock for logged_in");
    }
    dispatch_semaphore_signal(_logged_in);
    [super viewDidAppear:animated];
}

-(void)checkVersion {
    //BOOL x = [PetConnection mobile_version_supported];
    [PetConnection mobileVersionSupportedWithCallBack:^(NSArray * a ) {
        if (a==nil) {
            //this is a different conneciton error , caught by something else on login ? // TODO
        } else if (![a objectAtIndex:0]) {
            UIAlertView *theAlert = [[UIAlertView alloc] initWithTitle:@"Version unsupported"
                                                               message:@"Please update your mobile application."
                                                              delegate:self
                                                     cancelButtonTitle:@"ok"
                                                     otherButtonTitles:nil];
            [theAlert show];
        }
    }];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH,0), ^{
        [self checkVersion];
    });
    
    _login_action = dispatch_semaphore_create(1); //make the login action semaphore
    _logged_in = dispatch_semaphore_create(1); //make the login action semaphore
    NSLog(@"remember load: %@",[JNKeychain loadValueForKey:@"remember"]);
    loginButton.showsTouchWhenHighlighted = YES;
    if ([JNKeychain loadValueForKey:@"remember"]!=nil) {
        NSNumber * x = [JNKeychain loadValueForKey:@"remember"];
        rememberSwitch.on=([x isEqualToNumber:[NSNumber numberWithInt:1]]);
    } else {
        NSLog(@"remember save1: %@",[NSNumber numberWithBool:rememberSwitch.isOn]);
        [JNKeychain saveValue:[NSNumber numberWithBool:rememberSwitch.isOn] forKey:@"rememeber"];
    }
    

    
    //[loginButton setHighlighted:true];
    // Do any additional setup after loading the view.
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

-(void) loginResponse:(NSInteger)error_no withUsername:(NSString *)given_username withPassword:(NSString *)given_password {
    switch (error_no) {
        case CONNECTION_BAD_PASSWORD: {
            [[NSUserDefaults standardUserDefaults] setValue:nil forKey:@"username"];
            [[NSUserDefaults standardUserDefaults] synchronize];
            UIAlertView *theAlert = [[UIAlertView alloc] initWithTitle:@"Login failed"
                                                               message:@"Username and/or Password are incorrect."
                                                              delegate:self
                                                     cancelButtonTitle:@"ok"
                                                     otherButtonTitles:nil];
            [theAlert show];
            
            break;
        }
        case CONNECTION_ERROR: {
            UIAlertView *theAlert = [[UIAlertView alloc] initWithTitle:@"Connection error"
                                                               message:@"Something went wrong while connecting"
                                                              delegate:self
                                                     cancelButtonTitle:@"ok"
                                                     otherButtonTitles:nil];
            [theAlert show];
            break;
        }
        case CONNECTION_FAILED_CONNECT: {
            UIAlertView *theAlert = [[UIAlertView alloc] initWithTitle:@"Failed to connect"
                                                               message:@"Connection to server has failed"
                                                              delegate:self
                                                     cancelButtonTitle:@"ok"
                                                     otherButtonTitles:nil];
            [theAlert show];
            break;
        }
        case CONNECTION_OK: {
            [PetConnection streamVideoWithCallBack:^(NSDictionary *d ) {
                if (d==nil) {
                    UIAlertView *theAlert = [[UIAlertView alloc] initWithTitle:@"Failed to connect"
                                                                       message:@"Connection to petbot has failed"
                                                                      delegate:self
                                                             cancelButtonTitle:@"ok"
                                                             otherButtonTitles:nil];
                    [theAlert show];
                    return;
                }
                if (rememberSwitch.isOn) {
                    [self saveLogin:given_username password:given_password];
                }
                
                //see if we are already logged in, if not then actually perform the Segue
                long acquired = dispatch_semaphore_wait(_logged_in, DISPATCH_TIME_NOW);
                NSLog(@"sempahore result is %ld",acquired);
                if (acquired==0) {
                    NSLog(@"TRYING TO SEGUE");
                    [self performSegueWithIdentifier:@"login" sender:self];
                }
                NSLog(@"DONE SEGUING ");
            }];
            
            break;
        }
            
        default: {
            UIAlertView *theAlert = [[UIAlertView alloc] initWithTitle:@"Login failed"
                                                               message:@"Username and/or Password are incorrect."
                                                              delegate:self
                                                     cancelButtonTitle:@"ok"
                                                     otherButtonTitles:nil];
            [theAlert show];
            break;
        }
            
            
            
    }

}



- (IBAction)loginButtonPress:(id)sender {
    [loginButton setHighlighted:true]; //maybe should fork a thread for rest? otherwise no highlight :(
    //NSLog(@"%@",loginButton.backgroundColor);
    // Do any additional setup after loading the view, typically from a nib.
    NSString * given_username = self.username.text;
    NSString * given_password = self.password.text;
    
    long acquired = dispatch_semaphore_wait(_login_action, DISPATCH_TIME_NOW);
    NSLog(@"DISPATCH LOGIN!");
    if (acquired==0) {
        NSLog(@"DISPATCH LOGIN2!");
            [PetConnection loginUsername:given_username password:given_password withCallBack:^(NSInteger error_no) {
                
                NSLog(@"DISPATCH LOGIN RESPONSE!");
                [self loginResponse:error_no withUsername:given_username withPassword:given_password];
                dispatch_semaphore_signal(_login_action);
            }];
        
    } else {
        NSLog(@"dropping login event");
    }
}


- (IBAction)forgetUsername:(id)sender {
    [[NSUserDefaults standardUserDefaults] setValue:nil forKey:@"username"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    self.username.text=@"";
    self.username.placeholder=@"Username";
    self.password.text=@"";
    self.password.placeholder=@"Password";
}

- (IBAction)passwordEdit:(id)sender {
    if (!passwordEdited) {
        self.password.text=@"";
    }
    passwordEdited=true;
}

- (IBAction)usernameEdit:(id)sender {
    if (!usernameEdited) {
        self.username.text=@"";
    }
    usernameEdited=true;
}

-(NSUInteger)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskPortrait; // UIInterfaceOrientationMaskLandscapeRight;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return NO;
}

@end

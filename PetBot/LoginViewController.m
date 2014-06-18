//
//  LoginViewController.m
//  PetView
//
//  Created by Misko Dzamba on 2014-06-07.
//  Copyright (c) 2014 PetBot. All rights reserved.
//

#import "LoginViewController.h"
#import "PetConnection.h"

@interface LoginViewController () {
    BOOL passwordEdited;
    BOOL usernameEdited;
}

@end

@implementation LoginViewController

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
    NSString * stored_username = [[NSUserDefaults standardUserDefaults] stringForKey:@"username"];
    if (stored_username) {
        self.username.text=stored_username;
        self.password.text=@"";
        self.password.placeholder=@"Password";
    }
}

- (void)viewDidLoad
{
    [super viewDidLoad];

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

- (IBAction)loginButtonPress:(id)sender {
    // Do any additional setup after loading the view, typically from a nib.
    
    NSString * given_username = self.username.text;
    switch ([PetConnection loginUsername:given_username password:self.password.text]) {
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
            [PetConnection streamVideo];
            [[NSUserDefaults standardUserDefaults] setValue:given_username forKey:@"username"];
            [[NSUserDefaults standardUserDefaults] synchronize];
            [self performSegueWithIdentifier:@"login" sender:self];
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

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return NO;
}

@end

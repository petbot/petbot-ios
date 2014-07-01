//
//  LoginViewController.h
//  PetView
//
//  Created by Misko Dzamba on 2014-06-07.
//  Copyright (c) 2014 PetBot. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface LoginViewController : UIViewController <UITextFieldDelegate>
@property (weak, nonatomic) IBOutlet UITextField *username;
@property (weak, nonatomic) IBOutlet UITextField *password;
- (IBAction)loginButtonPress:(id)sender;
- (IBAction)forgetUsername:(id)sender;
- (IBAction)passwordEdit:(id)sender;
- (IBAction)usernameEdit:(id)sender;


@end

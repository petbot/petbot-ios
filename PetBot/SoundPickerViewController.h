//
//  SoundPickerViewController.h
//  PetBot
//
//  Created by Misko Dzamba on 2014-06-30.
//  Copyright (c) 2014 PetBot. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>


@interface SoundPickerViewController : UIViewController<UIPickerViewDelegate,AVAudioRecorderDelegate>
@property (weak, nonatomic) IBOutlet UIButton *playButton;
@property (weak, nonatomic) IBOutlet UIButton *recordPauseButton;
- (IBAction)playSoundPressed:(id)sender;
- (IBAction)recordPauseTapped:(id)sender;
- (IBAction)backTapped:(id)sender;
@property (weak, nonatomic) IBOutlet UIButton *recordPauseTapped;
- (IBAction)playTapped:(id)sender;
- (IBAction)uploadTapped:(id)sender;
- (IBAction)removeTapped:(id)sender;
@property (strong, nonatomic) IBOutlet UIButton *cancelButton;


@end

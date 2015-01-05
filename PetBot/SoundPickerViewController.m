//
//  SoundPickerViewController.m
//  PetBot
//
//  Created by Misko Dzamba on 2014-06-30.
//  Copyright (c) 2014 PetBot. All rights reserved.
//

#import "SoundPickerViewController.h"
#import "PetConnection.h"

@interface SoundPickerViewController () {
    NSArray *sounds;
    AVAudioPlayer *player;
    AVAudioRecorder *recorder;
    NSURL *outputFileURL;
}
    @property (weak, nonatomic) IBOutlet UIPickerView *picker;
@end

@implementation SoundPickerViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

-(void)populateSounds {
    //TODO lock and do something fancy?, critical section? drop later events, all the same
    [PetConnection listSoundsWithCallBack:^(NSArray *a) {
        if (a==nil) { //TODO THIS IS AN ERROR?
            return;
        }
            sounds = a;
            [_picker reloadAllComponents];
    }];

}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    
    //Get a list of sounds
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW,0), ^{
        [self populateSounds];
    });
    
    
    // Disable Stop/Play button when application launches
    //[_stopButton setEnabled:NO];
    [_playButton setEnabled:NO];
    
    // Set the audio file
    NSArray *pathComponents = [NSArray arrayWithObjects:
                               [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject],
                               @"petbot_sound_clip.mp4a",
                               nil];
    outputFileURL = [NSURL fileURLWithPathComponents:pathComponents];
    
    
    // Setup audio session
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayAndRecord error:nil];
    
    // Define the recorder setting
    NSMutableDictionary *recordSetting = [[NSMutableDictionary alloc] init];
    
    [recordSetting setValue:[NSNumber numberWithInt:kAudioFormatMPEG4AAC] forKey:AVFormatIDKey];
    [recordSetting setValue:[NSNumber numberWithFloat:44100.0] forKey:AVSampleRateKey];
    [recordSetting setValue:[NSNumber numberWithInt: 2] forKey:AVNumberOfChannelsKey];
    
    // Initiate and prepare the recorder
    recorder = [[AVAudioRecorder alloc] initWithURL:outputFileURL settings:recordSetting error:NULL];
    recorder.delegate = self;
    recorder.meteringEnabled = YES;
    [recorder prepareToRecord];
}

//Actions
- (IBAction)playSoundPressed:(id)sender {
    NSInteger selected_row = [_picker selectedRowInComponent:0];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW,0), ^{
        [PetConnection playSoundfile:[sounds objectAtIndex:selected_row] withCallBack:^(BOOL played) {
            //TODO handle if played or not?
        }];
    });
     
    
    [self dismissViewControllerAnimated:true completion:nil];
}



- (IBAction)playTapped:(id)sender {
    if (!recorder.recording){
        player = [[AVAudioPlayer alloc] initWithContentsOfURL:recorder.url error:nil];
        [player setDelegate:self];
        [player play];
    }
}

- (IBAction)uploadTapped:(id)sender {
    UIAlertView * alertView = [[UIAlertView alloc] initWithTitle:@"Sound name" message:@"Please enter a name for this sound:" delegate:self  cancelButtonTitle:@"Done" otherButtonTitles:nil];
    
	[alertView addButtonWithTitle:@"Cancel"];
    alertView.alertViewStyle = UIAlertViewStylePlainTextInput;
    [alertView show];
}



- (void)alertView:(UIAlertView *)alertView
clickedButtonAtIndex:(NSInteger)buttonIndex {
    if ([[alertView title] isEqualToString:@"Remove sound"]) {
        if (buttonIndex==0) {
            NSInteger selected_row = [_picker selectedRowInComponent:0];
            NSLog(@"should remove %@",[sounds objectAtIndex:selected_row]);
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW,0), ^{
                [PetConnection removeSoundfile:[sounds objectAtIndex:selected_row] withCallBack:^(BOOL ok) {
                    [self populateSounds];
                }];
            });
            //[PetConnection playSoundfile:[sounds objectAtIndex:selected_row]];
        } else {
            //clicked cancel
        }
    } else if ([[alertView title] isEqualToString:@"Sound name"]) {
        if (buttonIndex==0) {
        NSLog(@"Sound name is %@",[alertView textFieldAtIndex:0].text);
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW,0), ^{
                [PetConnection uploadSoundURL:outputFileURL withFilename:[alertView textFieldAtIndex:0].text withCallBack:^(BOOL ok) {
                    
                    [self populateSounds];
                }];
            });
        } else {
            //clicked cancel
        }
    } else {
        NSLog(@"Something bad has happened");
    }
}
- (IBAction)removeTapped:(id)sender {
    
    NSInteger selected_row = [_picker selectedRowInComponent:0];
	UIAlertView *alertView = [[UIAlertView alloc]
                              initWithTitle:@"Remove sound"
                              message:[NSString stringWithFormat:@"Remove sound %@?",[sounds objectAtIndex:selected_row]]
                              delegate:self
                              cancelButtonTitle:@"Remove"
                              otherButtonTitles:nil];
	
	[alertView addButtonWithTitle:@"Don't remove"];
	[alertView show];
}

- (IBAction)recordPauseTapped:(id)sender {
    // Stop the audio player before recording
    if (player.playing) {
        [player stop];
    }
    
    if (!recorder.recording) {
        AVAudioSession *session = [AVAudioSession sharedInstance];
        [session setActive:YES error:nil];
        
        // Start recording
        [recorder record];
        [_recordPauseButton setTitle:@"Done" forState:UIControlStateNormal];
        
    } else {
        
        // stop recording
        [recorder stop];
        [_recordPauseButton setTitle:@"Record" forState:UIControlStateNormal];
        
        AVAudioSession *audioSession = [AVAudioSession sharedInstance];
        [audioSession setActive:NO error:nil];
    }
    
    //[_stopButton setEnabled:YES];
    [_playButton setEnabled:NO];
}

- (IBAction)backTapped:(id)sender {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self dismissViewControllerAnimated:true completion:nil];
    });
}

//audio delegates

- (void) audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag{
    /*UIAlertView *alert = [[UIAlertView alloc] initWithTitle: @"Done"
                                                    message: @"Finish playing the recording!"
                                                   delegate: nil
                                          cancelButtonTitle:@"OK"
                                          otherButtonTitles:nil];
    [alert show];*/
}


- (void) audioRecorderDidFinishRecording:(AVAudioRecorder *)avrecorder successfully:(BOOL)flag{
    [_recordPauseButton setTitle:@"Record" forState:UIControlStateNormal];
    
    //[_stopButton setEnabled:NO];
    [_playButton setEnabled:YES];
}


//orientation lock

-(NSUInteger)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskPortrait; // UIInterfaceOrientationMaskLandscapeRight;
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


- (void)pickerView:(UIPickerView *)pickerView didSelectRow: (NSInteger)row inComponent:(NSInteger)component {
    // Handle the selection
}

// tell the picker how many rows are available for a given component
- (NSInteger)pickerView:(UIPickerView *)pickerView numberOfRowsInComponent:(NSInteger)component {
    return [sounds count];
}

// tell the picker how many components it will have
- (NSInteger)numberOfComponentsInPickerView:(UIPickerView *)pickerView {
    return 1;
}

// tell the picker the title for a given component
- (NSString *)pickerView:(UIPickerView *)pickerView titleForRow:(NSInteger)row forComponent:(NSInteger)component {
    //NSString *title;
    //title = [@"" stringByAppendingFormat:@"%d",row];
    
    return [sounds objectAtIndex:row];
}

// tell the picker the width of each row for a given component
- (CGFloat)pickerView:(UIPickerView *)pickerView widthForComponent:(NSInteger)component {
    int sectionWidth = 300;
    
    return sectionWidth;
}


- (void) prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    NSLog(@"USING segue %@",segue.identifier);
}




@end

//
//  SimpleCam.m
//  SimpleCam
//
//  Created by Logan Wright on 2/1/14.
//  Copyright (c) 2014 Logan Wright. All rights reserved.
//
//  Mozilla Public License v2.0
//
//  **
//
//  PLEASE FAMILIARIZE YOURSELF WITH THE ----- Mozilla Public License v2.0
//
//  **
//
//  Attribution is satisfied by acknowledging the use of SimpleCam,
//  or its creation by Logan Wright
//
//  **
//
//  You can use, modify and redistribute this code in your product,
//  but to satisfy the requirements of Mozilla Public License v2.0,
//  it is required to provide the source code for any fixes you make to it.
//
//  **
//
//  Covered Software is provided under this License on an “as is” basis, without warranty of any
//  kind, either expressed, implied, or statutory, including, without limitation, warranties that
//  the Covered Software is free of defects, merchantable, fit for a particular purpose or non-
//  infringing. The entire risk as to the quality and performance of the Covered Software is with
//  You. Should any Covered Software prove defective in any respect, You (not any Contributor)
//  assume the cost of any necessary servicing, repair, or correction. This disclaimer of
//  warranty constitutes an essential part of this License. No use of any Covered Software is
//  authorized under this License except under this disclaimer.
//
//  **
//

/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

static CGFloat optionUnavailableAlpha = 0.2;

#import "SimpleCam.h"
#import <ImageIO/ImageIO.h>

@interface SimpleCam ()
{
    // Measurements
    CGFloat screenWidth;
    CGFloat screenHeight;
    CGFloat topX;
    CGFloat topY;
    
    // Zoom scale
    CGFloat scale;
    
    // Resize Toggles
    BOOL isImageResized;
    BOOL isSaveWaitingForResizedImage;
    
    // Capture Toggle
    BOOL isCapturingImage;
    
    // Animate a "flash" on-screen when a photo is taken
    UIView *cameraCaptureFlashAnimation;
}

// Used to cover animation flicker during rotation
@property (strong, nonatomic) UIView * rotationCover;
@property (strong, nonatomic) UIView * verticalBackgroundLayer;
@property (strong, nonatomic) UIView * horizontalBackgroundLayer;

// Controls
@property (strong, nonatomic) UIButton * backBtn;
@property (strong, nonatomic) UIButton * captureBtn;
@property (strong, nonatomic) UIButton * switchCameraBtn;
@property (strong, nonatomic) UIButton * saveBtn;
@property (strong, nonatomic) UIButton * retakeBtn;

// AVFoundation Properties
@property (strong, nonatomic) AVCaptureSession * mySesh;
@property (strong, nonatomic) AVCaptureStillImageOutput *stillImageOutput;
@property (strong, nonatomic) AVCaptureDevice * myDevice;
@property (strong, nonatomic) AVCaptureVideoPreviewLayer * captureVideoPreviewLayer;

// View Properties
@property (strong, nonatomic) UIView * imageStreamV;
@property (strong, nonatomic) UIImageView * capturedImageV;
@property (strong, nonatomic) UIImage * capturedImage;

@end

@implementation SimpleCam;

@synthesize hideAllControls = _hideAllControls, hideBackButton = _hideBackButton, hideCaptureButton = _hideCaptureButton;
@synthesize enableZoom = _enableZoom, enableCameraCaptureAnimation = _enableCameraCaptureAnimation;

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        
        // Custom initialization
        self.controlAnimateDuration = 0;
    }
    return self;
}

- (void)viewDidLoad {
    
    [super viewDidLoad];
    
    if (floor(NSFoundationVersionNumber) <= NSFoundationVersionNumber_iOS_7_1) {
        // Pre iOS 8 -- No camera auth required.
        [self setup];
    }
    else {
        // iOS 8
        
        // Thanks: http://stackoverflow.com/a/24684021/2611971
        AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
        switch (status) {
            case AVAuthorizationStatusAuthorized:
                // Do setup early if possible.
                [self setup];
                break;
            default:
                break;
        }
        
    }
    
    
}

- (void) viewDidAppear:(BOOL)animated {
    
    [super viewDidAppear:animated];
    
    if (floor(NSFoundationVersionNumber) <= NSFoundationVersionNumber_iOS_7_1) {
        // Pre iOS 8 -- No camera auth required.
        [self animateIntoView];
    }
    else {
        // iOS 8
        AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
        switch (status) {
            case AVAuthorizationStatusDenied:
            case AVAuthorizationStatusRestricted:
                NSLog(@"SC: Not authorized, or restricted");
                [self.delegate simpleCamNotAuthorizedForCameraUse:self];
                break;
            case AVAuthorizationStatusAuthorized:
                [self animateIntoView];
                break;
            case AVAuthorizationStatusNotDetermined: {
                // not determined
                [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if(granted){
                            [self setup];
                            [self animateIntoView];
                        } else {
                            [self.delegate simpleCam:self didFinishWithImage:nil];
                        }
                    });
                }];
            }
            default:
                break;
        }
    }
}

- (void) animateIntoView
{
    //
    [UIView animateWithDuration:0 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        _imageStreamV.alpha = 1;
        _rotationCover.alpha = 1;
    } completion:^(BOOL finished) {
        if (finished) {
            if ([(NSObject *)_delegate respondsToSelector:@selector(simpleCamDidLoadCameraIntoView:)]) {
                [_delegate simpleCamDidLoadCameraIntoView:self];
            }
        }
    }];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    NSLog(@"SC: DID RECIEVE MEMORY WARNING");
    // Dispose of any resources that can be recreated.
}

#pragma mark - Setup


- (void) setup {
    
    self.view.clipsToBounds = NO;
    self.view.backgroundColor = [UIColor blackColor];
    
    /*
     The layout has shifted in iOS 8 causing problems.  I realize that this isn't the best solution, so if you're looking at this, feel free to submit a Pull Request.  This is an older project.
     */
    CGRect screen = [UIScreen mainScreen].bounds;
    CGFloat currentWidth = CGRectGetWidth(screen);
    CGFloat currentHeight = CGRectGetHeight(screen);
    screenWidth = currentWidth < currentHeight ? currentWidth : currentHeight;
    screenHeight = currentWidth < currentHeight ? currentHeight : currentWidth;
    
    if (_imageStreamV == nil) _imageStreamV = [[UIView alloc]init];
    _imageStreamV.alpha = 0;
    _imageStreamV.frame = self.view.bounds;
    [self.view addSubview:_imageStreamV];
    
    if (_capturedImageV == nil) _capturedImageV = [[UIImageView alloc]init];
    _capturedImageV.frame = _imageStreamV.frame; // just to even it out
    _capturedImageV.backgroundColor = [UIColor clearColor];
    _capturedImageV.userInteractionEnabled = YES;
    _capturedImageV.contentMode = UIViewContentModeScaleAspectFit;
    [self.view insertSubview:_capturedImageV aboveSubview:_imageStreamV];
    
    // for focus
    UITapGestureRecognizer * focusTap = [[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(tapSent:)];
    focusTap.numberOfTapsRequired = 1;
    [_capturedImageV addGestureRecognizer:focusTap];
    
    // for zoom
    if (_enableZoom) {
        UIPinchGestureRecognizer * zoomPinch = [[UIPinchGestureRecognizer alloc]initWithTarget:self action:@selector(pinchToZoom:)];
        [_capturedImageV addGestureRecognizer:zoomPinch];
    }
    
    // SETTING UP CAM
    if (_mySesh == nil) _mySesh = [[AVCaptureSession alloc] init];

    if([_mySesh canSetSessionPreset:AVCaptureSessionPreset1280x720]){
        _mySesh.sessionPreset = AVCaptureSessionPreset1280x720;
    } else if([_mySesh canSetSessionPreset:AVCaptureSessionPreset640x480]){
        _mySesh.sessionPreset = AVCaptureSessionPreset640x480;
    } else if ([_mySesh canSetSessionPreset:AVCaptureSessionPresetMedium]) {
        _mySesh.sessionPreset = AVCaptureSessionPresetMedium;
    } else if([_mySesh canSetSessionPreset:AVCaptureSessionPresetLow]){
        _mySesh.sessionPreset = AVCaptureSessionPresetLow;
    }

    
    _captureVideoPreviewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:_mySesh];
    _captureVideoPreviewLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    _captureVideoPreviewLayer.frame = _imageStreamV.layer.bounds; // parent of layer

    [_imageStreamV.layer addSublayer:_captureVideoPreviewLayer];
    
    // rear camera: 0 front camera: 1
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    if (devices.count==0) {
        NSLog(@"SC: No devices found (for example: simulator)");
        return;
    }
    _myDevice = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo][0];
    
    if ([_myDevice isFlashAvailable] && _myDevice.flashActive && [_myDevice lockForConfiguration:nil]) {
        //NSLog(@"SC: Turning Flash Off ...");
        _myDevice.flashMode = AVCaptureFlashModeOff;
        [_myDevice unlockForConfiguration];
    }
    
    NSError * error = nil;
    AVCaptureDeviceInput * input = [AVCaptureDeviceInput deviceInputWithDevice:_myDevice error:&error];
    
    if (!input) {
        // Handle the error appropriately.
        NSLog(@"SC: ERROR: trying to open camera: %@", error);
        [_delegate simpleCam:self didFinishWithImage:_capturedImage];
    }
    
    [_mySesh addInput:input];
    
    _stillImageOutput = [[AVCaptureStillImageOutput alloc] init];
    NSDictionary * outputSettings = [[NSDictionary alloc] initWithObjectsAndKeys: AVVideoCodecJPEG, AVVideoCodecKey, nil];
    [_stillImageOutput setOutputSettings:outputSettings];
    [_mySesh addOutput:_stillImageOutput];
    
    if (self.interfaceOrientation == UIInterfaceOrientationLandscapeLeft) {
        _captureVideoPreviewLayer.connection.videoOrientation = AVCaptureVideoOrientationLandscapeLeft;
    }
    else if (self.interfaceOrientation == UIInterfaceOrientationLandscapeRight) {
        _captureVideoPreviewLayer.connection.videoOrientation = AVCaptureVideoOrientationLandscapeRight;
    }
    
    [_mySesh startRunning];

    // -- LOAD ROTATION COVERS BEGIN -- //
    /*
     Rotating causes a weird flicker, I'm in the process of looking for a better
     solution, but for now, this works.
     */
    
    // Stream Cover
    _rotationCover = [UIView new];
    _rotationCover.backgroundColor = [UIColor blackColor];
    _rotationCover.bounds = CGRectMake(0, 0, screenHeight * 3, screenHeight * 3); // 1 full screen size either direction
    _rotationCover.center = self.view.center;
    _rotationCover.autoresizingMask = UIViewAutoresizingNone;
    _rotationCover.alpha = 0;
    [self.view insertSubview:_rotationCover belowSubview:_imageStreamV];
    // -- LOAD ROTATION COVERS END -- //
    
    // -- PREPARE OUR CONTROLS -- //
    [self loadControls];
    
    // -- PREPARE CAMERA FLASH ANIMATION -- //
    
    if (_enableCameraCaptureAnimation) {
        if (cameraCaptureFlashAnimation) {
            [cameraCaptureFlashAnimation removeFromSuperview];
            cameraCaptureFlashAnimation = nil;
        }
        
        cameraCaptureFlashAnimation = [[UIView alloc] initWithFrame:self.view.bounds];
        cameraCaptureFlashAnimation.backgroundColor = [UIColor whiteColor];
        cameraCaptureFlashAnimation.alpha = 0.0f;
        [self.view addSubview:cameraCaptureFlashAnimation];
    }
}

#pragma mark CAMERA CONTROLS

- (void) loadControls {
    
    // -- LOAD BUTTON IMAGES BEGIN -- //
    UIImage * cameraRotateImg = [UIImage imageNamed:@"CameraRotate.png"];
    UIImage * captureImg = [UIImage imageNamed:@"shutter"];
    // -- LOAD BUTTON IMAGES END -- //
    
    // -- VERTICAL BACKGROUND LAYER BEGIN -- //
    CGRect frame;
    CGFloat height = screenHeight * 0.12;
    frame.size = CGSizeMake(self.view.frame.size.width, height);
    frame.origin.x = 0;
    frame.origin.y = self.view.frame.size.height - height;
    self.verticalBackgroundLayer = [[UIView alloc] initWithFrame:frame];
    self.verticalBackgroundLayer.backgroundColor = [UIColor blackColor];
    self.verticalBackgroundLayer.backgroundColor = [UIColor colorWithRed:0
                                                                 green:0
                                                                  blue:0
                                                                 alpha:0.3f];
    self.verticalBackgroundLayer.autoresizingMask =
        UIViewAutoresizingFlexibleWidth |
        UIViewAutoresizingFlexibleTopMargin |
        UIViewAutoresizingFlexibleLeftMargin;
    
    [self.view addSubview:self.verticalBackgroundLayer];
    
    // Back button
    frame.size = CGSizeMake(120, 40);
    frame.origin.x = (self.verticalBackgroundLayer.frame.size.width - frame.size.width);
    frame.origin.y = (self.verticalBackgroundLayer.frame.size.height - frame.size.height)/2;
    _backBtn = [[UIButton alloc] initWithFrame:frame];
    [_backBtn setTitle:@"Cancel" forState:UIControlStateNormal];
    [_backBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _backBtn.titleLabel.font = [UIFont systemFontOfSize:18];
    _backBtn.titleLabel.numberOfLines = 0;
    _backBtn.titleLabel.minimumScaleFactor = .5;
    _backBtn.bounds = CGRectMake(0, 0, 120, 40);
    [_backBtn addTarget:self action:@selector(backBtnPressed:) forControlEvents:UIControlEventTouchUpInside];
    _backBtn.autoresizingMask =
        UIViewAutoresizingFlexibleLeftMargin |
        UIViewAutoresizingFlexibleRightMargin |
        UIViewAutoresizingFlexibleTopMargin |
        UIViewAutoresizingFlexibleBottomMargin;
    [self.verticalBackgroundLayer addSubview:_backBtn];
    
    // Switch camera button
    frame.size = CGSizeMake(cameraRotateImg.size.width * 0.75, cameraRotateImg.size.height * 0.75);
    frame.origin.x = 20;
    frame.origin.y = (self.verticalBackgroundLayer.frame.size.height - frame.size.height)/2;;
    _switchCameraBtn = [[UIButton alloc] initWithFrame:frame];
    [_switchCameraBtn setImage:cameraRotateImg forState:UIControlStateNormal];
    [_switchCameraBtn addTarget:self action:@selector(switchCameraBtnPressed:) forControlEvents:UIControlEventTouchUpInside];
    _switchCameraBtn.autoresizingMask =
        UIViewAutoresizingFlexibleLeftMargin |
        UIViewAutoresizingFlexibleRightMargin |
        UIViewAutoresizingFlexibleTopMargin |
        UIViewAutoresizingFlexibleBottomMargin;
    [self.verticalBackgroundLayer addSubview:_switchCameraBtn];
    
    // Capture image button
    frame.size = captureImg.size;
    frame.origin.x = (self.verticalBackgroundLayer.frame.size.width - frame.size.width)/2;
    frame.origin.y = (self.verticalBackgroundLayer.frame.size.height - frame.size.height)/2;
    _captureBtn = [[UIButton alloc] initWithFrame:frame];
    [_captureBtn setImage:captureImg forState:UIControlStateNormal];
    [_captureBtn addTarget:self action:@selector(captureBtnPressed:) forControlEvents:UIControlEventTouchUpInside];
    _captureBtn.autoresizingMask =
        UIViewAutoresizingFlexibleLeftMargin |
        UIViewAutoresizingFlexibleRightMargin |
        UIViewAutoresizingFlexibleTopMargin |
        UIViewAutoresizingFlexibleBottomMargin;
    [self.verticalBackgroundLayer addSubview:_captureBtn];
    // -- VERTICAL BACKGROUND LAYER END -- //
    
    // -- HORIZONTAL BACKGROUND LAYER START -- //
    // CGFloat height = screenHeight * 0.08;
    frame.size = CGSizeMake(self.view.frame.size.width, height);
    frame.origin.x = 0;
    frame.origin.y = self.view.frame.size.height - height;
    self.horizontalBackgroundLayer = [[UIView alloc] initWithFrame:frame];
    self.horizontalBackgroundLayer.backgroundColor = [UIColor blackColor];
    self.horizontalBackgroundLayer.backgroundColor = [UIColor colorWithRed:0
                                                                   green:0
                                                                    blue:0
                                                                   alpha:0.3f];
    self.horizontalBackgroundLayer.autoresizingMask =
        UIViewAutoresizingFlexibleWidth |
        UIViewAutoresizingFlexibleTopMargin |
        UIViewAutoresizingFlexibleLeftMargin;
    
    [self.view addSubview:self.horizontalBackgroundLayer];
    
    // Save button
    frame.size = CGSizeMake(120, 40);
    frame.origin.x = (self.horizontalBackgroundLayer.frame.size.width - frame.size.width);
    frame.origin.y = (self.horizontalBackgroundLayer.frame.size.height - frame.size.height)/2;
    _saveBtn = [[UIButton alloc] initWithFrame:frame];
    [_saveBtn setTitle:@"Use Photo" forState:UIControlStateNormal];
    [_saveBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _saveBtn.titleLabel.font = [UIFont systemFontOfSize:18];
    _saveBtn.titleLabel.numberOfLines = 0;
    _saveBtn.titleLabel.minimumScaleFactor = .5;
    _saveBtn.bounds = CGRectMake(0, 0, 120, 40);
    [_saveBtn addTarget:self action:@selector(saveBtnPressed:) forControlEvents:UIControlEventTouchUpInside];
    _saveBtn.autoresizingMask =
        UIViewAutoresizingFlexibleLeftMargin |
        UIViewAutoresizingFlexibleTopMargin |
        UIViewAutoresizingFlexibleBottomMargin;
    [self.horizontalBackgroundLayer addSubview:_saveBtn];
    
    // Retake photo button
    frame.origin.x = 0;
    _retakeBtn = [[UIButton alloc] initWithFrame:frame];
    [_retakeBtn setTitle:@"Retake" forState:UIControlStateNormal];
    [_retakeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _retakeBtn.titleLabel.font = [UIFont systemFontOfSize:18];
    _retakeBtn.titleLabel.numberOfLines = 0;
    _retakeBtn.titleLabel.minimumScaleFactor = .5;
    _retakeBtn.bounds = CGRectMake(0, 0, 120, 40);
    [_retakeBtn addTarget:self action:@selector(retakeBtnPressed:) forControlEvents:UIControlEventTouchUpInside];
    _retakeBtn.autoresizingMask =
        UIViewAutoresizingFlexibleRightMargin |
        UIViewAutoresizingFlexibleTopMargin |
        UIViewAutoresizingFlexibleBottomMargin;
    [self.horizontalBackgroundLayer addSubview:_retakeBtn];
    
    // -- HORIZONTAL BACKGROUND LAYER END -- //
    
    // If a device doesn't have multiple cameras, fade out button ...
    if ([AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo].count == 1) {
        _switchCameraBtn.alpha = optionUnavailableAlpha;
    }
    else {
        [_switchCameraBtn addTarget:self action:@selector(switchCameraBtnPressed:) forControlEvents:UIControlEventTouchUpInside];
    }
    
    // Draw camera controls
    [self drawControls];
}

- (void) drawControls {
    if (self.hideAllControls) {
        [_verticalBackgroundLayer setHidden:YES];
        [_horizontalBackgroundLayer setHidden:YES];
        return;
    }
    
    [UIView animateWithDuration:self.controlAnimateDuration delay:0 options:UIViewAnimationOptionCurveEaseOut  animations:^{
            if (_capturedImageV.image) {
                [_verticalBackgroundLayer setHidden:YES];
                [_horizontalBackgroundLayer setHidden:NO];
            } else {
                [_verticalBackgroundLayer setHidden:NO];
                [_horizontalBackgroundLayer setHidden:YES];
            }
    } completion:nil];
}

- (void) capturePhoto {    
    if (isCapturingImage) {
        return;
    }
    isCapturingImage = YES;
    
    AVCaptureConnection *videoConnection = nil;
    for (AVCaptureConnection *connection in _stillImageOutput.connections)
    {
        for (AVCaptureInputPort *port in [connection inputPorts])
        {
            if ([[port mediaType] isEqual:AVMediaTypeVideo] )
            {
                videoConnection = connection;
                break;
            }
        }
        if (videoConnection) { break; }
    }
    
    [_stillImageOutput captureStillImageAsynchronouslyFromConnection:videoConnection completionHandler: ^(CMSampleBufferRef imageSampleBuffer, NSError *error)
     {
         // Camera "flash" animation
         if (_enableCameraCaptureAnimation) {
             [UIView animateWithDuration:0.2f animations:^{
                 cameraCaptureFlashAnimation.alpha = 1.0f;[cameraCaptureFlashAnimation setNeedsDisplay];
             } completion:^(BOOL finished) {
                 [UIView animateWithDuration:0.2f animations:^{
                     cameraCaptureFlashAnimation.alpha = 0.0f;
                 }];
             }];
         }
         
         if(!CMSampleBufferIsValid(imageSampleBuffer))
         {
             return;
         }
         NSData *imageData = [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:imageSampleBuffer];
         
         UIImage * capturedImage = [[UIImage alloc]initWithData:imageData scale:1];
         
         if (_myDevice == [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo][0]) {
             // rear camera active
             if (self.interfaceOrientation == UIInterfaceOrientationLandscapeRight) {
                 CGImageRef cgRef = capturedImage.CGImage;
                 capturedImage = [[UIImage alloc] initWithCGImage:cgRef scale:1.0 orientation:UIImageOrientationUp];
             }
             else if (self.interfaceOrientation == UIInterfaceOrientationLandscapeLeft) {
                 CGImageRef cgRef = capturedImage.CGImage;
                 capturedImage = [[UIImage alloc] initWithCGImage:cgRef scale:1.0 orientation:UIImageOrientationDown];
             }
         }
         else if (_myDevice == [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo][1]) {
             // front camera active
             
             // flip to look the same as the camera
             if (self.interfaceOrientation == UIInterfaceOrientationLandscapeRight)
                 capturedImage = [UIImage imageWithCGImage:capturedImage.CGImage scale:capturedImage.scale orientation:UIImageOrientationDown];
             else if (self.interfaceOrientation == UIInterfaceOrientationLandscapeLeft)
                 capturedImage = [UIImage imageWithCGImage:capturedImage.CGImage scale:capturedImage.scale orientation:UIImageOrientationUp];
             
         }
         
         if (self.interfaceOrientation == UIInterfaceOrientationPortraitUpsideDown) {
             capturedImage = [UIImage imageWithCGImage:capturedImage.CGImage scale:capturedImage.scale orientation:UIImageOrientationLeft];
         }
         
         isCapturingImage = NO;
         _capturedImageV.image = [self crop:capturedImage];
         _capturedImage = _capturedImageV.image;
         // show captured image view
         _capturedImageV.alpha = 1.0f;
         // hide image stream view
         _imageStreamV.alpha = 0.0f;
         imageData = nil;
         
         // If we have disabled the photo preview directly fire the delegate callback, otherwise, show user a preview
         _disablePhotoPreview ? [self photoCaptured] : [self drawControls];
         
         if ([(NSObject *)_delegate respondsToSelector:@selector(simpleCam:didCaptureImage:)]) {
             [_delegate simpleCam:self didCaptureImage:_capturedImage];
         }
     }];
}

- (BOOL) retakePhoto {
    if (_capturedImageV.image) {
        _imageStreamV.alpha = 1.0f;
        _capturedImageV.contentMode = UIViewContentModeScaleAspectFill;
        _capturedImageV.backgroundColor = [UIColor clearColor];
        _capturedImageV.image = nil;
        _capturedImage = nil;
        
        isImageResized = NO;
        isSaveWaitingForResizedImage = NO;
        
        [self.view insertSubview:_rotationCover belowSubview:_imageStreamV];
        
        [self drawControls];
        return YES;
    }
    
    return NO;
}

- (void) photoCaptured {
    if (isImageResized) {
        [_delegate simpleCam:self didFinishWithImage:_capturedImage];
    }
    else {
        isSaveWaitingForResizedImage = YES;
        [self resizeImage];
    }
}

#pragma mark BUTTON EVENTS

- (void) captureBtnPressed:(id)sender {
    [self capturePhoto];
}

- (void) saveBtnPressed:(id)sender {
    [self photoCaptured];
}

- (void) backBtnPressed:(id)sender {
    if (![self retakePhoto]) {
        [_delegate simpleCam:self didFinishWithImage:_capturedImage];
    }
}

- (void) retakeBtnPressed:(id)sender {
    [self retakePhoto];
}

- (void) switchCameraBtnPressed:(id)sender {
    if (isCapturingImage != YES) {
        if (_myDevice == [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo][0]) {
            if([AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo].count > 1){
                // rear active, switch to front
                _myDevice = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo][1];
            
                [_mySesh beginConfiguration];
                AVCaptureDeviceInput * newInput = [AVCaptureDeviceInput deviceInputWithDevice:_myDevice error:nil];
                for (AVCaptureInput * oldInput in _mySesh.inputs) {
                    [_mySesh removeInput:oldInput];
                }
                [_mySesh addInput:newInput];
                [_mySesh commitConfiguration];
            }
        }
        else if (_myDevice == [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo][1]) {
            // front active, switch to rear
            _myDevice = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo][0];
            [_mySesh beginConfiguration];
            AVCaptureDeviceInput * newInput = [AVCaptureDeviceInput deviceInputWithDevice:_myDevice error:nil];
            for (AVCaptureInput * oldInput in _mySesh.inputs) {
                [_mySesh removeInput:oldInput];
            }
            [_mySesh addInput:newInput];
            [_mySesh commitConfiguration];
        }
    }
}

#pragma mark TAP TO FOCUS

- (void) tapSent:(UITapGestureRecognizer *)sender {
    
    if (_capturedImageV.image == nil) {
        CGPoint aPoint = [sender locationInView:_imageStreamV];
        if (_myDevice != nil) {
            if([_myDevice isFocusPointOfInterestSupported] &&
               [_myDevice isFocusModeSupported:AVCaptureFocusModeAutoFocus]) {
                
                // we subtract the point from the width to inverse the focal point
                // focus points of interest represents a CGPoint where
                // {0,0} corresponds to the top left of the picture area, and
                // {1,1} corresponds to the bottom right in landscape mode with the home button on the right—
                // THIS APPLIES EVEN IF THE DEVICE IS IN PORTRAIT MODE
                // (from docs)
                // this is all a touch wonky
                double pX = aPoint.x / _imageStreamV.bounds.size.width;
                double pY = aPoint.y / _imageStreamV.bounds.size.height;
                double focusX = pY;
                // x is equal to y but y is equal to inverse x ?
                double focusY = 1 - pX;
                
                //NSLog(@"SC: about to focus at x: %f, y: %f", focusX, focusY);
                if([_myDevice isFocusPointOfInterestSupported] && [_myDevice isFocusModeSupported:AVCaptureFocusModeAutoFocus]) {
                    
                    if([_myDevice lockForConfiguration:nil]) {
                        [_myDevice setFocusPointOfInterest:CGPointMake(focusX, focusY)];
                        [_myDevice setFocusMode:AVCaptureFocusModeAutoFocus];
                        [_myDevice setExposurePointOfInterest:CGPointMake(focusX, focusY)];
                        [_myDevice setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
                        //NSLog(@"SC: Done Focusing");
                    }
                    [_myDevice unlockForConfiguration];
                }
            }
        }
    }
}

#pragma mark PINCH TO ZOOM

- (void) pinchToZoom:(UIPinchGestureRecognizer *)gestureRecognizer {
    
    if([gestureRecognizer state] == UIGestureRecognizerStateBegan) {
        // Reset the last scale, necessary if there are multiple objects with different scales
        scale = [gestureRecognizer scale];
    }
    
    if ([gestureRecognizer state] == UIGestureRecognizerStateBegan ||
        [gestureRecognizer state] == UIGestureRecognizerStateChanged) {
        
        CGFloat currentScale = [[_imageStreamV.layer valueForKeyPath:@"transform.scale"] floatValue];
        
        // Constants to adjust the max/min values of zoom
        const CGFloat kMaxScale = 2.0;
        const CGFloat kMinScale = 1.0;
        
        CGFloat newScale = 1 -  (scale - [gestureRecognizer scale]);
        newScale = MIN(newScale, kMaxScale / currentScale);
        newScale = MAX(newScale, kMinScale / currentScale);
        
        CGAffineTransform transform = CGAffineTransformScale([_imageStreamV transform], newScale, newScale);
        _imageStreamV.transform = transform;
        
        scale = [gestureRecognizer scale];  // Store the previous scale factor for the next pinch gesture call
    }
}

#pragma mark RESIZE IMAGE

- (CGRect) calculateBoundsForSource:(CGSize)src withTarget:(CGSize)target {
    CGRect result = CGRectMake(0, 0, 0, 0);
    
    CGFloat scaleX1 = target.width;
    CGFloat scaleY1 = (src.height * target.width) / src.width;
    CGFloat scaleX2 = (src.width * target.height) / src.height;
    CGFloat scaleY2 = target.height;
    
    if (scaleX2 > target.width) {
        result.size.width = round(2.0f * scaleX1) / 2.0f;
        result.size.height = round(2.0f * scaleY1) / 2.0f;
    } else {
        result.size.width = round(2.0f * scaleX2) / 2.0f;
        result.size.height = round(2.0f * scaleY2) / 2.0f;
    }
    result.origin.x = round(target.width - result.size.width) / 2.0f;
    result.origin.y = round(target.height - result.size.height) / 2.0f;
    
    return result;
}

- (void) resizeImage {
    
    // Set Orientation
//    BOOL isLandscape = UIInterfaceOrientationIsLandscape(self.interfaceOrientation) ? YES : NO;
    
    // Set Size
//    CGSize size = (isLandscape) ? CGSizeMake(screenHeight, screenWidth) : CGSizeMake(screenWidth, screenHeight);
    
    // Set Draw Rect
//    CGRect drawRect = [self calculateBoundsForSource:_capturedImageV.image.size withTarget:size];
    
    // START CONTEXT
        //    UIGraphicsBeginImageContextWithOptions(size, YES, 2.0);
        //    [_capturedImageV.image drawInRect:drawRect];
        //    _capturedImageV.image = UIGraphicsGetImageFromCurrentImageContext();
        //    UIGraphicsEndImageContext();
    // END CONTEXT
    
    // See if someone's waiting for resized image
    if (isSaveWaitingForResizedImage == YES) [_delegate simpleCam:self didFinishWithImage:_capturedImage];
    
    isImageResized = YES;
}

- (UIImage *)crop:(UIImage *)img {
    CGFloat currentScale = [[_imageStreamV.layer valueForKeyPath:@"transform.scale"] floatValue];
    
    NSInteger newW = img.size.width / currentScale;
    NSInteger newH = img.size.height / currentScale;
    NSInteger newX1 = (img.size.width / 2) - (newW / 2);
    NSInteger newY1 = (img.size.height / 2) - (newH / 2);
    
    CGRect rect = { -newX1, -newY1, img.size.width, img.size.height };
    
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(newW, newH), true, 1.0);
    
    [img drawInRect:rect];
    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    return result;
}

#pragma mark ROTATION

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration {

    if (_capturedImageV.image) {
        _capturedImageV.backgroundColor = [UIColor blackColor];
        
        // Move for rotation
        [self.view insertSubview:_rotationCover belowSubview:_capturedImageV];
        
        if (!isImageResized) {
            [self resizeImage];
        }
    }
    
    CGRect targetRect;
    if (UIInterfaceOrientationIsLandscape(toInterfaceOrientation)) {
        targetRect = CGRectMake(0, 0, screenHeight, screenWidth);
        
        if (toInterfaceOrientation == UIInterfaceOrientationLandscapeLeft) {
            _captureVideoPreviewLayer.connection.videoOrientation = AVCaptureVideoOrientationLandscapeLeft;
        }
        else if (toInterfaceOrientation == UIInterfaceOrientationLandscapeRight) {
            _captureVideoPreviewLayer.connection.videoOrientation = AVCaptureVideoOrientationLandscapeRight;
        }
    }
    else {
        targetRect = CGRectMake(0, 0, screenWidth, screenHeight);
        
        if (toInterfaceOrientation == UIInterfaceOrientationPortraitUpsideDown) {
            _captureVideoPreviewLayer.connection.videoOrientation = AVCaptureVideoOrientationPortraitUpsideDown;
        } else {
            _captureVideoPreviewLayer.connection.videoOrientation = AVCaptureVideoOrientationPortrait;
        }
    }
    
    // reset zoom
    _imageStreamV.transform = CGAffineTransformIdentity;
    
    [UIView animateWithDuration:duration delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        for (UIView * v in @[_capturedImageV, _imageStreamV, self.view]) {
            v.frame = targetRect;
        }
        
        // not in for statement, cuz layer
        _captureVideoPreviewLayer.frame = _imageStreamV.bounds;
        
    } completion:^(BOOL finished) {
        [self drawControls];
    }];
    
}

#pragma mark CLOSE

- (void) closeWithCompletion:(void (^)(void))completion {
    
    // Need alpha 0.0 before dismissing otherwise sticks out on dismissal
    _rotationCover.alpha = 0.0;
    
    // free memory associated with camera and video, before dismissing view.
    [_mySesh stopRunning];

    [self dismissViewControllerAnimated:NO completion:^{
        
        completion();
        
        // Clean Up
        isImageResized = NO;
        isSaveWaitingForResizedImage = NO;
        
        _mySesh = nil;
        
        _capturedImage = nil;
        _capturedImageV.image = nil;
        [_capturedImageV removeFromSuperview];
        _capturedImageV = nil;
        
        [_imageStreamV removeFromSuperview];
        _imageStreamV = nil;
        
        [_rotationCover removeFromSuperview];
        _rotationCover = nil;
        
        _stillImageOutput = nil;
        _myDevice = nil;
        
        self.view = nil;
        _delegate = nil;
        [self removeFromParentViewController];
        
    }];
}

#pragma mark COLORS

- (UIColor *) darkGreyColor {
    return [UIColor colorWithRed:0.226082 green:0.244034 blue:0.297891 alpha:1];
}
- (UIColor *) redColor {
    return [UIColor colorWithRed:1 green:0 blue:0.105670 alpha:.6];
}
- (UIColor *) greenColor {
    return [UIColor colorWithRed:0.128085 green:.749103 blue:0.004684 alpha:0.6];
}
- (UIColor *) blueColor {
    return [UIColor colorWithRed:0 green:.478431 blue:1 alpha:1];
}

#pragma mark STATUS BAR

- (BOOL)prefersStatusBarHidden {
    return YES;
}

#pragma mark GETTERS | SETTERS

- (void) setHideAllControls:(BOOL)hideAllControls {
    _hideAllControls = hideAllControls;
    
    // This way, hideAllControls can be used as a toggle.
    [self drawControls];
}
- (BOOL) hideAllControls {
    return _hideAllControls;
}
- (void) setHideBackButton:(BOOL)hideBackButton {
    _hideBackButton = hideBackButton;
    _backBtn.hidden = _hideBackButton;
}
- (BOOL) hideBackButton {
    return _hideBackButton;
}
- (void) setHideCaptureButton:(BOOL)hideCaptureButton {
    _hideCaptureButton = hideCaptureButton;
    _captureBtn.hidden = YES;
}
- (BOOL) hideCaptureButton {
    return _hideCaptureButton;
}

@end

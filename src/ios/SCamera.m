//
//  SCamera.m
//
//  Created by Christopher McCabe on 02/09/2016.
//
//

#import "SCamera.h"
#import "UIImage+CropScaleOrientation.h"

#define SC_PHOTO_PREFIX @"sc_photo_"

@implementation SCamera

- (void)takePicture:(CDVInvokedUrlCommand*)command {
    _callbackId = command.callbackId;
    _pictureOptions = [SCPictureOptions createFromTakePictureArguments:command];

    SimpleCam* simpleCam = [SimpleCam new];
    simpleCam.enableZoom = YES;
    simpleCam.delegate = self;

    // Perform UI operations on the main thread
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.viewController presentViewController:simpleCam
                                          animated:YES
                                        completion:nil];
    });
}

- (NSData*)processImage:(UIImage*)image options:(SCPictureOptions*)options
{
    NSData* data = nil;

    if ((options.targetSize.width > 0) && (options.targetSize.height > 0)) {
        image = [image imageByScalingNotCroppingForSize:options.targetSize];
    }

    if ([options.encodingType isEqual:@"png"]) {
        data = UIImagePNGRepresentation(image);
    }
    else {
        if ((options.targetSize.width <= 0) && (options.targetSize.height <= 0) && [options.quality integerValue] == 100){
            // use image unedited as requested , don't resize
            data = UIImageJPEGRepresentation(image, 1.0);
        } else {
            data = UIImageJPEGRepresentation(image, [options.quality floatValue] / 100.0f);
        }
    }

    return data;
}

- (NSString*)tempFilePath:(NSString*)extension
{
    NSString* docsPath = [NSTemporaryDirectory()stringByStandardizingPath];
    NSFileManager* fileMgr = [[NSFileManager alloc] init]; // recommended by Apple (vs [NSFileManager defaultManager]) to be threadsafe
    NSString* filePath;

    // generate unique file name
    int i = 1;
    do {
        filePath = [NSString stringWithFormat:@"%@/%@%03d.%@", docsPath, SC_PHOTO_PREFIX, i++, extension];
    } while ([fileMgr fileExistsAtPath:filePath]);

    return filePath;
}

#pragma mark SIMPLE CAM DELEGATE

- (void) simpleCam:(SimpleCam *)simpleCam didFinishWithImage:(UIImage *)image {
    // Close simpleCam - use this as opposed to 'dismissViewController' otherwise, the captureSession may not close properly and may result in memory leaks.

    [simpleCam closeWithCompletion:^{
        CDVPluginResult* result = nil;
        NSLog(@"SimpleCam is done closing ... ");

        if (image == nil) {
            result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"no image selected"];
        } else {
            NSData* data = [self processImage:image options:_pictureOptions];
            if (data) {

                NSString* extension = [_pictureOptions.encodingType isEqual:@"png"] ? @"png" : @"jpg";
                NSString* filePath = [self tempFilePath:extension];
                NSError* err = nil;

                // save file
                if (![data writeToFile:filePath options:NSAtomicWrite error:&err]) {
                    result = [CDVPluginResult resultWithStatus:CDVCommandStatus_IO_EXCEPTION messageAsString:[err localizedDescription]];
                } else {
                    result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:[[NSURL fileURLWithPath:filePath] absoluteString]];
                }
            }
        }

        [self.commandDelegate sendPluginResult:result callbackId:_callbackId];
    }];
}

- (void) simpleCamNotAuthorizedForCameraUse:(SimpleCam *)simpleCam {
    [simpleCam closeWithCompletion:^{
        NSLog(@"SimpleCam is done closing ... Not Authorized");
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wtautological-pointer-compare"
        NSString* settingsButton = (&UIApplicationOpenSettingsURLString != NULL)
        ? NSLocalizedString(@"Settings", nil)
        : nil;
#pragma clang diagnostic pop

        // Denied; show an alert
        dispatch_async(dispatch_get_main_queue(), ^{
            [[[UIAlertView alloc] initWithTitle:[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"]
                                        message:NSLocalizedString(@"Access to the camera has been prohibited; please enable it in the Settings app to continue.", nil)
                                       delegate:self
                              cancelButtonTitle:NSLocalizedString(@"OK", nil)
                              otherButtonTitles:settingsButton, nil] show];
        });
    }];
}

// Delegate for camera permission UIAlertView
- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    // If Settings button (on iOS 8), open the settings app
    if (buttonIndex == 1) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wtautological-pointer-compare"
        if (&UIApplicationOpenSettingsURLString != NULL) {
            [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString]];
        }
#pragma clang diagnostic pop
    }

    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"has no access to camera"];   // error callback expects string ATM

    [self.commandDelegate sendPluginResult:result callbackId:_callbackId];
}


@end

@implementation SCPictureOptions

+ (instancetype) createFromTakePictureArguments:(CDVInvokedUrlCommand*)command
{
    SCPictureOptions* pictureOptions = [[SCPictureOptions alloc] init];

    pictureOptions.quality = [command argumentAtIndex:0 withDefault:@(50)];

    NSNumber* targetWidth = [command argumentAtIndex:1 withDefault:nil];
    NSNumber* targetHeight = [command argumentAtIndex:2 withDefault:nil];
    pictureOptions.targetSize = CGSizeMake(0, 0);
    if ((targetWidth != nil) && (targetHeight != nil)) {
        pictureOptions.targetSize = CGSizeMake([targetWidth floatValue], [targetHeight floatValue]);
    }

    pictureOptions.encodingType = [command argumentAtIndex:3 withDefault:@"jpeg"];

    return pictureOptions;
}

@end

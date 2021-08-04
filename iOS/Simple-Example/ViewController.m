//
//  ViewController.m
//  Simple-Example
//

#import "ViewController.h"

@implementation ViewController

- (void)viewDidAppear:(BOOL)animated{
    NSLog(@"init - viewDidAppear");
#if DEBUG
    NSLog(@"1111122222 - viewDidAppear");
#endif
    [super viewDidAppear:animated];
}

- (IBAction) onCrash:(__unused id) sender
{
    NSArray *arr = @[];
    NSLog(@"%@ 111", arr[0]);
    
//    char* ptr = (char*)-1;
//    *ptr = 10;
}

@end

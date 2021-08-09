//
//  MainVC.m
//  Advanced-Example
//

#import "MainVC.h"

#import <KSCrash/KSCrash.h>
#import "AppDelegate.h"
#import <KSCrash/KSCrashInstallation.h>

/**
 * Some sensitive info that should not be printed out at any time.
 *
 * If you have Objective-C introspection turned on, it would normally
 * introspect this class, unless you add it to the list of
 * "do not introspect classes" in KSCrash. We do precisely this in 
 * -[AppDelegate configureAdvancedSettings]
 */



@interface SensitiveInfo: NSObject

@property(nonatomic, readwrite, strong) NSString* password;

@end

@implementation SensitiveInfo

@end



@interface MainVC () <UITableViewDelegate, UITableViewDataSource>

@property(nonatomic, readwrite, strong) SensitiveInfo* info;
@property(nonatomic, readwrite, strong) UITableView* tableView;
@property(nonatomic, readwrite, strong) NSArray* dateList;

@end

@implementation MainVC

- (id) initWithCoder:(NSCoder *)aDecoder
{
    if((self = [super initWithCoder:aDecoder]))
    {
        // This info could be leaked during introspection unless you tell KSCrash to ignore it.
        // See -[AppDelegate configureAdvancedSettings] for more info.
        self.info = [SensitiveInfo new];
        self.info.password = @"it's a secret!";
    }
    return self;
}

- (void) viewDidLoad {
    [super viewDidLoad];
    [self initTableView];
    [self initData];
}

- (void)initTableView{
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds];
    [self.view addSubview:self.tableView];
    
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
}

- (void) sendAllExceptions {
    AppDelegate* appDelegate = (AppDelegate*)[UIApplication sharedApplication].delegate;

    [appDelegate.crashInstallation sendAllReportsWithCompletion:^(NSArray *filteredReports, BOOL completed, NSError *error) {
        if(completed) {
            NSLog(@"\n****Sent %lu reports", (unsigned long)[filteredReports count]);
            NSLog(@"\n%@", filteredReports);
            //        [[KSCrash sharedInstance] deleteAllReports];
        } else {
            NSLog(@"Failed to send reports: %@", error);
        }
    }];
}

- (void)initData{
    self.dateList = @[@"Report Exception-User", // 0
                      @"Exception-Pointer C++", // 1
                      @"Exception-NSException-NSArray", // 2
                      @"Exception-野指针(X)", //3
                      @"Exception-没有selector", //4
                      @"Exception-Mach", // 5
                      @"Exception-Signal",//6
                      @"Exception-主线程死锁",//7
                      @"Exception-Zombie内存？",//8
                      @"Other"];
}

# pragma tableview delegate

- (NSURL *) _getObj{
    NSURL *url = [NSURL URLWithString:@"111"];
    return url;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath{
    NSInteger index = indexPath.item;
    NSLog(@"index = %ld", index);
    if (index == 0) {
        NSException* ex = [NSException exceptionWithName:@"testing exception name" reason:@"testing exception reason" userInfo:@{@"testing exception key":@"testing exception value"}];
        [KSCrash sharedInstance].currentSnapshotUserReportedExceptionHandler(ex);
        [KSCrash sharedInstance].monitoring = KSCrashMonitorTypeProductionSafe;
        [self sendAllExceptions];
    } else if (index == 1) {
        char* invalid = (char*)-1;
        *invalid = 1;
    } else if (index == 2) {
        NSLog(@"item 100 = %@",self.dateList[100]);
    } else if (index == 3) {
        NSURL *aa;
        @autoreleasepool {
            NSURL *url = [NSURL URLWithString:@"111"];
            aa = url;
        }
        
        NSLog(@"aa.len = %@",aa.host);
    } else if (index == 4) {
        NSString *aa = @"111";
        UIViewController *vc = (UIViewController *)aa;
        NSLog(@"aa.len = %@", vc.title);
    } else if (index == 5) { // Mach
        NSLog(@"TODO:");
    } else if (index == 6) { // Signal
        NSLog(@"TODO:");
    } else if (index == 7) { // 主线程死锁
        NSLog(@"TODO:");
    } else if (index == 8) { // Zombie内存
        NSLog(@"TODO:");
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{
    return [self.dateList count];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView{
    return 1;
}

static NSString* reuseIndentifier = @"tableViewCell-1";
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseIndentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:reuseIndentifier];
    }
    NSInteger index = indexPath.item;
    cell.textLabel.text = self.dateList[index];
    return cell;
}

@end

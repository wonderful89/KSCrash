//
//  Crasher.m
//
//  Created by Karl Stenerud on 2012-01-28.
//

#import "Crasher.h"
#import <KSCrash/KSCrash.h>
//#import <KSCrash/NSZombieBase.h>
#import <pthread.h>
#import <exception>

class MyException: public std::exception
{
public:
    virtual const char* what() const noexcept;
};

const char* MyException::what() const noexcept
{
    return "Something bad happened...";
}

class MyCPPClass
{
public:
    void throwAnException()
    {
        throw MyException();
    }
};


@interface MyClass: NSObject @end
@implementation MyClass @end

@interface MyProxy: NSProxy @end
@implementation MyProxy @end

@interface RefHolder: NSObject
{
    __unsafe_unretained id _ref;
}
@property(nonatomic, readwrite, assign) id ref;

@end

@implementation RefHolder

- (id) ref
{
    return _ref;
}

- (void) setRef:(id) ref
{
    _ref = ref;
}

@end


@interface Crasher ()

@property(nonatomic, readwrite, retain) NSLock* lock;

@end


@implementation Crasher

@synthesize lock = _lock;

- (id) init
{
    if((self = [super init]))
    {
        self.lock = [[NSLock alloc] init];
    }
    return self;
}

int* g_crasher_null_ptr = NULL;
int g_crasher_denominator = 0;

- (void) throwUncaughtNSException
{
    id data = [NSArray arrayWithObject:@"Hello World"];
    [(NSDictionary*)data objectForKey:@""];
}

- (void) dereferenceBadPointer
{
    char* ptr = (char*)-1;
    *ptr = 1;
}

- (void) dereferenceNullPointer
{
    *g_crasher_null_ptr = 1;
}

/// 对象被损坏-
- (void) useCorruptObject
{
    // From http://landonf.bikemonkey.org/2011/09/14
    
    // Random data
    void* pointers[] = {NULL, NULL, NULL};
    void* randomData[] = {
        (void*)"a",
        (void*)"b",
        (void*)pointers,
        (void*)"d",
        (void*)"e",
        (void*)"f"};
    
    // A corrupted/under-retained/re-used piece of memory
    struct {void* isa;} corruptObj = {randomData};
    
    // Message an invalid/corrupt object.
    // This will deadlock if called in a crash handler.
    [(__bridge id)&corruptObj class];
}

- (void) spinRunloop
{
    // From http://landonf.bikemonkey.org/2011/09/14
    
    dispatch_async(dispatch_get_main_queue(), ^
    {
        NSLog(@"ERROR: Run loop should be dead but isn't!");
    });
    *g_crasher_null_ptr = 1;
}

static volatile int counter = 0; // To prevent recursion optimization

/// 引起栈溢出；不断累加的方式
- (void) causeStackOverflow
{
    [self causeStackOverflow];
    counter++;
}

- (void) doAbort
{
    abort();
}

/// 除0异常
- (void) doDiv0
{
    int value = 10;
    value /= g_crasher_denominator;
    NSLog(@"%d", value);
}

/// 非法指令异常
- (void) doIllegalInstruction
{
    unsigned int data[] = {0x11111111, 0x11111111};
    void (*funcptr)() = (void (*)())data;
    funcptr();
}

/// 访问释放的对象-野指针
- (void) accessDeallocatedObject
{
//    NSArray* array = [[NSArray alloc] initWithObjects:@"", nil];
//    [array release];
//    void* ptr = array;
//    memset(ptr, 0xe1, 16);
//    [array objectAtIndex:10];
//    return;

    RefHolder* ref = [RefHolder new];
    ref.ref = [NSArray arrayWithObjects:@"test1", @"test2", nil];

    dispatch_async(dispatch_get_main_queue(), ^
                   {
                       NSLog(@"Object = %@", [ref.ref objectAtIndex:1]);
                   });
}

/// 访问释放的Proxy-野指针？
- (void) accessDeallocatedPtrProxy
{
    RefHolder* ref = [RefHolder new];
    /// NSProxy 对象第一次点击就 crash 了，但是NSObject第二次点击才会 crash。
    ref.ref = [MyProxy alloc]; //[NSObject new]; //

    dispatch_async(dispatch_get_main_queue(), ^
                   {
                       NSLog(@"Object = %@", ref.ref);
                   });
}

/// ？？
- (void) zombieNSException
{
    @try
    {
        NSString* value = @"This is a string";
        [NSException raise:@"TurboEncabulatorException"
                    format:@"Spurving bearing failure: Barescent skor motion non-sinusoidal for %p", value];
    }
    @catch (NSException *exception)
    {
        RefHolder* ref = [RefHolder new];
        ref.ref = exception;

        dispatch_async(dispatch_get_main_queue(), ^
                       {
                           NSLog(@"Exception = %@", ref.ref);
                       });
    }
}

- (void) zombieNSURL
{
//    NSURL *url = [NSURL new]; // 不会正常调用进去
//    MyTest *url = [MyTest new];
    MyNSURL *url = [MyNSURL new];
//    NSArray *url = [NSArray new]; // 比较多，不容易查找.
    RefHolder* ref = [RefHolder new];
//        ref.ref = exception;
    ref.ref = url;

    dispatch_async(dispatch_get_main_queue(), ^
                   {
                       NSLog(@"inner url = %@", ref.ref);
                   });
    NSLog(@"outer url = %@", ref.ref);
}
/// memset 操作非法写
- (void) corruptMemory
{
    size_t stringsize = sizeof(uintptr_t) * 2 + 2;
    NSString* string = [NSString stringWithFormat:@"%d", 1];
    NSLog(@"%@", string);
    void* cast = (__bridge void*)string;
    uintptr_t address = (uintptr_t)cast;
    void* ptr = (char*)address + stringsize;
    memset(ptr, 0xa1, 500);
}

/// 用lock创建死锁
- (void) deadlock
{
    [self.lock lock];
    [NSThread sleepForTimeInterval:0.2f];
    dispatch_async(dispatch_get_main_queue(), ^
                   {
                       [self.lock lock];
                   });
}

/// pthreadAPI发生异常-以为或者的名字放在第二个参数。但是没有空间。
- (void) pthreadAPICrash
{
    // http://landonf.bikemonkey.org/code/crashreporting
    pthread_getname_np(pthread_self(), (char*)0x1, 1);
}

/// 用户自定义的crash
- (void) userDefinedCrash
{
    NSString* name = @"Script Error";
    NSString* reason = @"fragment is not defined";
    NSString* language = @"karlscript";
    NSString* lineOfCode = @"string.append(fragment)";
    NSArray* stackTrace = [NSArray arrayWithObjects:
                           @"Printer.script, line 174: in function assembleComponents",
                           @"Printer.script, line 209: in function print",
                           @"Main.script, line 10: in function initialize",
                           nil];

    [[KSCrash sharedInstance] reportUserException:name
                                           reason:reason
                                         language:language
                                       lineOfCode:lineOfCode
                                       stackTrace:stackTrace
                                    logAllThreads:YES
                                 terminateProgram:NO];
}



/// 抛出c++异常
- (void) throwUncaughtCPPException
{
    MyCPPClass instance;
    instance.throwAnException();
}

@end

@implementation MyTest

- (void)dealloc
{
    NSLog(@"MyTest dealloc");
}

@end


@implementation MyNSURL

- (void)dealloc
{
    NSLog(@"MyNSURL dealloc");
}

@end

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <dlfcn.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <ifaddrs.h>
#import <mach/mach_time.h>

typedef void* IOHIDEventSystemClientRef;
typedef void* IOHIDEventRef;

typedef IOHIDEventSystemClientRef (*p_IOHIDEventSystemClientCreate)(CFAllocatorRef allocator);
typedef IOHIDEventRef (*p_IOHIDEventCreateDigitizerEvent)(CFAllocatorRef allocator, uint64_t timeStamp, uint32_t transducerType, uint32_t index, uint32_t identity, uint32_t eventMask, uint32_t buttonMask, double x, double y, double z, double tipPressure, double barrelPressure, boolean_t range, boolean_t touch, uint32_t options);
typedef IOHIDEventRef (*p_IOHIDEventCreateDigitizerFingerEvent)(CFAllocatorRef allocator, uint64_t timeStamp, uint32_t index, uint32_t identity, uint32_t eventMask, double x, double y, double z, double tipPressure, double twist, boolean_t range, boolean_t touch, uint32_t options);
typedef void (*p_IOHIDEventAppendEvent)(IOHIDEventRef parent, IOHIDEventRef child, uint32_t options);
typedef void (*p_IOHIDEventSetIntegerValue)(IOHIDEventRef event, uint32_t field, CFIndex value);
typedef void (*p_IOHIDEventSetSenderID)(IOHIDEventRef event, uint64_t senderID);
typedef void (*p_IOHIDEventSystemClientDispatchEvent)(IOHIDEventSystemClientRef client, IOHIDEventRef event);
typedef void (*p_BKSHIDEventSetDigitizerInfo)(IOHIDEventRef event, uint32_t contextID, boolean_t systemGestureisPossible, boolean_t isSystemGestureStateChangeEvent, CFStringRef displayUUID, CFTimeInterval initialTouchTimestamp, float maxForce);

static IOHIDEventSystemClientRef hidClient = NULL;
static p_IOHIDEventCreateDigitizerEvent fnCreateDigitizerEvent = NULL;
static p_IOHIDEventCreateDigitizerFingerEvent fnCreateFingerEvent = NULL;
static p_IOHIDEventAppendEvent fnAppendEvent = NULL;
static p_IOHIDEventSetIntegerValue fnSetIntValue = NULL;
static p_IOHIDEventSetSenderID fnSetSenderID = NULL;
static p_IOHIDEventSystemClientDispatchEvent fnDispatchEvent = NULL;
static p_BKSHIDEventSetDigitizerInfo fnBKSSetDigitizerInfo = NULL;
static int receivedCount = 0;

void initHID() {
    void *handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW);
    if (handle) {
        p_IOHIDEventSystemClientCreate fnCreate = (p_IOHIDEventSystemClientCreate)dlsym(handle, "IOHIDEventSystemClientCreate");
        fnCreateDigitizerEvent = (p_IOHIDEventCreateDigitizerEvent)dlsym(handle, "IOHIDEventCreateDigitizerEvent");
        fnCreateFingerEvent = (p_IOHIDEventCreateDigitizerFingerEvent)dlsym(handle, "IOHIDEventCreateDigitizerFingerEvent");
        fnAppendEvent = (p_IOHIDEventAppendEvent)dlsym(handle, "IOHIDEventAppendEvent");
        fnSetIntValue = (p_IOHIDEventSetIntegerValue)dlsym(handle, "IOHIDEventSetIntegerValue");
        fnSetSenderID = (p_IOHIDEventSetSenderID)dlsym(handle, "IOHIDEventSetSenderID");
        fnDispatchEvent = (p_IOHIDEventSystemClientDispatchEvent)dlsym(handle, "IOHIDEventSystemClientDispatchEvent");
        if (fnCreate) hidClient = fnCreate(kCFAllocatorDefault);
    }
    void *bksHandle = dlopen("/System/Library/PrivateFrameworks/BackBoardServices.framework/BackBoardServices", RTLD_NOW);
    if (bksHandle) {
        fnBKSSetDigitizerInfo = (p_BKSHIDEventSetDigitizerInfo)dlsym(bksHandle, "BKSHIDEventSetDigitizerInfo");
    }
}

void sendTouch(double normX, double normY, int type) {
    if (!hidClient || !fnCreateDigitizerEvent || !fnCreateFingerEvent) return;
    uint64_t ts = mach_absolute_time();
    // 1 = Range, 2 = Touch, 4 = Position
    uint32_t eventMask = (type == 0) ? (1 | 2 | 4) : ((type == 1) ? 4 : (1 | 2));
    boolean_t isTouch = (type == 2) ? false : true;
    double pressure = isTouch ? 1.0 : 0.0;

    IOHIDEventRef parent = fnCreateDigitizerEvent(kCFAllocatorDefault, ts, 3, 0, 0, eventMask, 0, normX, normY, 0, pressure, 0, isTouch, isTouch, 0);
    IOHIDEventRef finger = fnCreateFingerEvent(kCFAllocatorDefault, ts, 1, 2, eventMask, normX, normY, 0, pressure, 0, isTouch, isTouch, 0);
    
    if (parent && finger) {
        if (fnSetIntValue) {
            fnSetIntValue(parent, 0xB0019, 1); // kIOHIDEventFieldIsBuiltIn
            fnSetIntValue(finger, 0xB0019, 1);
            fnSetIntValue(parent, 0xB0007, 1); // Integrated display
        }
        if (fnSetSenderID) {
            fnSetSenderID(parent, 0x8000000817319372ULL);
        }
        fnAppendEvent(parent, finger, 0);
        if (fnBKSSetDigitizerInfo) {
            fnBKSSetDigitizerInfo(parent, 0, false, false, NULL, 0, 0);
        }
        fnDispatchEvent(hidClient, parent);
        CFRelease(finger);
        CFRelease(parent);
    }
}

NSString* getWiFiIPAddress() {
    NSString *address = @"Khong tim thay Wi-Fi";
    struct ifaddrs *interfaces = NULL;
    if (getifaddrs(&interfaces) == 0) {
        struct ifaddrs *temp = interfaces;
        while (temp != NULL) {
            if (temp->ifa_addr->sa_family == AF_INET) {
                if ([[NSString stringWithUTF8String:temp->ifa_name] isEqualToString:@"en0"]) {
                    address = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)temp->ifa_addr)->sin_addr)];
                }
            }
            temp = temp->ifa_next;
        }
    }
    freeifaddrs(interfaces);
    return address;
}

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (strong, nonatomic) UIWindow *window;
@property (strong, nonatomic) UILabel *statusLabel;
@property (strong, nonatomic) AVAudioEngine *audioEngine;
@end

@implementation AppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    initHID();
    [UIApplication sharedApplication].idleTimerDisabled = YES;
    [self keepAliveInBackground];

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    UIViewController *vc = [[UIViewController alloc] init];
    vc.view.backgroundColor = [UIColor systemBackgroundColor];

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 100, self.window.bounds.size.width - 40, 260)];
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightMedium];
    [self updateUI];
    [vc.view addSubview:self.statusLabel];

    UIButton *testBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    testBtn.frame = CGRectMake(60, 380, self.window.bounds.size.width - 120, 50);
    [testBtn setTitle:@"Bam thu vao day (Test)" forState:UIControlStateNormal];
    testBtn.backgroundColor = [UIColor systemBlueColor];
    [testBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    testBtn.layer.cornerRadius = 10;
    [testBtn addTarget:self action:@selector(onTestBtnTapped) forControlEvents:UIControlEventTouchUpInside];
    [vc.view addSubview:testBtn];

    self.window.rootViewController = vc;
    [self.window makeKeyAndVisible];

    [self startTCPServer];
    return YES;
}

- (void)onTestBtnTapped {
    self.statusLabel.backgroundColor = [[UIColor systemGreenColor] colorWithAlphaComponent:0.25];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.statusLabel.backgroundColor = [UIColor clearColor];
    });
}

- (void)updateUI {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.statusLabel.text = [NSString stringWithFormat:@"Remote Server Dang Chay\n\nIP iPhone: %@\nPort: 8888\nHID: %@ | BKS: %@\nSo lenh da nhan: %d",
            getWiFiIPAddress(),
            hidClient ? @"OK" : @"LOI",
            fnBKSSetDigitizerInfo ? @"OK" : @"LOI",
            receivedCount];
    });
}

- (void)keepAliveInBackground {
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayback withOptions:AVAudioSessionCategoryMixWithOthers error:nil];
    [session setActive:YES error:nil];
    
    self.audioEngine = [[AVAudioEngine alloc] init];
    AVAudioMixerNode *mainMixer = [self.audioEngine mainMixerNode];
    mainMixer.outputVolume = 0.0;
    [self.audioEngine prepare];
    [self.audioEngine startAndReturnError:nil];
}

- (void)startTCPServer {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        int server_fd = socket(AF_INET, SOCK_STREAM, 0);
        int opt = 1;
        setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

        struct sockaddr_in address;
        address.sin_family = AF_INET;
        address.sin_addr.s_addr = INADDR_ANY;
        address.sin_port = htons(8888);

        bind(server_fd, (struct sockaddr *)&address, sizeof(address));
        listen(server_fd, 5);

        while (1) {
            int client_fd = accept(server_fd, NULL, NULL);
            if (client_fd < 0) continue;
            char buffer[512];
            ssize_t bytesRead;
            while ((bytesRead = recv(client_fd, buffer, sizeof(buffer) - 1, 0)) > 0) {
                buffer[bytesRead] = '\0';
                NSString *cmd = [NSString stringWithUTF8String:buffer];
                for (NSString *line in [cmd componentsSeparatedByString:@"\n"]) {
                    NSArray *parts = [line componentsSeparatedByString:@","];
                    if (parts.count == 3) {
                        receivedCount++;
                        int type = [parts[0] intValue];
                        double nx = [parts[1] doubleValue];
                        double ny = [parts[2] doubleValue];
                        sendTouch(nx, ny, type);
                    }
                }
                [self updateUI];
            }
            close(client_fd);
        }
    });
}
@end

int main(int argc, char * argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
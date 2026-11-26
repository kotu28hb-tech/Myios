#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <IOSurface/IOSurfaceRef.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <dlfcn.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <ifaddrs.h>
#import <mach/mach_time.h>

// Private API chup man hinh phan cung IOSurface
extern IOSurfaceRef UIWindowCreateIOSurface(void) __attribute__((weak_import));
typedef void (*p_CARenderServerRenderDisplay)(kern_return_t a, CFStringRef b, IOSurfaceRef surface, int x, int y);
static p_CARenderServerRenderDisplay fnRenderDisplay = NULL;

// Private API IOHIDEvent & BackBoardServices
typedef void* IOHIDEventSystemClientRef;
typedef void* IOHIDEventRef;
typedef IOHIDEventSystemClientRef (*p_IOHIDEventSystemClientCreate)(CFAllocatorRef allocator);
typedef IOHIDEventRef (*p_IOHIDEventCreateDigitizerEvent)(CFAllocatorRef allocator, uint64_t timeStamp, uint32_t transducerType, uint32_t index, uint32_t identity, uint32_t eventMask, uint32_t buttonMask, double x, double y, double z, double tipPressure, double barrelPressure, boolean_t range, boolean_t touch, uint32_t options);
typedef IOHIDEventRef (*p_IOHIDEventCreateDigitizerFingerEvent)(CFAllocatorRef allocator, uint64_t timeStamp, uint32_t index, uint32_t identity, uint32_t eventMask, double x, double y, double z, double tipPressure, double twist, boolean_t range, boolean_t touch, uint32_t options);
typedef void (*p_IOHIDEventAppendEvent)(IOHIDEventRef parent, IOHIDEventRef child, uint32_t options);
typedef void (*p_IOHIDEventSetIntegerValue)(IOHIDEventRef event, uint32_t field, CFIndex value);
typedef void (*p_IOHIDEventSystemClientDispatchEvent)(IOHIDEventSystemClientRef client, IOHIDEventRef event);
typedef void (*p_BKSHIDEventSendToFocusedProcess)(IOHIDEventRef event);

static IOHIDEventSystemClientRef hidClient = NULL;
static p_IOHIDEventCreateDigitizerEvent fnCreateDigitizerEvent = NULL;
static p_IOHIDEventCreateDigitizerFingerEvent fnCreateFingerEvent = NULL;
static p_IOHIDEventAppendEvent fnAppendEvent = NULL;
static p_IOHIDEventSetIntegerValue fnSetIntValue = NULL;
static p_IOHIDEventSystemClientDispatchEvent fnDispatchEvent = NULL;
static p_BKSHIDEventSendToFocusedProcess fnSendToFocused = NULL;

void initPrivateAPIs() {
    void *qc = dlopen("/System/Library/Frameworks/QuartzCore.framework/QuartzCore", RTLD_NOW);
    if (qc) fnRenderDisplay = (p_CARenderServerRenderDisplay)dlsym(qc, "CARenderServerRenderDisplay");

    void *io = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW);
    if (io) {
        p_IOHIDEventSystemClientCreate fnCreate = (p_IOHIDEventSystemClientCreate)dlsym(io, "IOHIDEventSystemClientCreate");
        fnCreateDigitizerEvent = (p_IOHIDEventCreateDigitizerEvent)dlsym(io, "IOHIDEventCreateDigitizerEvent");
        fnCreateFingerEvent = (p_IOHIDEventCreateDigitizerFingerEvent)dlsym(io, "IOHIDEventCreateDigitizerFingerEvent");
        fnAppendEvent = (p_IOHIDEventAppendEvent)dlsym(io, "IOHIDEventAppendEvent");
        fnSetIntValue = (p_IOHIDEventSetIntegerValue)dlsym(io, "IOHIDEventSetIntegerValue");
        fnDispatchEvent = (p_IOHIDEventSystemClientDispatchEvent)dlsym(io, "IOHIDEventSystemClientDispatchEvent");
        if (fnCreate) hidClient = fnCreate(kCFAllocatorDefault);
    }

    void *bks = dlopen("/System/Library/PrivateFrameworks/BackBoardServices.framework/BackBoardServices", RTLD_NOW);
    if (bks) {
        fnSendToFocused = (p_BKSHIDEventSendToFocusedProcess)dlsym(bks, "BKSHIDEventSendToFocusedProcess");
    }
}

void sendTouch(double normX, double normY, int type) {
    if (!fnCreateDigitizerEvent || !fnCreateFingerEvent) return;
    uint64_t ts = mach_absolute_time();
    uint32_t eventMask = (type == 0) ? (1 | 2 | 4) : ((type == 1) ? 4 : (1 | 2));
    boolean_t isTouch = (type == 2) ? false : true;
    double pressure = isTouch ? 1.0 : 0.0;

    IOHIDEventRef parent = fnCreateDigitizerEvent(kCFAllocatorDefault, ts, 3, 0, 0, eventMask, 0, normX, normY, 0, pressure, 0, isTouch, isTouch, 0);
    IOHIDEventRef finger = fnCreateFingerEvent(kCFAllocatorDefault, ts, 1, 2, eventMask, normX, normY, 0, pressure, 0, isTouch, isTouch, 0);
    if (parent && finger) {
        if (fnSetIntValue) {
            fnSetIntValue(parent, 0xB0019, 1);
            fnSetIntValue(finger, 0xB0019, 1);
        }
        fnAppendEvent(parent, finger, 0);
        if (fnSendToFocused) {
            fnSendToFocused(parent);
        } else if (hidClient && fnDispatchEvent) {
            fnDispatchEvent(hidClient, parent);
        }
        CFRelease(finger);
        CFRelease(parent);
    }
}

NSData* captureScreenJPEG() {
    if (!fnRenderDisplay) return nil;
    // Kich thuoc khung hinh giam 1/3 cua iPhone 12 Pro Max (428 x 926) de truyen muot qua Wi-Fi
    int w = 428;
    int h = 926;
    int bytesPerRow = w * 4;
    NSDictionary *props = @{
        (__bridge NSString *)kIOSurfaceWidth: @(w),
        (__bridge NSString *)kIOSurfaceHeight: @(h),
        (__bridge NSString *)kIOSurfaceBytesPerElement: @(4),
        (__bridge NSString *)kIOSurfaceBytesPerRow: @(bytesPerRow),
        (__bridge NSString *)kIOSurfacePixelFormat: @(0x42475241) // 'BGRA'
    };
    IOSurfaceRef surface = IOSurfaceCreate((__bridge CFDictionaryRef)props);
    if (!surface) return nil;

    fnRenderDisplay(0, CFSTR("LCD"), surface, 0, 0);
    IOSurfaceLock(surface, kIOSurfaceLockReadOnly, NULL);
    void *baseAddr = IOSurfaceGetBaseAddress(surface);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(baseAddr, w, h, 8, bytesPerRow, colorSpace, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    CGImageRef cgImg = CGBitmapContextCreateImage(ctx);
    IOSurfaceUnlock(surface, kIOSurfaceLockReadOnly, NULL);

    NSMutableData *jpegData = [NSMutableData data];
    if (cgImg) {
        CGImageDestinationRef dest = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)jpegData, kUTTypeJPEG, 1, NULL);
        if (dest) {
            NSDictionary *opts = @{ (__bridge NSString *)kCGImageDestinationLossyCompressionQuality: @(0.55) };
            CGImageDestinationAddImage(dest, cgImg, (__bridge CFDictionaryRef)opts);
            CGImageDestinationFinalize(dest);
            CFRelease(dest);
        }
        CGImageRelease(cgImg);
    }
    if (ctx) CGContextRelease(ctx);
    if (colorSpace) CGColorSpaceRelease(colorSpace);
    CFRelease(surface);
    return jpegData;
}

NSString* getWiFiIP() {
    NSString *address = @"127.0.0.1";
    struct ifaddrs *interfaces = NULL;
    if (getifaddrs(&interfaces) == 0) {
        for (struct ifaddrs *temp = interfaces; temp != NULL; temp = temp->ifa_next) {
            if (temp->ifa_addr->sa_family == AF_INET && [[NSString stringWithUTF8String:temp->ifa_name] isEqualToString:@"en0"]) {
                address = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)temp->ifa_addr)->sin_addr)];
            }
        }
    }
    freeifaddrs(interfaces);
    return address;
}

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (strong, nonatomic) UIWindow *window;
@property (strong, nonatomic) AVAudioEngine *audioEngine;
@end

@implementation AppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    initPrivateAPIs();
    [UIApplication sharedApplication].idleTimerDisabled = YES;
    
    // Giu app chay ngam lien tuc
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayback withOptions:AVAudioSessionCategoryOptionMixWithOthers error:nil];
    [session setActive:YES error:nil];
    self.audioEngine = [[AVAudioEngine alloc] init];
    [self.audioEngine mainMixerNode].outputVolume = 0.0;
    [self.audioEngine prepare];
    [self.audioEngine startAndReturnError:nil];

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    UIViewController *vc = [[UIViewController alloc] init];
    vc.view.backgroundColor = [UIColor systemBackgroundColor];

    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(20, 120, self.window.bounds.size.width - 40, 260)];
    lbl.numberOfLines = 0;
    lbl.textAlignment = NSTextAlignmentCenter;
    lbl.font = [UIFont systemFontOfSize:18 weight:UIFontWeightMedium];
    lbl.text = [NSString stringWithFormat:@"iPhone Mirror & Control\n\nIP Wi-Fi: %@\nPort Hinh Anh: 9100\nPort Dieu Khien: 8888\nRender API: %@ | Touch API: %@",
                getWiFiIP(),
                fnRenderDisplay ? @"OK" : @"LOI",
                fnSendToFocused ? @"BKS-OK" : @"HID"];
    [vc.view addSubview:lbl];

    self.window.rootViewController = vc;
    [self.window makeKeyAndVisible];

    [self startControlServer];
    [self startScreenStreamServer];
    return YES;
}

- (void)startControlServer {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        int server_fd = socket(AF_INET, SOCK_STREAM, 0);
        int opt = 1;
        setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
        struct sockaddr_in addr = {0};
        addr.sin_family = AF_INET;
        addr.sin_addr.s_addr = INADDR_ANY;
        addr.sin_port = htons(8888);
        bind(server_fd, (struct sockaddr *)&addr, sizeof(addr));
        listen(server_fd, 5);

        while (1) {
            int client_fd = accept(server_fd, NULL, NULL);
            if (client_fd < 0) continue;
            char buf[512];
            ssize_t n;
            while ((n = recv(client_fd, buf, sizeof(buf) - 1, 0)) > 0) {
                buf[n] = '\0';
                NSString *cmd = [NSString stringWithUTF8String:buf];
                for (NSString *line in [cmd componentsSeparatedByString:@"\n"]) {
                    NSArray *p = [line componentsSeparatedByString:@","];
                    if (p.count == 3) sendTouch([p[1] doubleValue], [p[2] doubleValue], [p[0] intValue]);
                }
            }
            close(client_fd);
        }
    });
}

- (void)startScreenStreamServer {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        int server_fd = socket(AF_INET, SOCK_STREAM, 0);
        int opt = 1;
        setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
        struct sockaddr_in addr = {0};
        addr.sin_family = AF_INET;
        addr.sin_addr.s_addr = INADDR_ANY;
        addr.sin_port = htons(9100);
        bind(server_fd, (struct sockaddr *)&addr, sizeof(addr));
        listen(server_fd, 5);

        while (1) {
            int client_fd = accept(server_fd, NULL, NULL);
            if (client_fd < 0) continue;
            
            NSString *header = @"HTTP/1.1 200 OK\r\nContent-Type: multipart/x-mixed-replace; boundary=frame\r\n\r\n";
            send(client_fd, [header UTF8String], header.length, 0);

            while (1) {
                @autoreleasepool {
                    NSData *jpg = captureScreenJPEG();
                    if (jpg && jpg.length > 0) {
                        NSString *partHeader = [NSString stringWithFormat:@"--frame\r\nContent-Type: image/jpeg\r\nContent-Length: %lu\r\n\r\n", (unsigned long)jpg.length];
                        if (send(client_fd, [partHeader UTF8String], partHeader.length, 0) <= 0) break;
                        if (send(client_fd, jpg.bytes, jpg.length, 0) <= 0) break;
                        if (send(client_fd, "\r\n", 2, 0) <= 0) break;
                    }
                }
                usleep(33000); // ~30 FPS
            }
            close(client_fd);
        }
    });
}
@end

int main(int argc, char * argv[]) {
    setuid(0);
    setgid(0);
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
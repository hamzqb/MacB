// MacB's reader for the system's Now Playing information.
//
// Since macOS 15.4 MediaRemote answers only processes Apple has entitled, so
// an app cannot ask it what is playing. /usr/bin/perl is one of those
// processes; MacB starts it, has it load this library, and calls
// `macb_nowplaying_stream`. The library then writes one JSON line to stdout
// whenever what is playing changes, and reads one command per line from stdin
// ("toggle", "next", "previous", "seek <seconds>").
//
// It only reads the Now Playing information and sends the same transport
// commands the media keys do. It exits when MacB goes away.

#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>
#include <dlfcn.h>
#include <unistd.h>

typedef void (*GetInfoFn)(dispatch_queue_t, void (^)(NSDictionary *));
typedef void (*GetIsPlayingFn)(dispatch_queue_t, void (^)(Boolean));
typedef void (*GetClientFn)(dispatch_queue_t, void (^)(id));
typedef CFStringRef (*ClientBundleFn)(id);
typedef void (*RegisterFn)(dispatch_queue_t);
typedef Boolean (*SendCommandFn)(int, NSDictionary *);
typedef void (*SetElapsedFn)(double);

static GetInfoFn getInfo;
static GetIsPlayingFn getIsPlaying;
static GetClientFn getClient;
static ClientBundleFn clientBundle;
static ClientBundleFn clientParentBundle;
static SendCommandFn sendCommand;
static SetElapsedFn setElapsed;
static dispatch_queue_t queue;
static NSString *lastArtworkHash = @"";
static NSString *lastLine = @"";

static NSString *hashOf(NSData *data) {
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *hex = [NSMutableString string];
    for (int i = 0; i < 8; i++) [hex appendFormat:@"%02x", digest[i]];
    return hex;
}

static id jsonValue(id value) {
    if ([value isKindOfClass:NSString.class] || [value isKindOfClass:NSNumber.class]) return value;
    if ([value isKindOfClass:NSDate.class]) return @([(NSDate *)value timeIntervalSince1970]);
    return nil;
}

static void emit(NSDictionary *info, BOOL playing, NSString *bundle) {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    NSDictionary *keys = @{
        @"kMRMediaRemoteNowPlayingInfoTitle": @"title",
        @"kMRMediaRemoteNowPlayingInfoArtist": @"artist",
        @"kMRMediaRemoteNowPlayingInfoAlbum": @"album",
        @"kMRMediaRemoteNowPlayingInfoDuration": @"duration",
        @"kMRMediaRemoteNowPlayingInfoElapsedTime": @"elapsed",
        @"kMRMediaRemoteNowPlayingInfoPlaybackRate": @"rate",
        @"kMRMediaRemoteNowPlayingInfoTimestamp": @"timestamp",
        @"kMRMediaRemoteNowPlayingInfoShuffleMode": @"shuffle",
        @"kMRMediaRemoteNowPlayingInfoRepeatMode": @"repeat",
    };
    for (NSString *key in keys) {
        id value = jsonValue(info[key]);
        if (value) out[keys[key]] = value;
    }
    out[@"playing"] = @(playing);
    if (bundle) out[@"bundle"] = bundle;
    NSData *artwork = info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
    NSString *artworkHash = [artwork isKindOfClass:NSData.class] && artwork.length > 0 ? hashOf(artwork) : @"";
    out[@"artworkHash"] = artworkHash;
    NSData *lineWithoutArt = [NSJSONSerialization dataWithJSONObject:out options:NSJSONWritingSortedKeys error:nil];
    NSString *comparable = [[NSString alloc] initWithData:lineWithoutArt encoding:NSUTF8StringEncoding];
    BOOL artworkChanged = ![artworkHash isEqualToString:lastArtworkHash];
    if (!artworkChanged && [comparable isEqualToString:lastLine]) return;
    lastLine = comparable;
    if (artworkChanged && artworkHash.length > 0) out[@"artwork"] = [artwork base64EncodedStringWithOptions:0];
    lastArtworkHash = artworkHash;
    NSData *data = [NSJSONSerialization dataWithJSONObject:out options:0 error:nil];
    if (!data) return;
    fwrite(data.bytes, 1, data.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

static void refresh(void) {
    getInfo(queue, ^(NSDictionary *info) {
        getIsPlaying(queue, ^(Boolean playing) {
            if (!getClient || !clientBundle) { emit(info ?: @{}, playing, nil); return; }
            getClient(queue, ^(id client) {
                NSString *bundle = nil;
                if (client) {
                    // A browser tab reports the browser's helper; its parent is the browser.
                    CFStringRef parent = clientParentBundle ? clientParentBundle(client) : NULL;
                    CFStringRef own = clientBundle(client);
                    bundle = (__bridge NSString *)(parent ?: own);
                }
                emit(info ?: @{}, playing, bundle);
            });
        });
    });
}

static void runCommand(NSString *line) {
    NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([trimmed isEqualToString:@"toggle"]) sendCommand(2, nil);
    else if ([trimmed isEqualToString:@"next"]) sendCommand(4, nil);
    else if ([trimmed isEqualToString:@"previous"]) sendCommand(5, nil);
    else if ([trimmed hasPrefix:@"seek "] && setElapsed) setElapsed([[trimmed substringFromIndex:5] doubleValue]);
    else if ([trimmed isEqualToString:@"refresh"]) { lastLine = @""; }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 150 * NSEC_PER_MSEC), queue, ^{ refresh(); });
}

void macb_nowplaying_stream(void) {
    void *handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    if (!handle) exit(2);
    getInfo = (GetInfoFn)dlsym(handle, "MRMediaRemoteGetNowPlayingInfo");
    getIsPlaying = (GetIsPlayingFn)dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    getClient = (GetClientFn)dlsym(handle, "MRMediaRemoteGetNowPlayingClient");
    clientBundle = (ClientBundleFn)dlsym(handle, "MRNowPlayingClientGetBundleIdentifier");
    clientParentBundle = (ClientBundleFn)dlsym(handle, "MRNowPlayingClientGetParentAppBundleIdentifier");
    sendCommand = (SendCommandFn)dlsym(handle, "MRMediaRemoteSendCommand");
    setElapsed = (SetElapsedFn)dlsym(handle, "MRMediaRemoteSetElapsedTime");
    RegisterFn registerForNotifications = (RegisterFn)dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications");
    if (!getInfo || !getIsPlaying || !sendCommand) exit(3);

    queue = dispatch_queue_create("MacB.NowPlaying", DISPATCH_QUEUE_SERIAL);
    if (registerForNotifications) registerForNotifications(queue);
    NSArray *names = @[
        @"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
        @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
        @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
        @"kMRMediaRemoteNowPlayingPlaybackQueueChangedNotification",
    ];
    for (NSString *name in names) {
        [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil
                                                    usingBlock:^(NSNotification *note) { dispatch_async(queue, ^{ refresh(); }); }];
    }

    dispatch_source_t input = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, STDIN_FILENO, 0, queue);
    __block NSMutableString *buffer = [NSMutableString string];
    dispatch_source_set_event_handler(input, ^{
        char chunk[512];
        ssize_t count = read(STDIN_FILENO, chunk, sizeof chunk);
        if (count <= 0) exit(0); // MacB closed the pipe: it is gone.
        [buffer appendString:[[NSString alloc] initWithBytes:chunk length:count encoding:NSUTF8StringEncoding] ?: @""];
        NSRange newline;
        while ((newline = [buffer rangeOfString:@"\n"]).location != NSNotFound) {
            NSString *line = [buffer substringToIndex:newline.location];
            [buffer deleteCharactersInRange:NSMakeRange(0, newline.location + 1)];
            runCommand(line);
        }
    });
    dispatch_resume(input);

    // Safety net for notifications that never come, and for a parent that
    // died without closing the pipe.
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 0), 3 * NSEC_PER_SEC, NSEC_PER_SEC / 2);
    dispatch_source_set_event_handler(timer, ^{
        if (getppid() == 1) exit(0);
        refresh();
    });
    dispatch_resume(timer);

    // Notifications are delivered on the main run loop.
    CFRunLoopRun();
}

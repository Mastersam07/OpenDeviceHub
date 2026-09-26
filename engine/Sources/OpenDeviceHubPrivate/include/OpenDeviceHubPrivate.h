#import <Foundation/Foundation.h>

/// Declarations for the CoreSimulator symbols the adapter sends messages to. These are protocols
/// only: no Apple class is declared, nothing is linked, and every selector here was confirmed on
/// Xcode 26.5 (17F42) and again on Xcode 27 (27A266a) before being written down.
///
/// The BOOL getters are spelled `available` rather than `isAvailable`, which is what the runtime
/// actually exports on both builds.
///
/// There is deliberately no `NS_ASSUME_NONNULL` here. Everything on the other side is a remote
/// proxy into another process, and a proxy returns nil once its device goes away, which happens
/// mid call during a shutdown. Anything object typed crossing this boundary is `_Nullable` unless
/// it has been shown never to be nil, and what we pass in is `_Nonnull` so nothing imports as an
/// implicitly unwrapped optional that would trap on use rather than at the binding.

@protocol ODHSimDeviceType <NSObject>
@property (nonatomic, readonly, nullable) NSString *identifier;
@property (nonatomic, readonly, nullable) NSString *name;
/// The point scale, 3.0 on an iPhone 17 Pro. `mainScreenSize` is in pixels, not points.
@property (nonatomic, readonly) float mainScreenScale;
@property (nonatomic, readonly) CGSize mainScreenSize;
@end

@protocol ODHSimRuntime <NSObject>
@property (nonatomic, readonly, nullable) NSString *identifier;
@property (nonatomic, readonly, nullable) NSString *name;
@property (nonatomic, readonly, nullable) NSString *versionString;
@property (nonatomic, readonly) BOOL available;
@end

@protocol ODHSimDevice <NSObject>
@property (nonatomic, readonly, nullable) NSUUID *UDID;
@property (nonatomic, readonly, nullable) NSString *name;
@property (nonatomic, readonly) NSUInteger state;
@property (nonatomic, readonly, nullable) NSString *stateString;
@property (nonatomic, readonly, nullable) id<ODHSimDeviceType> deviceType;
/// Nil when the device's runtime is not installed, which is common for devices left behind by an
/// uninstalled iOS version. `runtimeIdentifier` is still populated in that case, so it is the
/// reliable source for the identifier.
@property (nonatomic, readonly, nullable) id<ODHSimRuntime> runtime;
@property (nonatomic, readonly, nullable) NSString *runtimeIdentifier;
@property (nonatomic, readonly) BOOL available;
@property (nonatomic, readonly, nullable) id io;
/// Delivers a low memory warning to the guest. Verified present on Xcode 26.5 (17F42).
- (void)simulateMemoryWarning;
/// Returns a mach port for a service in the device's own namespace, or 0. Used to reach the
/// guest's workspace port, which is what carries orientation.
- (unsigned int)lookup:(NSString *_Nonnull)service error:(NSError *_Nullable *_Nullable)error;
/// Connects or disconnects the Mac's keyboard as the device's hardware keyboard. `keyboardType`
/// comes from `IndigoHIDGetKeyboardType`. Verified present on Xcode 27 (27A266a).
- (BOOL)setHardwareKeyboardEnabled:(BOOL)enabled
                      keyboardType:(unsigned char)keyboardType
                             error:(NSError *_Nullable *_Nullable)error;
/// Sets the guest's keyboard language, for example "en-US". Verified present on Xcode 27 (27A266a).
- (BOOL)setKeyboardLanguage:(NSString *_Nonnull)language
                      error:(NSError *_Nullable *_Nullable)error;
@end

@protocol ODHSimDeviceSet <NSObject>
/// Deliberately untyped. Annotating the element type makes Swift bridge the array with a checked
/// cast, and the real `SimDevice` does not formally adopt these protocols, so the check traps.
/// Elements are cast individually instead.
@property (nonatomic, readonly, nullable) NSArray *devices;
/// `SimDeviceSet` adopts `SimDeviceNotifier`, so one registration here covers every device in the
/// set, including devices booted by something else. The returned handle is what unregisters it.
/// Verified on Xcode 27 (27A266a).
///
/// The notification is a dictionary, but it is declared as `id` because nothing guarantees that:
/// the block is typed `void (^)(id)` and different senders put different things in it.
- (NSUInteger)registerNotificationHandlerOnQueue:(dispatch_queue_t _Nonnull)queue
                                         handler:(void (^_Nonnull)(id _Nullable))handler;
- (BOOL)unregisterNotificationHandler:(NSUInteger)handle error:(NSError *_Nullable *_Nullable)error;
@end

@protocol ODHSimDisplayDescriptorState <NSObject>
/// 0 is a panel the device actually has, 1 an external display port that stays empty while unused.
/// A foldable reports more than one port with class 0, one per panel, all live at the same time.
@property (nonatomic, readonly) unsigned short displayClass;
@property (nonatomic, readonly) unsigned int defaultWidthForDisplay;
@property (nonatomic, readonly) unsigned int defaultHeightForDisplay;
@property (nonatomic, readonly) unsigned int defaultPixelFormat;
@property (nonatomic, readonly, nullable) NSURL *mask;
@end

@protocol ODHSimDisplayRenderable <NSObject>
@property (nonatomic, readonly) CGSize displaySize;
@property (nonatomic, readonly) NSUInteger displayPitch;
- (void)registerCallbackWithUUID:(NSUUID *_Nonnull)uuid
        damageRectanglesCallback:(void (^_Nonnull)(id _Nullable))block;
- (void)unregisterDamageRectanglesCallbackWithUUID:(NSUUID *_Nonnull)uuid;
@end

@protocol ODHSimDisplayIOSurfaceRenderable <NSObject>
/// An `IOSurface`, declared as `id` so Swift does not try to bridge it. Nil until the device has
/// something to show.
@property (nonatomic, readonly, nullable) id framebufferSurface;
/// The same frame with the device's bezel applied, rounded corners and any cutout.
/// CoreSimulator keeps this as a second live surface, so a bezel costs nothing to draw.
@property (nonatomic, readonly, nullable) id maskedFramebufferSurface;
- (void)registerCallbackWithUUID:(NSUUID *_Nonnull)uuid
        ioSurfacesChangeCallback:(void (^_Nonnull)(id _Nullable))block;
- (void)unregisterIOSurfacesChangeCallbackWithUUID:(NSUUID *_Nonnull)uuid;
@end

@protocol ODHSimDeviceIOPortDescriptor <NSObject>
@property (nonatomic, readonly, nullable) id state;
@end

@protocol ODHSimDeviceIOPort <NSObject>
@property (nonatomic, readonly, nullable) id descriptor;
/// Stable for the life of the boot, which is what lets a chosen panel be remembered.
@property (nonatomic, readonly, nullable) NSUUID *uuid;
@end

@protocol ODHSimDeviceIO <NSObject>
/// Untyped for the same reason as `ODHSimDeviceSet.devices`, and because the elements are remote
/// proxies rather than a concrete class.
@property (nonatomic, readonly, nullable) NSArray *ioPorts;
@end

@protocol ODHSimDeviceLegacyHIDClient <NSObject>
/// `message` points at an `IndigoHIDMessageStruct`. With `freeWhenDone` the client takes ownership
/// of the buffer and frees it, so it has to come from `malloc` or `calloc`.
- (void)sendWithMessage:(void *_Nonnull)message
           freeWhenDone:(BOOL)freeWhenDone
        completionQueue:(dispatch_queue_t _Nullable)queue
             completion:(void (^_Nonnull)(NSError *_Nullable))completion;
@end

/// The pasteboard bridge between the Mac and a booted device, from `SimPasteboardPlus`, which lives
/// inside CoreSimulator's own bundle. The port comes from `-[SimDevice lookup:error:]` with the
/// service name `SimPasteboardInterfaceListener` reports. Verified on Xcode 27 (27A266a).
@protocol ODHSimPasteboardInterface <NSObject>
/// `managingPasteboard` is the `NSPasteboard` to keep in step. Typed `id` so this header does not
/// pull in AppKit.
- (instancetype _Nullable)initWithConnectingToPort:(unsigned int)port
                                managingPasteboard:(id _Nullable)pasteboard
                                          delegate:(id _Nullable)delegate
                                     delegateQueue:(id _Nullable)queue;
/// The Mac's clipboard to the device.
- (void)push;
/// The device's clipboard to the Mac.
- (void)pull;
- (void)enableRemoteAutosync;
- (void)disableRemoteAutosync;
@end

@protocol ODHSimServiceContext <NSObject>
- (nullable id<ODHSimDeviceSet>)defaultDeviceSetWithError:(NSError *_Nullable *_Nullable)error;
@end

/// Sent to the `SimServiceContext` class object itself. It is declared as an instance method
/// because the receiver is the class object, whose methods live on the metaclass, and because a
/// protocol class method would import into Swift as a static member that an existential cannot call.
@protocol ODHSimServiceContextClass <NSObject>
- (nullable id<ODHSimServiceContext>)sharedServiceContextForDeveloperDir:(NSString *_Nonnull)developerDir
                                                                   error:(NSError *_Nullable *_Nullable)error;
@end


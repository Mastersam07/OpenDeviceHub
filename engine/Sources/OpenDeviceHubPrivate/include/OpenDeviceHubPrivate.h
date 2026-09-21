#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Declarations for the CoreSimulator symbols the adapter sends messages to. These are protocols
/// only: no Apple class is declared, nothing is linked, and every selector here was confirmed on
/// Xcode 26.5 (17F42) before being written down.
///
/// The BOOL getters are spelled `available` rather than `isAvailable`, which is what the runtime
/// actually exports on 17F42.

@protocol ODHSimDeviceType <NSObject>
@property (nonatomic, readonly) NSString *identifier;
@property (nonatomic, readonly) NSString *name;
/// The point scale, 3.0 on an iPhone 17 Pro. `mainScreenSize` is in pixels, not points.
@property (nonatomic, readonly) float mainScreenScale;
@property (nonatomic, readonly) CGSize mainScreenSize;
@end

@protocol ODHSimRuntime <NSObject>
@property (nonatomic, readonly) NSString *identifier;
@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) NSString *versionString;
@property (nonatomic, readonly) BOOL available;
@end

@protocol ODHSimDevice <NSObject>
@property (nonatomic, readonly) NSUUID *UDID;
@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) NSUInteger state;
@property (nonatomic, readonly) NSString *stateString;
@property (nonatomic, readonly, nullable) id<ODHSimDeviceType> deviceType;
/// Nil when the device's runtime is not installed, which is common for devices left behind by an
/// uninstalled iOS version. `runtimeIdentifier` is still populated in that case, so it is the
/// reliable source for the identifier.
@property (nonatomic, readonly, nullable) id<ODHSimRuntime> runtime;
@property (nonatomic, readonly) NSString *runtimeIdentifier;
@property (nonatomic, readonly) BOOL available;
@property (nonatomic, readonly, nullable) id io;
@end

@protocol ODHSimDeviceSet <NSObject>
/// Deliberately untyped. Annotating the element type makes Swift bridge the array with a checked
/// cast, and the real `SimDevice` does not formally adopt these protocols, so the check traps.
/// Elements are cast individually instead.
@property (nonatomic, readonly) NSArray *devices;
@end

@protocol ODHSimDisplayDescriptorState <NSObject>
/// 0 is the device's own screen. A second port with class 1 exists and stays empty while unused.
@property (nonatomic, readonly) unsigned short displayClass;
@property (nonatomic, readonly) unsigned int defaultWidthForDisplay;
@property (nonatomic, readonly) unsigned int defaultHeightForDisplay;
@property (nonatomic, readonly) unsigned int defaultPixelFormat;
@property (nonatomic, readonly, nullable) NSURL *mask;
@end

@protocol ODHSimDisplayRenderable <NSObject>
@property (nonatomic, readonly) CGSize displaySize;
@property (nonatomic, readonly) NSUInteger displayPitch;
- (void)registerCallbackWithUUID:(NSUUID *)uuid damageRectanglesCallback:(void (^)(id))block;
- (void)unregisterDamageRectanglesCallbackWithUUID:(NSUUID *)uuid;
@end

@protocol ODHSimDisplayIOSurfaceRenderable <NSObject>
/// An `IOSurface`, declared as `id` so Swift does not try to bridge it. Nil until the device has
/// something to show.
@property (nonatomic, readonly, nullable) id framebufferSurface;
- (void)registerCallbackWithUUID:(NSUUID *)uuid ioSurfacesChangeCallback:(void (^)(id))block;
- (void)unregisterIOSurfacesChangeCallbackWithUUID:(NSUUID *)uuid;
@end

@protocol ODHSimDeviceIOPortDescriptor <NSObject>
@property (nonatomic, readonly, nullable) id state;
@end

@protocol ODHSimDeviceIOPort <NSObject>
@property (nonatomic, readonly, nullable) id descriptor;
@end

@protocol ODHSimDeviceIO <NSObject>
/// Untyped for the same reason as `ODHSimDeviceSet.devices`, and because the elements are remote
/// proxies rather than a concrete class.
@property (nonatomic, readonly) NSArray *ioPorts;
@end

@protocol ODHSimServiceContext <NSObject>
- (nullable id<ODHSimDeviceSet>)defaultDeviceSetWithError:(NSError **)error;
@end

/// Sent to the `SimServiceContext` class object itself. It is declared as an instance method
/// because the receiver is the class object, whose methods live on the metaclass, and because a
/// protocol class method would import into Swift as a static member that an existential cannot call.
@protocol ODHSimServiceContextClass <NSObject>
- (nullable id<ODHSimServiceContext>)sharedServiceContextForDeveloperDir:(NSString *)developerDir
                                                                   error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END

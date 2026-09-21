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
@end

@protocol ODHSimDeviceSet <NSObject>
/// Deliberately untyped. Annotating the element type makes Swift bridge the array with a checked
/// cast, and the real `SimDevice` does not formally adopt these protocols, so the check traps.
/// Elements are cast individually instead.
@property (nonatomic, readonly) NSArray *devices;
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

#import "MihonRuntimeBridge.h"
#import <TargetConditionals.h>

#if !TARGET_OS_SIMULATOR && __has_include("../MihonRuntime/.prepared/Headers/jni.h")
#define KUCHIE_HAS_OPENJDK 1
#include "../MihonRuntime/.prepared/Headers/jni.h"
#include <dlfcn.h>
#include <string>
#include <vector>
#endif

static NSError *RuntimeError(NSString *message) {
  return [NSError errorWithDomain:@"io.kuchie.extension-runtime"
                             code:1
                         userInfo:@{NSLocalizedDescriptionKey: message}];
}

#ifdef KUCHIE_HAS_OPENJDK
// Zero needs a larger stack than the XNU stack on a GCD worker.
@interface MihonRuntimeWorker : NSThread
- (void)submit:(dispatch_block_t)operation;
@end

@implementation MihonRuntimeWorker {
  NSCondition *_condition;
  NSMutableArray<dispatch_block_t> *_operations;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    self.stackSize = 8 * 1024 * 1024;
    self.name = @"Kuchie Extension Runtime";
    _condition = [NSCondition new];
    _operations = [NSMutableArray new];
  }
  return self;
}

- (void)submit:(dispatch_block_t)operation {
  [_condition lock];
  [_operations addObject:[operation copy]];
  [_condition signal];
  [_condition unlock];
}

- (void)main {
  for (;;) {
    @autoreleasepool {
      [_condition lock];
      while (_operations.count == 0) {
        [_condition wait];
      }
      dispatch_block_t operation = _operations.firstObject;
      [_operations removeObjectAtIndex:0];
      [_condition unlock];
      operation();
    }
  }
}
@end

namespace {
MihonRuntimeWorker *Worker() {
  static MihonRuntimeWorker *worker;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    worker = [MihonRuntimeWorker new];
    [worker start];
  });
  return worker;
}

struct EmbeddedRuntime {
  JNIEnv *environment = nullptr;
  jclass bridge = nullptr;
  jmethodID start = nullptr;
  jmethodID stop = nullptr;
  void *library = nullptr;
  NSString *dataDirectory;

  NSError *prepare() {
    if (bridge && start && stop) {
      return nil;
    }
    if (environment) {
      return RuntimeError(@"The extension runtime failed to initialize. Restart Kuchie to retry.");
    }

    NSBundle *bundle = NSBundle.mainBundle;
    NSURL *frameworkURL = [bundle.privateFrameworksURL
        URLByAppendingPathComponent:@"OpenJDKRuntime.framework" isDirectory:YES];
    NSURL *home = [frameworkURL URLByAppendingPathComponent:@"lib" isDirectory:YES];
    NSURL *resources = [bundle.resourceURL
        URLByAppendingPathComponent:@"KuchieMihonRuntime" isDirectory:YES];
    if (!frameworkURL || !resources) {
      return RuntimeError(@"The embedded extension runtime files are incomplete.");
    }
    NSString *modulePath = [home URLByAppendingPathComponent:@"lib/modules"].path;
    NSString *bridgePath = [resources URLByAppendingPathComponent:@"KuchieExtensionRuntime.jar"].path;
    NSString *serverPath = [resources URLByAppendingPathComponent:@"MExtensionServer.jar"].path;
    NSString *overlayPath = [resources URLByAppendingPathComponent:@"ExtCompat.jar"].path;
    NSString *loggingPath = [resources URLByAppendingPathComponent:@"JavaLogging.jar"].path;
    NSString *trustPath = [home URLByAppendingPathComponent:@"lib/security/cacerts"].path;
    NSFileManager *files = NSFileManager.defaultManager;
    for (NSString *path in @[modulePath, bridgePath, serverPath, overlayPath, loggingPath, trustPath]) {
      if (![files isReadableFileAtPath:path]) {
        return RuntimeError(@"The embedded extension runtime files are incomplete.");
      }
    }

    NSError *directoryError = nil;
    NSURL *support = [files URLForDirectory:NSApplicationSupportDirectory
                                    inDomain:NSUserDomainMask
                           appropriateForURL:nil
                                      create:YES
                                       error:&directoryError];
    NSURL *data = [support URLByAppendingPathComponent:@"MihonExtensions" isDirectory:YES];
    NSURL *temporary = [files.temporaryDirectory URLByAppendingPathComponent:@"MihonExtensions"
                                                                 isDirectory:YES];
    if (!data ||
        ![files createDirectoryAtURL:data withIntermediateDirectories:YES
                          attributes:nil error:&directoryError] ||
        ![files createDirectoryAtURL:temporary withIntermediateDirectories:YES
                          attributes:nil error:&directoryError]) {
      return directoryError ?: RuntimeError(@"Could not create extension runtime storage.");
    }
    dataDirectory = data.path;

    NSURL *binary = [frameworkURL URLByAppendingPathComponent:@"OpenJDKRuntime"];
    library = dlopen(binary.fileSystemRepresentation, RTLD_NOW | RTLD_GLOBAL);
    if (!library) {
      return RuntimeError(@"Could not load the signed extension runtime framework.");
    }
    auto initialize = reinterpret_cast<void (*)()>(dlsym(library, "KuchieOpenJDKInitialize"));
    auto create = reinterpret_cast<jint (*)(JavaVM **, void **, void *)>(
        dlsym(library, "JNI_CreateJavaVM"));
    if (!initialize || !create) {
      dlclose(library);
      library = nullptr;
      return RuntimeError(@"The extension runtime is missing its JVM entry points.");
    }
    const char *requiredSymbols[] = {
      "JDK_Canonicalize", "JIMAGE_Open", "JIMAGE_Close",
      "JIMAGE_FindResource", "JIMAGE_GetResource", "VerifyClassForMajorVersion"
    };
    for (const char *name : requiredSymbols) {
      if (!dlsym(RTLD_DEFAULT, name)) {
        dlclose(library);
        library = nullptr;
        return RuntimeError(@"The extension runtime is missing JVM support symbols.");
      }
    }

    NSArray<NSString *> *arguments = @[
      [NSString stringWithFormat:@"-Djava.class.path=%@:%@:%@", bridgePath, overlayPath, serverPath],
      [@"-Xbootclasspath/a:" stringByAppendingString:loggingPath],
      [@"-Djava.home=" stringByAppendingString:home.path],
      [@"-Djava.io.tmpdir=" stringByAppendingString:temporary.path],
      [@"-Duser.home=" stringByAppendingString:dataDirectory],
      [@"-Dsuwayomi.tachidesk.config.server.rootDir=" stringByAppendingString:dataDirectory],
      [@"-Djavax.net.ssl.trustStore=" stringByAppendingString:trustPath],
      @"-Djavax.net.ssl.trustStorePassword=changeit",
      @"-Djava.awt.headless=true",
      @"-Dfile.encoding=UTF-8",
      @"-Djava.net.preferIPv4Stack=true",
      @"-Dorg.slf4j.simpleLogger.defaultLogLevel=warn",
      @"-Xverify:all",
      @"-XX:+UseSerialGC",
      @"-Xms128m",
      @"-Xmx512m",
      @"-XX:NewSize=64m",
      @"-XX:MaxNewSize=256m",
      @"-Xss8m",
    ];
    std::vector<std::string> strings;
    for (NSString *argument in arguments) {
      strings.emplace_back(argument.UTF8String);
    }
    std::vector<JavaVMOption> options;
    for (auto &argument : strings) {
      options.push_back({const_cast<char *>(argument.c_str()), nullptr});
    }
    JavaVMInitArgs configuration = {
      JNI_VERSION_1_8, static_cast<jint>(options.size()), options.data(), JNI_FALSE
    };
    JavaVM *vm = nullptr;
    initialize();
    jint status = create(&vm, reinterpret_cast<void **>(&environment), &configuration);
    if (status != JNI_OK || !environment) {
      return RuntimeError([NSString stringWithFormat:@"Could not initialize the JVM (%d).", status]);
    }

    jclass localClass = environment->FindClass("io/kuchie/runtime/ExtensionRuntime");
    if (!localClass) {
      return exception(@"Could not load the extension runtime entry class.");
    }
    bridge = static_cast<jclass>(environment->NewGlobalRef(localClass));
    environment->DeleteLocalRef(localClass);
    if (!bridge) {
      return exception(@"Could not retain the extension runtime entry class.");
    }
    start = environment->GetStaticMethodID(
        bridge, "start", "(ILjava/lang/String;Ljava/lang/String;)I");
    if (!start) {
      return exception(@"The extension runtime start entry point is unavailable.");
    }
    stop = environment->GetStaticMethodID(bridge, "shutdown", "()V");
    return stop ? nil : exception(@"The extension runtime stop entry point is unavailable.");
  }

  NSError *exception(NSString *message) const {
    if (environment->ExceptionCheck()) {
      environment->ExceptionDescribe();
      environment->ExceptionClear();
    }
    return RuntimeError(message);
  }

  NSInteger launch(NSInteger port, NSString *token, NSError **error) {
    *error = prepare();
    if (*error) {
      return 0;
    }
    if (environment->PushLocalFrame(3) != JNI_OK) {
      *error = exception(@"Could not allocate extension runtime startup arguments.");
      return 0;
    }
    jstring directory = environment->NewStringUTF(dataDirectory.fileSystemRepresentation);
    jstring authToken = directory ? environment->NewStringUTF(token.UTF8String) : nullptr;
    jint actualPort = authToken
        ? environment->CallStaticIntMethod(bridge, start, static_cast<jint>(port), directory, authToken)
        : 0;
    if (environment->ExceptionCheck() || actualPort <= 0 || actualPort > 65535) {
      *error = exception(@"Could not start the extension runtime on this device.");
      actualPort = 0;
    }
    environment->PopLocalFrame(nullptr);
    return actualPort;
  }

  NSError *shutdown() {
    if (!environment || !stop) {
      return nil;
    }
    environment->CallStaticVoidMethod(bridge, stop);
    return environment->ExceptionCheck() ? exception(@"Could not stop the extension runtime.") : nil;
  }
};

// All JNI calls run on a single permanently attached native thread.
EmbeddedRuntime runtime;
}
#endif

@implementation MihonRuntimeBridge

+ (void)startOnPort:(NSInteger)port
              token:(NSString *)token
         completion:(void (^)(NSInteger, NSError * _Nullable))completion {
#ifdef KUCHIE_HAS_OPENJDK
  [Worker() submit:^{
    NSError *error = nil;
    NSInteger activePort = runtime.launch(port, token, &error);
    dispatch_async(dispatch_get_main_queue(), ^{ completion(activePort, error); });
  }];
#else
  completion(0, RuntimeError(@"The embedded extension runtime is unavailable on this build."));
#endif
}

+ (void)stopWithCompletion:(void (^)(NSError * _Nullable))completion {
#ifdef KUCHIE_HAS_OPENJDK
  [Worker() submit:^{
    NSError *error = runtime.shutdown();
    dispatch_async(dispatch_get_main_queue(), ^{ completion(error); });
  }];
#else
  completion(nil);
#endif
}

@end

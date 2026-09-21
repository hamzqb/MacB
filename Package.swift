// swift-tools-version: 6.0
import PackageDescription

/// llama.cpp, vendored by scripts/vendor-llama.sh: the local model MacB can
/// talk with when there is no internet, or no wish to use it. Metal on the
/// GPU, the CPU backend as ggml's fallback. Optimised even in debug builds —
/// an unoptimised model is too slow to be worth testing.
let llamaSettings: [CSetting] = [
    .headerSearchPath("include-cpp"),
    .headerSearchPath("src"),
    .headerSearchPath("ggml/src"),
    .headerSearchPath("ggml/src/ggml-cpu"),
    .headerSearchPath("ggml/src/ggml-metal"),
    .define("GGML_USE_CPU"),
    .define("GGML_USE_METAL"),
    .define("GGML_METAL_NDEBUG"),
    .define("NDEBUG"),
    .define("_DARWIN_C_SOURCE"),
    // ggml looks for its kernels next to the app; MacB points it at them
    // with GGML_METAL_PATH_RESOURCES before the first model loads.
    .define("SWIFTPM_MODULE_BUNDLE", to: "[NSBundle mainBundle]"),
    .unsafeFlags(["-O3", "-fno-objc-arc", "-w"])
]
let llamaCXXSettings: [CXXSetting] = [
    .headerSearchPath("include-cpp"),
    .headerSearchPath("src"),
    .headerSearchPath("ggml/src"),
    .headerSearchPath("ggml/src/ggml-cpu"),
    .headerSearchPath("ggml/src/ggml-metal"),
    .define("GGML_USE_CPU"),
    .define("GGML_USE_METAL"),
    .define("GGML_METAL_NDEBUG"),
    .define("NDEBUG"),
    .define("_DARWIN_C_SOURCE"),
    .unsafeFlags(["-O3", "-w"])
]

let package = Package(
    name: "MacB",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MacB", targets: ["MacB"])],
    targets: [
        .target(name: "MacBCore"),
        .target(
            name: "CLlama",
            path: "Vendor/llama",
            exclude: ["LICENSE", "VERSION"],
            publicHeadersPath: "include",
            cSettings: llamaSettings,
            cxxSettings: llamaCXXSettings,
            linkerSettings: [.linkedFramework("Metal"), .linkedFramework("Foundation")]
        ),
        .executableTarget(name: "MacB", dependencies: ["MacBCore", "CLlama"]),
        .testTarget(name: "MacBCoreTests", dependencies: ["MacBCore"])
    ],
    swiftLanguageModes: [.v5],
    cLanguageStandard: .c11,
    cxxLanguageStandard: .cxx17
)

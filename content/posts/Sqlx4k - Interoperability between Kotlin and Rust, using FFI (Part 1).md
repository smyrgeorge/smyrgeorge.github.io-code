---
author: Yorgos S.
authorLink: "https://github.com/smyrgeorge"
categories:
- dev
cover:
  image: /images/bfc5f1d0b3838151728b268ebedb1f89b234eea8.png
date: "2024-08-01T17:19:17+02:00"
subtitle: A short series on Kotlin and Rust FFI.
tags:
- dev
- kotlin
- ffi
- rust
title: Sqlx4k - Interoperability between Kotlin and Rust, using FFI (Part 1)
---

## Introduction

Previously, in the [Sqlx4k - Introduction to Kotlin Native and FFI (Part 2)](https://smyrgeorge.github.io/posts/sqlx4k---introduction-to-the-kotlin-native-and-ffi-part-2/), the second part of this series, we attempted to provide an introduction to how `C Interoperability` functions in Kotlin, offering various examples from the [GitHub - smyrgeorge/sqlx4k](https://github.com/smyrgeorge/sqlx4k) codebase.

`Sqlx4k` is a small, non-blocking PostgreSQL database driver written in Kotlin for the Native platform. It wraps the `sqlx` driver from the Rust ecosystem under the hood. The communication between the two languages is facilitated using FFI.

In this article, we are going to see in detail how it works and how we can benefit from the integration between the two.

![sqlx4k](/images/bfc5f1d0b3838151728b268ebedb1f89b234eea8.png)

## Project Setup

First of all, let's take a look at the file tree:
- The Kotlin code is located under the `src` directory.
- The Rust code is located in the `rust_lib` directory.

``` text
sqlx4k
├── build.gradle.kts
├── rust_lib
│   ├── Cargo.lock
│   ├── Cargo.toml
│   ├── build.rs
│   └── src
│       └── lib.rs
└── src
    ├── nativeInterop
    │   └── cinterop
    │       ├── aarch64-apple-darwin.def
    │       ├── aarch64-unknown-linux-gnu.def
    │       ├── x86_64-apple-darwin.def
    │       └── x86_64-unknown-linux-gnu.def
    └── nativeMain
        └── kotlin
            └── io
                └── github
                    └── smyrgeorge
                        └── sqlx4k
                            ├── Driver.kt
                            ├── Sqlx4k.kt
                            ├── Transaction.kt
                            └── impl
                                ├── Postgres.kt
                                └── extensions.kt
```

For more details, you can always take a look at the project's repository.

### Rust Setup

Now, let's examine the Rust configuration. First, take a look at the `Cargo.toml` file:

``` toml
# We going to show only the important parts here.
# You can see the full file in the project's repoisory.
[lib]
crate-type = ["staticlib"]

[build-dependencies]
# https://crates.io/crates/cbindgen
cbindgen = "0.26.0"
```

So, we can make the following observations:
- `crate-type` must be `staticlib`. According to the documentation: *A static system library will be produced. This is different from other library outputs in that the compiler will never attempt to link to staticlib outputs. The purpose of this output type is to create a static library containing all of the local crate's code along with all upstream dependencies. This output type will create .a files on Linux, macOS and Windows (MinGW), and *.lib files on Windows (MSVC). This format is recommended for use in situations such as linking Rust code into an existing non-Rust application because it will not have dynamic dependencies on other Rust code.*
- We need the build-dependency `cbindgen`. *Creates C/C++11 headers for Rust libraries which expose a public C API.\*

### Kotlin Setup

Now, let's take a look at the `build.gradle.kts` file that configures the Kotlin part. We will focus on the most interesting sections.

``` kotlin
import org.gradle.nativeplatform.platform.internal.DefaultNativePlatform
import org.jetbrains.kotlin.gradle.plugin.mpp.KotlinNativeTarget
import java.lang.System.getenv

plugins {
    kotlin("multiplatform")
}

// Find the current OS and Architecture.
private val os = DefaultNativePlatform.getCurrentOperatingSystem()
private val arch = DefaultNativePlatform.getCurrentArchitecture()

// Appends `.exe` if the build is running in wingows.
private val exeExt: String
    get() = when {
        os.isWindows -> ".exe"
        else -> ""
    }

// Locate the cargo executable.
private val cargo: String
    get() = when {
        os.isWindows -> getenv("USERPROFILE")
        else -> getenv("HOME")
    }?.let(::File)
        ?.resolve(".cargo/bin/cargo$exeExt")
        ?.takeIf { it.exists() }
        ?.absolutePath
        ?: throw GradleException(
            "Rust cargo binary is required to build project.")

// Build targets
val chosenTargets = (properties["targets"] as? String)?.split(",")
    ?: listOf("macosArm64", "macosX64", "linuxArm64", "linuxX64")

kotlin {
    fun KotlinNativeTarget.rust(target: String) {
        compilations.getByName("main").cinterops {
            create("librust_lib") {
                // Create a gradle task for each of one of the build targets.
                val cargo = tasks.create("cargo-$target") {
                    exec {
                        executable = cargo
                        args(
                            "build",
                            "--manifest-path",
                            projectDir
                                .resolve("rust_lib/Cargo.toml")
                                .absolutePath, // Path to the `Cargo.toml` file.
                            "--package", "rust_lib",
                            "--lib",
                            "--target=$target", // Define the Rust build target.
                            "--release"
                        )
                    }
                }

                // Build Rust code before call interop task.
                tasks.getByName(interopProcessingTaskName) {
                    dependsOn(cargo)
                }

                // Set the .def file for each platform.
                // The .def file describes what will be included into bindings.
                definitionFile.set(
                    projectDir
                    .resolve("src/nativeInterop/cinterop/$target.def")
                )
            }
        }
    }

    // Setup the build targets.
    // For each platform we need to define the rust target build.
    val availableTargets = mapOf(
        Pair("macosArm64") { macosArm64 { rust("aarch64-apple-darwin") } },
        Pair("macosX64") { macosX64 { rust("x86_64-apple-darwin") } },
        Pair("linuxArm64") { linuxArm64 { rust("aarch64-unknown-linux-gnu") } },
        Pair("linuxX64") { linuxX64 { rust("x86_64-unknown-linux-gnu") } },
    )

    // Invoke build for each one of the selected targets.
    chosenTargets.forEach {
        println("Enabling target $it")
        availableTargets[it]?.invoke()
    }

    // Other configs, non-related to this article (depedencies etc.).
    applyDefaultHierarchyTemplate()
    sourceSets {
        configureEach {
            languageSettings.progressiveMode = true
        }
        val nativeMain by getting {
            dependencies {
                // https://github.com/Kotlin/kotlinx.coroutines
                implementation(
                    "org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.1")
            }
        }
    }
}
```

#### .def files

According to the Kotlin documentation, we need to create some `.def` files that define the bindings. In our case, for the `aarch64-apple-darwin` target, we have the following file:

``` text
package = librust_lib
headers = rust_lib.h
compilerOpts = -I./rust_lib/target

staticLibraries = librust_lib.a
libraryPaths = ./rust_lib/target/aarch64-apple-darwin/release
```

## Build

If we build the project we should see something like:

``` text
> Configure project :sqlx4k
Enabling target macosArm64
    ...
    ...
    Finished `release` profile [optimized] target(s) in 7.17s
Enabling target macosX64
    ...
    ...
    Finished `release` profile [optimized] target(s) in 7.14s
Enabling target linuxArm64
    ...
    ...
    Finished `release` profile [optimized] target(s) in 7.17s
Enabling target linuxX64
    ...
    ...
    Finished `release` profile [optimized] target(s) in 7.14s
...
BUILD SUCCESSFUL in 24s
35 actionable tasks: 3 executed, 32 up-to-date
```

As we can see, `gradle` first triggers the build of the Rust code for each of the selected targets (in our case, `macosArm64`, `macosX64`, `linuxArm64`, `linuxX64`) and then builds the Kotlin code (located under the `src` folder).

### Generated Rust Files

The Rust build generates a couple of files that are then used by the Kotlin compiler.

`rust_lib/target/rust_lib.h`:
The generated (by `cbindgen`, that we saw earlier) C bindings (header files)

``` c
// Only a small part of the original file is shown here.

#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

#define OK -1

#define ERROR_DATABASE 0

typedef struct Sqlx4kColumn {
  int ordinal;
  char *name;
  int kind;
  int size;
  void *value;
} Sqlx4kColumn;

void sqlx4k_query(const char *sql, void *callback, void (*fun)(struct Ptr, struct Sqlx4kResult*));

void sqlx4k_fetch_all(const char *sql,
                      void *callback,
                      void (*fun)(struct Ptr, struct Sqlx4kResult*));

void sqlx4k_free_result(struct Sqlx4kResult *ptr);
```

`rust_lib/target/aarch64-apple-darwin/release/librust_lib.a`:
The native binary that will be linked to our code. Of course, we should find the corresponding `.a` files for each platform for which we enabled the build.

## Let's see a code example in action

Assuming that you have the following Rust function:

``` rust
#[no_mangle]
pub extern "C" fn sqlx4k_pool_size() -> c_int {
    unsafe { SQLX4K.get().unwrap() }.pool.size() as c_int
}
```

Then, you can call the above Rust function from the Kotlin as follows:

``` kotlin
import librust_lib.sqlx4k_pool_size
fun poolSize(): Int = sqlx4k_pool_size()
```

In this article we don't going to explain how FFI works at the Rust part. You can easily review the available documentation. Also feel free to look at the references section below. You can find several other examples in the project's codebase.

## Conclusion

As we can see, it is actually very easy to "integrate" Kotlin with Rust.

At this moment, with the Kotlin ecosystem still in a very young stage, we can benefit by bringing well-tested libraries and functionality to the ecosystem.

In the next part of this series, we will see in detail how we can utilise the `async` features that both languages offer in order to create non-blocking IO code. Until then, you can review the previous articles here: [:: exploration and stuff ::](https://smyrgeorge.github.io/) and also check out my GitHub repository: [smyrgeorge (Yorgos S.) · GitHub](https://github.com/smyrgeorge).

------------------------------------------------------------------------

## References

- [cbindgen - crates.io: Rust Package Registry](https://crates.io/crates/cbindgen)
- [Interoperability with C \| Kotlin Documentation](https://kotlinlang.org/docs/native-c-interop.html)
- [Linkage - The Rust Reference](https://doc.rust-lang.org/reference/linkage.html)
- [FFI - The Rustonomicon](https://doc.rust-lang.org/nomicon/ffi.html)

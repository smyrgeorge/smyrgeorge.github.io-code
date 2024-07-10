---
author: Yorgos S.
authorLink: "https://github.com/smyrgeorge"
categories:
- dev
cover:
  image: /images/7a68c51ab98060e8e5b4cbdbae694e450abfb270.png
date: "2024-07-08T13:26:07+02:00"
subtitle: A small series of articles about the Kotlin FFI.
tags:
- dev
- kotlin
- ffi
- rust
- database-driver
- postgres
- mysql
- sqlite
title: Sqlx4k - Introduction to the Kotlin native and FFI (Part 1)
---

## Introduction

Recently, I began experimenting with the **Kotlin Native platform**. I initiated a new repository and attempted to create a simple project utilizing the **ktor** libraries. The purpose of the project was to recreate a small service that integrates some basic libraries and compile it to a native target (macosArm64 in my case). The service aimed to offer support for:

- Dependency injection
- HTTP server
- Database access (PostgreSQL)
- Additionally, RabbitMQ support (though it isn't a priority for now)

In this first article of the series, I aim to describe how I ended up writing "low-level" code (FFI between Kotlin and Rust) and also to highlight the importance of native compatibility in Kotlin Native. In the subsequent parts, I'll attempt to provide more detailed examples of how I managed to implement a simple SQL driver for PostgreSQL, using the sqlx (Rust) library.

## Ktor

I discovered that starting a new project with Ktor is very easy.

Ktor, developed by JetBrains, is a Kotlin-based framework optimized for asynchronous I/O operations, enabling efficient web and microservices development. Leveraging Kotlin's coroutines, Ktor facilitates non-blocking I/O, which significantly enhances application scalability and performance. Its architecture supports seamless integration of async features, making it ideal for building responsive, high-performance applications with streamlined concurrency management.

I began with the [Ktor: Project Generator](https://start.ktor.io/settings) and created a sample project.

Then, I only had to make a few changes to the **build.gradle.kts** file:

``` kotlin
plugins {
    kotlin("multiplatform") version "2.0.0"
}

repositories {
    mavenCentral()
}

group = "io.github.smyrgeorge"
version = "0.1.0"

val ktorVersion = "3.0.0-beta-1"
val koinVersion = "3.5.6"
kotlin {
    // Enable the according to your platform (you can enable them all):
    macosArm64 { binaries { executable() } }
    // linuxX64 { binaries { executable() } }
    // linuxX64 { binaries { executable() } }

    applyDefaultHierarchyTemplate()
    sourceSets {
        val nativeMain by getting {
            dependencies {
                // Ktor with CIO
                implementation("io.ktor:ktor-server-cio:$ktorVersion")
                // Koin (DI)
                implementation("io.insert-koin:koin-core:$koinVersion")
                // Database driver
                implementation("io.github.smyrgeorge:sqlx4k:0.4.0")
            }
        }
    }
}
```

And then I changed the **main** function to be like the default example:

``` kotlin
fun main() {
    embeddedServer(CIO, port = 8080) {
        routing {
            get ("/") {
                call.respondText("Hello, world!")
            }
        }
    }.start(wait = true)
}
```

Then I build the project with:

``` sh
./gradlew build
```

And finally, I started my sample service (ktor-native-sample):

``` shell
./build/bin/macosArm64/releaseExecutable/ktor-native-sample.kexe
```

And I then I saw the following logs:

``` text
[INFO] (io.ktor.server.Application): Application started in 0.0 seconds.
[INFO] (io.ktor.server.Application): Responding at http://0.0.0.0:8080
```

As we can observe, the startup time was less than a second (a few milliseconds, I guess), which I find to be the interesting part. Additionally, I must mention that the memory usage was around **\~5MB**.

## A little bit of the background.

So, the reality is that over the last couple of years, I have developed numerous projects using the Spring Boot stack (using Kotlin instead of Java). I believe we're all aware of the notably slow startup times associated with JVM-based applications, not to mention the memory consumption (approximately \~50MB at startup).

Naturally, those coming from other tech stacks (e.g., Rust, or something similar) might find this amusing. To a large extent, I almost agree with them. However, transitioning from one technology stack to another can sometimes be challenging.

For instance, I have been working for the same company for nearly 9 years now, and during this time, my team and I have implemented several projects and products using several technologies. In the back-end side, almost from the start, we chose the Spring Boot (Kotlin) stack. And I believe it has served us very well and also the code base has aged really well. Just to provide an example, we have a very large (and complex) insurance project, and we managed to migrate almost the entire project to Kotlin-async (coroutines) in just 5-6 months.

During the migration period, we had to modify the parts of the code that accessed the database, the queues, and, of course, the entry points (e.g., the HTTP layer). Apart from that, in almost the rest of the codebase (service layer), we only needed to add the **suspend** keyword to indicate that a function is asynchronous (similar to async in Rust or JavaScript). It was a relatively easy process, considering the volume of code we had written up to that point and the complexity of the business model. Therefore, I consider this a significant success story.

## Kotlin Native ecosystem

So, I began to explore libraries that support multiplatform capabilities, specifically those that target to the native platform (e.g., to be compiled for linuxArm64). Very quickly, I realised that the ecosystem is still in a very early stage. Consequently, I contemplated developing some libraries myself. The most critical component for the type of applications my team has been building over the last few years is database access, specifically to PostgreSQL databases. However, as of now, there is no native driver available (or at least I couldn't find one), prompting me to consider creating one. I soon realised that this task was not going to be easy. Additionally, during my research, I discovered some small projects that wrap the **libpq** (the official **C** database client) library using FFI.

I also forgot to mention that in several side projects over the past few years, I have used the Rust programming language. Thus, I thought that perhaps I could try wrapping one of the Rust database drivers. I opted for **sqlx** because I had used it in the past and I believe it offers decent performance.

## Sqlx4k

So, I ended up creating **sqlx4k** (perhaps not the best name, but I wanted to convey that it's a wrapper around the **sqlx** library). Sqlx4k is a minimal (and I believe it should remain minimal in the future) non-blocking database driver. Currently, it only supports PostgreSQL, but I plan to extend support to MySQL and eventually SQLite databases. By "minimal," I mean it's essentially a convenient wrapper around the Rust library, providing an idiomatic Kotlin API for database access.

![sqlx4k](/images/7a68c51ab98060e8e5b4cbdbae694e450abfb270.png)

As part of this article, I wanted to offer an introduction. In subsequent parts of this series, I will briefly describe how I managed to bridge the two different "worlds."

If you found this introduction interesting and wish to experiment, you can add the dependency to your project and start exploring:

``` kotlin
implementation("io.github.smyrgeorge:sqlx4k:x.y.z")
```

You can find the latest published version here: [Maven Central: io.github.smyrgeorge:sqlx4k](https://central.sonatype.com/artifact/io.github.smyrgeorge/sqlx4k)

Here is a small example:

``` kotlin
val pg = Postgres(
    host = "localhost",
    port = 15432,
    username = "postgres",
    password = "postgres",
    database = "test",
    maxConnections = 10 // set the max-pool-size here
)

// Named parameters:
pg.query("drop table if exists :table;", mapOf("table" to "sqlx4k")).getOrThrow()

pg.fetchAll("select * from :table;", mapOf("table" to "sqlx4k")) {
    val id: Sqlx4k.Row.Column = get("id")
    Test(id = id.value.toInt())
}

// Transactions:
val tx1: Transaction = pg.begin().getOrThrow()
tx1.query("delete from sqlx4k;").getOrThrow()
tx1.fetchAll("select * from sqlx4k;") {
    println(debug())
}
pg.fetchAll("select * from sqlx4k;") {
    println(debug())
}
tx1.commit().getOrThrow()
```

Also, take a look at the project's repository on GitHub:
[GitHub - smyrgeorge/sqlx4k: A small non-blocking database driver written in Kotlin for the Native platform.](https://github.com/smyrgeorge/sqlx4k)

All contributions are welcome. Thank you for now.

------------------------------------------------------------------------

## References

- [Kotlin Programming Language](https://kotlinlang.org/)
- [Ktor: Build Asynchronous Servers and Clients in Kotlin \| Ktor Framework](https://ktor.io/)
- [GitHub - launchbadge/sqlx: 🧰 The Rust SQL Toolkit. An async, pure Rust SQL crate featuring compile-time checked queries without a DSL. Supports PostgreSQL, MySQL, and SQLite.](https://github.com/launchbadge/sqlx)

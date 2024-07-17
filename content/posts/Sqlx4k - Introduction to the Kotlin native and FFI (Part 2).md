---
author: Yorgos S.
authorLink: "https://github.com/smyrgeorge"
categories:
- dev
cover:
  image: /images/16b3c7cfabbce3d7e297a63c597f29abb7049f3c.png
date: "2024-07-16T20:11:34+02:00"
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
title: Sqlx4k - Introduction to the Kotlin native and FFI (Part 2)
---

## Introduction

In the previous [part](https://smyrgeorge.github.io/posts/sqlx4k---introduction-to-the-kotlin-native-and-ffi-part-1/) of this series, I attempted to explain the importance of the Kotlin FFI (Foreign Function Interface) compatibility layer. As I mentioned, I believe it is a very effective way (at least for now) to leverage other ecosystems (such as the Rust ecosystem) to bring functionality to the Kotlin/Native ecosystem, in which I see a great deal of potential.

## FFI

Foreign Function Interface (FFI) is a programming feature that enables code written in one language to call and interact with code written in another language. It acts as a bridge, allowing developers to leverage the strengths of different programming languages within a single project. FFI is essential for integrating diverse software libraries and for accessing hardware or operating system features not directly available in the host language. Implementing FFI involves defining bindings that specify how functions from one language can be called from another, including the necessary data type conversions.

## Kotlin FFI

As of the time these lines are being written, Kotlin/Native Interop (FFI) is still considered experimental. However, based on the experience I have had so far, it has seemed to me to be really stable. Take a look at the official documentation here: [Interoperability with C \| Kotlin Documentation](https://kotlinlang.org/docs/native-c-interop.html)

### Call a C function

Let's begin with a simple example. Assume we have a small C library:

``` c
// This could be part of header file (e.g. lib.h)
// The actual implementation of the C functions is not shown here.

// Just a simple function that accepts a C string.
void hello_1(char *msg);
void hello_2(const char *msg);
```

Here is the Kotlin part:

``` kotlin
// Import the C functions
import mylib.hello_1
import mylib.hello_2

fun hello() {
    hello_1("Hello from Kotlin".cstr)
    hello_2("Hello from Kotlin".cstr)
}
```

### More examples

Here again, we have the C code:

``` c
int fun_that_returns_int(void);

// A LinkedList Node
typedef struct Node {
  char *a_string_value;
  int an_int_value;
  struct Node *next;
} Node;

struct Node *get_a_node();
```

And the Kotlin:

``` kotlin
val r1: Int = fun_that_returns_int()

// Here we can access the properties of a struct.
val r2: CPointer<Node>? = get_a_node()
val node: Node? = r2?.pointed

if (node == null) {
    println("null pointer returned")
}

node?.let {
    println(it.a_string_value?.toKString() ?: "null value returned")
    println(it.an_int_value)
    
    // Same as above (handle the pointer).
    it.next?.let { it1 ->
        // Handle the next node of the List.
    }
}
```

### Pass a callback function to the C code

The ability to "pass" functions to the C code is really helpful, especially if we want to create asynchronous flows. The basic idea is that we are going to call the foreign function from our code (in our case, the Kotlin code we will continue without blocking), and as soon as the result is ready, the foreign code will make the callback back to our code and provide the result data. In the case of `sqlx4k`, this was very important in order to create a `non-blocking` database driver.

The following examples are parts of `sqlx4k`, which wraps a database driver that is actually written in `Rust`. Although in this tutorial we are not going to see any Rust code, we will see a lot of C code. In reality, almost all the time we need to think about how the equivalent code would be in C. The reason is that almost all programming languages that provide `FFI` (Foreign Function Interface) offer bindings for C and C++.

Kotlin also provides interoperability with Swift and Objective-C (for more details, check the official documentation).

So, here is the C code.

``` c
// Query result
typedef struct Sqlx4kResult {
  int error; // error code
  char *error_message;
  void *tx; // transaction pointer
  int size; // result set size
  struct Sqlx4kRow *rows; // pointer to rows
} Sqlx4kResult;

// Raw pointer wrapper
typedef struct Ptr {
  void *ptr;
} Ptr;

void sqlx4k_query(const char *sql,
                  // Ignore for now.
                  void *continuation,
                  // Function pointer.
                  void (*callback)(struct Ptr, struct Sqlx4kResult*));
```

In the following example, we make a call to the `C` function `sqlx4k_query` and we pass the following arguments:
- `sql:` the query that we need to execute in the database
- `continuation:` ignore for now (used for the `async-io`)
- `callback:` the function that the C code will call as soon as the result is ready.

For now, let's try to ignore the `continuation` and the `async-io` part of the code, let's focus on the callback part.

``` kotlin
// It's just an example, we do not return the actual fetched data.
suspend fun query(sql: String) {
    suspendCoroutine { c: Continuation<CPointer<Sqlx4kResult>?> ->
        // Create a [StableRef] of the [Continuation] instance.
        // StableRef<Continuation<CPointer<Sqlx4kResult>?>>
        val ref = StableRef.create(c)
        val continuation: CPointer<out CPointed> = ref.asCPointer()
        // Call the actual C function.
        sqlx4k_query(sql, continuation, callback)
    }
}

// [callback] is the Kotlin function that we need to pass to the C code.
val callback = staticCFunction<APtr, ACPointer, Unit> { c, r ->
    val ref = c.useContents { ptr }!!
        .asStableRef<Continuation<CPointer<Sqlx4kResult>?>>()
    ref.get().resume(r)
    ref.dispose()
}

typealias APtr = CValue<Ptr>
typealias ACPointer = CPointer<Sqlx4kResult>?
```

First of all, let's take a look at the [`staticCFunction`](https://kotlinlang.org/docs/native-c-interop.html#callbacks).
In the Kotlin code, it is defined (as part of the `kotlinx.cinterop` package) like:

``` kotlin
public external fun <P1, P2, R> staticCFunction(
    function: (P1, P2) -> R
): CPointer<CFunction<(P1, P2) -> R>>
```

In our example, we use the [`staticCFunction`](https://kotlinlang.org/docs/native-c-interop.html#callbacks) to declare a function that takes two arguments, of type `APtr` and `CPointer`, and returns `Unit`. The C code can call this function as if it was a pure C function.

## How to "not-block"

In the previous example, we saw that we can pass a callback to the foreign code. In this section, we are going to explain how the "suspend" part works.

Kotlin offers the [`suspendCoroutine`](https://kotlinlang.org/api/core/kotlin-stdlib/kotlin.coroutines/suspend-coroutine.html) function.

*According to the documentation:
Obtains the current continuation instance inside suspend functions and suspends the currently running coroutine. `Continuation`: Interface representing a continuation after a suspension point that returns a value of type T.*

In other words, it is a way to `suspend` the execution flow, and the [`Continuation`]() instance can provide us the way to continue the flow (in our case, after the data from the database are fetched).

So, as we saw:

``` kotlin
// The code will suspend here.
suspendCoroutine { c: Continuation<CPointer<Sqlx4kResult>?> ->
    // Create a [StableRef] of the [Continuation] instance.
    // StableRef<Continuation<CPointer<Sqlx4kResult>?>>
    val ref = StableRef.create(c)
    val continuation: CPointer<out CPointed> = ref.asCPointer()
    // Call the actual C function.
    sqlx4k_query(sql, continuation, callback)
}
```

We need to pass the [`Continuation`](https://kotlinlang.org/api/core/kotlin-stdlib/kotlin.coroutines/-continuation/) to the foreign code and then the foreign code will provide back to us (as a C raw pointer).

The way that `Kotlin` provides in order to pass references from "one world to another" is with [`StableRef`](https://kotlinlang.org/api/core/kotlin-stdlib/kotlinx.cinterop/-stable-ref/):

``` kotlin
// Function pointer that will be passed to the foreign code.
val callback = staticCFunction<APtr, ACPointer, Unit> { c, r ->
    // Cast raw pointer back to [StableRef]
    val ref = c.useContents { ptr }!!
        .asStableRef<Continuation<CPointer<Sqlx4kResult>?>>()
    // Call the resume, continue the suspended flow above.
    ref.get().resume(r)
    // Dispose (will free) the ref,
    // thus clear the reference to the continuation
    ref.dispose()
}
```

I believe the process is now a bit more understandable. We perform the reverse process:
- Access the returned struct from the foreign code using `useContents`.
- Cast the raw pointer back to a `StableRef`.
- `Resume` the suspended flow.
- `Dispose` of the `StableRef`.

## Memory management

Although until now everything seems very straightforward, there are some caveats. At every moment of this process, we need to keep in mind the memory management and how each one of the "worlds" allocates and deallocates memory. This is very crucial in order to avoid memory leaks.

While I was developing the `sqlx4k` library, I created the following rule:

> **Each one of the "worlds" (language) needs to manage its own memory.**

<figure>
<img
src="../Sqlx4k%20-%20Introduction%20to%20the%20Kotlin%20native%20and%20FFI%20(Part%202)/16b3c7cfabbce3d7e297a63c597f29abb7049f3c.png"
title="wikilink" alt="sqlx4k-free-memory.excalidraw.png" />
<figcaption
aria-hidden="true">sqlx4k-free-memory.excalidraw.png</figcaption>
</figure>

This simply means that each language should deallocate the memory it allocated. In other words, we need to provide some more functions that will do this job for us. For instance, in my case, I created the following function that frees the allocated memory:

``` c
// Function that deallocates the memory for a Sqlx4kResult struct.
// Accepts a pointer to a struct [Sqlx4kResult].
void sqlx4k_free_result(struct Sqlx4kResult *ptr);
```

In each language, this process could be a bit different. In my case, with Rust, I almost hacked the memory management by intentionally "leaking" memory and then calling the `sqlx4k_free_result` function from the Kotlin code in order to free the memory, thus avoiding a memory leak:

``` kotlin
fun <T> CPointer<Sqlx4kResult>?.use(f: (it: Sqlx4kResult) -> T): T {
    return try {
        // "Point" to the pointer
        this?.pointed?.let { f(it) }
            ?: error("null pointer exception")
    } finally {
        // Ensure that allways we will free the memory.
        sqlx4k_free_result(this)
    }
}
```

In the next part of this series, I will provide detailed examples on how I managed to do it (it wasn't so difficult in the end).

## Conclusion

Although we need to be a bit more careful, especially with memory management---even in the case of Kotlin and Rust, which are considered memory-safe languages---I believe the whole process is not that difficult. Moreover, if you manage to "wire" the two languages for a given example (like wrapping a database driver), then doing it for a different task will become much easier, since you will have gained the knowledge and "invented" the necessary mechanics (or tricks, if you prefer).

I think the benefits are numerous:
- Continue writing in Kotlin, as it is a modern and easy-to-learn language.
- Benefit from applications with a small memory footprint.
- Provide the Kotlin ecosystem with libraries that will help us develop more applications, especially on the backend.

As always, take a look at the project's repository on GitHub:
[GitHub - smyrgeorge/sqlx4k: A small non-blocking database driver written in Kotlin for the Native platform.](https://github.com/smyrgeorge/sqlx4k)

All contributions are welcome. Thank you very much.

------------------------------------------------------------------------

## References

- [Foreign function interface - Wikipedia](https://en.wikipedia.org/wiki/Foreign_function_interface)
- [Interoperability with C \| Kotlin Documentation](https://kotlinlang.org/docs/native-c-interop.html)

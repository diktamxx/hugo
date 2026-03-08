---
title: "理解虚拟线程（Java 21 Virtual Threads，VT）"
slug: "Java 21 Virtual Threads"
categories: ["Java"]
tags: ["Java","并发编程"]
date: "2024-08-12"
cover: "images/cover.png"
thumbnail: "images/cover.png"
summary: "最好的性能调优就是升级JDK。"
---

虚拟线程最大的优势在于 I/O 处理场景。因为不会阻塞（平台线程），所以能够使 I/O 密集型应用拥有更大的吞吐量。
此外，对于 CPU 资源受限的环境也很适合。

## 线程种类
- 平台线程：泛指 JVM 线程（如：java.lang.Thread）。负责执行用户态代码（如：应用程序任务）。在 64bit 系统中每条线程默认占 1MB。这就是为什么需要池化复用的原因，因为创建线程的成本比较大。参考：`java -XX:+PrintFlagsFinal --version | grep ThreadStackSize`
- 内核线程：由操作系统管理。负责系统资源访问，承载平台线程。在 HotSpot 中，平台线程和内核线程通常是一对一的关系，但不同的 JVM 实现可能有所差别
- 虚拟线程：在 java.lang.Thread 的基础上实现，同属用户态。在 Java 中，平台线程和虚拟线程是一对多的关系。在该上下文中，平台线程被称为载体。虚拟线程本质上只是一个 Java 对象，大小通常在 1～2 KB 左右。因为创建成本极低，所以无需池化或复用

## 虚拟线程（VT）

未引入 VT 之前，Java 程序要想异步执行任务就需要依赖平台线程。但直接使用平台线程会存在一个问题。当任务在执行期间遇到阻塞操作，对应的平台线程也会被阻塞，直至操作返回为止。该过程会引发上下文切换 —— 对程序请求处理的吞吐量影响较大，因为在切换期间不会执行用户态代码（即无法处理请求）。

可将 VT 看作是一种特殊的任务包装器或者介乎于平台线程和异步任务之间的抽象层，它使得任务和平台线程得以解耦。客户端将任务交给 VT 后，Java Runtime 会动态地将 VT 绑定在某条平台线程上执行 —— 平台线程由`java.util.concurrent.ForkJoinPool#common`提供。值得注意，VT 和平台线程的关系并不是固定的。一旦 VT 在执行任务期间被阻塞平台线程就会将其卸载，然后绑定其他可执行的 VT 继续处理（其他）任务。换句话说，性能提升并非来自于 VT 本身，而是来自于平台线程得到了更高的使用效率 —— 因为减少了上下文切换所带来的性能损耗。

基本上阻塞操作都会导致 VT 被其载体卸载。但目前（JDK 24之前）还存在一些特例会导致载体无法卸载 VT，而无法卸载则意味着会直接阻塞载体（平台线程）。这种现象称为固定，之所以会发生这种情况是因为历史遗留原因。某些线程调度工作需要依赖内核的支持，然而在目前版本的 Java Runtime 中暂时无法摆脱这一事实。从另一个角度来看，可以将固定视为一种安全措施。譬如 JVM 的`synchronized`语义实际上是参照[监控器](https://en.wikipedia.org/wiki/Monitor_(synchronization))来实现的，所以又叫监控锁。当某条线程获取到`synchronized`之后，JVM 就会通过自旋（即“忙等待”）的方式来持续监控该线程以便及时地更新监控器信息。而问题在于 JVM 监控的是平台线程，而非 VT。因为目前`synchronized`其实是针对平台线程来实现的，若果不进行 VT 固定就会出现一个问题。譬如当 VT1 获取到监控锁后因阻塞而被载体卸载，载体转而绑定 VT2 继续执行其他任务。此时，从 JVM 角度来看真正持有监控锁的其实载体本身。也就是说，VT2 因为载体而得到了监控锁，这显然是一个问题。因此，针对该问题 Java Runtime 会在 VT 阻塞时执行如下策略：

- 发生条件阻塞时（如：synchronized、Object#wait、BlockingQueue#take 等），载体因受到 Java Runtime 限制而将无法卸载 VT。此时载体（平台线程）将会被阻塞。该问题将会在 JDK 24（[JEP-491](https://openjdk.org/jeps/491)）中解决
- 发生I/O阻塞时，Java Runtime 就会让载体卸载 VT，并将 I/O 操作注册到内核中（如 epoll、kqueue），直到对应文件描述符就绪后才会恢复 VT（真正运行需要等待载体装载）

Java Runtime 并不会因为载体被固定而增加并行度 —— 默认并行度为机器 CPU 的核心数，可参考：`java.util.concurrent.ForkJoinPool#common`的实现。所以从应用层面应该尽量避免固定。譬如使用`java.util.concurrent.locks.ReentrantLock`替代`synchronized`。当出现固定时，意味着应用程序对 CPU 的使用率将会降低，因为平台线程可以被阻塞。为了解决这问题，可以透过设置系统变量`jdk.virtualThreadScheduler.maxPoolSize`来指定最大的平台线程数。但要注意该值要大于`jdk.virtualThreadScheduler.parallelism`才有作用。


## 注意
- VT 不需要被池化。因为 VT 的堆栈只是一个普通对象，受 GC 管理。理论上只要堆内存足够大的话就可以大规模创建 VT。
- VT 无法通过`jstack`和`jcmd <pid> Thead.print`进行堆栈转存，因为它们并不是针对 VT 设计的。想要获取包含 VT 的堆栈转存信息可以用`jcmd <pid> Thread.dump_to_file -format=json <file>` 命令。
- Tomcat 从 9.0 开始可在 server.xml 中手动添加一个 className 为`org.apache.catalina.core.StandardVirtualThreadExecutor`的 Executor，然后再配置到想要使用 VT 的 Connector 上就可以运用 VT 来处理网络请求了。
- VT 属于守护精灵线程，所以不会影响进程的退出决策。


## 拓展
Netflix 曾经遇到过载体无法卸载 VT 的情况
- [Java 21 Virtual Threads - Dude, Where’s My Lock?](https://netflixtechblog.com/java-21-virtual-threads-dude-wheres-my-lock-3052540e231d)。

JVM 处理 VT 阻塞
- [Project loom, what happens when virtual thread makes a blocking system call?](https://stackoverflow.com/questions/70174468/project-loom-what-happens-when-virtual-thread-makes-a-blocking-system-call)。

VT 的出现是否会让反应式编程变得无关紧要？
- 答案是否定的。反应式本质上是一种架构风格，在[反应式宣言](https://www.reactivemanifesto.org/zh-CN)中被规范。它主张应用架构应该满足 *即时响应*、*回弹*、*弹性*、*消息驱动* 等特性。而 VT 只是异步编程技术的一种实现。或者说，两者完全可以结合使用。

I/O 模型和线程的关系
- 曾经有个著名的问题叫 [C10k](https://en.wikipedia.org/wiki/C10k_problem) —— 让服务器能够同时处理 10000 个客户端请求。但以前的 I/O 操作属于同步阻塞式。这通常意味着请求数有多大线程数就要多大。否则服务器会被阻塞，从而无法处理后续请求；严重起来甚至会崩溃。所以对于旧时的服务器配置来说，处理该问题相当有难度。直到异步 I/O 模型的出现（准确来说是多路复用机制。它能够同时监听多个文件描述符），单条线程终于可以同时处理多个 I/O 而不会被一直阻塞。只需少量线程就能够处理大并发需求 —— 著名的 EventLoop 模型就此诞。或者你可能听说过 Reactor 模式（如：Netty）和 Node.js，其核心都是 EventLoop 模型。通过线程独占资源来避免并发性，再透过开发规范来约束开发者切勿阻塞 EventLoop 线程来达到 CPU 利用率最大化（，否则整个 EventLoop 处理都会被阻塞）。这就是 EventLoop 高效的根本原因。


## 参考资料
- [Busy waiting](https://en.wikipedia.org/wiki/Busy_waiting)
- [Tomcat 9.0 changelog](https://tomcat.apache.org/tomcat-9.0-doc/changelog.html)
- [JEP 491: Synchronize Virtual Threads without Pinning](https://openjdk.org/jeps/491)
- [Maximum Number of Threads per Process in Linux](https://www.baeldung.com/linux/max-threads-per-process)
- [Demystifying Virtual Thread Performance: Unveiling the Truth Beyond the Buzz](https://dzone.com/articles/demystifying-virtual-thread-performance-unveiling?utm_source=chatgpt.com)
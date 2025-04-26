---
title: "理解虚拟线程（JDK 21 Virtual Threads）"
categories: ["Java"]
tags: ["Java","并发编程"]
date: "2024-08-12"
cover: "images/cover.png"
thumbnail: "images/cover.png"
draft: false
summary: "最好的性能调优就是升级JDK。"
---

虚拟线程（Virtual Threads，简称：VT）最大的优势在于**I/O处理**。因为不会阻塞（平台线程），所以能够使**I/O密集型系统**拥有更大的吞吐量。这无疑是一种相当可观的性能提升。

## 线程的种类
- **平台线程**：泛指由 JVM 实现的线程（如 java.lang.Thread）。属于**用户态线程**。用于执行用户态代码（如应用程序中的任务）
- **内核线程**：由操作系统管理。属于**内核态线程**。用于访问系统资源。在 HotSpot 中，平台线程和内核线程通常是**一对一**的关系（。不同的JVM可能有不同的实现）
- **虚拟线程**（java.lang.VirtualThread）：基于`java.lang.Thread`实现，所以同属**用户态线程（Thread 实现）**。在 Java 中，平台线程和虚拟线程是**一对多**的关系；在该上下文中，平台线程被称为VT的**载体**

## 虚拟线程（VT）

未引入 VT 之前，Java 程序要想异步执行某个任务就需要依赖平台线程。但平台线程存在一个问题；当任务执行期间遇到阻塞操作时，其执行（平台）线程就会被阻塞。
一旦线程被阻塞，它就会被 JVM 挂起直至**阻塞操作返回**并**获取到执行资源**为止。
该过程称为**上下文切换**，对于应用程序而言是一种对吞吐量影响较大的操作（，因为切换期间并不执行应用代码）。

可将 VT 看作是一种**特殊的任务包装器**或**介乎于平台线程和异步任务之间的抽象层（，使得任务和平台线程得以解耦）**。
客户端将任务交给 VT 后，Java Runtime 会动态地将 VT 绑定到某条平台线程上执行（，该平台线程由`java.util.concurrent.ForkJoinPool#common`提供）。
值得注意，VT 和平台线程的关系并不是固定的。一旦 VT 在执行任务期间被阻塞，其平台线程就会将其卸载，并绑定其他可执行的 VT 继续处理（其他）任务。
换句话说，性能提升并非来自于 VT 本身，而是来自于**平台线程得到了更高的使用效率**（，因为减少了上下文切换所导致的性能损耗）。

基本上阻塞操作都会导致 VT 被其载体卸载。然而，目前（JDK 24之前）还存在一些特例会导致载体无法卸载 VT。
无法卸载意味着会直接阻塞载体（即平台线程），这种情况称为**固定**。
之所以发生**固定**是因为历史遗留原因。一些线程调度工作需要依赖内核的支持，然而在目前版本的 Java Runtime 中暂时无法摆脱这一事实。
从另一个角度来看，**固定**实际上是一种安全措施。譬如 JVM 的`synchronized`语义实际上是参照[监控器](https://en.wikipedia.org/wiki/Monitor_(synchronization))来实现的（，所以又叫“监控锁”）。当某条线程获取到`synchronized`之后，JVM 就会通过自旋（又叫“忙等待”）的方式来持续监控该线程以便及时地更新监控器信息。但问题在于 JVM 监控的是平台线程，而非 VT。也就说，就目前而言`synchronized`是针对平台线程来实现的。因此，若果不进**固定**的话就会出现这么一种情况。VT 获取到监控锁后因阻塞而被载体卸载，载体转而绑定 VT2（泛指其它可被直接执行的 VT）。此时，从 JVM 层面来看，真正持有监控锁的其实是当前 VT2 的载体。即因为载体的重新绑定了，导致 VT2 获得了监控锁。所以这显然是存在问题的。因此，针对以上问题。Java Runtime 会在 VT 阻塞时执行如下策略：

- 发生**条件阻塞**时（如 synchronized、Object#wait、BlockingQueue#take 等），载体因受到 Java Runtime 限制而将无法卸载 VT。此时载体（平台线程）将会被阻塞
    - ⚠️ 该问题将会在 JDK 24（[JEP-491](https://openjdk.org/jeps/491)）中解决（阅读下文）
- 发生**I/O阻塞**时，Java Runtime 就会让载体卸载 VT，并将 I/O 操作注册到内核中（如 epoll、kqueue），直到对应文件描述符就绪后才会恢复 VT（真正运行需要等待载体装载）

Java Runtime 并不会因为载体被**固定**而增加并行度（。其并行度默认为机器 CPU 的核心数，可参考`java.util.concurrent.ForkJoinPool#common`的实现），所以应该尽可能地避免**固定**。例如使用`java.util.concurrent.locks.ReentrantLock`替代`synchronized`。当出现**固定**时，意味着应用程序对 CPU 的使用率将会降低（因为载体/平台线程被阻塞）。为了解决这问题，可以添加系统变量`jdk.virtualThreadScheduler.maxPoolSize`来指定最大的平台线程数。但该值要大于`jdk.virtualThreadScheduler.parallelism`才有作用。


## 注意
- VT 不需要被池化。因为 VT 的堆栈只是一个普通对象（，这意味着受到 GC 管理，并且可以被复用）。理论上只要堆内存足够大的话就可以大规模创建 VT
- VT 无法通过`jstack`和`jcmd <pid> Thead.print`进行堆栈转存，因为它们并不是针对 VT 设计的。想要获取包含 VT 的堆栈转存信息，可以使用`jcmd <pid> Thread.dump_to_file -format=json <file>` 命令
- Tomcat 从 9.0 开始可在 server.xml 中手动添加一个 className 为`org.apache.catalina.core.StandardVirtualThreadExecutor`的 Executor，然后再配置到想要使用 VT 的 Connector 上就可以运用 VT 来处理网络请求了
- VT 属于**守护线程/精灵线程**，所以不会影响进程的退出决策


## 拓展
- Netflix 就曾经遇到过载体无法卸载 VT 的情况: [Java 21 Virtual Threads - Dude, Where’s My Lock?](https://netflixtechblog.com/java-21-virtual-threads-dude-wheres-my-lock-3052540e231d)
- JVM 处理 VT 阻塞: [Project loom, what happens when virtual thread makes a blocking system call?](https://stackoverflow.com/questions/70174468/project-loom-what-happens-when-virtual-thread-makes-a-blocking-system-call)
- VT 的出现是否让**反应式编程**变得无关紧要？答案是否定的。反应式编程本质上只是一种编程范式（由[反应式宣言](https://www.reactivemanifesto.org/zh-CN)规范）。它主张的是**即时响应**、**弹性（如背压）**、**消息驱动**等价值观。而 VT 只是异步编程技术的一种实现。在命令式编程中，你依然需要有意识地使用 VT，但在反应式编程中默认就是异步的（，当然你也可以使用 VT 来实现反应式编程）


## 参考
- [Busy waiting](https://en.wikipedia.org/wiki/Busy_waiting)
- [Tomcat 9.0 changelog](https://tomcat.apache.org/tomcat-9.0-doc/changelog.html)
- [JEP 491: Synchronize Virtual Threads without Pinning](https://openjdk.org/jeps/491)
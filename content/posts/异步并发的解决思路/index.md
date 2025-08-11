---
title: "并发解决思路"
slug: "Concurrent programming solutions"
categories: ["Java"]
tags: ["Java","并发编程"]
date: "2023-04-18"
cover: "images/cover.png"
thumbnail: "images/cover.png"
summary: "并发，就是彼此无法感知。"
---

<b>内容修订</b>
- 2025/07/23：重构文章

并发是指多条线程（或进程）同时访问共享变量，但互相无法感知对方的存在。
这种“无法感知”主要体现在，当前线程对共享变量的更新对于其他线程而言是不可见。
因此，并发在多线程（或进程）协作中会带来重大的安全隐患。譬如多条线程同时修改共享变量（而又没有安全策略控制的前提下）就会导致数据不一致。

## 解决思路

**同步[^1]**

使用锁对临界区进行访问互斥，实现共享变量的串行化访问。

注意，锁的性能开销较大。其中一个重要原因是，只有竞争到锁的线程才能继续执行。这在高负载场景，对请求处理的吞吐量影响较大。另一个原因是，每次释放锁后线程都需要将计算结果从寄存器中刷新到主存以确保其可见性。而该操作效率较低（因为CPU的速度远比RAM快）。针对以上问题，较稳常见的解决方案是细化锁（如：段锁、读写锁）或消除锁语义（参考下文）。

在 Java 中，可通过 synchronized 或 java.util.concurrent.locks.Lock 实现。

**线程变量**

每条线程都有自己的变量。不共享自然就没有并发。

因为没有共享状态，所以当前方案并不适合需要多线程协作的需求。
在 Java 中，可通过 ThreadLocal 或 ScopeValue（Java 20）来实现。

**乐观策略**

基于比较并交换（Compare-And-Swap，CAS）技术[^2]实现原子更新。

CAS 较为适合竞争不太激烈的场景。否则会很容易导致 CPU 使用率飙升，从而影响整体的吞吐量。
另外，CAS 仅能确保单个写操作上的原子性，因此并不适合多写场景。

在 Java 中，可通过 java.util.concurrent.atomic 包实现 CAS。例如 AtomicStampedReference 还能解决[ABA问题](https://en.wikipedia.org/wiki/Compare-and-swap#ABA_problem)。


**不可变**

将共享变量设计成不可变。而不可变的状态不存在并发，因为线程本身能够实现可重复读[^3]。但和线程变量一样，因为不涉及并发修改共享变量（因为不能）。所以该方式同样不适用于多线程协作需求。

实现不可变性的方式有多种。如 Java 的 final 关键字和 record 类、写时复制模式、读时复制模式和写操作忽略等等。可根据实际情况来选择实现策略。

**无状态**

将对象设计成无状态。因为没有能够共享的变量，所以就不存在并发性。

这种设计模式在服务器组件中常见。因为服务器程序需要长时间运行。所以为了降低内存使用率，通常就会将服务组件设计成单例。但又因为单例对象可能在多线程环境下被共享，所以为了防止出现数据不一致，服务器组件通常会被设计成无状态。

## 拓展：什么是 Happened-before？
由计算机科学家[Leslie Lamport](https://zh.wikipedia.org/zh-cn/%E8%8E%B1%E6%96%AF%E5%88%A9%C2%B7%E5%85%B0%E6%B3%A2%E7%89%B9)提出的一种可用于辨识事件先后发生顺序（或并发性）的理论[^4]（具体源自[Lamport时钟](https://en.wikipedia.org/wiki/Lamport_timestamp)）。即当明确知道事件 A 先于事件 B 发生时，那么事件 A 的结果必然对事件 B 可见（至少逻辑上成立）。换言之，两者并不存在并发问题。

后来种理论被用于实现异步编程模型语义。例如 Java Memory Model（JMM）的 synchronized、volatile。而其他常用编程语言通常也有标准库的 atomic 库用来支持该语义。例如在 JMM 中，synchronized 在同一个监控锁上支持 `synchronized unlock happened-before lock` 语义。即在同一 synchronized 块中，上一条持锁线程的操作结果必然对当前持锁线程可见。而 volatile 则支持 `volatile write happened-before read` 语义，即上一个 write 操作的结果必然对当前 read 操作可见。具体可以参考 [Java Language Specification - Happens-before Order](https://docs.oracle.com/javase/specs/jls/se21/html/jls-17.html#jls-17.4.5)。

注意，volatile 本身并不支持原子语义。它是通过一种名为[内存屏障](https://en.wikipedia.org/wiki/Memory_barrier)的技术实现的。其中写屏障能够确保上一个 write 及其（同区域）之前的操作对当前 read 可见。读屏障则可以确保 read 及其（同区域）之后的操作能够避免指令重排序[^5]。
```
// 理解例子
class Example {
    int a = 0;
    volatile int b = 0;

    // 1）先执行
    void write() {
        a = 1;      // 普通写
        b = 1;      // volatile写，会插入“写屏障”
    }

    // 2）后执行
    void read() {
        if (b == 1) {       // volatile读，会插入“读屏障”
            assert(a == 1); // 因为“写屏障”结果为：true
        }
    }
}
```

## 参考
- [Happened before](https://en.wikipedia.org/wiki/Happened-before)
- [Java memory model](https://en.wikipedia.org/wiki/Java_memory_model)
- [Critical section](https://en.wikipedia.org/wiki/Critical_section)
- [Compare-and-swap](https://en.wikipedia.org/wiki/Compare-and-swap#Implementations)
- [aliasing bug](http://www.catb.org/jargon/html/A/aliasing-bug.html)

[^1]: 在异步编程中，同步指的是多线程（或进程）同时访问共享变量时看上去像是串行化一样。即每次只有一条线程在访问变量。
[^2]: CAS本质上是一种由CPU（架构）提供的原子指令。但从软件设计层面而言，CAS也是一种设计模式。在分布式环境下，可实现离线并发控制（即optimistic offline lock模式）。
[^3]: 可重复读指的是，在线程多次读取同一个共享变量时，其值是预先可知的。
[^4]: 据了解 Happened-before 这种理论，其实源自于 Leslie Lamport 的论文[《Time, clocks, and the ordering of events in a distributed system》](https://dl.acm.org/doi/10.1145/359545.359563)
[^5]: 指令重排序是一种提高代码执行效率的优化机制。因为并不是所有代码都存在时间耦合关系。


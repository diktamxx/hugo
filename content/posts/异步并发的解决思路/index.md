---
title: "异步并发的解决思路"
slug: "Concurrent programming solutions"
categories: ["Java"]
tags: ["Java","并发编程"]
date: "2023-04-18"
cover: "images/cover.png"
thumbnail: "images/cover.png"
summary: "并发，就是彼此无法感知。"
---

## 1. 基本概念

### 1.1 并发和同步
**并发**：操组之间互相无法感知。通常用来描述“存在多个操作同时访问同一个状态”的异步场景。

**同步**：使用*某种机制（通常泛指“锁”或“信号量”）*将*并发操作*变得受控制。

### 1.2 什么是Happened-before？
*Happened-before*是*Leslie Lamport*提出的一种用来描述两个事件先后发生顺序的论述（参考: *Lamport逻辑时钟*[^1]）。*Happened-before*中强调，如果`A happened-before B`，那么`A`必然对`B`可见。

后来这一种论述被广泛应用于*编程语言并发模型*的实现。如*Java Memory Model*的*synchronized*、*volatile*、*java.util.concurrent*，其他语言的*atomic*标准库基本上也都支持。

譬如我们可以说，`synchronized unlock happened-before lock`，意思是上一个`unlock`临界区（即被机制保护的部分）的操作结果，必然对当前`lock`临界区可见。背后的含义是`unlock`临界区和`lock`临界区不存在并发性，即它们是并发安全的。

`volatile`也有同样效果，但理解起来更为复杂一些。当我们说`volatile write happened-before read`时，表面上可以简单理解为是上一个`write`结果必然对当前`read`可见。
然而`volatile`是通过一种由CPU架构提供名为**内存栅栏/内存屏障（写屏障、读屏障）[^2]** 的技术来实现的。*写屏障*能够同时确保`write`之前的操作对`read`可见。而*读屏障*则能够确保`read`之后的操作避免*指令重排序（一种提高代码执行效率的机制）*。
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



## 2. 安全隐患
**更新覆盖**：一个操作的更新了覆盖另一个操作的更新，导致部分更改丢失。

**脏读**：读取到另一个操组尚未提交（即中间状态）的状态
* ⚠️ 虽然一些编程语言有自己的内存模型。如*Java Memory Model*，线程有自己的工作内存（一种抽象概念），但它依然无法避免脏读。譬如第一次读操作必然从主存中读取，然而主存若没有相关机制保护的话，就无法解决异步并发所带来的安全隐患

## 3. 解决思路
### 3.1 隔离
* 使用*锁（访问互斥）*或*信号量(限制操作数)* 对临界区进行并发同步控制
    * 期间还可以通过*细化锁策略（段锁、读写锁）*或*消除锁语义（由运行时提供）* 来提高并发效率
* *将状态放入*线程变量（ThreadLocal）*或*域值（ScopeValue，Java 20）* 中，通过隐藏其可见性来避免并发

### 3.2 不可变
* 用final修饰属性
* 忽略操作或直接抛异常
* 写时复制。即修改操作仅在副本上进行。通常还会将修改后的副本返回给客户端
* 读操作防*别名Bug[^3]*。即读操作直接返回副本

### 3.3 无状态
* 对象没有保持状态的属性，如果有那么属性本身也应该是无状态的。或者属性本身就是不可变的。


[^1]: [Lamport timestamp](https://en.wikipedia.org/wiki/Lamport_timestamp)
[^2]: [Memory barrier](https://en.wikipedia.org/wiki/Memory_barrier)
[^3]: [aliasing bug](http://www.catb.org/jargon/html/A/aliasing-bug.html)

## 参考
* [Happened before](https://en.wikipedia.org/wiki/Happened-before)
* [Java memory model](https://en.wikipedia.org/wiki/Java_memory_model)
* [Critical section](https://en.wikipedia.org/wiki/Critical_section)
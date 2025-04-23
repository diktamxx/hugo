---
title: "异常处理的哲学"
categories: ["Java"]
tags: ["Java", "异常处理"]
date: "2023-03-27"
cover: "images/cover.png"
thumbnail: "images/cover.png"
summary: "不理解异常，又如何自定义异常？"
---

在 Java 中，异常被分为两大类：**受检异常（checked exception）**、**未受检异常（unchecked exception）**。

**受检异常**的编程语义可理解为**可预知，且客户端有能力解决的问题**。它包含`java.lang.Exception`、`java.lang.Throwable`两种类型。它们会受到**编译器**监管。当发现客户端没有及时处理异常时，其源码就会无法编译通过。这样设计最主要的目的是希望使用 API 的开发者能够及时地处理相应的异常。比较典型的例子是`java.io.IOException`。譬如当`java.io.FileInputStream#FileInputStream(java.io.File)`中的`file`不存在时，就会抛出`java.io.FileNotFoundException`。
然而，核心问题在于为什么`FileNotFoundException`需要被及时处理？这牵涉到异常在代码设计（或处理）层面的哲学。其背后的基础逻辑是，API设计者期望使用者能够及时并明确地处理相关异常。这中逻辑思维基于设计者的经验和期望。以前面提到的`FileInputStream(java.io.File)`为例，它是一个**同步API**。换言之，它必须执行找到目标文件，否则就无法执行后续操作。出于这一原因，客户端（开发者）有必要给出一个明确的解决方案。譬如使用必然存在的默认文件来代替。当然，API 客户端也可能出现不知道何处理异常的情况，此时客户端可以选择接着往外层抛出异常，以便更外层的客户端来处理它。但这种做法只应该在迫不得已的时候才进行，否则受检异常和未受检异常将变得无区别（，除了受检异常会继续要求客户端继续往外层抛出异常之外）。
因此，在进行 API 设计期间，当发现某操作必须满足某种条件，而这一条件（根据经验而言）客户端又有能力解决的话，那么就可以使用受检异常来对该语义进行建模。

**未受检异常**的编程语义是**无法预计或解决的问题**。它包含`java.lang.Error`、`java.lang.RuntimeException`两种类型。其典型例子是`java.lang.NullPointerException`和`java.lang.IllegalArgumentException`。两者通常还都会涉及到外部输入；如*没有在数据库中找到对应的数据记录*、*用户提交的请求不符合规则*。这些问题 API 通常是无法控制和解决的；或者说，它们应该直接被系统用户所感知，而不是被程序暗地里解决。针对未受检异常，通常应对方案是实施[防御性编程](https://zh.wikipedia.org/wiki/%E9%98%B2%E5%BE%A1%E6%80%A7%E7%BC%96%E7%A8%8B)。即在相应位置增加**校验逻辑**或**兜底操作**。常见例子有*前置条件判定*、*AOP捕获*、*声明式处理（通常由SDK支持。在函数式/链式编程中被受青睐）* 等。换句话说，当遇到*无法预计*、*无法解决*、*不应由程序解决*等问题时，就可以运用未受检异常来将其建模。

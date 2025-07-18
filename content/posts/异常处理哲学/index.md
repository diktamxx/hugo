---
title: "异常处理哲学"
slug: "Java Exception Handling Philosophy"
categories: ["Java"]
tags: ["Java", "异常处理"]
date: "2023-03-27"
cover: "images/cover.png"
thumbnail: "images/cover.png"
summary: "不要滥用全局异常处理机制。"
---

<b>内容修订</b>
- 2025/06/08：调整文章结构，使其更易于阅读

| 用语 <div style="width:8em"> | 解释 |
| ----------- | ----------- |
| 客户端 | 泛指使用 API 的地方。|
| 编程语义 | 代码程序所表达的真实意图。|
| 代码单元 | 泛指某种代码整体。如*代码块*、*方法*、*类*、*包*、*模块*等。|
| 技术债务 | 这是一种隐喻，指代开发人员为了提高交付速度而选择一些不明智的解决方案。这种行为就像债务一样。当债务无法得到妥善处理时，项目最终就会被拖垮（变得难以理解和维护，甚至无法扩展，最后甚至失败）。|

在 Java 中，异常被分为两大类：**受检异常（checked exception）**、**未受检异常（unchecked exception）**。

**受检异常**包含`java.lang.Exception`、`java.lang.Throwable`两种类型。它们会受到**编译器**检测；当发现客户端没有及时处理异常时，就会阻止编译通过。其设计目的是希望客户端能够及时地给出解决方案。典型例子是`java.io.IOException`。当执行`java.io.FileInputStream#FileInputStream(java.io.File)`时，若`file`不存在就会抛出`java.io.IOException`（具体类型为：`java.io.FileNotFoundException`）。值得理解的是，为什么`java.io.IOException`需要被及时处理。这其实是一种 API 设计哲学，因为`java.io.FileInputStream#FileInputStream(java.io.File)`是一个**同步API**。换言之，它必须能够正确找到目标文件，否则就无法正常地往下执行其他操作。出于这一原因，所以客户端就有必要给出一个明确的解决方案。例如使用必然存在的默认文件来代替。当然，客户端也可能会出现不知道何处理的情况。此时可以选择将异常往外层抛出，以便让更外层的客户端来处理它。但需要强调，这种做法只是迫不得已。否则*受检异常*和*未受检异常*将变得无本质区别。因此，可将*受检异常*的编程语义理解为**可预计且客户端有能力解决的问题**。

**未受检异常**包含`java.lang.Error`、`java.lang.RuntimeException`两种类型。典型例子是`java.lang.NullPointerException`和`java.lang.IllegalArgumentException`。通常两者类型都会涉及到外部输入。例如 *在数据库中没有找到对应ID的数据记录*、*用户提交的请求不符合规则* 等。这些问题客户端通常是无法控制或解决的。换言之，出现这些问题时，最好是将其反馈给最终用户，而不是暗地里处理它。因为这样可能会引发歧义，让问题变得复杂。*编译器*并不会检测*未受检异常*，因此较为常见的应对方案是实施[防御性编程](https://zh.wikipedia.org/wiki/%E9%98%B2%E5%BE%A1%E6%80%A7%E7%BC%96%E7%A8%8B)。即在相应位置增加**校验逻辑**或**兜底操作**。较为常见的例子有*前置条件判定*、*AOP捕获*、*声明式处理（通常由SDK支持。在函数式/链式编程中被受青睐）*这些。可将*未受检异常*的编程语义理解为**无法预计或解决的问题**。因此，当遇到*无法预计*、*无法解决*、*不应由程序解决*等问题时，就可以运用未受检异常来将其建模。

在实际编程中，一个较能说明该问题的例子是 `spring-tx`。因为其声明式事务（`@Transactional`）默认只会回滚*未受检异常*。
作为框架（出于设计哲学愿意）它需要针对这种意外情况进行兜底。而*受检异常*则被视为一种客户端职责。

另外，在进行程序设计时，最好不要滥用**全局异常处理机制**，而是应该先根据实际的问题来选择*受检异常*或*未受检异常*，再进行针对性处理。
事实上**全局异常处理机制**用得不好的话很容易就会变成一种反模式。因为稍有不慎就会将模块信息带出去，导致模块与外界产生耦合（。同时，逻辑外泄也会导致可理解性降低）。所以个人更推荐将其视为一种*兜底方案*，只在迫不得已时才使用。
切勿因为它可以*简化编程模型*和*节省几行代码*就牺牲*内聚性*或*可理解性*。因为这些看起来简单和便捷的技术方案，对于一个需要长期维护的项目而言通常可以是“致命”的。因为往往正是因为存在大量投机取巧的解决方案（技术债务），所以项目代码才会变得难以理解和维护。因此，要想拥有较高的可理解性和可维护性的代码，最应该紧记的是**高内聚，低耦合**这一设计原则。
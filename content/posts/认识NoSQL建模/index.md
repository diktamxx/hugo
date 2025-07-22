---
title: "认识NoSQL建模"
slug: "Data Modeling with Nosql"
categories: ["NoSQL"]
tags: ["NoSQL","数据建模","数据库"]
date: "2023-07-22"
cover: "images/cover.png"
thumbnail: "images/cover.png"
summary: "不会建模跟不会用数据库其实没什么区别。"
---

<b>内容修订</b>
- 2024/05/12：添加了应对“大属性”的建模方案

| 用语 <div style="width:8em"> | 解释 |
| ----------- | ----------- |
| SoR | 记录系统（System of record）。泛指一等数据源（，应用的状态会以该数据源为准）。 |
| 派生数据库 | 根据 SoR 派生出来的（二等）数据源。通常用于满足 *提高操作性能*、*扩展SoR特性* 场景。|
| 查询模式 | 针对数据（记录）的使用需求。主要是 Schema 和查询方式两个方面。|


**数据建模**是指**为数据设计<u>内存结构和存储结构之间的映射关系</u>的过程**。而**数据模型**则是该过程的产物，它由一系列*结构定义*、*约束规则*及其*关系*组成。
[Martin Fowler](https://en.wikipedia.org/wiki/Martin_Fowler_(software_engineer))将*数据模型*定义为**认知和操作数据时所使用的模型，是一种数据库组织数据的方式**。

与SQL（泛指*关系型数据库*）不同。NoSQL 通常并不遵循[关系建模范式](https://en.wikipedia.org/wiki/Database_normalization)。甚至不同的 NoSQL 实现其*数据建模*方式也大有差别。**设计者需要根据 <u>NoSQL 所提供的具体特性</u>，以及<u>系统实际的查询模式</u>来进行建模决策**。

*关系模型*的优势在于*查询的灵活性*和*数据一致性*。对于遵循范式的*数据模型*而言，可以通过灵活的 SQL 来聚合数据（如*join*）。而且因为没有冗余，所以其数据一致性几乎能够满足所有严苛场景。然而，在面对大数据量存取需求时，该模型会显得相当乏力。或者说，*关系模型*本身就不是针对大数据场景而设计的。

在为*业务系统*进行 NoSQL 数据建模时，比较常用的方案是**面向聚合建模**。简单来说就是将相关信息放在一起。至于“相关”到底如何定义，则取决于具体系统的查询模式。这是因为 NoSQL 通常不提供*ACID事务*承诺，在**多指令任务**上下文中无法确保最基本的*原子性*。或者说，NoSQL 对于*原子性*的支持非常有限。大部分**仅支持单指令/文档级别的原子性**，所以在进行*数据建模*时就需要将相关信息放在一起，以便满足*原子性*。
*面向聚合建模*通常可以透过两种方式来实现：**嵌入**和**引用（嵌入）**。
*嵌入*指的是将*关联（或关联的一部份）*直接嵌入到文档中。适用于*数据规模较少*、*对读性能有要求*、*关联内容不常变化（甚至不可变）*、*允许最终一致性*等需求场景。例如在电商上下文中，可以直接将订单项集合嵌入到具体订单中。因为订单一旦被提交，其订单项集合信息就不应再被修改。
而*引用*的概念其实和 SQL 中的*外键*大致相同。即只将*关联*的标识嵌入到文档中。适用于 *关联内容经常变化*、*对一致性有较高要求* 的场景。
然而，因为*聚合模型*没有遵循范式设计，所以通常情况下或多或少都会存在一些冗余数据[^1]。这使得设计者需要额外引入**数据同步机制**来保持数据之间的一致性。

有时光靠*嵌入*和*引用*两种模式可能无法满足需求。譬如在社交网络中，明星的追随者（followers）数量通常是巨大的（可能几千万，甚至数亿）。此时即便只是将追随者标识嵌入到明星文档中，也无法避免其其体积变大。但该问题的关键在于，文档的一般的查询用例其实并不需要获取追随者的信息。所以完全可以考虑将追随者建模成独立的集合[^2]（这种模式在 SQL 中通常称为*垂直切分*）。另外，极端环境下追随者文档可能会益处[^3]。此时可以使用[异常模式(Outlier Pattern)](https://www.mongodb.com/company/blog/building-with-patterns-the-outlier-pattern)来解决。但该模式会明显增加查询复杂度，所以在应它之前应该先量化负载以确定是否真的有这个必要。

相较于*关系模型*，***聚合模型*建模需要更加关注应用系统的查询模式**。
*关系模型*基于 SQL 查询的灵活性，可以在建模期间忽略查询模式来进行设计。
但*聚合模型*无法做到这点。因为 NoSQL 的数据建模与其具体实现存在特性耦合；
只有在建模期间同时考虑*查询模式*和 NoSQL 特性才能发挥其所长。

值得注意。现代应用系统经常会同时使用多种类型的数据库；
但根据经验而言，**很多缺乏设计经验的开发者会忽视数据建模工作**。
一个较为典型的反模式是将 SoR 的*数据模型*直接映射到*派生数据库*[^4]。
这种做法会一定程度丢失派生数据库的优势；特别是数据库类型为 NoSQL 时，因为 NoSQL 通常不具备完整的*ACID事务*特性。

[^1]: 采用嵌入式数据建模，会一定程度降低数据一致性。这一点需要紧记。
[^2]: 追随者集合的基础模式可以是 `{"_id": 明星标识, "followers":[追随者标识]}`
[^3]: MongoDB 中[单个（BSON）文档的最大体积是16MB](https://www.mongodb.com/zh-cn/docs/manual/core/document/#document-size-limit)
[^4]: 建议只有在 SoR 不能满足实际需求时才应该引入*派生数据库*。因为同时维护多个数据库会一定程度降低数据的一致性，同时还会带来额外的维护和设计成本。

## 参考
- 《NoSQL Distilled: A Brief Guide to the Emerging World of Polyglot Persistence》Martin Fowler
- Data Modeling：[MongoDB](https://www.mongodb.com/zh-cn/docs/manual/data-modeling/)、[Cassandra](https://cassandra.apache.org/doc/latest/cassandra/developing/data-modeling/index.html)、[Neo4j](https://neo4j.com/docs/getting-started/data-modeling/)、[Redis](/files/8-Data-Modeling-Patterns-in-Redis.pdf)
- [Building with Patterns: A Summary](https://www.mongodb.com/company/blog/building-with-patterns-a-summary)

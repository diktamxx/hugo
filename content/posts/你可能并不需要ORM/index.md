---
title: "你可能并不需要ORM（Object–relational mapping）"
slug: "You may not need an Object-relational mapping ORM"
categories: ["软件架构"]
tags: ["软件架构","Java"]
date: "2023-03-12"
cover: "images/cover.png"
thumbnail: "images/cover.png"
summary: "不是面向对象编程又何须ORM。"
---

| 用语 <div style="width:8em"> | 解释 |
| ----------- | ----------- |
| OO | Object-Oriented，泛指面向对面概念模型。|
| OOP | Object-Oriented Programming，基于OO的编程范式。|
| ER | Entity–relationship。一种遵循[关系建模范式](https://en.wikipedia.org/wiki/Database_normalization)的数据模型。|
| 阻抗失谐 | impedance mismatch。形容概念模型之间存在映射成本。该词汇常用于 OO、ER 等上下文。|
| 抽象（计算机科学）| 对具体细节进行概括的过程。本质上是一种**通过屏蔽细节信息来简化理解或应该**的解决方案。|
| 抽象泄漏 | 违反了*抽象*本身的原则，令到相关人员需要了解*抽象*背后的细节信息。对于技术工具而言，*抽象泄漏*会让开发者产生额外的理解和学习成本。|
| 数据一致性问题 | 因数据存在多个版本而引发的逻辑错误问题。|
| PO | Persistence Object。指代那些用于映射成 ER（数据模型）的内存模型。| 
| DTO | Data transfer object。一种应用于上下文边界之间的数据载体。同时也是一种解耦模式。|

ORM 的诞生主要是为了解决OO和ER之间存在的*阻抗失谐*问题。
帮助开发者处理 OO（内存模型）和ER（数据模型）的映射关系，简化持久层编码工作。然而时至今日，其实 ORM 在业界仍然是备受争议。
有人认为，它可以让简单问题变得更简单，但复杂问题也会变得更复杂[^1]。
亦有人说，它是一种抽象失败的案例[^2]，因为其实现基本都存在*抽象泄漏*问题；它无法做到让开发者摆脱 SQL，甚至还需要开发者了解 ORM 本身的实现细节（譬如：N+1问题[^3]）。
结合相关实现（框架）的*学习曲线（通常较高）*和*复杂性*等考量因素，使用 ORM 通常是付出大过收益。

**衡量一个决策是否优秀的第一原则就是看它与需求的契合程度**。所以当你在“是否应该采用 ORM”这种问题上犹豫不决时，其实最应该做的事是重新理解 ORM 的特性。

前文提到，ORM 主要用于**解决OO和ER模型之间的阻抗失谐问题**。
个人认为，内存模型越是符合 OO 范式设计，那么 ORM 就会越适用。
另外，ORM 可以让开发者可以尽可能少地关注 SQL。而这**可以显著地提高开发效率**。特别是配合[spring data jpa](https://github.com/spring-projects/spring-data-jpa)使用时，效果尤为显著。
但问题在于透过关系映射**自动生成的 SQL 通常难以满足性能要求**。而且其**查询能力会受到框架限制[^4]**。但这些问题其实可以通过 [Native SQL](https://thorben-janssen.com/jpa-native-queries/)、[Querydsl](http://querydsl.com/)、[Projections](https://docs.spring.io/spring-data/jpa/reference/repositories/projections.html)、[QueryRewriter](https://docs.spring.io/spring-data/jpa/reference/jpa/query-methods.html#jpa.query-methods.query-rewriter) 等方案解决。
通常 ORM 还**拥有较好的移植性**。譬如有规范（如：JPA）支持切换框架实现，并且能够根据具体的数据库类型来生成方言 SQL。但经常维护[过度设计](https://en.wikipedia.org/wiki/Overengineering)系统的开发者可能会认为这是一种伪需求。因为他们很少遇到需要变更数据库类型的情况。然而，受到良好设计思想（如：[KISS原则](https://en.wikipedia.org/wiki/KISS_principle)）约束的系统可能会因为*用户或数据负载扩张*而需要变更数据库类型；企业也可能会出于*资金*或*战略*原因采取同样的措施。但不论何种原因，变更数据库类型都是一项棘手的任务。此时可将 ORM 视为一种能一定程度降低数据库类型变更成本的方案。
此外，ORM 框架通常会**内置缓存层**实现来避免不必要的 SQL 查询。但这种功能一般只适用于单体应用。因为横向伸缩节点时，可能会因为无法感知其他节点的更新操作而引发*数据一致性问题[^5]*。

相较于 ORM 而言，**采用非 ORM 框架会使得开发者无法回避 SQL 知识**。但这通常不会成为问题；因为对于后端开发而言，这本身就是一项必备的技能。
另外，非 ORM 框架通常抽象程度较低。这意味着开发者**需要更多的工作量**，但好处是能够**拥有更高的灵活性**来满足*性能*和*复杂查询*需求。而且根据具体实现的差异，其实也会提供一定程度的*移植性*和*阻抗失谐*解决方案。譬如 JOOQ 就提供*移植性*。
值得注意，中国境内目前最流行的（Java）非 ORM 框架是 MyBatis[^6]（数据源自：google trends）。其优势在于能够*集中式管理SQL*。而在*灵活性*方面，MyBatis 提供了动态标签。但相较于 JOOQ，它会将部份代码逻辑下推到 XML 中。个人并不喜欢这种设计。

整体而言，**ORM 更适合<u>注重开发效率</u>或<u>开发周期较短</u>的项目。
但从长远来看，非 ORM 通常是更好的选择**。特别是自研产品，*灵活性*要比*开发效率*更有价值。因为可扩展的前提是架构本身需要是灵活的。

## 拓展：善用投射（Projections）

投射的概念并非现定于 ORM 上下文。善用投射可以有效地实践[接口隔离原则（ISP）](https://zh.wikipedia.org/wiki/%E6%8E%A5%E5%8F%A3%E9%9A%94%E7%A6%BB%E5%8E%9F%E5%88%99)[^7]。

值得注意，用于投射场景的数据容器本质上是一种 DTO，而非 PO。
然而为其命名时，若采用“Dto”作为后缀可能会显得不那么协调。因为貌似在强调与 PO 之间的区别（。但事实上它确实从持久层而来，与其相关）。所以个人认为以“Projection”作为后缀可能会更为合适一些。但更好的做法是将相关*数据容器*组织到一个源码文件中。譬如 UserProjection.Address、UserProjection.Profile。这样可以有效地避免命名所带来的困扰。

## 参考
- [Object–relational mapping](https://en.wikipedia.org/wiki/Object%E2%80%93relational_mapping)
- [Object–relational impedance mismatch](https://en.wikipedia.org/wiki/Object%E2%80%93relational_impedance_mismatch)
- [Entity–relationship model](https://en.wikipedia.org/wiki/Entity%E2%80%93relationship_model)
- [Hibernate ORM](https://hibernate.org/orm/)
- [Hibernate Query Language](https://docs.jboss.org/hibernate/orm/current/querylanguage/html_single/Hibernate_Query_Language.html)
- [Is ORM still an anti-pattern?](https://news.ycombinator.com/item?id=36497613)
- [Leaky abstraction](https://en.wikipedia.org/wiki/Leaky_abstraction)
- [The Law of Leaky Abstractions](https://www.joelonsoftware.com/2002/11/11/the-law-of-leaky-abstractions/)

[^1]: ORM 的使用复杂度与内存模型本身的复杂度成正相关关系。
[^2]: ORM 属于抽象失败这一观点，个人理解针对的是 ORM 实现（即框架）。因为 ORM 本身只是一种概念。
[^3]: N+1 是 ORM 实现中的一个备受争议的问题。它描述这么一种情况，当查询一个存在嵌套关系的内存模型（PO）时，就会产生额外针对关联目标的 SQL 查询。至于需要执行多少额外的 SQL 查询，则取决于 N 的大小，而 N 代表关联目标的数量。N+1 问题的核心在于批量执行 SQL 查询会降低系统性能（，因为涉及网络和磁盘I/O）。该问题常见的解决方案有（1）应用[懒加载](https://jakarta.ee/learn/docs/jakartaee-tutorial/current/persist/persistence-intro/persistence-intro.html#_using_collections_in_entity_fields_and_properties)策略。只在访问关联目标时才执行额外查询。（2）使用[JPA JOIN FETCH](https://jakarta.ee/learn/docs/jakartaee-tutorial/current/persist/persistence-querylanguage/persistence-querylanguage006.html#_joins)查询。预加载所有关联目标。
[^4]: ORM 框架的查询能力会受到自身设计影响。譬如近年来一些*关系型数据*开始支持 JSON 数据类型，但 ORM 框架则未必支持（至少需要些时间）。
[^5]: 微服务架构风格下，服务实例应该是无状态的（具体而言，不应该有*更新相关*的状态）。因为状态越少，伸缩性越好。
[^6]: 个人认为 MyBatis 之所以在中国流行，主要是因为一些所谓的“大厂”。这里其实反应着一个行业事实（至少中国是这样）。很多中小型企业和团队其实都缺乏良好的软件工程实践知识和经验，所以他们只能根据“大厂”的指引来作出决策。其底层逻辑是希望通过复制大厂的决策来取得同样的成功。
[^7]: ISP 中的*接口*并非特指编程语言中的抽象特性（如：interface），而是指代服务提供者对外暴露的 API。它是一种抽象概念。例如对象的 Getter 对于其客户端而言就属于*接口*。
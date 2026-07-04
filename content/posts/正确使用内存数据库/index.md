---
title: "正确使用内存数据库（Redis）"
slug: "Using Redis Correctly"
categories: ["NoSQL"]
tags: ["NoSQL","Redis","数据建模","数据库"]
date: "2024-09-24"
cover: "images/cover.png"
thumbnail: "images/cover.png"
summary: "是否容许数据丢失？这是个问题。"
showTableOfContents: true
---

| 用语 <div style="width:8em"> | 解释 |
| ----------- | ----------- |
| Redis OSS | Redis Open Source Software，泛指社区版 Redis。 |
| Redis Labs | Redis 公司的旧名。一个提供 Redis 实验性软件或模块的组织（例如 RedisMod）。 |
| Redis Stack | 由官方提供的（社区版）Redis 套件。旨在构建实时的数据平台；目前生产级别的推荐方案。内置了 Redis OSS、稳定的 Redis Module、Redis Insight（UI）等。 |
| 分布式锁 | 泛指*分布式锁管理器（简称：DLM）*。代表某种操作的权限 |
| [墨菲定律（Murphy's Law）](https://en.wikipedia.org/wiki/Murphy%27s_law) | 任何可能出错的事情都会出错。|
| 死锁 | 一种*并发程序*设计缺陷。具体可描述为：因条件不满足，而无法获取或释放锁。进而导致其他并发个体处于持续等待的状态。|
| 缓存层 | 负责存取缓存的逻辑边界。它可以是*代码片段*、*库/框架*、*AOP*、*代理*等 |
| SoR | 记录系统（System of record）。通常泛指一等数据源；应用的状态会以该数据源为准。有时也称其为“事实数据源”。 |
| 分布式协调服务 | 在分布式环境下，帮助多个节点协调工作的一类中间件或服务。常见需要协调的工作有*主节点选举*、*主备切换*、*分布式锁*、*配置管理*、*策略性任务调度* 等。 |
| 消息队列 | 一种异步通信方式。支持*请求排序*、*请求缓冲*、*发布-订阅*等需求实现。 |
| 查询模式 | 特定于上下文的查询需求。 |
| 技术思维陷阱 | 开发者在设计、开发或维护软件时，因*对软件工程认知不足*或*对某种技术持有偏见*，而导致思维被固化。进而作出错误和低效的决策。 |
| 反模式 | 在实践中经常出现，但违背良好设计原则的解决方案。注意，是否为反模式通常与上下文有关。| 


## 1. 可靠性

Redis 提供了两种持久化方案：RDB (Redis Database)，条件间隔全量快照。AOF (Append Only File)，增量指令备份。

RDB 存在快照空窗期。这意味着一旦间隙期间发生故障就会存在数据丢失风险。
AOF（通过设置 appendfsync always）理论上可以做到每条指令都确保落盘。但在极端情况下 AOF 文件可能会被损坏（如：突然断电、进程崩溃、错误关闭），因此同样存在数据丢失风险[^1]。

注意，以上问题即便采用混合持久化方案（RDB + AOF）和复制架构也无法解决。因为 Redis 本身就不是为可靠存储而设计的。其实墨非定律已经道明一切，所以切勿存在侥幸的心理。当需求无法接受数据丢失时，就不应该只将数据存储在 Redis 中。另外，在必要时可以考虑将应用程序日志纳入为补偿服务的依据（但敏感信息应该先进行脱敏），以防数据丢失后彻底无法恢复。

## 2. 应用场景
### 2.1 特性需求<em style="color: #2C5B66;">（第一原则：允许数据丢失）</em>

#### 2.1.1 常见用例参考
- 服务注册和发现：set、zset
- 签到：bitmap
- 时间线（如：供稿服务、News Feed System）：zset
- 随机抽取：set
- 差集/交集/并集计算：set
- 二级索引：任何类型
- 布隆过滤器：RedisBloom
- 时序数据存储：RedisTimeSeries
- 空间检索：Geospatial
- 文档存储：RedisJSON
- 全文检索：RediSearch
    - [中文分词器：friso](https://github.com/lionsoul2014/friso) 
- 建议词典/Suggest（如：检索建议、@建议）：RediSearch
- 排名：zset
- Top-K（如：热搜、热词、热卖）：RedisBloom
- 基数统计（如：UV统计）：HyperLogLog
- 分布式会话：任何类型
- 去重：set
- 计数（如：PV统计）：string
- 流量控制：Lua + string
- 消息队列：stream


#### 2.1.2 关于 Redis 分布式锁

是否应该使用 Redis 来实现分布式锁（Distribute Lock Manager，DML），取决于能不能接受不可靠性。因为一旦出现数据丢失，锁语义就会被破坏，从而引发一致性问题。但若然能够接受这种不可靠性（譬如只是用锁来降低并发性），那么即便是单节点的 Redis 也能够胜任。

> 如何基于 Redis 实现 DLM 并非本文讨论范畴。而且大部份 Redis 客户端其实都有提供相关实现，所以在这里只会大致讲解一下实现思路。
>
> * 获取锁：`set <lockName> <threadMsg> NX PX <milliseconds>`
>   * 设置超时（`<milliseconds>` ）是为了避免死锁
>   * 在 Redis 2.6.12 之前，`setnx` 和 `expire` 两个指令无法确保原子性，需要引入 Lua 脚本解决。但在新版本中，`set` 指令提供了相关实现
>   * 锁被占用期间，仍然会有（其它）客户端尝试获取该锁。为了降低资源消耗，可以通过 [指数退避算法](https://cloud.google.com/memorystore/docs/redis/exponential-backoff?hl=zh-cn) 来解决
> * 释放锁：`del <lockName>`
>   * 超时机制可能会导致过早释放锁。此时客户端任务还未完成，会引发一致性问题。该问题可以引入租约机制来解决。例如在成功获取锁后，构建一条负责续约的（精灵）线程。其职责是，每隔一段时间就增加 `<milliseconds>` 值。直到真正释放锁时，再移除该线程
> * 锁重入：其实这并非一个必须要解决的问题。具体需要根据锁的使用场景而定。客户端可以在内存中构建一个计数器（如：线程变量），并在重入时执行递增操作。而释放锁，则执行递减操作。并再确保值为 0 后，才真正释放锁
> * 任务停顿：极端情况下（如：GC 操作），停顿会导致锁丢失（已经超时、续约失败），同样会引发一致性问题。该问题可以引入 [Fencing令牌](https://martin.kleppmann.com/2016/02/08/how-to-do-distributed-locking.html) 来解决

另外，针对 Redis DML 的不可靠性，官方提出了 [RedLock](https://redis.io/docs/latest/develop/use/patterns/distributed-locks/#the-redlock-algorithm) 作为解决方案。该算法的核心思路是通过 [仲裁（Quorum）](https://zh.m.wikipedia.org/zh-cn/Quorum_(%E5%88%86%E5%B8%83%E5%BC%8F%E7%B3%BB%E7%BB%9F)) 来实现（CAP）一致性。但鉴于实施成本问题（至少要 3 个 Redis 实例，最好是 5 个），个人建议还是选择更加可靠的解决方案。譬如 Zookeeper（ZAB CP）或 Etcd（Raft CP）。

### 2.2 缓存需求<em style="color: #2C5B66;">（第一原则：接受数据最终一致）</em>

#### 2.2.1 正确理解缓存

缓存的价值在于加速或避免查询。
此处的查询可理解为对 SoR 的直接访问或执行繁重的计算任务。

**使用缓存的第一原则是能够接受数据最终一致**。其根本原因是缓存层和 SoR 没有提供能够确保数据一致性的分布式协议。换句话说，只要（两种以上的）数据源之间没有提供数据一致性协议支持，就必然存在一致性问题。网上（和面试中）经常有人试图解决这一问题，但显然他们会徒劳无功。因为即便可以采用某种极端手段来使其达到一致，但这已然失去了缓存本身的意义。当同步成本大于其查询价值时，就已经说明这种决策是错误的。

虽然缓存层和 SoR 基本上无法实现强一致，但却有方法使其实现真正的顺序一致性。
方案是通过[CDC（Change data capture）](https://en.wikipedia.org/wiki/Change_data_capture)技术来捕获 SoR 上的数据变更事件，然后透过消息队列将事件投递给缓存更新程序来更新缓冲。较为常用的 CDC 实现是 Debezium 和 Flink CDC。

为了提高缓存使用效率，最应该做的事是**合理地选择缓存目标**。
个人建议可以将查询划分为两种类型：状态相关查询；其查询结果用于状态更新，所以尽可能避免使用缓存。非状态相关查询；其查询结果只需确保最终一致性（如：展示、报表计算、模糊统计），可以安全使用缓存。

根据经验而言，有两种关于缓存使用的反模式应该被重点关注。（1）贪图方便将计算结果放入缓存中。缓冲并不可靠，应该停止这种行为。可以用 Zookeeper（ZAB CP）、Etcd（Raft CP）、Consul（Raft CP）来代替。（2）在分布式系统中通过缓存来共享状态。这样做会隐藏通信的复杂性。随着系统迭代其维护工作会变得越来越困难，因为很难搞清楚底有谁在使用该状态。解决办法是使用 API 来替代共享状态。


#### 2.2.2 常见用例参考
- 静态内容（如：*静态页面或片段*）
- 仅需满足最终一致的数据（如：*外部系统查询*、*配置信息*）
- 用于展示的记录或文档、计算结果（如：*互动统计*）
- 社交媒体功能（如：追随者列表、关注者列表、@提及用户列表、互动用户列表）
- 体积较小的临时文件（如：*二维码图片*）。<em style="color:gray;">Redis Key 最大长度是 512 MB</em>


#### 2.2.3 设计模式
⚠️ 设计模式只是指导，而不是非此即彼。它们完全可以结合使用。

缓存端模式（Cache Aside）
- 特点
    - 延时加载
    - 缓存层不负责与 SoR 直接交互。该工作需要由客户端来负责
- 应用逻辑
    - 读操作
        1. 客户端请求缓存层
        2. 若缓存层无法命中，则客户端需要主动访问 SoR，然后再将响应结果更新至缓存层
    - 写操作
        - 方案1：写 SoR 后，再删除缓存层。能更有效低地缓存有用数，能一定程度节省缓存空间
        - 方案2：写 SoR 后，再更新缓存层。低并发场景下时效性更好。属于*空间换时间策略*

提前刷新模式（Refresh Ahead）
- 特点：客户端无需检索 SoR
- 应用逻辑：将数据预先或定期地加载到缓存层

本地缓存模式（Local Cache）
- 特点：将数据直接缓存在客户端内存
- 应用逻辑：可用编程语言内置的标准库，或第三方缓存库来实现

缓存层即SoR模式（Cache as SoR）
- 特点：SoR 对于客户端而言是透明的，客户端仅需和缓存层交互
- 元模式：
    - 直读（Read Through）
        - 和缓存端模式一样，但由缓存层来实现
    - 直写（Write Through）
        - 客户端更新缓存层后，再由缓存层将状态同步写入 SoR
    - 后写（Write Back）
        - 和*直写*基本一致。但缓存层通过异步写入 SoR


#### 2.2.4 应对极端情况

当系统需要应对大流量时，缓存层就会面临一系列考验。
从技术层面来说，缓存层在加速查询的同时还避免了请求直接进入 SoR。即同时提高了系统可用性和可靠性。因为大部分（尤其是业务型）系统的 SoR 依然用的是关系型数据库，但关系型数据库却不擅长应对大流量和大数据。

问题在于缓存层可能会失效（如：TTL、不可用）。一旦缓存层失效就可能会导致系统性能骤降，甚至崩溃。解决思路如下：
- 在网关增加流量控制，以防过载
- 在系统中使用本地缓存，避免过度依赖分布式缓冲
- 采集并分析缓存（key）使用率，实现动态 TTL 调整
- 使用 DLM 控制缓存更新的并发性，避免 SoR 出现大量并发更新请求
- 通过客户端缓存（如：浏览器、App）或[内容分发网络（CDN）](https://aws.amazon.com/cn/what-is/cdn/)来降低系统请求
- <s style="color: gray;">不设置 Redis TTL，避免缓存过期（不推荐：长期占用内存会影响性能，同时也不利于一致性）</s>
- 通过高可用部署方案提高分布式缓冲的可用性。注意，在大流量下可能会引发**热点（Hot Key）** 问题。譬如当一个拥有大量粉丝的明星在社交媒体上发布动态时，这条动态就会迎来一大批高频流量。这种流量最终会汇聚在某个缓冲节点上（因为明星的数据在这里），严重起来甚至会瘫痪节点[^2]。针对该问题，个人认为比较可行的方案是将热点数据广播到所有缓冲节点上，以此来实现负载均衡（可参考：[Hash tags](https://redis.io/docs/latest/operate/oss_and_stack/reference/cluster-spec/#key-distribution-model)）。至于何谓热点数据，则取决于具体用例。譬如在当前例子中可以是拥有大量粉丝的明星帐号

除了缓存失效外，还有一种称为**缓存穿透**的问题需求注意。穿透是指请求有意或无意地绕过了缓存层，导致流量直接落在了 SoR 上。引发该问题的常见两种情况是（1）开发者没有意识到需要增加缓存。这种情况通常比较好解决，只需在发现问题后及时加上即可。（2）系统部署在公网上遭到恶意攻击。譬如使用根本不存在的 key 发起大批量查询。因为根本没有数据，自然就无法命中缓存。该问题的解决思路如下：
- 在网关增加流量控制，以防过载
- 在网关采集流量特征，进行针对性限流
- 使用 [Bloom filter](https://zh.wikipedia.org/zh-cn/%E5%B8%83%E9%9A%86%E8%BF%87%E6%BB%A4%E5%99%A8) 或 [Cuckoo filter](https://en.wikipedia.org/wiki/Cuckoo_filter) 来查询
- 引入 [断路器（Circuit breaker）](https://zh.wikipedia.org/zh-cn/%E6%96%B7%E8%B7%AF%E5%99%A8%E8%A8%AD%E8%A8%88%E6%A8%A1%E5%BC%8F)，在必要时触发降级操作
- <s style="color: gray;">当 SoR 查询返回空时，在缓存层中设置占位（不推荐：毫无意义。攻击者不会愚蠢到使用重复 key 来进行攻击）</s>


## 3. 数据建模

如果对 NoSQL 建模没什么认识，可以先了解另一篇文章：[认识NoSQL建模]({{% ref "/posts/认识NoSQL建模/index.md" %}})。

一般的键值对或文档存储型 NoSQL 都可以优先考虑**面向聚合建模**来作为解决方案。只需确保聚合位于单个 key 上即可。但有时候查询可能并不需要返回完整的聚合信息，特别是聚合本身比较大时。此时可以通过**逻辑聚合**来解决该问题。
简单说，就是透过[名称空间（namespace）](https://zh.wikipedia.org/wiki/%E5%91%BD%E5%90%8D%E7%A9%BA%E9%97%B4)来组织（逻辑）聚合，而实际上聚合的数据是分散存储的。但遗憾的是 Redis 对于名称空间的支持比较有限。唯一类似的功能只有[逻辑数据库](https://redis.io/docs/latest/commands/select/)，但通常还[不建议使用](https://groups.google.com/g/redis-db/c/vS5wX8X4Cjg/m/8ounBXitG4sJ)。解决思路是**对 key 进行规范化命名**来模拟命名空间。
譬如可以将 key 名的格式限定为：`namespaceId:aggregationType:instanceId:instanceAttributeName`。
其中 `namespaceId` 表示租户标识。`instanceAttributeName` 代表聚合的组成部份，用于拆分聚合。这样做的另一个好处是聚合的不同部份可以根据实际需要来选择数据结构。

## 参考资料
- [Redis persistence](https://redis.io/docs/latest/operate/oss_and_stack/management/persistence)
- [First principle](https://en.wikipedia.org/wiki/First_principle)
- [Distributed Locks with Redis](https://redis.io/docs/latest/develop/use/patterns/distributed-locks/)
- [How to do distributed locking](https://martin.kleppmann.com/2016/02/08/how-to-do-distributed-locking.html)
- [System of record](https://en.wikipedia.org/wiki/System_of_record)
- [Cache Usage Patterns](https://www.ehcache.org/documentation/3.10/caching-patterns.html)
- [7 Redis Worst Practices](https://redis.io/blog/7-redis-worst-practices/)
- [Redis Anti-Patterns Every Developer Should Avoid](https://redis.io/learn/howtos/antipatterns)
- [Why is Redis So Fast Despite Being Single-Threaded?](https://medium.com/@aditimishra_541/why-is-redis-so-fast-despite-being-single-threaded-dc06ba33fc75)
- [Redis Data Modeling](/files/8-Data-Modeling-Patterns-in-Redis.pdf)
- [caffeine](https://github.com/ben-manes/caffeine)
- [RedLock implementations](https://redis.io/docs/latest/develop/use/patterns/distributed-locks/#implementations)


[^1]: Redis 7 提供了[multi part AOF](https://redis.io/docs/latest/operate/oss_and_stack/management/persistence/#append-only-file)特性，可将 AOF 切分为多个文件。能一定程度缩控制据丢失所涉及的数据面。
[^2]: 造成热点的另一情况是 key 值本身离散度低。此时取模策略会导致数据向特定节点倾斜，从而造成热点。解决思路是通过增加 key 的复杂性来提高其离散度（如：以多个字段的组合作为 key）。
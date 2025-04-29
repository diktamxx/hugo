---
title: "正确使用内存数据库（Redis）"
slug: "Using Redis Correctly"
categories: ["NoSQL"]
tags: ["NoSQL","Redis","数据建模"]
date: "2024-09-24"
cover: "images/cover.png"
thumbnail: "images/cover.png"
summary: "是否容许数据丢失？这是个问题。"
showTableOfContents: true
---

## 统一语言（减少理解偏差）
| 用语 <div style="width:8em"> | 解释 |
| ----------- | ----------- |
| Redis OSS | Redis Open Source Software，泛指社区版 Redis。 |
| Redis Labs | Redis 公司的旧名。一个提供 Redis 实验性软件或模块的组织（例如 RedisMod）。 |
| Redis Stack | 由官方提供的（社区版）Redis 套件。旨在构建实时的数据平台；目前生产级别的推荐方案。内置了 Redis OSS、稳定的 Redis Module、Redis Insight（UI）等。 |
| 分布式锁 | 泛指*分布式锁管理器（简称：DLM）*。代表某种操作的权限 |
| [墨菲定律（Murphy's Law）](https://en.wikipedia.org/wiki/Murphy%27s_law) | 任何可能出错的事情都会出错。|
| 死锁 | 一种*并发程序*设计缺陷。具体可描述为：因条件不满足，而无法获取或释放锁。进而导致其他并发个体处于持续等待的状态。|
| 缓存层 | 负责存取缓存的逻辑边界。它可以是*代码片段*、*库/框架*、*AOP*、*代理*等 |
| SoR | 记录系统（System of record）。泛指一等数据源（，应用的状态会以该数据源为准）。 |
| 分布式协调服务 | 在分布式环境下，帮助多个节点协调工作的一类中间件或服务。常见需要协调的工作有*主节点选举*、*主备切换*、*分布式锁*、*配置管理*、*策略性任务调度* 等。 |
| 消息队列 | 一种异步通信方式。支持*请求排序*、*请求缓冲*、*发布-订阅*等需求实现。 |
| 查询模式 | 特定于上下文的查询需求。 |
| 技术思维陷阱 | 开发者在设计、开发或维护软件时，因为*对软件工程认知不足*或*对某种技术持有偏见*，而导致思维被固化；从而导致作出错误或低效的决策。 |


## 1. 可靠性

Redis 提供了两种持久化方案：RDB (Redis Database)、AOF (Append Only File)。前者属于**条件间隔全量快照**；后者属于**增量指令备份**。

RDB 存在快照空窗期。这意味着间隙期间一旦发生宕机就会存在数据丢失风险。
AOF 理论上可以（通过设置 appendfsync always）做到每条指令都确保落盘。然而，在极端情况下（如*突然断电*、*进程崩溃或错误关闭*）AOF文件会存在损害的风险；一旦文件损坏就会导致数据丢失（。Redis 7 提供了[multi part AOF](https://redis.io/docs/latest/operate/oss_and_stack/management/persistence/#append-only-file)特性，可以将 AOF 切分为多个文件，从而降低数据丢失所涉及的数据面）。

注意，以上问题即便采用*混合持久化方案（RDB + AOF）* 和*复制架构*也无法解决。*墨非定律*已经道明一切，**切勿存在侥幸的心理**。

建议
- 当需求无法接受数据丢失时，就不应该使用 Redis 来作为解决方案
- 必要时，考虑使用*应用程序日志*来作为补偿依据，以防数据丢失后彻底无法恢复

## 2. 应用场景
### 2.1 特性需求<em style="color: gray;">（第一原则：<em style="color: #df4a4d;">可接受数据丢失</em>）</em>

#### 2.1.1 常见用例参考
- 服务注册和发现：set、zset
- 位图（如：*签到*）：bitmap
- 时间线（如：*供稿服务*、*News Feed System*）：zset
- 随机抽取：set
- 差集/交集/并集计算：set
- 二级索引：任何类型
- 布隆过滤器：RedisBloom
- 时序数据存储：RedisTimeSeries
- 空间检索：Geospatial
- 文档存储：RedisJSON
- 全文检索：RediSearch
    - [中文分词器：friso](https://github.com/lionsoul2014/friso) 
- 建议词典/Suggest（如：*检索建议*、*@建议*）：RediSearch
- 排名：zset
- Top-K（如：*热搜*、*热词*、*热卖商品*）：RedisBloom
- 基数统计（如：*UV统计*）：HyperLogLog
- 分布式会话：任何类型
- 数据去重：set
- 计数（如：*PV统计*）：string
- 流量控制：lua + string
- 消息队列：stream

#### 2.1.2 Redis DLM（分布式锁）

当需求**可以接受不可靠**（即*容许锁语义被破坏的情况发生*）时，Redis 方案就能够足以胜任。
而容许不可靠的前提是*需求本身属于最终一致性*或*仅仅只是利用 DLM 来降低并发性*。
譬如*处理并发缓存更新问题时，即便有多条进程同时操作也无关紧要*。但在**无法接受不可靠**时，则不建议使用 Redis 来作为解决方案。根本原因在于其持久化机制并不可靠。
一旦锁状态丢失就会破坏*锁语义*（即*同步机制被破坏*），进而导致不一致。这对于大部分系统来说都是无法容忍的。即便官方提议使用[RedLock](https://redis.io/docs/latest/develop/use/patterns/distributed-locks/#the-redlock-algorithm)来解决不可靠性。
RedLock 算法的核心逻辑是通过实施[分布式仲裁（Quorum）](https://zh.m.wikipedia.org/zh-cn/Quorum_(%E5%88%86%E5%B8%83%E5%BC%8F%E7%B3%BB%E7%BB%9F))来提供*可靠性*和*一致性*。但鉴于其*实施成本（至少3个独立的Redis节点；官方推荐5个）*以及*没有解决所有问题*（如*网络分区*、*时间回拨*），所以建议还是选择更加可靠的方案（如*Etcd（Raft CP协议）*、*Zookeeper（ZAB CP协议）*）。但如果要坚持使用 Redis，则可以参考 [RedLock implementations](https://redis.io/docs/latest/develop/use/patterns/distributed-locks/#implementations)。

不论使用何种技术作为解决方案也无法忽视**死锁**问题。在 DLM 上下文中，死锁通常是由于持锁进程因为某些原因而未能正确释放锁而导致的。常见解决方案是引入**超时释放机制**（如*TTL*、*临时会话*）。然而，超时释放又引发出另一个需要思考的问题。即超时时间（`timeout`值）应该如何设置？针对该问题通常有两种解决思路，就是额外增加**时间续约机制**或 **[Fencing令牌](https://en.wikipedia.org/wiki/Fencing_(computing))**。*续约*可以避免`timeout`过小问题，而*Fencing令牌*则可以让持有过时锁的客户端自己回滚（。譬如在极端情况下，可解决锁因 GC 而*续约*失效的情况）。

如何基于 Redis 来实现 DLM，并非本文讨论范畴。这里仅提供大体的实现思路。
首先 Redis 并没有像*关系型数据库*那样提供*ACID事务*。它无法为多条指令提供原子性保证。针对该问题可使用*Lua脚本*来实现类似的需求。因为 Redis 会将*Lua脚本*视为一个单一指令。因此，只需相应地进行[防御性编程](https://zh.wikipedia.org/wiki/%E9%98%B2%E5%BE%A1%E6%80%A7%E7%BC%96%E7%A8%8B)，就能够一定地满足对原子性的需求。思路如下：
> **获取锁**：基于*Lua脚本*，使用`setnx lockName threadMsg`来竞争锁；成功后则为`lockName`设置初始`timeout`值。此外，锁被占用期间其他客户端依然会持续地尝试获取锁；为了降低其失败（或请求）频率，可以通过[指数退避算法](https://cloud.google.com/memorystore/docs/redis/exponential-backoff?hl=zh-cn)来解决。

> **死锁问题**：通过引入时间续约机制来解决。可在成功获取到锁后，创建一条负责续约的精灵线程；该线程可以持续地为`lockName`增加或重制`timeout`值。直到客户端主动释放锁（即移除`lockName`）为止

> **锁重入（是一个性能优化）问题**：锁重入指的是*持锁客户端应该能够再次获取（它所持有的）锁*。注意，这并非是一个必须解决的问题；具体需要根据实际的使用情况而定（即是否有重入的需求）。然而，即便是没有重入机制，锁服务（即在 Redis 上执行的*Lua脚本*）也应该理所当然地支持持锁客户端再次获取锁（譬如发现是持锁客户端时，就直接响应获取成功）。所以通常情况下，在 DLM 上下文中谈论锁重入并非真的需要解决重入问题，而是避免持锁客户端执行无谓的外部请求而损耗性能（，因为它本身已经获取到锁）。换言之，实际上真正需要的是一个避免持锁客户端再次获取锁的机制。该问题可以通过本地线程变量来解决；只需要在获取锁成功后，在本地线程上构建一个计数器即可；每一次获取都递增1，反之递减1；当递减到0时，就向锁服务移除持有标识（即`lockName`）。


### 2.2 缓存需求<em style="color: gray;">（第一原则：<em style="color: #df4a4d;">可接受数据最终一致</em>）</em>

#### 2.2.1 正确理解缓存

缓存的价值在于可以**加速或避免查询**。这里的“查询”泛指为*对SoR进行直接访问*和*执行繁重的计算*。

**使用缓存的第一原则是能够接受数据最终一致**。其背后的根本原因在于*缓存层*和*SoR*（通常）没有提供能够确保数据一致性的协议。换言之，只要数据源之间没有一致性协议，那么就必然存在数据一致性问题。
网上（和面试中）经常有人试图解决这一问题；但可以说完全是徒劳无功的。因为即便可以采用某种极端手段来使其达到强一致，但这已然失去了缓存的价值。即当同步成本大于其查询价值时，这种决策就已经说明是错误的。

为了提高缓存的使用效率，**最应该做的是合理地选择缓存目标**。
其实通常情况下，一个系统中的大部分查询都不要强一致。我们可以大体将查询划分为两种类型，*状态相关查询*和*非状态相关查询*。**非状态相关查询**（如*展示内容*）并不影响系统状态，所以无需强求强一致；大部分情况下都可以使用缓存来优化查询。**状态相关查询**就正好相反，应该保证强一致，避免使用缓存。

对于计算结果相关的查询，需要谨慎对待。只有计算结果属于*非状态相关查询*时，才应用使用缓存。
据经验之谈，好些开发者会因为图方便而将*计算结果*放入 Redis。这是不可取的，因为它并非可靠存储。如果有这方面的需求，建议使用分布式协调服务来解决。譬如*Zookeeper（ZAB CP协议）*、*Etcd（Raft CP协议）*、*Consul（Raft CP协议）* 这些。
<em style="color:gray;">
> 💡 在分布式系统中，服务之间应该避免透过**共享状态**来进行通信。因为这样会隐藏通信的复杂性。其状态维护工作会随着系统迭代而变得隐晦（譬如难以得知到底有谁在维护和使用它）。这种不透明性最终会导致系统变得难以维护。解决方法是使用*API*来替代*共享状态*。
</em>


#### 2.2.2 常见用例参考
- 静态内容（如：*静态页面或片段*）
- 仅需满足最终一致的数据（如：*外部系统查询*、*配置信息*）
- 用于展示的记录或文档、计算结果（如：*互动统计*）
- 社交媒体功能（如：追随者列表、关注者列表、@提及用户列表、互动用户列表）
- 体积较小的临时文件（如：*二维码图片*）。<em style="color:gray;">Redis Key 最大（长度）可为 512 MB</em>


#### 2.2.3 设计模式
⚠️ 设计模式只是指导；不是非此即彼。它们完全可以结合使用。

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
- 应用逻辑：将数据*预先地*、*定期地*加载到缓存层

本地缓存模式（Local Cache。也叫*进程缓存*）
- 特点：将数据直接缓存在客户端内存
- 应用逻辑：可用编程语言内置的标准库，或第三方缓存库来实现

缓存层即SoR模式（Cache as SoR）
- 特点：SoR 对于客户端而言是透明的，客户端仅需和缓存层交互
- 元模式：
    - 直读（Read Through）
        - 和*缓存端模式*一样，但由缓存层来实现
    - 直写（Write Through）
        - 客户端更新缓存层后，再由缓存层将状态*同步*写入 SoR
    - 后写（Write Back）
        - 和*直写*基本一致。但缓存层通过*异步*写入 SoR


#### 2.2.4 增强一致性

虽然*缓存层*和*SoR*基本上无法实现强一致，但却有方法使其实现真正的最终一致。
可以通过[CDC（Change data capture）](https://en.wikipedia.org/wiki/Change_data_capture)技术来监控 SoR 上的数据变更事件，然后透过消息队列将事件投递给缓存更新程序来实现这一目的。较为常用的*CDC*实现有*Debezium*、*Flink CDC*、*Apache SeaTunnel*、*Logstash*、*Alibaba Canal* 等，可根据实际情况来进行选择。


#### 2.2.5 应对极端情况

当系统需要应对**大流量**时，*缓存层*将会面临一系列考验。
从技术层面来说，*缓存层*除了能够<u>加速查询</u>之外，另一大价值在于可以<u>阻挡（部份）流量直接进入SoR</u>。因为大部分（尤其是业务型）系统的 SoR 依然在使用*关系型数据库*，但*关系型数据库*并不擅长应对大流量和大数据。此时，*缓存层*就起到了防御的作用。
然而在某些极端情况下，*缓存层*可能会失效。<u>一旦*缓存层*失效就可能会导致系统*性能骤降*，甚至*崩溃*</u>。譬如在系统流量高峰期见，*缓存层*因*过期策略（TTL）* 而失效，导致流量直击 SoR。而一旦 SoR 负载到底极限，就很可能会拖垮整个系统（或服务）。这一现象被称为**缓存击穿**，指的是*缓存层*突然失效就像是被大流量打穿了一样<span style="color: gray;">（。此外，*缓存击穿*还有一种极端称作**缓存雪崩**，指短时间内*缓存层*发生大面积失效）</span>。问题的解决思路如下：
- 在网关增加流量控制，以防过载（对生产环境进行压测然，再计算出流控精度）
- 在程序中增加一层*本地缓存*，避免过度依赖 Redis
- 采集并分析缓存（key）使用率，实现动态 Redis TTL 调整
- 使用*分布式锁*来控制缓存更新，避免并发访问 SoR
- 通过*客户端缓存（浏览器、App）* 或[内容分发网络（CDN）](https://aws.amazon.com/cn/what-is/cdn/)来降低系统流量
- <s style="color: gray;">不设置 Redis TTL，避免缓存过期（不推荐：长期占用内存会影响性能，而且还会加剧数据不一致）</s>
- 实施*高可用架构*可以有效地避免*缓存雪崩*。注意，在大流量分布式环境下可能会引发**热点（Hot Key）** 问题。譬如当某个拥有大量追随者的明星在社交媒体上发布动态时，那么这条动态就会迎来一大批高频流量。这种<u>热点现象会导致流量汇聚，严重起来甚至会瘫痪节点</u>。较为可行的解决方案是<u>将热点数据广播到所有节点，从而实现负载均衡（可参考[Hash tags](https://redis.io/docs/latest/operate/oss_and_stack/reference/cluster-spec/#key-distribution-model)进行实现）</u>。至于何谓*热点数据*，则取决于具体系统。例如在社交媒体中，拥有大量追随者的明星（帐号）就可以被定义为*热点*。他们所发的动态就应该被广播到所有的缓存节点上

除了*缓存击穿*外，还有一种称为**缓存穿透**的问题尤其需求注意。*穿透*指的是请求有意或无意地绕过了缓存层，导致流量直接落在 SoR 上。在缓存上下文中，*穿透*比*击穿*更容易发生。
常见有两种情况，一是<u>开发者没有意识到需要增加缓存</u>。这种情况通常比较好解决。只需在发现 *SoR 负载较高*、*查询较慢*、*优化过 SoR，但没什么效果* 后，及时引入缓存层即可。
二是<u>系统部署在公网上遭到恶意攻击</u>（。譬如使用根本不存在的标识发起大批量查询。因为根本没有数据，自然就无法命中缓存）。该问题的解决思路如下：
- 在网关采集流量特征，进行针对性限流
- 使用[Bloom filter](https://zh.wikipedia.org/zh-cn/%E5%B8%83%E9%9A%86%E8%BF%87%E6%BB%A4%E5%99%A8)或[Cuckoo filter](https://en.wikipedia.org/wiki/Cuckoo_filter)来阻挡恶意查询
- 引入[断路器（Circuit breaker）](https://zh.wikipedia.org/zh-cn/%E6%96%B7%E8%B7%AF%E5%99%A8%E8%A8%AD%E8%A8%88%E6%A8%A1%E5%BC%8F)，在必要时触发降级操作
- <s style="color: gray;">当查询（SoR）返回空时，就在缓存层中设置临时占位（不推荐：毫无意义。攻击者不会愚蠢到使用重复标识来进行攻击）</s>




## 3. 数据建模

如果对 NoSQL 建模没什么认识，可以先参考另一篇文章：[认识NoSQL建模]({{% ref "/posts/认识NoSQL建模/index.md" %}})。

在 NoSQL 上下文中进行数据建模需要关注两点，**系统实际的查询模式**和**NoSQL特性**。
前者很容易理解，**针对具体查询需求来进行建模**。
但后者在 Redis 中较为多样化，因为它提供了多种*数据结构*。这意味着它存在多种建模方案吗？希望不要掉进*技术思维陷阱*。
技术的价值仅在于服务需求。这应该被视为软件开发的*第一原则*。
**优秀的设计应该根据实际需求来进行技术选型**。即便它提供一万种*数据结构*，但在*第一原则*面前都只是特定场景下的工具，而不应该反作用于需求。如果不明白这一点，那么设计和开发出来的系统通常会是*难以使用和维护*的（。但凡从事过几年软件开发，就职过几家公司。就知道这并非危言耸听）。
    
只要不是在“错误”行径上使用 Redis（如前文提到的*共享状态*），就仍然可以选择**面向聚合建模**来作为解决方案。只需确保聚合位于*单个key*上即可。但**某些时候查询可能并不需要返回完整的聚合，特别是<u>聚合比较大（Big Key）</u>时**。虽然部份*数据结构*支持返回聚合的部份内容（譬如 map、json），但未必满足所有需求。此时可以通过*逻辑聚合*来解决该问题。
简单说，就是**使用[名称空间（namespace）](https://zh.wikipedia.org/wiki/%E5%91%BD%E5%90%8D%E7%A9%BA%E9%97%B4)来组织（逻辑）聚合。而在结构层面聚合会被拆分成不同的组成部份**。
但遗憾的是 Redis 对*命名空间*的支持比较有限。唯一的实现只有[逻辑数据库](https://redis.io/docs/latest/commands/select/)，而且通常还[不建议使用](https://groups.google.com/g/redis-db/c/vS5wX8X4Cjg/m/8ounBXitG4sJ)（。因为数量有限，且结构上并没有实现隔离）。
解决办法是**透过<u>对key进行规范化命名</u>来模拟命名空间**。
例如可以将*key名*格式限定为：`namespaceId:aggregationType:instanceId:instanceAttributeName`。
其中`namespaceId`可以是*租户标识*。`instanceAttributeName`代表聚合的*组成部份*，用于拆分聚合；且不同的*组成部份*可以根据实际需求来使用不同的*数据结构*。注意，该格式只是一个例子。你应该根据实际系统的需求来规范化*key名*格式。





## 参考
- [Redis persistence](https://redis.io/docs/latest/operate/oss_and_stack/management/persistence)
- [First principle](https://en.wikipedia.org/wiki/First_principle)
- [Distributed Locks with Redis](https://redis.io/docs/latest/develop/use/patterns/distributed-locks/)
- [How to do distributed locking](https://martin.kleppmann.com/2016/02/08/how-to-do-distributed-locking.html)
- [System of record](https://en.wikipedia.org/wiki/System_of_record)
- [Cache Usage Patterns](https://www.ehcache.org/documentation/3.10/caching-patterns.html)
- [7 Redis Worst Practices](https://redis.io/blog/7-redis-worst-practices/)
- [Redis Anti-Patterns Every Developer Should Avoid](https://redis.io/learn/howtos/antipatterns)
- [Why is Redis So Fast Despite Being Single-Threaded?](https://medium.com/@aditimishra_541/why-is-redis-so-fast-despite-being-single-threaded-dc06ba33fc75)
- [caffeine](https://github.com/ben-manes/caffeine)

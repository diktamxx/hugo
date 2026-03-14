---
title: "应用日志模式"
slug: "Application system log mode"
categories: ["软件架构"]
tags: ["软件架构"]
date: "2024-11-12"
cover: "images/cover.png"
thumbnail: "images/cover.png"
summary: "世事变，有没有将你掩盖。尽量框住目前，大概。 -- 沙龙•陈奕迅"
---

1、明确日志目的。应用日志的核心价值通常是作为问题排查的依据，其服务对象主要是开发人员和运维人员。所有在进行应用日志设计时，应该优先聆听服务对象的需求和期望。

2、应用日志属于时序数据，其信息价值会随着时间流逝而降低 —— 这有别于审计日志；审计日志一种追责依据，属于功能性需求，所以需要长期存储。所以应用日志最好根据实际情况进行截断保存。例如可以启用滚动策略来切割日志文件，或仅保留 90 天的日志等。这样做可以一定程度降低维护和云环境的费用成本。

3、结构化的应用日志有利于与其他可观测性系统进行集成。如 [Logfmt（键值对）](https://www.cloudbees.com/blog/logfmt-a-log-format-thats-easy-to-read-and-write) 或 JSON。对于 JSON 而言，目前常见的风格有 [Elastic Common Schema（ECS）](http://github.com/elastic/ecs)、[Graylog Extended Log Format（GELG）](https://go2docs.graylog.org/current/getting_in_log_data/gelf.html)、[Logstash JSON format](https://github.com/logfellow/logstash-logback-encoder?tab=readme-ov-file#standard-fields) 。值得注意，虽然结构化的日志有利于集成，但在没有格式化工具的情况下通常会降低可读性。如果这是一个问题，则可以考虑采用“半结构化”策略。即结合 Logfmt 和 JSON —— 如今的日志采集工具通常都支持正则匹配，所以不太会影响其可集成性。

4、善用应用日志级别
- Trace：代码执行轨迹
- Debug：值得关注的调试点
- Info：具有监控意义的普通事件
- Warn：潜在隐患事件。不影正确性，但需要关注。该类事件通常与服务质量属性相关。例如 触发了断路或限流、重试次数过多、执行效率低下 等等
- Error：异常事件。意味着代码存在逻辑性错误。会影响系统正确性，需要尽快修复

5、尽量避免通过字符串拼接方式构建日志信息，而是使用参数化日志（理由与第 6 点相同）。例如：
```java
logger.info("userId: " + userId)    // 避免
logger.info("userId: {}", userId)   // 推荐
```

6、较为重量的日志信息，应该先进行日志级别匹配再输出。这样做的目的是避免执行无谓的计算。譬如在需要构建对象或者执行计算时，可以这样：
```java
var foo = ...

// 方案1
if(logger.isInfoEnabled()) {
  logger.info(buildMessage(foo))
}

// 方案2 - slf4j 2.x
logger
  .atInfo()
  .addArgument((Supplier) () -> buildMessage(foo))
  .log("{}", foo);
```

7、必要时对敏感信息进行脱敏，防止信息外泄。

8、应用日志应该包含完整的事件信息。譬如：
- 识别标识
    - 客户端标识
    - 请求标识
    - 用户标识
    - 服务标识
    - 操作标识
- 执行了什么操作
- 为什么会失败（异常事件）

注意，调用链尾部（即栈顶）会缺乏上下文信息，因为栈顶所得到的信息通常是已经被转换或过滤的结果。解决方案有两种：一是使用上下文对象在调用栈中共享信息。可以简单地通过入参来实现，也可以基于 Java 中的 ThreadLocal、Scope Values 或 [slf4j mdc](https://www.slf4j.org/manual.html#mdc) 实现。二是依赖编程语言的异常捕获机制。栈顶方法可以将异常抛给上层来处理，然后由上层来采集足够的信息后输出日志。

9、时间信息统一使用 [UTC](https://en.wikipedia.org/wiki/Coordinated_Universal_Time) 和 [ISO-8601](https://en.wikipedia.org/wiki/ISO_8601) 标准，待必要时再在客户端进行时区转换。参考日志分析器：[hl](https://github.com/pamburus/hl)、[log-viewer](https://github.com/sevdokimov/log-viewer)、[Seq](https://datalust.co)

10、在分布式环境下，优先考虑使用 [CNCF](https://en.wikipedia.org/wiki/Cloud_Native_Computing_Foundation) 标准方式来采集日志。譬如：[OpenTelemetry](https://opentelemetry.io/zh)
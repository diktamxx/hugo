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

1⃣️ 明确日志目的。应用日志的核心价值是作为问题排查的依据，其服务对象是开发人员和运维人员。所有在设计日志时，应该优先考虑服务对象的情况。

2⃣️ 应用日志属于时序数据，其信息价值通常会随着时间流逝而降低。这有别于审计日志；审计日志一种追责机制，属于功能性需求；所以需要长期存储。而应用日志则应该根据实际情况来截断旧的部份。例如可以启用滚动策略来切分日志文件，或仅保留 90 天的日志等。这样可以一定程度降低维护和（云环境）费用成本。

3⃣️ 通过结构化应用日志来提高其集成性。例如 [Logfmt（键值对）](https://www.cloudbees.com/blog/logfmt-a-log-format-thats-easy-to-read-and-write) 或 JSON。对于 JSON 而言，目前常见的风格有 [Elastic Common Schema（ECS）](http://github.com/elastic/ecs)、[Graylog Extended Log Format（GELG）](https://go2docs.graylog.org/current/getting_in_log_data/gelf.html)、[Logstash JSON format](https://github.com/logfellow/logstash-logback-encoder?tab=readme-ov-file#standard-fields)。注意，虽然结构化的应用日志有利于采集，但在没有工具的情况下可能会变得难以阅读。如果这是一个考虑点，则可以考虑采用“半结构化”策略。也就是将主要观察的信息用 Logfmt 组织，而非主要关注的信息则用 JSON，最后将其进行拼接即可（。集成工具通常都支持正则匹配，所以也不太会影响其集成性）。

4⃣️ 善用应用日志级别
- Trace：代码执行轨迹
- Debug：值得关注的调试点
- Info：具有监控意义的普通事件
- Warn：潜在隐患事件。不影正确性，但需要关注。该类事件通常与服务质量属性相关。譬如：触发了断路或限流、重试次数过多、执行效率低下 等等
- Error：异常事件。意味着代码存在逻辑性错误。会影响系统正确性，需要尽快修复

5⃣️ 较为重量的应用日志应该先判断开启与否再进行调用，以避免执行无谓的方法调用。譬如需要构建对象或执行计算的日志。可以这样：if(isEnableInfo()) logger.info(buildLog(...))

6⃣️ 应用日志应该包含完整的上下文信息
- 识别标识
    - 客户端ID
    - 请求ID
    - 用户ID
    - 服务ID
    - 请求路径
- 执行了什么操作（请求信息），为什么会失败（异常信息）

注意，调用链尾部（即栈顶）会缺乏上下文信息，因为栈顶所得到的信息通常是已经被转换或过滤的结果。解决方案有两种：一是使用上下文对象在调用栈中共享信息。可以简单地通过入参来实现，也可以基于 Java 中的 ThreadLocal、Scope Values 或 [slf4j mdc](https://www.slf4j.org/manual.html#mdc) 实现。二是依赖编程语言的异常捕获机制。栈顶方法可以将异常抛给上层来处理，然后由上层来采集足够的信息后输出日志。

7⃣️ 对敏感信息进行脱敏，防止机密和用户信息外泄。

8⃣️ 时间戳统一使用 UTC 格式，等必要时再在客户端中进行转换。相关日志分析器：[hl](https://github.com/pamburus/hl)、[log-viewer](https://github.com/sevdokimov/log-viewer)、[Seq](https://datalust.co)

9⃣️ 在分布式环境下，使用标准方案来采集日志。譬如：[OpenTelemetry](https://opentelemetry.io/zh)
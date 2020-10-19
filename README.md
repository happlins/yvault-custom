# yfii yvault代码分析

#### 项目依赖

安装openzeppelin依赖
```shell script
npm i @openzeppelin/contracts@2.5.1
```

#### 项目基本结构

[controller](./contracts/controller): 用于控制token对应的vault和strategy，以及连接vault和strategy的关系

[harvest](./contracts/harvest): 奖励代币分发（奖励减半策略）

[strategy](./contracts/strategy): 投资策略

[token](./contracts/token): 激励代币  

[vault](./contracts/vault): 目标代币存储池(返回iToken)


#### 项目架构逻辑

![系统架构](./res/img/系统架构图.png)

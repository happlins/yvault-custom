# vault详解

#### 主要功能

用户充值 

1. depositAll   
2. deposit(uint _amount)

用户提现

1. withdrawAll
2. withdraw(uint _amount)

计算用户收入

持有的itoken * getPricePerFullShare()

#### 主要逻辑

1. 用户存入token后，合约返回收益代币iToken给用户，

2. 当该合约存储的代币数量大于设置的最小投资值，则自动进行投资，通过调用controller.earn方法调用strategy.deposit方法进行投资。

3. 用户获取收益时，通过持有的iToken按照比例获取Token
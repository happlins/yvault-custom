# strategy 投资策略

#### 核心方法(必须实现的方法)
```solidity
interface strategy {
  // controller会将该合约需要的token发送给本合约，同时调用该方法，进行投资
  function deposit() public;
  // must exclude any tokens used in the yield 
  // Controller role - withdraw should return to Controller
  function withdraw(address) public;
  // Controller | Vault role - withdraw should always return to vault
  function withdraw(uint) public;
  // Controller | Vault role - withdraw should always return to vault
  function withdrawAll() public;
  function balanceOf() public;
}
```

#### 主要逻辑

该系列合约的主要功能时，将vault存储的token发送到该合约对应的平台进行生息。

因此，需要了解其他平台的流动性池的合约代码，同时检查其安全性，并且需要了解对应平台的利率计算模型，算出对应的年化率。

**例如：**[strategyDforceUSDT](./strategyDforceUSDT.sol)合约，是Dforce平台的USDT池的投资策略合约。

1. 该合约首先会将USDT存储到Dforce的USDT pool中，得到dUSDT 收益凭证代币，并且随着存储的时间同时会获得df(Dforce发送的代币)代币.
2. 当我们需要提取收益时，首先通过收益凭证token取回USDT(包含存款利息)和df代币，通过uniswap将df交换为USDT，具体分配方案，如下所示，
- 目前是90%换成原来的token
- 10%换成yfii
    - 1% call fee
    - 1% 保险
    - 5% reward pool
    - 3% team
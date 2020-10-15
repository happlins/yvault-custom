# Controller 方法和功能总结

### 功能描述
controller主要用来控制vault和Strategy的对应关系，方便切换投资策略。

### 核心参数
```solidity
   // 代币交换地址,uniswap token交换合约地址
   address public onesplit;
   // 代币对应的存储池
   mapping(address => address) public vaults;
   // 代币对应的投资策略
   mapping(address => address) public strategies;
   // 不同代币之间的转换策略
   // 现在暂时没有做，不排除以后会做跨token投资
   mapping(address => mapping(address => address)) public converters;
```

### 核心方法
```solidity
interface Controller {
    // 返回指定token的vault地址
    function vaults(address) external view returns (address);
    // 返回指定token的strategy地址
    function strategy(address) external view returns (address);
    // 取款操作
    // 会更加给定的token选择合适的strategy，调用它的withdraw方法
    function withdraw(address, uint) external;
    // 投资
    // vault会将token发送controller，并调用该方法
    // 该方法会将token发送到strategy，并调用strategy.deposit方法
    function earn(address, uint) external;
    // 设置代币对应的存储池
    function setVault(address _token, address _vault) public;
    // 设置代币对应的策略器
    function setStrategy(address _token, address _strategy) public;
}
```


# 减半合约实验

#### 部署合约
```javascript
const NewToken = artifacts.require("NewToken")
const BeeHoney = artifacts.require("BeeHoney")
const BeeHoneyRewards = artifacts.require("BeeHoneyRewards")

const MetaCoin = artifacts.require("MetaCoin");

module.exports = async function (deployer, network, accounts) {
    // 部署两个测试token
    // NewToken 用于默认需要存储的代币
    deployer.deploy(NewToken, "NewToken", "NT")
    let newToken = await NewToken.deployed()
    // 添加铸币者
    newToken.addMinter.call(accounts[0])
    // BeeHoney 用于奖励代币
    deployer.deploy(BeeHoney, "BeeHoney", "BHY")
    let beeHoney = await BeeHoney.deployed()

    // 部署减半合约
    deployer.deploy(BeeHoneyRewards, NewToken.address, BeeHoney.address)
    let beeHoneyRewards = await BeeHoneyRewards.deployed()

    // 将减半合约添加到BeeHoney的铸币者中
    beeHoney.addMinter.call(BeeHoneyRewards.address)
};

```

#### 测试功能
```javascript
let newToken = await NewToken.deployed()
let beeHoney = await BeeHoney.deployed()
let beeHoneyRewards = await BeeHoneyRewards.deployed()

// 给指定地址充值newToken代币,(1000 nt)
newToken.mint.call(accounts[0],"100000000000000000000")
// 执行减半合约的notifyRewardAmount方法，初始化相关参数
// 传入参数需要和合约中的initreward的值保持一致
// 总计2000BHY个奖励，按照每15分钟减半一次
// 也可自行修改，initreward和DURATION参数
beeHoneyRewards.notifyRewardAmount.call(1000 * 1e18)

// 存钱500 nt token
// 报错，需要解决
beeHoneyRewards.state.call("50000000000000000000")

// 获取奖励，发送到用户账号上
beeHoneyRewards.getReward.call()

// 获取用户奖励数
beeHoneyRewards.earned.call(accounts[0])
```
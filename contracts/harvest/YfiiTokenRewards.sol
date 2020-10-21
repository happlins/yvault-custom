pragma solidity ^0.5.16;

import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";

// 用于兼容自定义token
interface Mint {
    function mint(address account, uint amount) external;
}

// File: contracts/IRewardDistributionRecipient.sol

contract IRewardDistributionRecipient is Ownable {
    address rewardDistribution;

    function notifyRewardAmount(uint256 reward) external;

    modifier onlyRewardDistribution() {
        require(_msgSender() == rewardDistribution, "Caller is not reward distribution");
        _;
    }

    function setRewardDistribution(address _rewardDistribution)
    external
    onlyOwner {
        rewardDistribution = _rewardDistribution;
    }
}

// File: contracts/CurveRewards.sol

contract LPTokenWrapper {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public y;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function stake(uint256 amount) public {
        _totalSupply = _totalSupply.add(amount);
        _balances[msg.sender] = _balances[msg.sender].add(amount);
        y.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint256 amount) public {
        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = _balances[msg.sender].sub(amount);
        y.safeTransfer(msg.sender, amount);
    }
}

contract YfiiTokenRewards is LPTokenWrapper, IRewardDistributionRecipient {
    IERC20 public bhy;
    uint256 public constant DURATION = 15 minutes;

    // 初始数量1000bhy
    uint256 public initreward = 1000 * 1e18;
    // 开始时间
    uint256 public starttime = 1595779200; //utc+8 2020 07-27 0:00:00
    // 当前期数的结束时间
    uint256 public periodFinish = 0;
    // 奖励率
    uint256 public rewardRate = 0;
    // 最后领取奖励时间
    uint256 public lastUpdateTime;
    // 每个token的奖励
    uint256 public rewardPerTokenStored;
    // 用户以领取的每块奖励，用于计算时，减去当前值
    mapping(address => uint256) public userRewardPerTokenPaid;
    // 地址对应的奖励数
    mapping(address => uint256) public rewards;

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);

    constructor (IERC20 _y, IERC20 _bhy) public {
        y = _y;
        bhy = _bhy;
    }

    // 查看奖励时间，
    // 如果当前时间，小于本期结束时间，返回当前时间
    // 如果当前时间大于本期结束时间，返回本期结束时间
    function lastTimeRewardApplicable() public view returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }

    // 每个token的奖励
    function rewardPerToken() public view returns (uint256) {
        if (totalSupply() == 0) {
            return rewardPerTokenStored;
        }
        return
        rewardPerTokenStored.add(
            lastTimeRewardApplicable()
            .sub(lastUpdateTime)
            .mul(rewardRate)
            .mul(1e18)
            .div(totalSupply())
        );
    }

    // 获取用户奖励数
    function earned(address account) public view returns (uint256) {
        return
        balanceOf(account)
        .mul(rewardPerToken().sub(userRewardPerTokenPaid[account]))
        .div(1e18)
        .add(rewards[account]);
    }

    // 更新奖励
    modifier updateReward(address account) {
        // 获取每块存储奖励
        rewardPerTokenStored = rewardPerToken();
        // 获取奖励时间
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            // 更新用户的奖励数
            rewards[account] = earned(account);
            // 更新用户当前每块的领取奖励
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    // 检查是否减半
    modifier checkhalve() {
        if (block.timestamp >= periodFinish) {
            // 减半
            initreward = initreward.mul(49).div(100);
            // 铸币
            Mint(address(bhy)).mint(address(this), initreward);

            // 奖励速率
            rewardRate = initreward.div(DURATION);
            // 本期，结束时间
            periodFinish = block.timestamp.add(DURATION);
            emit RewardAdded(initreward);
        }
        _;
    }

    // 检查是否开始
    modifier checkStart() {
        require(block.timestamp > starttime, "not start");
        _;
    }


    // stake visibility is public as overriding LPTokenWrapper's stake() function
    // 存款方法，调用了LPTokenWrapper的方法stake，用于保存每个地址对应的token数
    function stake(uint256 amount) public updateReward(msg.sender) checkhalve checkStart {
        require(amount > 0, "Cannot stake 0");
        super.stake(amount);
        emit Staked(msg.sender, amount);
    }

    // 取款
    // 调用了LPTokenWrapper的方法withdraw
    function withdraw(uint256 amount) public updateReward(msg.sender) checkhalve checkStart {
        require(amount > 0, "Cannot withdraw 0");
        super.withdraw(amount);
        emit Withdrawn(msg.sender, amount);
    }

    // 退出
    function exit() external {
        // 取出所有的钱
        withdraw(balanceOf(msg.sender));
        // 获取的奖励
        getReward();
    }

    // 获得奖励
    function getReward() public updateReward(msg.sender) checkhalve checkStart {
        // 获取用户的奖励数
        uint256 reward = earned(msg.sender);
        if (reward > 0) {
            rewards[msg.sender] = 0;
            // 将奖励发送给用户
            bhy.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }


    function notifyRewardAmount(uint256 reward)
    external
    onlyRewardDistribution
    updateReward(address(0)) {
        // 当前块时间大于本期结束时间
        if (block.timestamp >= periodFinish) {
            rewardRate = reward.div(DURATION);
        } else {
            uint256 remaining = periodFinish.sub(block.timestamp);
            uint256 leftover = remaining.mul(rewardRate);
            rewardRate = reward.add(leftover).div(DURATION);
        }
        Mint(address(bhy)).mint(address(this), reward);
        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp.add(DURATION);
        emit RewardAdded(reward);
    }
}
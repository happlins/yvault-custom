/**
 *Submitted for verification at Etherscan.io on 2020-08-13
*/

// SPDX-License-Identifier: MIT

pragma solidity ^0.5.17;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Detailed.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "../interfaces/IController.sol";
import "../interfaces/dforce/DRewards.sol";
import "../interfaces/dforce/DERC20.sol";
import "../interfaces/uni/IUniswapRouter.sol";

/*

 A strategy must implement the following calls;
 
 - deposit()
 - withdraw(address) must exclude any tokens used in the yield - Controller role - withdraw should return to Controller
 - withdraw(uint) - Controller | Vault role - withdraw should always return to vault
 - withdrawAll() - Controller | Vault role - withdraw should always return to vault
 - balanceOf()
 
 Where possible, strategies must remain as immutable as possible, instead of updating variables, we update the contract by linking it in the controller
 
*/

contract StrategyDforceUSDT {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    // USDT
    address constant public want = address(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    // Dforce合约的地址
    address constant public d = address(0x868277d475E0e475E38EC5CdA2d9C83B5E1D9fc8);
    // dforce质押池地址
    address constant public pool = address(0x324EebDAa45829c6A8eE903aFBc7B61AF48538df);
    // 得到的token，df代币
    address constant public output = address(0x431ad2ff6a9C365805eBaD47Ee021148d6f7DBe0);
    // uniswap交换地址
    address constant public unirouter = address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    // 中间token
    address constant public weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // used for df <> weth <> usdc route

    // yfii token地址
    address constant public yfii = address(0xa1d0E215a23d7030842FC67cE582a6aFa3CCaB83);



    // 开发人员比例数和保险比例数
    uint public fee = 400;
    // 基金会比例数
    uint public burnfee = 500;
    // 合约调用比例数
    uint public callfee = 100;
    // 全部收益
    uint constant public max = 1000;

    uint public withdrawalFee = 0;
    uint constant public withdrawalMax = 10000;

    // 管理员地址
    address public governance;
    // controller 地址
    address public controller;
    // 基金会地址
    address public burnAddress = 0xB6af2DabCEBC7d30E440714A33E5BD45CEEd103a;

    string public getName;

    // uniswap通过df得到yfii
    address[] public swap2YFIIRouting;
    // uniswap通过df得到usdt
    address[] public swap2TokenRouting;


    constructor() public {
        governance = msg.sender;
        controller = 0xe14e60d0F7fb15b1A98FDE88A3415C17b023bf36;
        getName = string(
            abi.encodePacked("yfii:Strategy:",
            abi.encodePacked(ERC20Detailed(want).name(), "DF Token"
            )
            ));
        swap2YFIIRouting = [output, weth, yfii];
        swap2TokenRouting = [output, weth, want];
        doApprove();
    }

    function doApprove() public {
        IERC20(output).safeApprove(unirouter, 0);
        IERC20(output).safeApprove(unirouter, uint(- 1));
    }


    function deposit() public {
        // 获取USDT的余额
        uint _want = IERC20(want).balanceOf(address(this));
        if (_want > 0) {
            // 授权
            IERC20(want).safeApprove(d, 0);
            IERC20(want).safeApprove(d, _want);
            // 质押，获取dUSDT token（质押凭证）
            dERC20(d).mint(address(this), _want);
        }

        // 获取dUSDT数量
        uint _d = IERC20(d).balanceOf(address(this));
        if (_d > 0) {
            // 授权
            IERC20(d).safeApprove(pool, 0);
            IERC20(d).safeApprove(pool, _d);
            // 质押dUSDT
            dRewards(pool).stake(_d);
        }

    }

    // Controller only function for creating additional rewards from dust
    function withdraw(IERC20 _asset) external returns (uint balance) {
        require(msg.sender == controller, "!controller");
        require(want != address(_asset), "want");
        require(d != address(_asset), "d");
        balance = _asset.balanceOf(address(this));
        _asset.safeTransfer(controller, balance);
    }

    // Withdraw partial funds, normally used with a vault withdrawal
    function withdraw(uint _amount) external {
        require(msg.sender == controller, "!controller");
        uint _balance = IERC20(want).balanceOf(address(this));
        if (_balance < _amount) {
            _amount = _withdrawSome(_amount.sub(_balance));
            _amount = _amount.add(_balance);
        }

        uint _fee = 0;
        if (withdrawalFee > 0) {
            _fee = _amount.mul(withdrawalFee).div(withdrawalMax);
            IERC20(want).safeTransfer(IController(controller).rewards(), _fee);
        }


        address _vault = IController(controller).vaults(address(want));
        require(_vault != address(0), "!vault");
        // additional protection so we don't burn the funds
        IERC20(want).safeTransfer(_vault, _amount.sub(_fee));
    }

    // Withdraw all funds, normally used when migrating strategies
    function withdrawAll() external returns (uint balance) {
        require(msg.sender == controller, "!controller");
        _withdrawAll();


        balance = IERC20(want).balanceOf(address(this));

        address _vault = IController(controller).vaults(address(want));
        require(_vault != address(0), "!vault");
        // additional protection so we don't burn the funds
        IERC20(want).safeTransfer(_vault, balance);
    }

    function _withdrawAll() internal {
        dRewards(pool).exit();
        uint _d = IERC20(d).balanceOf(address(this));
        if (_d > 0) {
            dERC20(d).redeem(address(this), _d);
        }
    }

    function harvest() public {
        require(!Address.isContract(msg.sender), "!contract");
        dRewards(pool).getReward();

        doswap();
        // 将获得的df转成usdt和yfii
        dosplit();
        //分yfii
        deposit();
    }

    function doswap() internal {
        // 90%的收益给用户
        uint256 _2token = IERC20(output).balanceOf(address(this)).mul(90).div(100);
        // 10%的收益转换为yfii，用于说明中的用途
        uint256 _2yfii = IERC20(output).balanceOf(address(this)).mul(10).div(100);
        IUniswapRouter(unirouter).swapExactTokensForTokens(_2token, 0, swap2TokenRouting, address(this), now.add(1800));
        IUniswapRouter(unirouter).swapExactTokensForTokens(_2yfii, 0, swap2YFIIRouting, address(this), now.add(1800));
    }

    function dosplit() internal {
        uint b = IERC20(yfii).balanceOf(address(this));
        uint _fee = b.mul(fee).div(max);
        uint _callfee = b.mul(callfee).div(max);
        uint _burnfee = b.mul(burnfee).div(max);
        // 将上面获取的10%收益做以下划分
        // 3%给开发人员,1%保险费用
        IERC20(yfii).safeTransfer(IController(controller).rewards(), _fee);
        // 调用合约费用，1%
        IERC20(yfii).safeTransfer(msg.sender, _callfee);
        // 5%给基金会用于回购
        IERC20(yfii).safeTransfer(burnAddress, _burnfee);
        //burn fee 5%
    }

    function _withdrawSome(uint256 _amount) internal returns (uint) {
        uint _d = _amount.mul(1e18).div(dERC20(d).getExchangeRate());
        uint _before = IERC20(d).balanceOf(address(this));
        dRewards(pool).withdraw(_d);
        uint _after = IERC20(d).balanceOf(address(this));
        uint _withdrew = _after.sub(_before);
        _before = IERC20(want).balanceOf(address(this));
        dERC20(d).redeem(address(this), _withdrew);
        _after = IERC20(want).balanceOf(address(this));
        _withdrew = _after.sub(_before);
        return _withdrew;
    }

    // 获取USDT数量
    function balanceOfWant() public view returns (uint) {
        return IERC20(want).balanceOf(address(this));
    }

    // 通过dforce USDT pool池，获取USDT的数量（包括利息）
    function balanceOfPool() public view returns (uint) {
        return (dRewards(pool).balanceOf(address(this))).mul(dERC20(d).getExchangeRate()).div(1e18);
    }

    function getExchangeRate() public view returns (uint) {
        return dERC20(d).getExchangeRate();
    }

    function balanceOfD() public view returns (uint) {
        return dERC20(d).getTokenBalance(address(this));
    }

    function balanceOf() public view returns (uint) {
        return balanceOfWant()
        .add(balanceOfD())
        .add(balanceOfPool());
    }

    function setGovernance(address _governance) external {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    function setController(address _controller) external {
        require(msg.sender == governance, "!governance");
        controller = _controller;
    }

    function setFee(uint256 _fee) external {
        require(msg.sender == governance, "!governance");
        fee = _fee;
    }

    function setCallFee(uint256 _fee) external {
        require(msg.sender == governance, "!governance");
        callfee = _fee;
    }

    function setBurnFee(uint256 _fee) external {
        require(msg.sender == governance, "!governance");
        burnfee = _fee;
    }

    function setBurnAddress(address _burnAddress) public {
        require(msg.sender == governance, "!governance");
        burnAddress = _burnAddress;
    }

    function setWithdrawalFee(uint _withdrawalFee) external {
        require(msg.sender == governance, "!governance");
        require(_withdrawalFee <= 100, "fee >= 1%");
        //max:1%
        withdrawalFee = _withdrawalFee;
    }
}
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

/*
  使用Dforce平台在，kovan测试网上部署的合约
  合约地址
  USDT: "0x07de306FF27a2B630B1141956844eB1552B956B5",
  dUSDT: "0x4c153111272cB826A80627c4A51c48ccB7d3153B",
*/

contract StrategyDforceUSDTKovan {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    // USDT
    address constant public want = address(0x07de306FF27a2B630B1141956844eB1552B956B5);
    // Dforce合约的地址
    address constant public d = address(0x4c153111272cB826A80627c4A51c48ccB7d3153B);

    // 管理员地址
    address public governance;
    // controller 地址
    address public controller;

    string public getName;

    uint public withdrawalFee = 0;
    uint constant public withdrawalMax = 10000;

    constructor(address _controller) public {
        governance = msg.sender;
        controller = _controller;
        getName = string(
            abi.encodePacked("bee:Strategy:",
            abi.encodePacked(ERC20Detailed(want).name(), "DF Token"
            )
            ));
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
        uint _d = IERC20(d).balanceOf(address(this));
        if (_d > 0) {
            dERC20(d).redeem(address(this), _d);
        }
    }

    function _withdrawSome(uint256 _amount) internal returns (uint) {
        uint _d = _amount.mul(1e18).div(dERC20(d).getExchangeRate());
        uint _before = IERC20(want).balanceOf(address(this));
        dERC20(d).redeem(address(this), _d);
        uint _after = IERC20(want).balanceOf(address(this));
        uint _withdrew = _after.sub(_before);
        return _withdrew;
    }

    // 获取USDT数量
    function balanceOfWant() public view returns (uint) {
        return IERC20(want).balanceOf(address(this));
    }

    function balanceOfD() public view returns (uint) {
        return dERC20(d).getTokenBalance(address(this));
    }

    function balanceOf() public view returns (uint) {
        return balanceOfWant()
        .add(balanceOfD());
    }

    function setGovernance(address _governance) external {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    function setController(address _controller) external {
        require(msg.sender == governance, "!governance");
        controller = _controller;
    }
}
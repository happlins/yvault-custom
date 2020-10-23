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
import "../interfaces/uni/IUniswapRouter.sol";
import "../interfaces/comp/IComptroller.sol";
import "../interfaces/comp/ICErc20Delegator.sol";

/*

 A strategy must implement the following calls;

 - deposit()
 - withdraw(address) must exclude any tokens used in the yield - Controller role - withdraw should return to Controller
 - withdraw(uint) - Controller | Vault role - withdraw should always return to vault
 - withdrawAll() - Controller | Vault role - withdraw should always return to vault
 - balanceOf()

 Where possible, strategies must remain as immutable as possible, instead of updating variables, we update the contract by linking it in the controller

*/


contract StrategyCompUSDTKovan {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    // USDT
    address constant public want = address(0x07de306FF27a2B630B1141956844eB1552B956B5);
    // cUSDT 合约地址
    address constant public c = address(0x3f0A0EA2f86baE6362CF9799B523BA06647Da018);
    // comp 代币地址
    address constant public comp = address(0x61460874a7196d6a22D1eE4922473664b3E95270);
    // Comptroller 用于获取comp代币
    address constant public comptroller = address(0x5eAe89DC1C671724A672ff0630122ee834098657);

    // uni合约地址
    address constant public unirouter = address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    // 管理员地址
    address public governance;
    // controller 地址
    address public controller;

    string public getName;

    uint public withdrawalFee = 0;
    uint constant public withdrawalMax = 10000;

    address[] public swap2TokenRouting;

    constructor(address _controller) public {
        governance = msg.sender;
        controller = _controller;
        getName = string(
            abi.encodePacked("bee:Strategy:",
            abi.encodePacked(ERC20Detailed(want).name(), "DF Token"
            )
            ));
        swap2TokenRouting = [comp, want];
    }


    function deposit() public {
        // 获取USDT的余额
        uint _want = IERC20(want).balanceOf(address(this));
        if (_want > 0) {
            // 授权
            IERC20(want).safeApprove(c, 0);
            IERC20(want).safeApprove(c, _want);
            // 质押，获取cUSDT token（质押凭证）
            ICErc20Delegator(c).mint(_want);
        }
    }

    // Controller only function for creating additional rewards from dust
    function withdraw(IERC20 _asset) external returns (uint balance) {
        require(msg.sender == controller, "!controller");
        require(want != address(_asset), "want");
        require(c != address(_asset), "d");
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
        uint _c = ICErc20Delegator(c).balanceOf(address(this));
        if (_c > 0) {
            ICErc20Delegator(c).redeem(_c);
        }
    }


    function harvest() public {
        require(!Address.isContract(msg.sender), "!contract");
        // 取出所有comp
        IComptroller(comptroller).claimComp(address(this));

        uint _before = IERC20(want).balanceOf(address(this));
        uint compAmout = IERC20(comp).balanceOf(address(this));
        IUniswapRouter(unirouter).swapExactTokensForTokens(compAmout, 0, swap2TokenRouting, address(this), now.add(1800));
        uint _after = IERC20(want).balanceOf(address(this));

        uint tokenRewards = _after.sub(_before);

        // 基金会利润
        uint burnfee = tokenRewards.mul(15).div(100);
        IERC20(want).safeTransfer(IController(controller).rewards(), burnfee);
        // 把剩下的钱继续拿去存
        deposit();
    }


    function _withdrawSome(uint256 _amount) internal returns (uint) {
        uint _before = IERC20(want).balanceOf(address(this));
        ICErc20Delegator(c).redeemUnderlying(_amount);
        uint _after = IERC20(want).balanceOf(address(this));
        uint _withdrew = _after.sub(_before);
        return _withdrew;
    }

    // 获取USDT数量
    function balanceOfWant() public view returns (uint) {
        return IERC20(want).balanceOf(address(this));
    }

    function balanceOfC() public view returns (uint) {
        return ICErc20Delegator(c).balanceOf(address(this)).mul(ICErc20Delegator(c).exchangeRateStored().div(1e18));
    }

    function balanceOf() public view returns (uint) {
        return balanceOfWant()
        .add(balanceOfC());
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
/**
 *Submitted for verification at Etherscan.io on 2020-07-31
*/

// SPDX-License-Identifier: MIT

pragma solidity ^0.5.15;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Detailed.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "../interfaces/IController.sol";
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

interface Yam {
    function withdraw(uint) external;

    function getReward() external;

    function stake(uint) external;

    function balanceOf(address) external view returns (uint);

    function exit() external;

    function earned(address) external view returns (uint);
}



contract Strategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address public pool;
    address public output;
    string public getName;

    address constant public yfii = address(0xa1d0E215a23d7030842FC67cE582a6aFa3CCaB83);
    address constant public unirouter = address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    address constant public weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address constant public dai = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    address constant public ycrv = address(0xdF5e0e81Dff6FAF3A7e52BA697820c5e32D806A8);

    uint public fee = 400; //300 + 100
    uint public callfee = 100;
    uint public burnfee = 500;
    uint constant public max = 1000;


    uint public withdrawalFee = 10;
    uint constant public withdrawalMax = 10000;

    address public governance;
    address public controller;

    address  public want;

    address[] public swap2YFIIRouting;
    address[] public swap2TokenRouting;

    constructor(address _output, address _pool, address _want) public {
        governance = tx.origin;
        controller = 0xe14e60d0F7fb15b1A98FDE88A3415C17b023bf36;
        output = _output;
        pool = _pool;
        want = _want;
        getName = string(
            abi.encodePacked("yfii:Strategy:",
            abi.encodePacked(ERC20Detailed(want).name(),
            abi.encodePacked(":", ERC20Detailed(output).name())
            )
            ));
        doApprove();
        swap2YFIIRouting = [output, ycrv, weth, yfii];
        swap2TokenRouting = [output, ycrv, want];

    }

    function deposit() public {
        IERC20(want).safeApprove(pool, 0);
        IERC20(want).safeApprove(pool, IERC20(want).balanceOf(address(this)));
        Yam(pool).stake(IERC20(want).balanceOf(address(this)));
    }

    // Controller only function for creating additional rewards from dust
    function withdraw(IERC20 _asset) external returns (uint balance) {
        require(msg.sender == controller, "!controller");
        require(want != address(_asset), "want");
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

        uint _fee = _amount.mul(withdrawalFee).div(withdrawalMax);
        IERC20(want).safeTransfer(IController(controller).rewards(), _fee);

        address _vault = IController(controller).vaults(address(want));
        require(_vault != address(0), "!vault");
        // additional protection so we don't burn the funds
        IERC20(want).safeTransfer(_vault, _amount.sub(_fee));
    }

    // Withdraw all funds, normally used when migrating strategies
    function withdrawAll() public returns (uint balance) {
        require(msg.sender == controller || msg.sender == governance, "!controller");
        _withdrawAll();
        balance = IERC20(want).balanceOf(address(this));

        address _vault = IController(controller).vaults(address(want));
        require(_vault != address(0), "!vault");
        // additional protection so we don't burn the funds
        IERC20(want).safeTransfer(_vault, balance);

    }

    function _withdrawAll() internal {
        Yam(pool).exit();
    }

    function doApprove() public {
        IERC20(output).safeApprove(unirouter, uint(- 1));
    }

    function setNewPool(address _output, address _pool) public {
        require(msg.sender == governance, "!governance");
        //这边是切换池子以及挖到的代币
        //先退出之前的池子.
        harvest();
        withdrawAll();
        output = _output;
        pool = _pool;
        getName = string(
            abi.encodePacked("yfii:Strategy:",
            abi.encodePacked(ERC20Detailed(want).name(),
            abi.encodePacked(":", ERC20Detailed(output).name())
            )
            ));

    }

    function harvest() public {
        require(!Address.isContract(msg.sender), "!contract");
        Yam(pool).getReward();
        address _vault = IController(controller).vaults(address(want));
        require(_vault != address(0), "!vault");
        // additional protection so we don't burn the funds

        doswap();
        // fee
        uint b = IERC20(yfii).balanceOf(address(this));
        uint _fee = b.mul(fee).div(max);
        uint _callfee = b.mul(callfee).div(max);
        uint _burnfee = b.mul(burnfee).div(max);
        //4%  3% team +1% insurance
        IERC20(yfii).safeTransfer(IController(controller).rewards(), _fee);
        //call fee 1%
        IERC20(yfii).safeTransfer(msg.sender, _callfee);
        //TODO:把销毁地址改为 reward pool地址
        //burn fee 5%
        IERC20(yfii).safeTransfer(IController(controller).rewards(), _burnfee);

        deposit();

    }

    function doswap() internal {
        //output -> eth ->yfii
        uint256 _2token = IERC20(output).balanceOf(address(this)).mul(90).div(100);
        //90%
        uint256 _2yfii = IERC20(output).balanceOf(address(this)).mul(10).div(100);
        //10%
        IUniswapRouter(unirouter).swapExactTokensForTokens(_2token, 0, swap2TokenRouting, address(this), now.add(1800));
        IUniswapRouter(unirouter).swapExactTokensForTokens(_2yfii, 0, swap2YFIIRouting, address(this), now.add(1800));

    }

    function _withdrawSome(uint256 _amount) internal returns (uint) {
        Yam(pool).withdraw(_amount);
        return _amount;
    }


    function balanceOf() public view returns (uint) {
        return Yam(pool).balanceOf(address(this));

    }

    function balanceOfPendingReward() public view returns (uint){//还没有领取的收益有多少...
        return Yam(pool).earned(address(this));
    }

    function harvertYFII() public view returns (uint[] memory amounts){//未收割的token 能换成多少yfii
        uint _pendingReward = balanceOfPendingReward().mul(10).div(100);
        //10%
        return IUniswapRouter(unirouter).getAmountsOut(_pendingReward, swap2YFIIRouting);
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

    function setswap2YFIIRouting(address[] memory _path) public {
        require(msg.sender == governance, "!governance");
        swap2YFIIRouting = _path;
    }

    function setswap2TokenRouting(address[] memory _path) public {
        require(msg.sender == governance, "!governance");
        swap2TokenRouting = _path;
    }

    function setWithdrawalFee(uint _withdrawalFee) external {
        require(msg.sender == governance, "!governance");
        withdrawalFee = _withdrawalFee;
    }
}
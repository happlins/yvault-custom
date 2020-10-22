/**
 *Submitted for verification at Etherscan.io on 2020-08-13
*/

pragma solidity ^0.5.17;

import "github.com/OpenZeppelin/openzeppelin-contracts/blob/v2.5.1/contracts/token/ERC20/ERC20Detailed.sol";
import "github.com/OpenZeppelin/openzeppelin-contracts/blob/v2.5.1/contracts/token/ERC20/ERC20.sol";
import "github.com/OpenZeppelin/openzeppelin-contracts/blob/v2.5.1/contracts/token/ERC20/SafeERC20.sol";
import "github.com/OpenZeppelin/openzeppelin-contracts/blob/v2.5.1/contracts/math/SafeMath.sol";
import "github.com/OpenZeppelin/openzeppelin-contracts/blob/v2.5.1/contracts/utils/Address.sol";

import "../interfaces/IController.sol";

contract iVault is ERC20, ERC20Detailed {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    IERC20 public token;

    // 下面两个参数用户，将95%的资金用于投资
    uint public min = 9500;
    uint public constant max = 10000;
    uint public earnLowerlimit; //池内空余资金到这个值就自动earn

    // 管理员地址
    address public governance;
    // controller地址
    address public controller;

    constructor (address _controller, address _token, uint _earnLowerlimit) public ERC20Detailed(
        string(abi.encodePacked("BeeHoney ", ERC20Detailed(_token).name())),
        string(abi.encodePacked("b", ERC20Detailed(_token).symbol())),
        ERC20Detailed(_token).decimals()
    ) {
        token = IERC20(_token);
        governance = tx.origin;
        controller = _controller;
        earnLowerlimit = _earnLowerlimit;
    }

    function balance() public view returns (uint) {
        return token.balanceOf(address(this))
        .add(Controller(controller).balanceOf(address(token)));
    }

    function setMin(uint _min) external {
        require(msg.sender == governance, "!governance");
        min = _min;
    }

    function setGovernance(address _governance) public {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    function setController(address _controller) public {
        require(msg.sender == governance, "!governance");
        controller = _controller;
    }

    function setEarnLowerlimit(uint256 _earnLowerlimit) public {
        require(msg.sender == governance, "!governance");
        earnLowerlimit = _earnLowerlimit;
    }

    // 允许投资的最大金额
    // 保证有足够的资金用于提款
    function available() public view returns (uint) {
        return token.balanceOf(address(this)).mul(min).div(max);
    }

    // 投资，通过controller的earn调用，strategy的deposit方法，进行投资
    function earn() public {
        uint _bal = available();
        token.safeTransfer(controller, _bal);
        Controller(controller).earn(address(token), _bal);
    }

    function depositAll() external {
        deposit(token.balanceOf(msg.sender));
    }

    function deposit(uint _amount) public {
        // 对应token池中，现存的余额（vault+strategy（还没有被投资的余额））
        uint _pool = balance();
        uint _before = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), _amount);
        uint _after = token.balanceOf(address(this));
        // 存币的数量
        _amount = _after.sub(_before);
        // 通缩令牌的附加检查
        uint shares = 0;
        // 以发布的Btoken数量
        if (totalSupply() == 0) {
            shares = _amount;
        } else {
            shares = (_amount.mul(totalSupply())).div(_pool);
        }
        _mint(msg.sender, shares);
        if (token.balanceOf(address(this)) > earnLowerlimit) {
            earn();
        }
    }

    function withdrawAll() external {
        withdraw(balanceOf(msg.sender));
    }



    // No rebalance implementation for lower fees and faster swaps
    function withdraw(uint _shares) public {
        uint r = (balance().mul(_shares)).div(totalSupply());
        _burn(msg.sender, _shares);

        // Check balance
        uint b = token.balanceOf(address(this));
        if (b < r) {
            uint _withdraw = r.sub(b);
            Controller(controller).withdraw(address(token), _withdraw);
            uint _after = token.balanceOf(address(this));
            uint _diff = _after.sub(b);
            if (_diff < _withdraw) {
                r = b.add(_diff);
            }
        }

        token.safeTransfer(msg.sender, r);
    }

    function getPricePerFullShare() public view returns (uint) {
        return balance().mul(1e18).div(totalSupply());
    }
}
pragma solidity ^0.5.17;

interface ICErc20Delegator {
    // 存款
    function mint(uint mintAmount) external returns (uint);
    // 获取CToken的数量
    function balanceOf(address owner) external view returns (uint);
    // 通过CToken数量获取Token
    function redeem(uint redeemTokens) external returns (uint);
    // 获取指定数量的Token
    function redeemUnderlying(uint redeemAmount) external returns (uint);
    // 获取token和Ctoken之间的利率
    function exchangeRateStored() external view returns (uint);

}
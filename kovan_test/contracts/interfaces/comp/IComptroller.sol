pragma solidity ^0.5.17;


// 取comp的方法
interface IComptroller {
    function claimComp(address) external;
}
const Controller = artifacts.require("Controller")
const USDTVault = artifacts.require("iVault")
const StrategyDforceUSDTKovan = artifacts.require("StrategyDforceUSDTKovan")
const USDT = "0x07de306FF27a2B630B1141956844eB1552B956B5"

module.exports = async function (deployer, network, accounts) {
    // 部署controller
    await deployer.deploy(Controller, accounts[0])
    let controller = await Controller.deployed()
    // 设置管理员
    await controller.setGovernance(accounts[0])

    // 部署USDT vault
    await deployer.deploy(USDTVault, controller.address, USDT, "100000000")
    let iUSDT = await USDTVault.deployed()
    // 设置管理员
    await iUSDT.setGovernance(accounts[0])

    // 部署strategy
    await deployer.deploy(StrategyDforceUSDTKovan, controller.address)
    let strategyDforceUSDTKovan = await StrategyDforceUSDTKovan.deployed()
    // 设置管理员
    await strategyDforceUSDTKovan.setGovernance(accounts[0])

    // 设置USDT对应的vault和strategy
    await controller.setVault(USDT, iUSDT.address)
    await controller.setStrategy(USDT, strategyDforceUSDTKovan.address)
};
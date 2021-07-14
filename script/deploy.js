const BigNumber = require("bignumber.js");

const fs = require("fs");
const file = fs.createWriteStream("./deploy-logger.js", { 'flags': 'w'});
let logger = new console.Console(file, file);

const decimalStr = (value) => {
  return new BigNumber(value).multipliedBy(10 ** 18).toFixed(0, BigNumber.ROUND_DOWN)
}

const MAX = ethers.BigNumber.from('0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff')
const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000'


async function main() {
  // We get the contract to deploy
    [deployer, alice, bob] = await ethers.getSigners()
    deployer.name = 'deployer'
    alice.name = 'alice'
    bob.name = 'bob'

    usdt = await (await ethers.getContractFactory('TERC20')).deploy('Test USDT', 'USDT', 6)
    pricing = await (await ethers.getContractFactory('PMMPricing')).deploy()
    everlastingOptionPricing = await (await ethers.getContractFactory('EverlastingOptionPricing')).deploy()
    lToken = await (await ethers.getContractFactory('LTokenOption')).deploy('Deri Liquidity Token', 'DLT')
    pToken = await (await ethers.getContractFactory('PTokenOption')).deploy('Deri Position Token', 'DPT')
    pool = await (await ethers.getContractFactory('EverlastingOption')).deploy(
        pricing.address,
        everlastingOptionPricing.address,
        [
            decimalStr("1"),      // minPoolMarginRatio
            decimalStr("0.1"),  // minInitialMarginRatio
            decimalStr("0.05"),  // minMaintenanceMarginRatio
            decimalStr("10"),    // minLiquidationReward
            decimalStr("1000"),   // maxLiquidationReward
            decimalStr("0.5"),  // liquidationCutRatio
            decimalStr("0.2")   // protocolFeeCollectRatio
        ],
        [
            usdt.address,     // bTokenAddress
            lToken.address,   // lTokenAddress
            pToken.address,   // pTokenAddress
            ZERO_ADDRESS,     // liquidatorQualifierAddress
            deployer.address, // protocolFeeCollector
        ]
    )


    logger.log("deployer", deployer.address)
    logger.log("usdt.address", usdt.address)
    logger.log("lToken.address", lToken.address)
    logger.log("pToken.address", pToken.address)
    logger.log("pricing.address", pricing.address)
    logger.log("pool.address", pool.address)


    await lToken.setPool(pool.address)
    await pToken.setPool(pool.address)

    oracleBTCUSD = await ethers.getContractAt("SymbolOracleWoo", "0x78Db6d02EE87260a5D825B31616B5C29f927E430")
    oracleETHUSD = await ethers.getContractAt("SymbolOracleWoo", "0xdF0050D6A07C19C6F6505d3e66B68c29F41edA09")
    volatilityOracleBTC = await (await ethers.getContractFactory("VolatilityOracleOffChain")).deploy(
        "VOL-BTCUSD",
        "0x4C059dD7b01AAECDaA3d2cAf4478f17b9c690080",
        604800)
    volatilityOracleETH = await (await ethers.getContractFactory("VolatilityOracleOffChain")).deploy(
        "VOL-ETHUSD",
        "0x4C059dD7b01AAECDaA3d2cAf4478f17b9c690080",
        604800)


    await pool.addSymbol(
        0, 'BTCUSD-30000-C',
        decimalStr("30000"), // strikePrice
        true, // isCall
        oracleBTCUSD.address,
        volatilityOracleBTC.address,
        decimalStr("0.0001"), decimalStr("0.001"),
        decimalStr("0.00005"),
        decimalStr("0.999") // K
        )
    await pool.addSymbol(
        1, 'BTCUSD-50000-P',
        decimalStr("50000"), // strikePrice
        false, // isCall
        oracleBTCUSD.address,
        volatilityOracleBTC.address,
        decimalStr("0.0001"), decimalStr("0.001"),
        decimalStr("0.00005"),
        decimalStr("0.999") // K
    )
    await pool.addSymbol(
        2, 'ETHUSD-3000-C',
        decimalStr("3000"), // strikePrice
        true, // isCall
        oracleETHUSD.address,
        volatilityOracleETH.address,
        decimalStr("0.0001"), decimalStr("0.001"),
        decimalStr("0.00005"),
        decimalStr("0.999") // K
    )

    logger.log("oracleBTCUSD", oracleBTCUSD.address)
    logger.log("oracleETHUSD", oracleETHUSD.address)
    logger.log("volatilityOracleBTC", volatilityOracleBTC.address)
    logger.log("volatilityOracleETH", volatilityOracleETH.address)



    logger.log("aa")
    for (account of [deployer, alice, bob]) {
        await usdt.mint(account.address, decimalStr(100000))
        await usdt.connect(account).approve(pool.address, MAX)
        logger.log('mint to', account.name)
    }
    logger.log("finish")

}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
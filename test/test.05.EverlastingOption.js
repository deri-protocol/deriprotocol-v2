const hre = require('hardhat')
const { expect } = require('chai')
const BigNumber = require("bignumber.js");

const fs = require("fs");
const file = fs.createWriteStream("../deploy-logger.js", { 'flags': 'w'});
let logger = new console.Console(file, file);

const decimalStr = (value) => {
  return new BigNumber(value).multipliedBy(10 ** 18).toFixed(0, BigNumber.ROUND_DOWN)
}

// rescale
function one(value=1, left=0, right=18) {
    let from = ethers.BigNumber.from('1' + '0'.repeat(left))
    let to = ethers.BigNumber.from('1' + '0'.repeat(right))
    return ethers.BigNumber.from(value).mul(to).div(from)
}

function neg(value) {
    return value.mul(-1)
}

const MAX = ethers.BigNumber.from('0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff')
const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000'

describe('DeriV2', function () {

    let deployer
    let alice
    let bob

    let usdt

    let oracleBTCUSD
    let oracleETHUSD
    let oracleBTCUSDTV1
    let oracleBTCUSDTV2
    let oracleETHUSDTV1
    let volatilityOracle

    let pricing
    let everlastingOptionPricing
    let lToken
    let pToken
    let pool

    beforeEach(async function() {
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
        await lToken.setPool(pool.address)
        await pToken.setPool(pool.address)

        // oracleBTCUSD = await (await ethers.getContractFactory('NaiveOracle')).deploy()
        // oracleBTCUSDTV1 = await (await ethers.getContractFactory('NaiveOracle')).deploy()
        // oracleBTCUSDTV2 = await (await ethers.getContractFactory('NaiveOracle')).deploy()
        // oracleETHUSD = await (await ethers.getContractFactory('NaiveOracle')).deploy()
        // oracleETHUSDTV1 = await (await ethers.getContractFactory('NaiveOracle')).deploy()
        // await oracleBTCUSD.setPrice(decimalStr(40000))
        // await oracleBTCUSDTV1.setPrice(decimalStr(20))
        // await oracleBTCUSDTV2.setPrice(decimalStr(10))
        // await oracleETHUSD.setPrice(decimalStr(3000))
        // await oracleETHUSDTV1.setPrice(decimalStr(3))


        oracleBTCUSD = await ethers.getContractAt("SymbolOracleWoo", "0x78Db6d02EE87260a5D825B31616B5C29f927E430")
        oracleETHUSD = await ethers.getContractAt("SymbolOracleWoo", "0xdF0050D6A07C19C6F6505d3e66B68c29F41edA09")
        volatilityOracle = await ethers.getContractAt("VolatilityOracleOffChain", "0xB45a33E32379eB2D7cc40ce5201ab3320C633f25")

        //
        // volatilityOracle = await (await ethers.getContractFactory("VolatilityOracleOffChainMock")).deploy(
        //     "VOLA",
        //     "0x4C059dD7b01AAECDaA3d2cAf4478f17b9c690080",
        //     decimalStr("10"))
        // await volatilityOracle.updateVolitility(1, decimalStr(1), 0, ethers.constants.HashZero, ethers.constants.HashZero)
        //
        // volatilityOracle = await (await ethers.getContractFactory("VolatilityOracleOffChain")).deploy(
        //     "VOL-BTCUSD",
        //     "0x4C059dD7b01AAECDaA3d2cAf4478f17b9c690080",
        //     604800)





        await pool.addSymbol(
            0, 'BTCUSD-30000-C',
            decimalStr("30000"), // strikePrice
            true, // isCall
            oracleBTCUSD.address,
            volatilityOracle.address,
            decimalStr("0.0001"), decimalStr("0.001"),
            decimalStr("0.00005"),
            decimalStr("0.999") // K
            )
        await pool.addSymbol(
            1, 'BTCUSD-50000-P',
            decimalStr("50000"), // strikePrice
            false, // isCall
            oracleBTCUSD.address,
            volatilityOracle.address,
            decimalStr("0.0001"), decimalStr("0.001"),
            decimalStr("0.00005"),
            decimalStr("0.999") // K
        )
        await pool.addSymbol(
            2, 'ETHUSD-3000-C',
            decimalStr("3000"), // strikePrice
            true, // isCall
            oracleETHUSD.address,
            volatilityOracle.address,
            decimalStr("0.0001"), decimalStr("0.001"),
            decimalStr("0.00005"),
            decimalStr("0.999") // K
        )

        for (account of [deployer, alice, bob]) {
            await usdt.mint(account.address, decimalStr(100000))
            await usdt.connect(account).approve(pool.address, MAX)
        }
    })

    async function getStates() {
        block = await ethers.provider.getBlock()
        symbol0 = await pool.getSymbol(0)
        symbol1 = await pool.getSymbol(1)
        symbol2 = await pool.getSymbol(2)
        position_deployer_0 = await pToken.getPosition(deployer.address, 0)
        position_deployer_1 = await pToken.getPosition(deployer.address, 1)
        position_deployer_2 = await pToken.getPosition(deployer.address, 2)
        position_alice_0 = await pToken.getPosition(alice.address, 0)
        position_alice_1 = await pToken.getPosition(alice.address, 1)
        position_alice_2 = await pToken.getPosition(alice.address, 2)
        position_bob_0 = await pToken.getPosition(bob.address, 0)
        position_bob_1 = await pToken.getPosition(bob.address, 1)
        position_bob_2 = await pToken.getPosition(bob.address, 2)
        return {
            block: {
                number: block.number,
                timestamp: block.timestamp
            },
            pool: {
                balance: await usdt.balanceOf(pool.address),
                lTokenBalance: await lToken.totalSupply(),
                pTokenSupply: (await pToken.totalSupply()).toString(),
                activeSymbolIds: `[${(await pToken.getActiveSymbolIds()).toString()}]`,
                numPositionHolders0: (await pToken.getNumPositionHolders(0)).toString(),
                numPositionHolders1: (await pToken.getNumPositionHolders(1)).toString(),
                numPositionHolders2: (await pToken.getNumPositionHolders(2)).toString(),
                liquidity: await pool.getLiquidity(),
                protocolFeeAccrued: await pool.getProtocolFeeAccrued()
            },
            symbol0: {
                symbol: symbol0.symbol,
                intrinsicValue: symbol0.intrinsicValue,
                timeValue: symbol0.timeValue,
                cumulativeDiseqFundingRate: symbol0.cumulativeDiseqFundingRate,
                cumulativePremiumFundingRate: symbol0.cumulativePremiumFundingRate,
                tradersNetVolume: symbol0.tradersNetVolume,
                tradersNetCost: symbol0.tradersNetCost
            },
            symbol1: {
                symbol: symbol1.symbol,
                intrinsicValue: symbol1.intrinsicValue,
                timeValue: symbol1.timeValue,
                cumulativeDiseqFundingRate: symbol1.cumulativeDiseqFundingRate,
                cumulativePremiumFundingRate: symbol1.cumulativePremiumFundingRate,
                tradersNetVolume: symbol1.tradersNetVolume,
                tradersNetCost: symbol1.tradersNetCost
            },
            symbol2: {
                symbol: symbol2.symbol,
                intrinsicValue: symbol2.intrinsicValue,
                timeValue: symbol2.timeValue,
                cumulativeDiseqFundingRate: symbol2.cumulativeDiseqFundingRate,
                cumulativePremiumFundingRate: symbol2.cumulativePremiumFundingRate,
                tradersNetVolume: symbol2.tradersNetVolume,
                tradersNetCost: symbol2.tradersNetCost
            },
            deployer: {
                balance: await usdt.balanceOf(deployer.address),
                lTokenBalance: await lToken.balanceOf(deployer.address),
                margin: await pToken.getMargin(deployer.address),
                volume0: position_deployer_0.volume,
                cost0: position_deployer_0.cost,
                lastCumulativeDiseqFundingRate01: position_deployer_0.lastCumulativeDiseqFundingRate,
                lastCumulativePremiumFundingRate02: position_deployer_0.lastCumulativePremiumFundingRate,
                volume1: position_deployer_1.volume,
                cost1: position_deployer_1.cost,
                lastCumulativeDiseqFundingRate11: position_deployer_1.lastCumulativeDiseqFundingRate,
                lastCumulativePremiumFundingRate12: position_deployer_1.lastCumulativePremiumFundingRate,
                volume2: position_deployer_2.volume,
                cost2: position_deployer_2.cost,
                lastCumulativeDiseqFundingRate21: position_deployer_2.lastCumulativeDiseqFundingRate,
                lastCumulativePremiumFundingRate22: position_deployer_2.lastCumulativePremiumFundingRate,
            },
            alice: {
                balance: await usdt.balanceOf(alice.address),
                lTokenBalance: await lToken.balanceOf(alice.address),
                margin: await pToken.getMargin(alice.address),
                volume0: position_alice_0.volume,
                cost0: position_alice_0.cost,
                lastCumulativeDiseqFundingRate01: position_alice_0.lastCumulativeDiseqFundingRate,
                lastCumulativePremiumFundingRate02: position_alice_0.lastCumulativePremiumFundingRate,
                volume1: position_alice_1.volume,
                cost1: position_alice_1.cost,
                lastCumulativeDiseqFundingRate11: position_alice_1.lastCumulativeDiseqFundingRate,
                lastCumulativePremiumFundingRate12: position_alice_1.lastCumulativePremiumFundingRate,
                volume2: position_alice_2.volume,
                cost2: position_alice_2.cost,
                lastCumulativeDiseqFundingRate21: position_alice_2.lastCumulativeDiseqFundingRate,
                lastCumulativePremiumFundingRate22: position_alice_2.lastCumulativePremiumFundingRate,
            },
            bob: {
                balance: await usdt.balanceOf(bob.address),
                lTokenBalance: await lToken.balanceOf(bob.address),
                margin: await pToken.getMargin(bob.address),
                volume0: position_bob_0.volume,
                cost0: position_bob_0.cost,
                lastCumulativeDiseqFundingRate01: position_bob_0.lastCumulativeDiseqFundingRate,
                lastCumulativePremiumFundingRate02: position_bob_0.lastCumulativePremiumFundingRate,
                volume1: position_bob_1.volume,
                cost1: position_bob_1.cost,
                lastCumulativeDiseqFundingRate11: position_bob_1.lastCumulativeDiseqFundingRate,
                lastCumulativePremiumFundingRate12: position_bob_1.lastCumulativePremiumFundingRate,
                volume2: position_bob_2.volume,
                cost2: position_bob_2.cost,
                lastCumulativeDiseqFundingRate21: position_bob_2.lastCumulativeDiseqFundingRate,
                lastCumulativePremiumFundingRate22: position_bob_2.lastCumulativePremiumFundingRate,
            }
        }
    }

    async function showDiff(pre, cur, name=null, tx=null) {
        console.log('='.repeat(80))
        if (name != null && tx != null) {
            console.log(`${name}: ${(await tx.wait()).gasUsed.toString()}`)
            console.log('='.repeat(80))
        }
        for (key1 in pre) {
            console.log(key1)
            for (key2 in pre[key1]) {
                value1 = pre[key1][key2]
                value2 = cur[key1][key2]
                if (['number', 'timestamp', 'symbol', 'pTokenSupply', 'activeSymbolIds', 'numPositionHolders0', 'numPositionHolders1'].indexOf(key2) === -1) {
                    value1 = ethers.utils.formatEther(value1)
                    value2 = ethers.utils.formatEther(value2)
                }
                if (value1 === value2) {
                    console.log(`    ${key2.padEnd(36)}: ${value2}`)
                }
                else {
                    console.log(`    ${key2.padEnd(36)}: ${value1} ===> ${value2}`)
                }
            }
        }
    }

    async function addLiquidity(account, bAmount, show=false) {
        let tx
        if (show) {
            pre = await getStates()
            tx = await pool.connect(account).addLiquidity(bAmount, [])
            cur = await getStates()
            await showDiff(pre, cur, `${account.name}.addLiquidity(${ethers.utils.formatEther(bAmount)})`, tx)
        } else
            {
                // tx = await (pool.connect(account).functions['addLiquidity(uint256,(uint256,uint256,uint256,uint8,bytes32,bytes32)[])'](
                //     bAmount, []))
            tx = await pool.connect(account).addLiquidity(bAmount, [])
        }
    }

    async function removeLiquidity(account, bAmount, show=false) {
        let tx
        if (show) {
            pre = await getStates()
            tx = await pool.connect(account).removeLiquidity(bAmount, [])
            cur = await getStates()
            await showDiff(pre, cur, `${account.name}.removeLiquidity(${ethers.utils.formatEther(bAmount)})`, tx)
        } else {
            tx = await (pool.connect(account).removeLiquidity(bAmount, []))
            // tx = await pool.connect(account).removeLiquidity(bAmount, [])
        }
    }

    async function addMargin(account, bAmount, show=false) {
        let tx
        if (show) {
            pre = await getStates()
            tx = await pool.connect(account).addMargin(bAmount, [])
            cur = await getStates()
            await showDiff(pre, cur, `${account.name}.addMargin(${ethers.utils.formatEther(bAmount)})`, tx)
        } else {
            tx = await (pool.connect(account).functions['addMargin(uint256,(uint256,uint256,uint256,uint8,bytes32,bytes32)[])'](
                    bAmount, []))
            // tx = await pool.connect(account).addMargin(bAmount, [])
        }
    }

    async function removeMargin(account, bAmount, show=false) {
        let tx
        if (show) {
            pre = await getStates()
            tx = await pool.connect(account).removeMargin(bAmount, [])
            cur = await getStates()
            await showDiff(pre, cur, `${account.name}.removeMargin(${ethers.utils.formatEther(bAmount)})`, tx)
        } else {
            // tx = await (pool.connect(account).functions['removeMargin(uint256,(uint256,uint256,uint256,uint8,bytes32,bytes32)[])'](
            //         bAmount, []))
            tx = await pool.connect(account).removeMargin(bAmount, [])
        }
    }

    async function trade(account, symbolId, volume, show=false) {
        let tx
        if (show) {
            pre = await getStates()
            tx = await pool.connect(account).trade(symbolId, volume, [])
            cur = await getStates()
            await showDiff(pre, cur, `trade(${account.name}, ${symbolId}, ${ethers.utils.formatEther(volume)})`, tx)
        } else {
            // tx = await (pool.connect(account).functions['trade(uint256,int256,(uint256,uint256,uint256,uint8,bytes32,bytes32)[])'](
            //         symbolId, volume, []))
            tx = await pool.connect(account).trade(symbolId, volume, [])
        }
    }

    async function liquidate(account, trader, show=false) {
        let tx
        if (show) {
            pre = await getStates()
            tx = await pool.connect(account).liquidate(trader.address, [])
            cur = await getStates()
            await showDiff(pre, cur, `${account.name}.liquidate(${trader.name})`, tx)
        } else {
            // tx = await (pool.connect(account).functions['liquidate(address,(uint256,uint256,uint256,uint8,bytes32,bytes32)[])'](
            //         trader.address, []))
            tx = await pool.connect(account).liquidate(trader.address, [])
        }
    }

    async function collectProtocolFee(account, show=False) {
        let tx
        if (show) {
            pre = await getStates()
            tx = await pool.connect(account).collectProtocolFee()
            cur = await getStates()
            await showDiff(pre, cur, `${account.name}.collectProtocolFee()`, tx)
        } else {
            tx = await pool.connect(account).collectProtocolFee()
        }
    }

    // it('addLiquidity/removeLiquidity work correctly', async function () {
    //     await addLiquidity(deployer, decimalStr(10000), false)
    //     await addLiquidity(alice, decimalStr(50000), false)
    //
    //     await expect(removeLiquidity(deployer, decimalStr(20000), false)).to.be.revertedWith('LToken: burn amount exceeds balance')
    //     await removeLiquidity(alice, decimalStr(50000), false)
    //     await removeLiquidity(deployer, decimalStr(1000), false)
    // })
    //
    // it('addMargin/removeMargin work correctly', async function () {
    //     await addLiquidity(deployer, one(10000), false)
    //     await addLiquidity(alice, one(50000), false)
    //
    //     await addMargin(bob, one(10000), true)
    //     await removeMargin(bob, one(5000), true)
    //     await removeMargin(bob, one(10000), true)
    // })

    it('trade/liquidate work correctly', async function () {
        await addLiquidity(deployer, decimalStr(50000), false)
        // await addMargin(deployer, decimalStr(5000), false)
        await addMargin(alice, decimalStr(10000), false)

        console.log("test1")
        await trade(alice, 0, decimalStr(40000), false)
        // console.log("test2")
        // await trade(alice, 0, decimalStr("-100"), false)
        // // expect((await pToken.getPosition(bob.address, 0)).cost).to.equal("10020006668889629876640")
        // await oracleBTCUSD.setPrice(decimalStr(40000))
        // console.log("test3")
        // await trade(deployer, 0, decimalStr("-100"), true)



        // await expect(removeMargin(bob, decimalStr(200), true)).to.be.revertedWith('PerpetualPool: insufficient margin')
        // await oracleBTCUSD.setPrice(decimalStr(38000))
        // await liquidate(deployer, bob, true)
        // expect(await usdt.balanceOf(deployer.address)).to.equal(decimalStr(90010))

    })

    // it('trade/liquidate work correctly', async function () {
    //     await addLiquidity(deployer, decimalStr(10000), false)
    //     await addMargin(deployer, decimalStr(5000), false)
    //     await addMargin(alice, decimalStr(5000), false)
    //
    //     console.log("test1")
    //     await trade(deployer, 0, decimalStr(100), false)
    //     console.log("test2")
    //     await trade(alice, 0, decimalStr("-100"), false)
    //     // expect((await pToken.getPosition(bob.address, 0)).cost).to.equal("10020006668889629876640")
    //     await oracleBTCUSD.setPrice(decimalStr(40000))
    //     console.log("test3")
    //     await trade(deployer, 0, decimalStr("-100"), true)
    //
    //
    //
    //     // await expect(removeMargin(bob, decimalStr(200), true)).to.be.revertedWith('PerpetualPool: insufficient margin')
    //     // await oracleBTCUSD.setPrice(decimalStr(38000))
    //     // await liquidate(deployer, bob, true)
    //     // expect(await usdt.balanceOf(deployer.address)).to.equal(decimalStr(90010))
    //
    // })

    // it('trade/liquidate work correctly', async function () {
    //     await addLiquidity(deployer, decimalStr(10000), false)
    //     await addLiquidity(alice, decimalStr(50000), false)
    //     await addMargin(bob, decimalStr(2000), false)
    //
    //     await trade(bob, 0, decimalStr(10000), false)
    //     // expect((await pToken.getPosition(bob.address, 0)).cost).to.equal("10020006668889629876640")
    //     await oracleBTCUSD.setPrice(decimalStr(39000))
    //
    //     await trade(bob, 0, decimalStr(-10000), true)
    //
    //
    //
    //     // await expect(removeMargin(bob, decimalStr(200), true)).to.be.revertedWith('PerpetualPool: insufficient margin')
    //     // await oracleBTCUSD.setPrice(decimalStr(38000))
    //     // await liquidate(deployer, bob, true)
    //     // expect(await usdt.balanceOf(deployer.address)).to.equal(decimalStr(90010))
    //
    // })
    //
    // it('removeSymbol work correctly', async function () {
    //     await addLiquidity(alice, one(50000), false)
    //     await addMargin(bob, one(1000), false)
    //
    //     await trade(bob, 0, one(1000), true)
    //     await expect(pool.connect(deployer).removeSymbol(0)).to.be.revertedWith('PToken: exists position holders')
    //     await trade(bob, 0, one(-1000), true)
    //
    //     await expect(pool.connect(alice).removeSymbol(0)).to.be.revertedWith('Ownable: only controller')
    //     await pool.removeSymbol(0)
    //     cur = await getStates()
    //     await showDiff(cur, cur)
    //     //
    //     await expect(trade(bob, 0, one(1000), true)).to.be.revertedWith('PerpetualPool: invalid symbolId')
    // })
    //
    // it('toggleCloseOnly work correctly', async function () {
    //     await addLiquidity(alice, one(50000), false)
    //
    //     await oracleBTCUSD.setPrice(one(40000))
    //     await oracleETHUSD.setPrice(one(2000))
    //     await addMargin(bob, one(1000), false)
    //
    //     await trade(bob, 0, one(1000), true)
    //     await pool.toggleCloseOnly(0)
    //     await expect(trade(bob, 0, one(1000), true)).to.be.revertedWith('PToken: close only')
    //     await trade(bob, 0, one(-500), true)
    //
    //     await pool.toggleCloseOnly(0)
    //     await trade(bob, 0, one(500), true)
    //     await removeLiquidity(alice, one(10000), true)
    // })
    //
    // it('migration work correctly', async function () {
    //     await addLiquidity(deployer, one(50000), false)
    //
    //     await oracleBTCUSD.setPrice(one(40000))
    //     await oracleETHUSD.setPrice(one(2000))
    //
    //     await addMargin(alice, one(1000), false)
    //     await addMargin(bob, one(1000), false)
    //     await trade(alice, 0, one(1000), false)
    //     await trade(alice, 1, one(1000), false)
    //     await trade(bob, 1, one(-2000), false)
    //
    //     pool2 = await (await ethers.getContractFactory('EverlastingOption')).deploy(
    //         [
    //             one(),     // minPoolMarginRatio
    //             one(1, 1), // minInitialMarginRatio
    //             one(5, 2), // minMaintenanceMarginRatio
    //             one(100),  // minLiquidationReward
    //             one(1000), // maxLiquidationReward
    //             one(5, 1), // liquidationCutRatio
    //             one(2, 1)  // protocolFeeCollectRatio
    //         ],
    //         [
    //             usdt.address,     // bTokenAddress
    //             lToken.address,   // lTokenAddress
    //             pToken.address,   // pTokenAddress
    //             ZERO_ADDRESS,     // liquidatorQualifierAddress
    //             deployer.address, // protocolFeeCollector
    //         ]
    //     )
    //     await pool.prepareMigration(pool2.address, 3)
    //     await expect(pool.approveMigration()).to.be.revertedWith('PerpetualPool: migrationTimestamp not met yet')
    //
    //     await ethers.provider.send('evm_increaseTime', [86400*3])
    //     await pool.approveMigration()
    //     await expect(removeLiquidity(deployer, one(10000))).to.be.revertedWith('LToken: only pool')
    //     await expect(trade(alice, 0, one(-1000))).to.be.revertedWith('PToken: only pool')
    //
    //     source = pool.address
    //     pool = pool2
    //     await usdt.connect(alice).approve(pool.address, MAX)
    //     await addMargin(alice, one(1000), true)
    //
    //     await pool.executeMigration(source)
    //     expect(await usdt.balanceOf(source)).to.equal(0)
    //     expect(await usdt.balanceOf(pool2.address)).to.equal(one(53000))
    //
    //     await oracleBTCUSD.setPrice(one(31000))
    //     await oracleETHUSD.setPrice(one(1100))
    //     await liquidate(deployer, alice, true)
    //     await trade(bob, 1, one(2000), true)
    //     await removeMargin(bob, one(3000), true)
    // })

})

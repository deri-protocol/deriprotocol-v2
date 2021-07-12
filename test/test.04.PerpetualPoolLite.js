const hre = require('hardhat')
const { expect } = require('chai')
const BigNumber = require("bignumber.js");

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

    let account1
    let account2
    let account3

    let usdt

    let oracleBTCUSD
    let oracleETHUSD

    let lToken
    let pToken
    let pool

    beforeEach(async function() {
        [account1, account2, account3] = await ethers.getSigners()
        account1.name = 'account1'
        account2.name = 'account2'
        account3.name = 'account3'

        usdt = await (await ethers.getContractFactory('TERC20')).deploy('Test USDT', 'USDT', 18)

        lToken = await (await ethers.getContractFactory('LTokenLite')).deploy('Deri Liquidity Token', 'DLT')
        pToken = await (await ethers.getContractFactory('PTokenLite')).deploy('Deri Position Token', 'DPT')
        pool = await (await ethers.getContractFactory('PerpetualPoolLite')).deploy(
            [
                one(),     // minPoolMarginRatio
                one(1, 1), // minInitialMarginRatio
                one(5, 2), // minMaintenanceMarginRatio
                one(10),   // minLiquidationReward
                one(1000), // maxLiquidationReward
                one(5, 1), // liquidationCutRatio
                one(2, 1)  // protocolFeeCollectRatio
            ],
            [
                usdt.address,     // bTokenAddress
                lToken.address,   // lTokenAddress
                pToken.address,   // pTokenAddress
                ZERO_ADDRESS,     // liquidatorQualifierAddress
                account1.address, // protocolFeeCollector
            ]
        )
        await lToken.setPool(pool.address)
        await pToken.setPool(pool.address)

        oracleBTCUSD = await (await ethers.getContractFactory('TSymbolOracle')).deploy('BTCUSD', account1.address)
        oracleETHUSD = await (await ethers.getContractFactory('TSymbolOracle')).deploy('ETHUSD', account1.address)

        await pool.addSymbol(0, 'BTCUSD', oracleBTCUSD.address, one(1, 4), one(1, 3), one(5, 5))
        await pool.addSymbol(1, 'ETHUSD', oracleETHUSD.address, one(1, 3), one(1, 3), one(5, 5))

        for (account of [account1, account2, account3]) {
            await usdt.mint(account.address, one(100000))
            await usdt.connect(account).approve(pool.address, MAX)
        }
        console.log("pool", pool)
    })

    async function getStates() {
        block = await ethers.provider.getBlock()
        symbol0 = await pool.getSymbol(0)
        symbol1 = await pool.getSymbol(1)
        position10 = await pToken.getPosition(account1.address, 0)
        position11 = await pToken.getPosition(account1.address, 1)
        position20 = await pToken.getPosition(account2.address, 0)
        position21 = await pToken.getPosition(account2.address, 1)
        position30 = await pToken.getPosition(account3.address, 0)
        position31 = await pToken.getPosition(account3.address, 1)
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
                liquidity: await pool.getLiquidity(),
                protocolFeeAccrued: await pool.getProtocolFeeAccrued()
            },
            symbol0: {
                symbol: symbol0.symbol,
                price: symbol0.price,
                cumulativeFundingRate: symbol0.cumulativeFundingRate,
                tradersNetVolume: symbol0.tradersNetVolume,
                tradersNetCost: symbol0.tradersNetCost
            },
            symbol1: {
                symbol: symbol1.symbol,
                price: symbol1.price,
                cumulativeFundingRate: symbol1.cumulativeFundingRate,
                tradersNetVolume: symbol1.tradersNetVolume,
                tradersNetCost: symbol1.tradersNetCost
            },
            account1: {
                balance: await usdt.balanceOf(account1.address),
                lTokenBalance: await lToken.balanceOf(account1.address),
                margin: await pToken.getMargin(account1.address),
                volume0: position10.volume,
                cost0: position10.cost,
                lastCumulativeFundingRate0: position10.lastCumulativeFundingRate,
                volume1: position11.volume,
                cost1: position11.cost,
                lastCumulativeFundingRate1: position11.lastCumulativeFundingRate
            },
            account2: {
                balance: await usdt.balanceOf(account2.address),
                lTokenBalance: await lToken.balanceOf(account2.address),
                margin: await pToken.getMargin(account2.address),
                volume0: position20.volume,
                cost0: position20.cost,
                lastCumulativeFundingRate0: position20.lastCumulativeFundingRate,
                volume1: position21.volume,
                cost1: position21.cost,
                lastCumulativeFundingRate1: position21.lastCumulativeFundingRate
            },
            account3: {
                balance: await usdt.balanceOf(account3.address),
                lTokenBalance: await lToken.balanceOf(account3.address),
                margin: await pToken.getMargin(account3.address),
                volume0: position30.volume,
                cost0: position30.cost,
                lastCumulativeFundingRate0: position30.lastCumulativeFundingRate,
                volume1: position31.volume,
                cost1: position31.cost,
                lastCumulativeFundingRate1: position31.lastCumulativeFundingRate
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
        } else {
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
            tx = await pool.connect(account).removeLiquidity(bAmount, [])
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
            tx = await pool.connect(account).addMargin(bAmount, [])
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

    it('addLiquidity/removeLiquidity work correctly', async function () {
        console.log("start")
        await addLiquidity(account1, one(10000), true)
        // await addLiquidity(account2, one(50000), true)
        //
        // await expect(removeLiquidity(account1, one(20000), true)).to.be.revertedWith('LToken: burn amount exceeds balance')
        // await removeLiquidity(account1, one(1000), true)
        // await removeLiquidity(account2, one(50000), true)
    })

    // it('addMargin/removeMargin work correctly', async function () {
    //     await addLiquidity(account1, one(10000), false)
    //     await addLiquidity(account2, one(50000), false)
    //
    //     await addMargin(account3, one(10000), true)
    //     await removeMargin(account3, one(5000), true)
    //     await removeMargin(account3, one(10000), true)
    // })
    //
    // it('trade/liquidate work correctly', async function () {
    //     await addLiquidity(account1, one(10000), false)
    //     await addLiquidity(account2, one(50000), false)
    //
    //     await oracleBTCUSD.setPrice(one(40000))
    //     await oracleETHUSD.setPrice(one(2000))
    //     await addMargin(account3, one(1000), false)
    //
    //     await trade(account3, 0, one(1000), true)
    //     await trade(account3, 0, one(-2000), true)
    //     await expect(trade(account3, 1, one(10000), true)).to.be.revertedWith('PerpetualPool: insufficient margin')
    //     await trade(account3, 1, one(1000), true)
    //
    //     await oracleBTCUSD.setPrice(one(50000))
    //     await liquidate(account1, account3, true)
    //
    //     await collectProtocolFee(account2, true)
    // })
    //
    // it('removeSymbol work correctly', async function () {
    //     await addLiquidity(account2, one(50000), false)
    //
    //     await oracleBTCUSD.setPrice(one(40000))
    //     await oracleETHUSD.setPrice(one(2000))
    //     await addMargin(account3, one(1000), false)
    //
    //     await trade(account3, 0, one(1000), true)
    //     await expect(pool.connect(account1).removeSymbol(0)).to.be.revertedWith('PToken: exists position holders')
    //     await trade(account3, 0, one(-1000), true)
    //
    //     await expect(pool.connect(account2).removeSymbol(0)).to.be.revertedWith('Ownable: only controller')
    //     await pool.removeSymbol(0)
    //     cur = await getStates()
    //     await showDiff(cur, cur)
    //
    //     await expect(trade(account3, 0, one(1000), true)).to.be.revertedWith('PerpetualPool: invalid symbolId')
    // })
    //
    // it('toggleCloseOnly work correctly', async function () {
    //     await addLiquidity(account2, one(50000), false)
    //
    //     await oracleBTCUSD.setPrice(one(40000))
    //     await oracleETHUSD.setPrice(one(2000))
    //     await addMargin(account3, one(1000), false)
    //
    //     await trade(account3, 0, one(1000), true)
    //     await pool.toggleCloseOnly(0)
    //     await expect(trade(account3, 0, one(1000), true)).to.be.revertedWith('PToken: close only')
    //     await trade(account3, 0, one(-500), true)
    //
    //     await pool.toggleCloseOnly(0)
    //     await trade(account3, 0, one(500), true)
    //     await removeLiquidity(account2, one(10000), true)
    // })
    //
    // it('migration work correctly', async function () {
    //     await addLiquidity(account1, one(50000), false)
    //
    //     await oracleBTCUSD.setPrice(one(40000))
    //     await oracleETHUSD.setPrice(one(2000))
    //
    //     await addMargin(account2, one(1000), false)
    //     await addMargin(account3, one(1000), false)
    //     await trade(account2, 0, one(1000), false)
    //     await trade(account2, 1, one(1000), false)
    //     await trade(account3, 1, one(-2000), false)
    //
    //     pool2 = await (await ethers.getContractFactory('PerpetualPoolLite')).deploy(
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
    //             account1.address, // protocolFeeCollector
    //         ]
    //     )
    //     await pool.prepareMigration(pool2.address, 3)
    //     await expect(pool.approveMigration()).to.be.revertedWith('PerpetualPool: migrationTimestamp not met yet')
    //
    //     await ethers.provider.send('evm_increaseTime', [86400*3])
    //     await pool.approveMigration()
    //     await expect(removeLiquidity(account1, one(10000))).to.be.revertedWith('LToken: only pool')
    //     await expect(trade(account2, 0, one(-1000))).to.be.revertedWith('PToken: only pool')
    //
    //     source = pool.address
    //     pool = pool2
    //     await usdt.connect(account2).approve(pool.address, MAX)
    //     await addMargin(account2, one(1000), true)
    //
    //     await pool.executeMigration(source)
    //     expect(await usdt.balanceOf(source)).to.equal(0)
    //     expect(await usdt.balanceOf(pool2.address)).to.equal(one(53000))
    //
    //     await oracleBTCUSD.setPrice(one(31000))
    //     await oracleETHUSD.setPrice(one(1100))
    //     await liquidate(account1, account2, true)
    //     await trade(account3, 1, one(2000), true)
    //     await removeMargin(account3, one(3000), true)
    // })

})

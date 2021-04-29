const hre = require('hardhat')
const { expect } = require('chai')

// rescale
function one(value=1, fromDecimals=0, toDecimals=18) {
    let from = ethers.BigNumber.from('1' + '0'.repeat(fromDecimals))
    let to = ethers.BigNumber.from('1' + '0'.repeat(toDecimals))
    return ethers.BigNumber.from(value).mul(to).div(from)
}

function neg(value) {
    return value.mul(-1)
}

const MAX = ethers.BigNumber.from('0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff')
const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000'
const DEADLINE = parseInt(Date.now() / 1000) + 86400

describe('DeriV2', function () {

    let account1
    let account2
    let account3

    let unifactory
    let unirouter

    let usdt
    let weth
    let susi

    let pair1
    let pair2

    let swapperWETH
    let swapperSUSI

    let oracleWETH
    let oracleSUSI

    let oracleBTCUSD
    let oracleETHUSD

    let router
    let pool
    let pToken
    let lToken

    beforeEach(async function() {
        [account1, account2, account3] = await ethers.getSigners()
        account1.name = 'account1'
        account2.name = 'account2'
        account3.name = 'account3'

        unifactory = await (await ethers.getContractFactory('UniswapV2Factory')).deploy(account1.address)
        unirouter = await (await ethers.getContractFactory('UniswapV2Router02')).deploy(unifactory.address, ZERO_ADDRESS)

        usdt = await (await ethers.getContractFactory('TestTetherToken')).deploy('Test Tether USDT', 'USDT')
        weth = await (await ethers.getContractFactory('TERC20')).deploy('Test WETH', 'WETH', 18)
        susi = await (await ethers.getContractFactory('TERC20')).deploy('Test SUSHI', 'SUSHI', 18)

        for (token of [usdt, weth, susi])
            for (account of [account1, account2, account3])
                await token.connect(account).approve(unirouter.address, MAX)

        await usdt.mint(account1.address, one(1000000, 0, 6))
        await weth.mint(account1.address, one(1000))
        await susi.mint(account1.address, one(50000))

        await unirouter.connect(account1).addLiquidity(usdt.address, weth.address, one(1000000, 0, 6), one(500), 0, 0, account1.address, DEADLINE)
        await unirouter.connect(account1).addLiquidity(weth.address, susi.address, one(500), one(50000), 0, 0, account1.address, DEADLINE)

        pair1 = await ethers.getContractAt('contracts/test/UniswapV2Pair.sol:UniswapV2Pair', await unifactory.getPair(usdt.address, weth.address))
        pair2 = await ethers.getContractAt('contracts/test/UniswapV2Pair.sol:UniswapV2Pair', await unifactory.getPair(susi.address, weth.address))

        lToken = await (await ethers.getContractFactory('LToken')).deploy('Deri Liquidity Token', 'DLT', 0)
        pToken = await (await ethers.getContractFactory('PToken')).deploy('Deri Position Token', 'DPT', 0, 0)
        router = await (await ethers.getContractFactory('PerpetualPoolRouter')).deploy(lToken.address, pToken.address, ZERO_ADDRESS)
        pool = await (await ethers.getContractFactory('PerpetualPool')).deploy(
            [
                usdt.decimals(),
                one(2, 1),  // minBToken0Ratio
                one(),      // minPoolMarginRatio
                one(1, 1),  // minInitialMarginRatio
                one(5, 2),  // minMaintenanceMarginRatio
                one(10),    // minLiquidationReward
                one(200),   // maxLiquidationReward
                one(5, 1),  // liquidationCutRatio
                one(2, 1)   // protocolFeeCollectRatio
            ],
            [lToken.address, pToken.address, router.address]
        )
        await pToken.setPool(pool.address)
        await lToken.setPool(pool.address)
        await router.setPool(pool.address)

        swapperWETH = await (await ethers.getContractFactory('BTokenSwapper1')).deploy(
            unirouter.address, pair1.address, weth.address, usdt.address, false
        )
        swapperSUSI = await (await ethers.getContractFactory('BTokenSwapper2')).deploy(
            unirouter.address, pair2.address, pair1.address, susi.address, weth.address, usdt.address, false, true
        )

        oracleWETH = await (await ethers.getContractFactory('BTokenOracle1')).deploy(
            pair1.address, weth.address, usdt.address, false
        )
        oracleSUSI = await (await ethers.getContractFactory('BTokenOracle2')).deploy(
            pair2.address, pair1.address, susi.address, weth.address, usdt.address, false, true
        )

        oracleBTCUSD = await (await ethers.getContractFactory('TSymbolHandler')).deploy()
        oracleETHUSD = await (await ethers.getContractFactory('TSymbolHandler')).deploy()
        await oracleBTCUSD.setPrice(one(60000))
        await oracleETHUSD.setPrice(one(2000))

        await router.addBToken(usdt.address, ZERO_ADDRESS, ZERO_ADDRESS, one())
        await router.addBToken(weth.address, swapperWETH.address, oracleWETH.address, one(8, 1))
        await router.addBToken(susi.address, swapperSUSI.address, oracleSUSI.address, one(5, 1))

        await router.addSymbol('BTCUSD', oracleBTCUSD.address, one(1, 4), one(1, 4), one(1, 5))
        await router.addSymbol('ETHUSD', oracleETHUSD.address, one(1, 3), one(2, 4), one(2, 5))

        for (account of [account1, account2, account3]) {
            usdt.mint(account.address, one(100000, 0, 6))
            weth.mint(account.address, one(100000))
            susi.mint(account.address, one(100000))

            usdt.connect(account).approve(pool.address, MAX)
            weth.connect(account).approve(pool.address, MAX)
            susi.connect(account).approve(pool.address, MAX)
        }
    })

    it('deploy correctly', async function () {
        expect((await pool.getParameters()).minMaintenanceMarginRatio).to.equal(one(5, 2))
        expect((await pool.getAddresses()).lTokenAddress).to.equal(lToken.address)
        expect((await pool.getLength())[0]).to.equal(3)
        expect((await pool.getLength())[1]).to.equal(2)

        expect((await pool.getBToken(0)).discount).to.equal(one())
        expect((await pool.getBToken(1)).bTokenAddress).to.equal(weth.address)
        expect((await pool.getBToken(2)).swapperAddress).to.equal(swapperSUSI.address)

        expect((await pool.getSymbol(0)).symbol).to.equal('BTCUSD')
        expect((await pool.getSymbol(1)).multiplier).to.equal(one(1, 3))

        expect(await pool.getBTokenOracle(0)).to.equal(ZERO_ADDRESS)
        expect(await pool.getBTokenOracle(1)).to.equal(oracleWETH.address)
        expect(await pool.getBTokenOracle(2)).to.equal(oracleSUSI.address)

        expect(await pool.getSymbolOracle(0)).to.equal(oracleBTCUSD.address)
        expect(await pool.getSymbolOracle(1)).to.equal(oracleETHUSD.address)
    })

    it('setBTokenParameters work correctly', async function () {
        await router.connect(account1).setBTokenParameters(1, swapperWETH.address, oracleWETH.address, one(7, 1))
        expect((await pool.getBToken(1)).discount).to.equal(one(7, 1))
    })

    it('setSymbolParameters work correctly', async function () {
        await router.connect(account1).setSymbolParameters(0, oracleBTCUSD.address, one(1, 2), one(1, 3))
        expect((await pool.getSymbol(0)).feeRatio).to.equal(one(1, 2))
        expect((await pool.getSymbol(0)).fundingRateCoefficient).to.equal(one(1, 3))
    })

    it('pool work correctly', async function () {
        await router.connect(account1).addLiquidity(0, one(10000))
        expect(await usdt.balanceOf(pool.address)).to.equal(one(10000, 0, 6))
        expect(await usdt.balanceOf(account1.address)).to.equal(one(90000, 0, 6))
        expect((await pool.getBToken(0)).liquidity).to.equal(one(10000))

        await router.connect(account2).addLiquidity(1, one(20))
        expect(await weth.balanceOf(pool.address)).to.equal(one(20))
        expect(await weth.balanceOf(account2.address)).to.equal(one(99980))
        expect((await pool.getBToken(1)).liquidity).to.equal(one(20))

        await router.connect(account2).removeLiquidity(1, one(21))
        expect(await weth.balanceOf(pool.address)).to.equal(0)
        expect(await weth.balanceOf(account2.address)).to.equal(one(100000))
        expect((await pool.getBToken(1)).liquidity).to.equal(one(0))

        await router.connect(account2).addLiquidity(1, one(20))

        await router.connect(account1).removeLiquidity(0, one(12, 7))
        expect(await usdt.balanceOf(pool.address)).to.equal(one(10000, 0, 6).sub(1))
        expect(await usdt.balanceOf(account1.address)).to.equal(one(90000, 0, 6).add(1))
        expect((await pool.getBToken(0)).liquidity).to.equal(one(9999999999, 6))

        await router.connect(account1).addLiquidity(0, one(19, 7))
        expect(await usdt.balanceOf(pool.address)).to.equal(one(10000, 0, 6))
        expect(await usdt.balanceOf(account1.address)).to.equal(one(90000, 0, 6))
        expect((await pool.getBToken(0)).liquidity).to.equal(one(10000))

        await router.connect(account3).addMargin(2, one(200))
        expect(await susi.balanceOf(pool.address)).to.equal(one(200))
        expect(await pToken.getMargin(account3.address, 2)).to.equal(one(200))

        await router.connect(account3).trade(0, one(100))
        expect(await pool.getProtocolFeeCollected()).to.equal(one(12, 3))
        expect((await pool.getSymbol(0)).tradersNetVolume).to.equal(one(100))
        expect((await pool.getBToken(1)).pnl).to.equal(one(36571, 6))
        expect(await pToken.getMargin(account3.address, 0)).to.equal(neg(one(6, 2)))

        await router.connect(account3).removeMargin(2, one())
        expect(await pToken.getMargin(account3.address, 0)).to.equal(0)
        expect(await pToken.getMargin(account3.address, 2)).to.equal(one('198996977642695826730', 0, 0))

        await router.connect(account3).trade(1, neg(one(200)))
        expect((await pool.getBToken(1)).pnl).to.equal(one(85462, 6))
        expect((await pToken.getPosition(account3.address, 1)).volume).to.equal(neg(one(200)))

        await router.connect(account1).removeLiquidity(0, one(100))
        expect((await lToken.getAsset(account1.address, 0)).lastCumulativePnl).to.equal(one(26744, 10))

        await router.connect(account2).addLiquidity(1, one())
        await oracleBTCUSD.setPrice(one(62000))

        await router.connect(account2).addLiquidity(1, one())
        expect((await lToken.getAsset(account2.address, 1)).pnl).to.equal(neg(one(15362316, 6)))
    })

    it('migration work correctly', async function () {
        await router.connect(account1).addLiquidity(0, one(10000))
        await router.connect(account3).addMargin(2, one(200))
        await router.connect(account3).trade(1, neg(one(200)))

        router2 = await (await ethers.getContractFactory('PerpetualPoolRouter')).deploy(lToken.address, pToken.address, ZERO_ADDRESS)
        pool2 = await (await ethers.getContractFactory('PerpetualPool')).deploy(
            [
                usdt.decimals(),
                one(5, 1),  // minBToken0Ratio
                one(),      // minPoolMarginRatio
                one(1, 1),  // minInitialMarginRatio
                one(5, 2),  // minMaintenanceMarginRatio
                one(10),    // minLiquidationReward
                one(200),   // maxLiquidationReward
                one(5, 1),  // liquidationCutRatio
                one(2, 1)   // protocolFeeCollectRatio
            ],
            [lToken.address, pToken.address, router2.address]
        )
        await router2.connect(account1).setPool(pool2.address)

        await router.connect(account1).prepareMigration(router2.address, 3)
        await expect(router.connect(account1).approveMigration()).to.be.revertedWith('migration time not met')

        await ethers.provider.send('evm_increaseTime', [86400*3])
        await router.connect(account1).approveMigration()
        await expect(router.connect(account1).removeLiquidity(0, one())).to.be.revertedWith('LToken: only pool')
        await expect(router.connect(account3).trade(1, one(200))).to.be.revertedWith('PToken: only pool')

        await router2.connect(account1).executeMigration(router.address)
        expect(await usdt.balanceOf(pool.address)).to.equal(0)
        expect(await susi.balanceOf(pool.address)).to.equal(0)
        expect(await usdt.balanceOf(pool2.address)).to.equal(one(10000, 0, 6))
        expect(await susi.balanceOf(pool2.address)).to.equal(one(200))

        expect((await pool2.getLength())[0]).to.equal(3)
        expect((await pool2.getLength())[1]).to.equal(2)
        expect((await pool2.getParameters()).minBToken0Ratio).to.equal(one(5, 1))
        await router2.connect(account3).trade(1, one(200))
        expect((await pToken.getPosition(account3.address, 1)).volume).to.equal(0)
        await router2.connect(account1).removeLiquidity(0, one(1000))
        expect((await lToken.getAsset(account1.address, 0)).liquidity).to.equal(one(9000228479, 6))
    })

})

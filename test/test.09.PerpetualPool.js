
MAX = ethers.BigNumber.from('0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF')
ZERO_ADDRESS = '0x0000000000000000000000000000000000000000'
DEADLINE = parseInt(Date.now() / 1000) + 86400

function bb(value, decimals=18) {
    return ethers.utils.parseUnits(value.toString(), decimals)
}

describe('Test', function () {

    let unifactory
    let unirouter
    let busd
    let wbnb
    let cake
    let pair1
    let pair2
    let lToken
    let pToken
    let router
    let pool
    let swapper1
    let swapper2
    let boracle1
    let boracle2
    let soracle1
    let soracle2

    let account0
    let account1
    let account2
    let account3

    beforeEach(async function() {
        [account0, account1, account2, account3] = await ethers.getSigners()

        unifactory = await (await ethers.getContractFactory('UniswapV2Factory')).deploy(account0.address)
        unirouter = await (await ethers.getContractFactory('UniswapV2Router02')).deploy(unifactory.address, ZERO_ADDRESS)

        busd = await (await ethers.getContractFactory('TERC20')).deploy('Test BUSD', 'BUSD', 18)
        wbnb = await (await ethers.getContractFactory('TERC20')).deploy('Test WBNB', 'WBNB', 18)
        cake = await (await ethers.getContractFactory('TERC20')).deploy('Test CAKE', 'CAKE', 18)

        for (token of [busd, wbnb, cake]) {
            await token.connect(account0).approve(unirouter.address, MAX)
        }
        await busd.mint(account0.address, bb(600000))
        await wbnb.mint(account0.address, bb(1000))
        await cake.mint(account0.address, bb(10000))

        await unirouter.connect(account0).addLiquidity(busd.address, wbnb.address, bb(400000), bb(1000), 0, 0, account0.address, DEADLINE)
        await unirouter.connect(account0).addLiquidity(busd.address, cake.address, bb(200000), bb(10000), 0, 0, account0.address, DEADLINE)
        pair1 = await ethers.getContractAt(
            'contracts/test/UniswapV2Pair.sol:UniswapV2Pair',
            await unifactory.getPair(busd.address, wbnb.address)
        )
        pair2 = await ethers.getContractAt(
            'contracts/test/UniswapV2Pair.sol:UniswapV2Pair',
            await unifactory.getPair(busd.address, cake.address)
        )

        lToken = await (await ethers.getContractFactory('LToken')).deploy('Deri Liquidity Token', 'DLT', 0)
        pToken = await (await ethers.getContractFactory('PToken')).deploy('Deri Position Token', 'DPT', 0, 0)
        router = await (await ethers.getContractFactory('PerpetualPoolRouter')).deploy(lToken.address, pToken.address, ZERO_ADDRESS)
        pool = await (await ethers.getContractFactory('PerpetualPool')).deploy(
            [
                await busd.decimals(),
                bb(0.2),  // minBToken0Ratio
                bb(1),    // minPoolMarginRatio
                bb(0.1),  // minInitialMarginRatio
                bb(0.05), // minMaintenanceMarginRatio
                bb(0),    // minLiquidationReward
                bb(1000), // maxLiquidationReward
                bb(0.5),  // liquidationCutRatio
                bb(0.2)   // protocolFeeCollectRatio
            ],
            [lToken.address, pToken.address, router.address, account0.address]
        )
        await pToken.setPool(pool.address)
        await lToken.setPool(pool.address)
        await router.setPool(pool.address)

        swapper1 = await (await ethers.getContractFactory('BTokenSwapper1')).deploy(
            unirouter.address, pair1.address, wbnb.address, busd.address, wbnb.address < busd.address, bb(0.2), bb(0.5)
        )
        swapper2 = await (await ethers.getContractFactory('BTokenSwapper1')).deploy(
            unirouter.address, pair2.address, cake.address, busd.address, cake.address < busd.address, bb(0.2), bb(0.5)
        )
        boracle1 = await (await ethers.getContractFactory('BTokenOracle1')).deploy(
            pair1.address, wbnb.address, busd.address, wbnb.address < busd.address
        )
        boracle2 = await (await ethers.getContractFactory('BTokenOracle1')).deploy(
            pair2.address, cake.address, busd.address, cake.address < busd.address
        )

        soracle1 = await (await ethers.getContractFactory('TSymbolHandler')).deploy()
        soracle2 = await (await ethers.getContractFactory('TSymbolHandler')).deploy()
        await soracle1.setPrice(bb(60000))
        await soracle2.setPrice(bb(3000))

        await router.addBToken(busd.address, ZERO_ADDRESS, ZERO_ADDRESS, bb(1))
        await router.addBToken(wbnb.address, swapper1.address, boracle1.address, bb(0.8))
        await router.addBToken(cake.address, swapper2.address, boracle2.address, bb(0.5))

        await router.addSymbol('BTCUSD', soracle1.address, bb(0.0001), bb(0.001), bb(0.0001))
        await router.addSymbol('ETHUSD', soracle2.address, bb(0.001), bb(0.002), bb(0.0002))

        for (account of [account0, account1, account2, account3]) {
            busd.mint(account.address, bb(1000000))
            wbnb.mint(account.address, bb(1000))
            cake.mint(account.address, bb(10000))

            busd.connect(account).approve(pool.address, MAX)
            wbnb.connect(account).approve(pool.address, MAX)
            cake.connect(account).approve(pool.address, MAX)
        }
    })

    it('test', async function () {
        await router.connect(account0).addLiquidity(0, bb(1000000))
        await router.connect(account1).addMargin(1, bb(100))
        await router.connect(account1).trade(0, bb(10000))

        await router.connect(account2).addLiquidity(2, bb(1000))
        await router.connect(account0).removeLiquidity(0, bb(10000))
        await router.connect(account0).addLiquidity(0, bb(10000))

        await soracle1.setPrice(bb(59000))
        await router.connect(account1).removeMargin(1, bb(10))
        await router.connect(account1).trade(0, bb(-100))

        await soracle1.setPrice(bb(28000))
        await router.connect(account3).functions['liquidate(address)'](account1.address)
        // await router.connect(account3).functions['liquidate(uint256)'](1)
    })

})

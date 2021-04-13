require('@nomiclabs/hardhat-ethers');
const hre = require('hardhat');

function rescale(value, fromDecimals, toDecimals) {
    let from = ethers.BigNumber.from('1' + '0'.repeat(fromDecimals));
    let to = ethers.BigNumber.from('1' + '0'.repeat(toDecimals));
    return ethers.BigNumber.from(value).mul(to).div(from);
}

const ONE = rescale(1, 0, 18);
const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';

let network;
let deployer;

async function logTransaction(title, transaction) {
    let receipt = await transaction.wait();
    if (receipt.contractAddress != null) {
        title = `${title}: ${receipt.contractAddress}`;
    }
    let gasEthers = transaction.gasPrice.mul(receipt.gasUsed);
    console.log('='.repeat(80));
    console.log(title);
    console.log('='.repeat(80));
    console.log(receipt);
    console.log(`Gas: ${ethers.utils.formatUnits(transaction.gasPrice, 'gwei')} GWei / ${receipt.gasUsed} / ${ethers.utils.formatEther(gasEthers)}`);
    console.log('');
    await new Promise(resolve => setTimeout(resolve, 2000));
}

async function getNetwork() {
    network = await ethers.provider.getNetwork();
    if (network.chainId === 97)
        network.name = 'bsctestnet';
    else if (network.chainId === 256)
        network.name = 'hecotestnet';
    [deployer] = await ethers.getSigners();

    console.log('='.repeat(80));
    console.log('Network and Deployer');
    console.log('='.repeat(80));
    console.log('Network:', network.name, network.chainId);
    console.log('Deployer:', deployer.address);
    console.log('Deployer Balance:', ethers.utils.formatEther(await deployer.getBalance()));
    console.log('');
}

let poolFactoryAddress = '0xBD600570dF9f32635c003B623900b03bf0971325';

let addresses = [
    '0xBEB5e7Fbe233f0BbE70309020cdBef02D395F895', // perpetualPoolTemplate
    '0x0619DeFEC4583172197F7F4544c94B50d77E424D', // pTokenTemplate
    '0x273f122Db312EfA27ab2aB809621c5848D1D2a16', // lTokenTemplate
    ZERO_ADDRESS,                                 // liquidatorQualifier
    '0x4C059dD7b01AAECDaA3d2cAf4478f17b9c690080', // dao
    '0x4C059dD7b01AAECDaA3d2cAf4478f17b9c690080', // poolController
];

let parameters = [
    ONE,            // minPoolMarginRatio
    ONE.div(10),    // minInitialMarginRatio
    ONE.div(20),    // minMaintenanceMarginRatio
    ONE.mul(10),    // minLiquidationReward
    ONE.mul(1000),  // maxLiquidationReward
    ONE.div(2),     // liquidationCutRatio
    ONE.div(4)      // daoFeeCollectRatio
];

let symbols = [
    [
        'BTCUSD',                                       // symbol
        '0x2e2619759889301709709E0bb4f19C402338F1e1',   // handlerAddress
        ONE.div(10000),                                 // multiplier
        ONE.div(10000),                                 // feeRatio
        ONE.div(100000)                                 // fundingRateCoefficient
    ],
    [
        'ETHUSD',                                       // symbol
        '0xE32f67f7C65884342E8B2faB2364a28D9f2A2Cf6',   // handlerAddress
        ONE.div(1000),                                  // multiplier
        ONE.div(10000),                                 // feeRatio
        ONE.div(100000)                                 // fundingRateCoefficient
    ]
];

let bTokens = [
    // USDT
    [
        '0x77F120dF3A2e518BdFDE4330a6140c77103271DA',   // bTokenAddress
        ZERO_ADDRESS,                                   // handlerAddress
        ONE                                             // discount
    ],
    // WETH
    [
        '0x2479FA8779C494b47A57e909417AACCe5c2e594d',   // bTokenAddress
        '0x559aea84ca9c27a5FcD112EB5a64Ff39410885b9',   // handlerAddress
        ONE.mul(8).div(10)                              // discount
    ],
    // SUSHI
    [
        '0xA1E0a0709f1eFE65833a088a4426da6d6BC14b9D',   // bTokenAddress
        '0xe544c58a74aD120406798f28105fFB12c28a6e41',   // handlerAddress
        ONE.mul(6).div(10)                              // discount
    ],
    // DAI
    [
        '0x436F052d6163bC714703F6d851dBEa828cf74f23',   // bTokenAddress
        '0x3fe571a553a1ec1c971a42e0141aaa7204e4735a',   // handlerAddress
        ONE.mul(9).div(10)                              // discount
    ]
];

let perpetualPoolAddress = '0xA62243929e166eAf031BD07fA5842BEee005E508';


async function deployPoolFactory() {
    let poolFactory = await (await ethers.getContractFactory('PoolFactory')).deploy();
    await logTransaction('PoolFactory', poolFactory.deployTransaction);
}

async function deployTemplates() {
    let perpetualPoolTemplate = await (await ethers.getContractFactory('PerpetualPool')).deploy();
    await logTransaction('PerpetualPoolTemplate', perpetualPoolTemplate.deployTransaction);

    let pTokenTemplate = await (await ethers.getContractFactory('PToken')).deploy();
    await logTransaction('PTokenTemplate', pTokenTemplate.deployTransaction);

    let lTokenTemplate = await (await ethers.getContractFactory('LToken')).deploy();
    await logTransaction('LTokenTemplate', lTokenTemplate.deployTransaction);
}

async function deployHandlers() {
    let sHandler1 = await (await ethers.getContractFactory('SymbolHandlerBTCUSDT')).deploy();
    await logTransaction('Symbol Handler BTCUSDT', sHandler1.deployTransaction);

    let sHandler2 = await (await ethers.getContractFactory('SymbolHandlerETHUSDT')).deploy();
    await logTransaction('Symbol Handler ETHUSDT', sHandler2.deployTransaction);

    // let bHandler2 = await (await ethers.getContractFactory('BTokenHandlerWETHUSDT')).deploy();
    // await logTransaction('BHandler WETHUSDT', bHandler2.deployTransaction);

    // let bHandler3 = await (await ethers.getContractFactory('BTokenHandlerSUSHIUSDT')).deploy();
    // await logTransaction('BHandler SUSHIUSDT', bHandler3.deployTransaction);

    // let bHandler4 = await (await ethers.getContractFactory('BTokenHandlerDAIUSDT')).deploy();
    // await logTransaction('BHandler DAIUSDT', bHandler4.deployTransaction);
}

async function createPerpetualPool() {
    let poolFactory = await ethers.getContractAt('PoolFactory', poolFactoryAddress);
    let tx = await poolFactory.createPerpetualPool(addresses, symbols, bTokens, parameters);
    await logTransaction('CreatePerpetualPool', tx);
}

async function initAccounts() {
    let [account1, account2, account3] = await ethers.getSigners();
    let max = ethers.BigNumber.from('0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff');

    let b1 = await ethers.getContractAt('TERC20', bTokens[0][0]);
    let b2 = await ethers.getContractAt('TERC20', bTokens[1][0]);
    let b3 = await ethers.getContractAt('TERC20', bTokens[2][0]);
    let b4 = await ethers.getContractAt('TERC20', bTokens[3][0]);

    let tx;

    tx = await b1.connect(account1).approve(perpetualPoolAddress, max); await logTransaction('Approve', tx);
    tx = await b2.connect(account1).approve(perpetualPoolAddress, max); await logTransaction('Approve', tx);
    tx = await b3.connect(account1).approve(perpetualPoolAddress, max); await logTransaction('Approve', tx);
    tx = await b4.connect(account1).approve(perpetualPoolAddress, max); await logTransaction('Approve', tx);

    tx = await b1.connect(account2).approve(perpetualPoolAddress, max); await logTransaction('Approve', tx);
    tx = await b2.connect(account2).approve(perpetualPoolAddress, max); await logTransaction('Approve', tx);
    tx = await b3.connect(account2).approve(perpetualPoolAddress, max); await logTransaction('Approve', tx);
    tx = await b4.connect(account2).approve(perpetualPoolAddress, max); await logTransaction('Approve', tx);

    tx = await b1.connect(account3).approve(perpetualPoolAddress, max); await logTransaction('Approve', tx);
    tx = await b2.connect(account3).approve(perpetualPoolAddress, max); await logTransaction('Approve', tx);
    tx = await b3.connect(account3).approve(perpetualPoolAddress, max); await logTransaction('Approve', tx);
    tx = await b4.connect(account3).approve(perpetualPoolAddress, max); await logTransaction('Approve', tx);
}

async function main() {
    await getNetwork();
    // await deployPoolFactory();
    // await deployTemplates();
    await deployHandlers();
    // await createPerpetualPool();
    // await initAccounts();
}

main()
.then(() => process.exit(0))
.catch(error => {
    console.error(error);
    process.exit(1);
});

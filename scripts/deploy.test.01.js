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

let cloneFactoryAddress = '0xbF777a34c62C3310117322ad03B053BC8e296e25';
let perpetualPoolTemplateAddress = '0x9055989Ae6B61ba87D4B4e2ceD2562B38337F35A';
let pTokenTemplateAddress = '0x6a01bbeA811f7dbC1034a46cDB85038EC8F83b53';
let lTokenTemplateAddress = '0xe92d5aCc83874F36cf473b3382A4d77bE72d2Bc9';
let perpetualPoolAddress = '0x95a8F9Eb0098edA7B2D5Dd904d8049730F2b5E49';
let pTokenAddress = '0xb0c3B2295a1bc0C391430aC2a4874258316f48Cb';

let parameters = {
    minPoolMarginRatio: ONE,
    minInitialMarginRatio: ONE.div(10),
    minMaintenanceMarginRatio: ONE.div(20),
    minLiquidationReward: ONE.mul(10),
    maxLiquidationReward: ONE.mul(1000),
    liquidationCutRatio: ONE.div(2),
    daoFeeCollectRatio: ONE.div(4)
};

let symol1 = {
    symbol: 'BTCUSD',
    handlerAddress: '0xFFF44f9DbB2aC1B95ce431A97bb627e2B0Dc0089',
    multiplier: ONE.mul(10000),
    feeRatio: ONE.div(10000),
    fundingRateCoefficient: ONE.div(100000)
};
let symbol2 = {
    symbol: 'ETHUSD',
    handlerAddress: '0x3dD43d122614f2D27d176cbE99ee1D5fbCE0bc01',
    multiplier: ONE.mul(1000),
    feeRatio: ONE.div(20000),
    fundingRateCoefficient: ONE.div(200000)
};
let bToken1 = {
    // USDT
    bTokenAddress: '0x77F120dF3A2e518BdFDE4330a6140c77103271DA',
    lTokenAddress: '0xd1eFAfaFEFeCafF9535CcAF786D888CE9043B30a',
    handlerAddress: ZERO_ADDRESS,
    decimals: 6,
    discount: ONE
};
let bToken2 = {
    // WETH
    bTokenAddress: '0x2479FA8779C494b47A57e909417AACCe5c2e594d',
    lTokenAddress: '0x5c58591dd73e5eB962dd4fD711485F5c064a029b',
    handlerAddress: '',
    decimals: 18,
    discount: ONE.mul(8).div(10)
};
let bToken3 = {
    // SUSHI
    bTokenAddress: '0xA1E0a0709f1eFE65833a088a4426da6d6BC14b9D',
    lTokenAddress: '0x58025C683e5EFFaC1d8621e799BeF8143fe521d3',
    handlerAddress: '',
    decimals: 18,
    discount: ONE.mul(6).div(10)
};
let bToken4 = {
    // DAI
    bTokenAddress: '0x436F052d6163bC714703F6d851dBEa828cf74f23',
    lTokenAddress: '0xB5960156e70c063a4613Db22Ba7D3bCA7fBA790d',
    handlerAddress: '',
    decimals: 18,
    discount: ONE.mul(9).div(10)
};

async function deploy() {

    // let cloneFactory = await (await ethers.getContractFactory('CloneFactory')).deploy();
    // await logTransaction('CloneFactory', cloneFactory.deployTransaction);

    // let perpetualPoolTemplate = await (await ethers.getContractFactory('PerpetualPool')).deploy();
    // await logTransaction('PerpetualPoolTemplate', perpetualPoolTemplate.deployTransaction);

    // let pTokenTemplate = await (await ethers.getContractFactory('PToken')).deploy();
    // await logTransaction('PTokenTemplate', pTokenTemplate.deployTransaction);

    // let lTokenTemplate = await (await ethers.getContractFactory('LToken')).deploy();
    // await logTransaction('LTokenTemplate', lTokenTemplate.deployTransaction);

    let cloneFactory = await ethers.getContractAt('CloneFactory', cloneFactoryAddress);
    let perpetualPoolTemplate = await ethers.getContractAt('PerpetualPool', perpetualPoolTemplateAddress);
    let pTokenTemplate = await ethers.getContractAt('PToken', pTokenTemplateAddress);
    let lTokenTemplate = await ethers.getContractAt('LToken', lTokenTemplateAddress);

    // await cloneFactory.clone(perpetualPoolTemplateAddress);
    // console.log('PerpetualPool', await cloneFactory.cloned());

    // await cloneFactory.clone(pTokenTemplateAddress);
    // console.log('PToken', await cloneFactory.cloned());

    let perpetualPool = await ethers.getContractAt('PerpetualPool', perpetualPoolAddress);
    let pToken = await ethers.getContractAt('PToken', pTokenAddress);

    // await perpetualPool.initialize(
    //     [
    //         parameters.minPoolMarginRatio,
    //         parameters.minInitialMarginRatio,
    //         parameters.minMaintenanceMarginRatio,
    //         parameters.minLiquidationReward,
    //         parameters.maxLiquidationReward,
    //         parameters.liquidationCutRatio,
    //         parameters.daoFeeCollectRatio
    //     ],
    //     [
    //         pTokenAddress,
    //         ZERO_ADDRESS,
    //         '0x4C059dD7b01AAECDaA3d2cAf4478f17b9c690080',
    //         '0x4C059dD7b01AAECDaA3d2cAf4478f17b9c690080'
    //     ]
    // );

    // await pToken.initialize('DeriV2 Position Token', 'DPT', 0, 0, perpetualPoolAddress);

    // let sHandler1 = await (await ethers.getContractFactory('SymbolHandlerBTCUSDT')).deploy();
    // await logTransaction('Symbol Handler BTCUSDT', sHandler1.deployTransaction);

    // let sHandler2 = await (await ethers.getContractFactory('SymbolHandlerETHUSDT')).deploy();
    // await logTransaction('Symbol Handler ETHUSDT', sHandler2.deployTransaction);

    // await cloneFactory.clone(lTokenTemplateAddress);
    // let lToken1 = await ethers.getContractAt('LToken', await cloneFactory.cloned());
    // console.log('lToken1', lToken1.address);
    // await lToken1.initialize('DeriV2 Liquidity Token', 'DLT', perpetualPoolAddress);

    // await cloneFactory.clone(lTokenTemplateAddress);
    // let lToken2 = await ethers.getContractAt('LToken', await cloneFactory.cloned());
    // console.log('lToken2', lToken2.address);
    // await lToken2.initialize('DeriV2 Liquidity Token', 'DLT', perpetualPoolAddress);

    // await cloneFactory.clone(lTokenTemplateAddress);
    // let lToken3 = await ethers.getContractAt('LToken', await cloneFactory.cloned());
    // console.log('lToken3', lToken3.address);
    // await lToken3.initialize('DeriV2 Liquidity Token', 'DLT', perpetualPoolAddress);

    await cloneFactory.clone(lTokenTemplateAddress);
    let lToken4 = await ethers.getContractAt('LToken', await cloneFactory.cloned());
    console.log('lToken4', lToken4.address);
    await lToken4.initialize('DeriV2 Liquidity Token', 'DLT', perpetualPoolAddress);


}

async function main() {
    await getNetwork();
    await deploy();
}

main()
.then(() => process.exit(0))
.catch(error => {
    console.error(error);
    process.exit(1);
});

require('@nomiclabs/hardhat-ethers');
const hre = require('hardhat');

function rescale(value, fromDecimals, toDecimals) {
    let from = ethers.BigNumber.from('1' + '0'.repeat(fromDecimals));
    let to = ethers.BigNumber.from('1' + '0'.repeat(toDecimals));
    return ethers.BigNumber.from(value).mul(to).div(from);
}

const ONE = rescale(1, 0, 18);

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

async function deployBTokens() {
    let TestTetherToken = await ethers.getContractFactory('TestTetherToken');
    let TERC20 = await ethers.getContractFactory('TERC20');

    // USDT
    let usdt = await TestTetherToken.deploy('Test Tether USDT', 'USDT');
    await logTransaction('USDT', usdt.deployTransaction);

    // AAA
    let aaa = await TERC20.deploy('Test ERC20 AAA', 'AAA', 18);
    await logTransaction('AAA', aaa.deployTransaction);

    // BBB
    let bbb = await TERC20.deploy('Test ERC20 BBB', 'BBB', 18);
    await logTransaction('BBB', bbb.deployTransaction);

    // CCC
    let ccc = await TERC20.deploy('Test ERC20 CCC', 'CCC', 18);
    await logTransaction('CCC', ccc.deployTransaction);
}

async function main() {
    await getNetwork();
    await deployBTokens();
}

main()
.then(() => process.exit(0))
.catch(error => {
    console.error(error);
    process.exit(1);
});

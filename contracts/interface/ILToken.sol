// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import './IERC721.sol';

interface ILToken is IERC721 {

    struct Asset {
        // amount of base token lp provided, i.e. WETH
        // this will be used as the weight to distribute future pnls
        int256 liquidity;
        // lp's pnl in bToken0
        int256 pnl;
        // snapshot of cumulativePnl for lp at last settlement point (add/remove liquidity), in bToken0, i.e. USDT
        int256 lastCumulativePnl;
    }

    event UpdateAsset(
        address owner,
        uint256 bTokenId,
        int256  liquidity,
        int256  pnl,
        int256  lastCumulativePnl
    );

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function pool() external view returns (address);

    function totalMinted() external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function numBTokens() external view returns (uint256);

    function setPool(address newPool) external;

    function setNumBTokens(uint256 num) external;

    function exists(address owner) external view returns (bool);

    function getAsset(address owner, uint256 bTokenId) external view returns (Asset memory);

    function getAssets(address owner) external view returns (Asset[] memory);

    function updateAsset(address owner, uint256 bTokenId, Asset memory asset) external;

    function mint(address owner) external;

    function burn(address owner) external;

}

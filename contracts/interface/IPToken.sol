// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

interface IPToken {

    struct Position {
        int256 volume;
        int256 cost;
        int256 lastCumuFundingRate;
    }

    function exists(address account) external view returns (bool);

    function getMargin(address account, uint256 bTokenId) external view returns (int256);

    function getMargins(address account) external view returns (int256[] memory);

    function getPosition(address account, uint256 symbolId) external view returns (Position memory);

    function getPositions(address account) external view returns (Position[] memory);

    function mint(address account, uint256 bTokenId, uint256 bAmount) external;

    function addMargin(address account, uint256 bTokenId, int256 amount) external;

    function updateMargin(address account, uint256 bTokenId, int256 amount) external;

    function updateMargins(address account, int256[] memory margins) external;

    function updatePosition(address account, uint256 symbolId, Position memory position) external;

}

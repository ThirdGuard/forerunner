// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {Test, console, Vm} from "forge-std/Test.sol";

import "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract BaseUtils is Test {
    // Api to modify test vm state.
    Vm internal constant FORGE_VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /*             */
    /* Forge Hacks */
    /*             */

    function modifyBalance(address token_, address user_, uint256 amount_) internal returns (uint256 slot_) {
        IERC20 erc20 = IERC20(token_);
        bool found;
        for (uint256 i = 0; i < 10; i++) {  
            // Get before value in case the slot is wrong, so can restore the value.
            bytes32 beforeValue = FORGE_VM.load(address(token_), keccak256(abi.encode(user_, slot_)));
            
            // Modify storage slot.
            FORGE_VM.store(address(token_), keccak256(abi.encode(user_, slot_)), bytes32(amount_));

            uint256 balance = erc20.balanceOf(user_);
            
            if (balance == amount_) {
                found = true;
                break;
            }

            // Restore value.
            FORGE_VM.store(address(token_), keccak256(abi.encode(user_, slot_)), beforeValue);
            slot_ += 1;
        }

        if (!found) {
            assertTrue(false, "Never found storage slot to modify for ERC20 balance hack.");
        }
    }

    function modifyBalanceWithKnownSlot(address token_, address user_, uint256 amount_, uint256 slot) internal {
        FORGE_VM.store(address(token_), keccak256(abi.encode(user_, slot)), bytes32(amount_));
    }

    /**
     * @dev Shifts block.timestamp and block.number ahead.
     * @param seconds_ to shift block.timestamp and block.number ahead.
     */
    function shift(uint256 seconds_) public {
        console.log("Shifting forward seconds", seconds_);
        FORGE_VM.warp(block.timestamp + seconds_);
        FORGE_VM.roll(block.number + getApproximateBlocksFromSeconds(seconds_));
    }

    /**
     * @dev Shifts block.timestamp and block.number ahead.
     * @param seconds_ to shift block.timestamp and block.number ahead.
     */
    function getApproximateBlocksFromSeconds(uint256 seconds_) public pure returns (uint256 blocks_) {
        uint256 secondsPerBlock = 14;
        return seconds_ / secondsPerBlock;
    }

    /*               */
    /* General Utils */
    /*               */

    function compareStrings(string memory a_, string memory b_) public pure returns (bool) {
        return (keccak256(abi.encodePacked((a_))) == keccak256(abi.encodePacked((b_))));
    }

    function toWei(uint256 amount, uint8 decimals) public pure returns(uint256){
        return amount*10**decimals;
    }

    function changeWei(uint256 amount, uint8 fromDecimals, uint8 toDecimals) public pure returns(uint256){
        return amount*10**toDecimals/10**fromDecimals;
    }
}
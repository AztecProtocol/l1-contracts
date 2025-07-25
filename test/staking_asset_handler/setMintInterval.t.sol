// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.27;

import {StakingAssetHandlerBase} from "./base.t.sol";
import {StakingAssetHandler, IStakingAssetHandler} from "@aztec/mock/StakingAssetHandler.sol";
import {Ownable} from "@oz/access/Ownable.sol";

// solhint-disable comprehensive-interface
// solhint-disable func-name-mixedcase
// solhint-disable ordering

contract SetMintIntervalTest is StakingAssetHandlerBase {
  function test_WhenCallerOfSetMintIntervalIsNotOwner(address _caller) external {
    vm.assume(_caller != address(this));
    // it reverts
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, _caller));
    vm.prank(_caller);
    stakingAssetHandler.setMintInterval(mintInterval);
  }

  function test_WhenCallerOfSetMintIntervalIsOwner(uint256 _newMintInterval) external {
    // it sets the mint interval
    // it emits a {IntervalUpdated} event
    vm.expectEmit(true, true, true, true, address(stakingAssetHandler));
    emit IStakingAssetHandler.IntervalUpdated(_newMintInterval);
    stakingAssetHandler.setMintInterval(_newMintInterval);
    assertEq(stakingAssetHandler.mintInterval(), _newMintInterval);
  }

  function test_WhenOwnerTriesToMintBeforeTheNewIntervalHasPassed(
    uint256 _newMintInterval,
    uint256 _jump
  ) external {
    // the "last mint timestamp" is 0 before the first mint

    _newMintInterval = bound(_newMintInterval, mintInterval + 1, 1e18);
    _jump = bound(_jump, 1, _newMintInterval);
    stakingAssetHandler.setMintInterval(_newMintInterval);

    vm.warp(_newMintInterval - _jump);

    uint256 lastMintTimestamp = stakingAssetHandler.lastMintTimestamp();

    // it reverts
    vm.expectRevert(
      abi.encodeWithSelector(
        IStakingAssetHandler.ValidatorQuotaFilledUntil.selector,
        lastMintTimestamp + _newMintInterval
      )
    );
    vm.prank(address(0xbeefdeef));
    stakingAssetHandler.addValidator(address(1), validMerkleProof, fakeProof);
  }

  function test_WhenOwnerTriesToMintAfterTheNewIntervalHasPassed(uint256 _newMintInterval) external {
    // it mints
    // it emits a {Minted} event
    // it updates the last mint timestamp

    _newMintInterval = bound(_newMintInterval, mintInterval + 1, type(uint24).max);
    setMockZKPassportVerifier();

    vm.expectEmit(true, true, true, true, address(stakingAssetHandler));
    emit IStakingAssetHandler.IntervalUpdated(_newMintInterval);
    stakingAssetHandler.setMintInterval(_newMintInterval);

    vm.warp(block.timestamp + _newMintInterval);

    vm.expectEmit(true, true, true, true, address(stakingAssetHandler));
    emit IStakingAssetHandler.ValidatorAdded(address(staking), address(1), WITHDRAWER);
    vm.prank(address(0xbeefdeef));
    stakingAssetHandler.addValidator(address(1), validMerkleProof, realProof);

    assertEq(stakingAssetHandler.lastMintTimestamp(), block.timestamp);
  }
}

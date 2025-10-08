// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.27;

import {TestBase} from "@test/base/Base.sol";
import {FailingERC20} from "@test/mocks/FailingERC20.sol";
import {RollupBuilder} from "@test/builder/RollupBuilder.sol";
import {IRollup} from "@aztec/core/interfaces/IRollup.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";

contract RollupNonCompliantAssetTest is TestBase {
  using stdStorage for StdStorage;

  IRollup internal rollup;
  FailingERC20 internal failingAsset;
  StdStorage private stdstore;
  address internal sequencer = address(0xBEEF);

  function setUp() public {
    failingAsset = new FailingERC20("fail", "FAIL", address(this));

    RollupBuilder builder = new RollupBuilder(address(this)).setSlashingQuorum(1).setSlashingRoundSize(1);
    builder.setTestERC20(failingAsset);
    builder.deploy();

    rollup = IRollup(address(builder.getConfig().rollup));
    failingAsset = FailingERC20(address(builder.getConfig().testERC20));

    address governance = address(builder.getConfig().governance);
    vm.prank(governance);
    rollup.setRewardsClaimable(true);
  }

  function test_ClaimSequencerRewardsRevertsWhenTransferFails() external {
    uint256 amount = 1e18;

    stdstore.target(address(rollup)).sig(IRollup.getSequencerRewards.selector).with_key(sequencer).checked_write(amount);

    deal(address(failingAsset), address(rollup), amount);

    failingAsset.setFailTransfer(true);

    vm.expectRevert();
    rollup.claimSequencerRewards(sequencer);
  }
}

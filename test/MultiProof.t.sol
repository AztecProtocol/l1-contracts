// SPDX-License-Identifier: Apache-2.0
// Copyright 2024 Aztec Labs.
pragma solidity >=0.8.27;

import {DecoderBase} from "./base/DecoderBase.sol";

import {Registry} from "@aztec/governance/Registry.sol";
import {FeeJuicePortal} from "@aztec/core/messagebridge/FeeJuicePortal.sol";
import {TestERC20} from "@aztec/mock/TestERC20.sol";
import {TestConstants} from "./harnesses/TestConstants.sol";
import {RewardDistributor} from "@aztec/governance/RewardDistributor.sol";
import {ProposeArgs, ProposeLib} from "@aztec/core/libraries/rollup/ProposeLib.sol";

import {Timestamp, Slot, Epoch, TimeLib} from "@aztec/core/libraries/TimeLib.sol";

import {Strings} from "@oz/utils/Strings.sol";
import {Errors} from "@aztec/core/libraries/Errors.sol";

import {RollupBase, IInstance} from "./base/RollupBase.sol";
import {RollupBuilder} from "./builder/RollupBuilder.sol";
import {Ownable} from "@oz/access/Ownable.sol";
import {stdStorage, StdStorage} from "forge-std/StdStorage.sol";
import {RewardBooster, ActivityScore} from "@aztec/core/reward-boost/RewardBooster.sol";
import {BoostedHelper} from "./boosted_rewards/BoostRewardHelper.sol";
// solhint-disable comprehensive-interface

/**
 * Blocks are generated using the `integration_l1_publisher.test.ts` tests.
 * Main use of these test is shorter cycles when updating the decoder contract.
 */
contract MultiProofTest is RollupBase {
  using stdStorage for StdStorage;
  using ProposeLib for ProposeArgs;
  using TimeLib for Timestamp;
  using TimeLib for Slot;
  using TimeLib for Epoch;

  Registry internal registry;
  TestERC20 internal testERC20;
  FeeJuicePortal internal feeJuicePortal;
  RewardDistributor internal rewardDistributor;
  RewardBooster internal rewardBooster;

  uint256 internal SLOT_DURATION;
  uint256 internal EPOCH_DURATION;

  address internal sequencer = address(bytes20("sequencer"));

  constructor() {
    TimeLib.initialize(
      block.timestamp,
      TestConstants.AZTEC_SLOT_DURATION,
      TestConstants.AZTEC_EPOCH_DURATION,
      TestConstants.AZTEC_PROOF_SUBMISSION_EPOCHS
    );
    SLOT_DURATION = TestConstants.AZTEC_SLOT_DURATION;
    EPOCH_DURATION = TestConstants.AZTEC_EPOCH_DURATION;
  }

  /**
   * @notice  Set up the contracts needed for the tests with time aligned to the provided block name
   */
  modifier setUpFor(string memory _name) {
    {
      DecoderBase.Full memory full = load(_name);
      uint256 slotNumber = Slot.unwrap(full.block.header.slotNumber);
      uint256 initialTime =
        Timestamp.unwrap(full.block.header.timestamp) - slotNumber * SLOT_DURATION;
      vm.warp(initialTime);
    }

    RollupBuilder builder = new RollupBuilder(address(this)).setTargetCommitteeSize(0);
    builder.deploy();

    rollup = IInstance(address(builder.getConfig().rollup));
    testERC20 = builder.getConfig().testERC20;

    feeJuicePortal = FeeJuicePortal(address(rollup.getFeeAssetPortal()));

    rewardBooster = RewardBooster(address(rollup.getRewardConfig().booster));

    // Deploy the test helper such that we can easily update storage and replace the implementation
    BoostedHelper boostedHelper = new BoostedHelper(rollup, rewardBooster.getConfig());
    vm.etch(address(rewardBooster), address(boostedHelper).code);

    _;
  }

  function warpToL2Slot(uint256 _slot) public {
    vm.warp(Timestamp.unwrap(rollup.getTimestampForSlot(Slot.wrap(_slot))));
  }

  function logStatus() public {
    uint256 provenBlockNumber = rollup.getProvenBlockNumber();
    uint256 pendingBlockNumber = rollup.getPendingBlockNumber();
    emit log_named_uint("proven block number", provenBlockNumber);
    emit log_named_uint("pending block number", pendingBlockNumber);

    address[2] memory provers = [address(bytes20("alice")), address(bytes20("bob"))];

    emit log_named_decimal_uint("sequencer rewards", rollup.getSequencerRewards(sequencer), 18);
    emit log_named_decimal_uint(
      "prover rewards", rollup.getCollectiveProverRewardsForEpoch(Epoch.wrap(0)), 18
    );

    for (uint256 i = 0; i < provers.length; i++) {
      for (uint256 j = 1; j <= provenBlockNumber; j++) {
        bool hasSubmitted = rollup.getHasSubmitted(Epoch.wrap(0), j, provers[i]);
        if (hasSubmitted) {
          emit log_named_string(
            string.concat("prover has submitted proof up till block ", Strings.toString(j)),
            string(abi.encode(provers[i]))
          );
        }
      }
      emit log_named_decimal_uint(
        string.concat("prover ", string(abi.encode(provers[i])), " rewards"),
        rollup.getSpecificProverRewardsForEpoch(Epoch.wrap(0), provers[i]),
        18
      );
    }
  }

  function testMultipleProvers() public setUpFor("mixed_block_1") {
    address alice = address(bytes20("alice"));
    address bob = address(bytes20("bob"));

    // We need to mint some fee asset to the portal to cover the 30M mana spent.
    deal(address(testERC20), address(feeJuicePortal), 30e6 * 1e18);

    _proposeBlock("mixed_block_1", 1, 15e6);
    _proposeBlock("mixed_block_2", 2, 15e6);

    assertEq(rollup.getProvenBlockNumber(), 0, "Block already proven");

    string memory name = "mixed_block_";
    _proveBlocks(name, 1, 1, alice);
    _proveBlocks(name, 1, 1, bob);
    _proveBlocks(name, 1, 2, bob);

    logStatus();

    assertTrue(rollup.getHasSubmitted(Epoch.wrap(0), 1, alice));
    assertFalse(rollup.getHasSubmitted(Epoch.wrap(0), 2, alice));
    assertTrue(rollup.getHasSubmitted(Epoch.wrap(0), 1, bob));
    assertTrue(rollup.getHasSubmitted(Epoch.wrap(0), 2, bob));

    assertEq(rollup.getProvenBlockNumber(), 2, "Block not proven");

    {
      // Ensure that we cannot claim rewards when not toggled yet
      vm.expectRevert(abi.encodeWithSelector(Errors.Rollup__RewardsNotClaimable.selector));
      rollup.claimSequencerRewards(sequencer);

      vm.expectRevert(abi.encodeWithSelector(Errors.Rollup__RewardsNotClaimable.selector));
      rollup.claimProverRewards(alice, new Epoch[](1));

      vm.prank(Ownable(address(rollup)).owner());
      rollup.setRewardsClaimable(true);
    }

    {
      uint256 sequencerRewards = rollup.getSequencerRewards(sequencer);
      assertGt(sequencerRewards, 0, "Sequencer rewards is zero");
      vm.prank(sequencer);
      uint256 sequencerRewardsClaimed = rollup.claimSequencerRewards(sequencer);
      assertEq(sequencerRewardsClaimed, sequencerRewards, "Sequencer rewards not claimed");
      assertEq(rollup.getSequencerRewards(sequencer), 0, "Sequencer rewards not zeroed");
    }

    Epoch[] memory epochs = new Epoch[](1);
    epochs[0] = Epoch.wrap(0);

    {
      uint256 aliceRewards = rollup.getSpecificProverRewardsForEpoch(Epoch.wrap(0), alice);
      assertEq(aliceRewards, 0, "Alice rewards not zero");
    }

    {
      uint256 bobRewards = rollup.getSpecificProverRewardsForEpoch(Epoch.wrap(0), bob);
      assertGt(bobRewards, 0, "Bob rewards is zero");

      Epoch deadline = TimeLib.toDeadlineEpoch(epochs[0]);

      vm.expectRevert(
        abi.encodeWithSelector(Errors.Rollup__NotPastDeadline.selector, deadline, Epoch.wrap(0))
      );
      vm.prank(bob);
      rollup.claimProverRewards(bob, epochs);

      vm.warp(Timestamp.unwrap(rollup.getTimestampForSlot(deadline.toSlots())));
      vm.prank(bob);
      uint256 bobRewardsClaimed = rollup.claimProverRewards(bob, epochs);

      assertEq(bobRewardsClaimed, bobRewards, "Bob rewards not claimed");
      assertEq(
        rollup.getSpecificProverRewardsForEpoch(Epoch.wrap(0), bob), 0, "Bob rewards not zeroed"
      );

      vm.expectRevert(
        abi.encodeWithSelector(Errors.Rollup__AlreadyClaimed.selector, bob, Epoch.wrap(0))
      );
      vm.prank(bob);
      rollup.claimProverRewards(bob, epochs);
    }
  }

  function testMultipleProversBoostedRewards() public setUpFor("mixed_block_1") {
    address alice = address(bytes20("alice"));
    address bob = address(bytes20("bob"));

    // We need to mint some fee asset to the portal to cover the 30M mana spent.
    deal(address(testERC20), address(feeJuicePortal), 30e6 * 1e18);

    _proposeBlock("mixed_block_1", 1, 15e6);
    _proposeBlock("mixed_block_2", 2, 15e6);

    assertEq(rollup.getProvenBlockNumber(), 0, "Block already proven");

    ActivityScore memory activityScore = rewardBooster.getActivityScore(alice);

    assertEq(
      rollup.getSharesFor(alice), rollup.getSharesFor(bob), "Alice shares not equal to bob shares"
    );

    uint256 maxActivityScore = TestConstants.getRewardBoostConfig().maxScore;
    uint256 maxShares = TestConstants.getRewardBoostConfig().k;

    BoostedHelper(address(rewardBooster)).setActivityScore(alice, maxActivityScore);

    assertGt(
      rollup.getSharesFor(alice),
      rollup.getSharesFor(bob),
      "Alice shares not greater than bob shares"
    );

    activityScore = rewardBooster.getActivityScore(alice);
    assertEq(activityScore.value, maxActivityScore, "Activity score not set");
    assertEq(rollup.getSharesFor(alice), maxShares, "Alice shares not set");

    assertEq(
      rollup.getSpecificProverRewardsForEpoch(Epoch.wrap(0), alice), 0, "Alice rewards not zeroed"
    );
    assertEq(
      rollup.getSpecificProverRewardsForEpoch(Epoch.wrap(0), bob), 0, "Bob rewards not zeroed"
    );

    string memory name = "mixed_block_";
    _proveBlocks(name, 1, 1, alice);
    _proveBlocks(name, 1, 1, bob);

    logStatus();

    assertTrue(rollup.getHasSubmitted(Epoch.wrap(0), 1, alice));
    assertTrue(rollup.getHasSubmitted(Epoch.wrap(0), 1, bob));
    assertEq(rollup.getProvenBlockNumber(), 1, "Block not proven");

    uint256 totalRewards = rollup.getCollectiveProverRewardsForEpoch(Epoch.wrap(0));
    uint256 totalShares = (rollup.getSharesFor(bob) + rollup.getSharesFor(alice));

    {
      uint256 aliceRewards = rollup.getSpecificProverRewardsForEpoch(Epoch.wrap(0), alice);
      assertEq(
        aliceRewards,
        totalRewards * rollup.getSharesFor(alice) / totalShares,
        "Alice rewards not correct"
      );
    }
    {
      uint256 bobRewards = rollup.getSpecificProverRewardsForEpoch(Epoch.wrap(0), bob);
      assertEq(
        bobRewards, totalRewards * rollup.getSharesFor(bob) / totalShares, "Bob rewards not correct"
      );
    }
  }

  function testNoHolesInProvenBlocks() public setUpFor("mixed_block_1") {
    _proposeBlock("mixed_block_1", 1, 15e6);
    _proposeBlock("mixed_block_2", TestConstants.AZTEC_EPOCH_DURATION + 1, 15e6);

    string memory name = "mixed_block_";
    _proveBlocksFail(
      name,
      2,
      2,
      address(bytes20("alice")),
      abi.encodeWithSelector(Errors.Rollup__StartIsNotBuildingOnProven.selector)
    );
  }

  function testProofsAreInOneEpoch() public setUpFor("mixed_block_1") {
    _proposeBlock("mixed_block_1", 1, 15e6);
    _proposeBlock("mixed_block_2", TestConstants.AZTEC_EPOCH_DURATION + 1, 15e6);

    string memory name = "mixed_block_";
    _proveBlocksFail(
      name,
      1,
      2,
      address(bytes20("alice")),
      abi.encodeWithSelector(Errors.Rollup__StartAndEndNotSameEpoch.selector, 0, 1)
    );
  }
}

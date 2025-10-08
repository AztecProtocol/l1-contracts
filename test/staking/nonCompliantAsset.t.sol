// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.27;

import {TestERC20} from "@aztec/mock/TestERC20.sol";
import {StakingBase} from "./base.t.sol";
import {FailingERC20} from "@test/mocks/FailingERC20.sol";
import {RollupBuilder} from "@test/builder/RollupBuilder.sol";
import {RollupConfigInput} from "@aztec/core/interfaces/IRollup.sol";
import {BN254Lib} from "@aztec/shared/libraries/BN254Lib.sol";

contract StakingNonCompliantAssetTest is StakingBase {
  FailingERC20 internal failingAsset;

  function setUp() public override {
    failingAsset = new FailingERC20("fail", "FAIL", address(this));

    RollupBuilder builder = new RollupBuilder(address(this)).setSlashingQuorum(1).setSlashingRoundSize(1);
    builder.setTestERC20(failingAsset);
    builder.deploy();

    registry = builder.getConfig().registry;

    RollupConfigInput memory rollupConfig = builder.getConfig().rollupConfigInput;
    EPOCH_DURATION_SECONDS = rollupConfig.aztecEpochDuration * rollupConfig.aztecSlotDuration;

    staking = IStaking(address(builder.getConfig().rollup));
    stakingAsset = TestERC20(address(failingAsset));

    ACTIVATION_THRESHOLD = staking.getActivationThreshold();
    EJECTION_THRESHOLD = staking.getEjectionThreshold();
    SLASHER = staking.getSlasher();
  }

  function test_DepositRevertsWhenTransferFromReturnsFalse() external {
    mint(address(this), ACTIVATION_THRESHOLD);
    stakingAsset.approve(address(staking), ACTIVATION_THRESHOLD);

    failingAsset.setFailTransferFrom(true);

    vm.expectRevert();
    staking.deposit({
      _attester: ATTESTER,
      _withdrawer: WITHDRAWER,
      _publicKeyInG1: BN254Lib.g1Zero(),
      _publicKeyInG2: BN254Lib.g2Zero(),
      _proofOfPossession: BN254Lib.g1Zero(),
      _moveWithLatestRollup: true
    });
  }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.27;

import {WithGSE} from "./base.sol";
import {FailingERC20} from "@test/mocks/FailingERC20.sol";
import {GSEBuilder} from "@test/builder/GseBuilder.sol";
import {BN254Lib} from "@aztec/shared/libraries/BN254Lib.sol";

contract GSENonCompliantAssetTest is WithGSE {
  FailingERC20 internal failingAsset;
  address internal rollup;

  function setUp() public override {
    failingAsset = new FailingERC20("fail", "FAIL", address(this));

    GSEBuilder builder = new GSEBuilder();
    builder.setTestERC20(failingAsset);
    builder.deploy();

    gse = builder.getConfig().gse;
    stakingAsset = TestERC20(address(failingAsset));
    governance = builder.getConfig().governance;

    rollup = address(0x1234);
    vm.prank(gse.owner());
    gse.addRollup(rollup);
  }

  function test_DepositRevertsWhenTransferOrApproveFails() external {
    uint256 activationThreshold = gse.ACTIVATION_THRESHOLD();

    vm.prank(stakingAsset.owner());
    stakingAsset.mint(rollup, activationThreshold);

    vm.prank(rollup);
    stakingAsset.approve(address(gse), activationThreshold);

    failingAsset.setFailTransferFrom(true);

    vm.prank(rollup);
    vm.expectRevert();
    gse.deposit(address(1), address(2), BN254Lib.g1Zero(), BN254Lib.g2Zero(), BN254Lib.g1Zero(), false);

    failingAsset.setFailTransferFrom(false);
    failingAsset.setFailApprove(true);

    vm.prank(rollup);
    vm.expectRevert();
    gse.deposit(address(1), address(2), BN254Lib.g1Zero(), BN254Lib.g2Zero(), BN254Lib.g1Zero(), false);
  }
}

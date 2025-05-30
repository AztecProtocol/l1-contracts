// SPDX-License-Identifier: Apache-2.0
// Copyright 2024 Aztec Labs.
pragma solidity >=0.8.27;

import {Test} from "forge-std/Test.sol";

import {NaiveMerkle} from "./Naive.sol";
import {FrontierMerkle} from "../harnesses/Frontier.sol";

contract FrontierTest is Test {
  function setUp() public {
    // Pause gas metering as calculating the root on each insert is expensive
    vm.pauseGasMetering();
  }

  function testFrontier() public {
    uint256 depth = 10;

    NaiveMerkle merkle = new NaiveMerkle(depth);
    FrontierMerkle frontier = new FrontierMerkle(depth);

    uint256 upper = frontier.SIZE();
    for (uint256 i = 0; i < upper; i++) {
      bytes32 leaf = sha256(abi.encode(i + 1));
      merkle.insertLeaf(leaf);
      frontier.insertLeaf(leaf);
      assertEq(merkle.computeRoot(), frontier.root(), "Frontier Roots should be equal");
    }
  }
}

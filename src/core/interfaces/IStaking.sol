// SPDX-License-Identifier: Apache-2.0
// Copyright 2024 Aztec Labs.
pragma solidity >=0.8.27;

import {SnapshottedAddressSet} from "@aztec/core/libraries/staking/AddressSnapshotLib.sol";
import {Timestamp} from "@aztec/core/libraries/TimeMath.sol";
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// None -> Does not exist in our setup
// Validating -> Participating as validator
// Living -> Not participating as validator, but have funds in setup,
// 			 hit if slashes and going below the minimum
// Exiting -> In the process of exiting the system
enum Status {
  NONE,
  VALIDATING,
  LIVING,
  EXITING
}

struct ValidatorInfo {
  uint256 stake;
  address withdrawer;
  address proposer;
  Status status;
}

struct OperatorInfo {
  address proposer;
  address attester;
}

struct Exit {
  Timestamp exitableAt;
  address recipient;
}

struct StakingStorage {
  IERC20 stakingAsset;
  address slasher;
  uint256 minimumStake;
  Timestamp exitDelay;
  SnapshottedAddressSet attesters;
  mapping(address attester => ValidatorInfo) info;
  mapping(address attester => Exit) exits;
}

interface IStakingCore {
  event Deposit(
    address indexed attester, address indexed proposer, address indexed withdrawer, uint256 amount
  );
  event WithdrawInitiated(address indexed attester, address indexed recipient, uint256 amount);
  event WithdrawFinalised(address indexed attester, address indexed recipient, uint256 amount);
  event Slashed(address indexed attester, uint256 amount);

  function deposit(address _attester, address _proposer, address _withdrawer, uint256 _amount)
    external;
  function initiateWithdraw(address _attester, address _recipient) external returns (bool);
  function finaliseWithdraw(address _attester) external;
  function slash(address _attester, uint256 _amount) external;
}

interface IStaking is IStakingCore {
  function getInfo(address _attester) external view returns (ValidatorInfo memory);
  function getExit(address _attester) external view returns (Exit memory);
  function getActiveAttesterCount() external view returns (uint256);
  function getAttesterAtIndex(uint256 _index) external view returns (address);
  function getProposerAtIndex(uint256 _index) external view returns (address);
  function getProposerForAttester(address _attester) external view returns (address);
  function getOperatorAtIndex(uint256 _index) external view returns (OperatorInfo memory);
  function getSlasher() external view returns (address);
  function getStakingAsset() external view returns (IERC20);
  function getMinimumStake() external view returns (uint256);
  function getExitDelay() external view returns (Timestamp);
}

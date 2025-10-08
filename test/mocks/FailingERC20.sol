// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.27;

import {TestERC20} from "@aztec/mock/TestERC20.sol";

contract FailingERC20 is TestERC20 {
  bool public failTransfer;
  bool public failTransferFrom;
  bool public failApprove;

  constructor(string memory _name, string memory _symbol, address _owner)
    TestERC20(_name, _symbol, _owner)
  {}

  function setFailTransfer(bool _shouldFail) external {
    failTransfer = _shouldFail;
  }

  function setFailTransferFrom(bool _shouldFail) external {
    failTransferFrom = _shouldFail;
  }

  function setFailApprove(bool _shouldFail) external {
    failApprove = _shouldFail;
  }

  function transfer(address _to, uint256 _value) public override returns (bool) {
    bool success = super.transfer(_to, _value);
    return failTransfer ? false : success;
  }

  function transferFrom(address _from, address _to, uint256 _value) public override returns (bool) {
    bool success = super.transferFrom(_from, _to, _value);
    return failTransferFrom ? false : success;
  }

  function approve(address _spender, uint256 _value) public override returns (bool) {
    bool success = super.approve(_spender, _value);
    return failApprove ? false : success;
  }
}

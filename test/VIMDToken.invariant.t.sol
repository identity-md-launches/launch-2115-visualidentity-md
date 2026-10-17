// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {VIMDToken} from "../src/VIMDToken.sol";

/// @dev Tracks an independent ledger over a closed set of local test actors.
contract TokenHandler is Test {
    VIMDToken public immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(VIMDToken token_) {
        token = token_;
        for (uint256 i; i < actors.length; ++i) {
            actors[i] = makeAddr(string.concat("invariant actor ", vm.toString(i)));
            expectedBalance[actors[i]] = 1_000_000_000 * 10 ** 18 / actors.length;
        }
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        amount = bound(amount, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        // Exercise revocations, the exact unlimited sentinel, and its finite neighbor.
        // Other finite approvals fit within the supply so they can actually be exhausted.
        uint256 mode = amount % 5;
        if (mode == 0) amount = 0;
        else if (mode == 1) amount = type(uint256).max;
        else if (mode == 2) amount = type(uint256).max - 1;
        else amount = bound(amount, 0, 1_000_000_000 * 10 ** 18);
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address to = _actor(toSeed);
        uint256 allowed = expectedAllowance[owner][spender];
        uint256 available = expectedBalance[owner];
        amount = bound(amount, 0, available < allowed ? available : allowed);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        expectedBalance[owner] -= amount;
        expectedBalance[to] += amount;
        if (allowed != type(uint256).max) expectedAllowance[owner][spender] -= amount;
    }

    function rejectedTransferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address to = _actor(toSeed);
        uint256 allowed = expectedAllowance[owner][spender];
        uint256 available = expectedBalance[owner];
        uint256 excessive = (available < allowed ? available : allowed) + 1;
        vm.prank(spender);
        (bool success, bytes memory reason) =
            address(token).call(abi.encodeCall(token.transferFrom, (owner, to, excessive)));
        assertFalse(success, "overspending must revert");
        if (allowed < excessive) {
            assertEq(
                reason,
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, excessive)
            );
        } else {
            assertEq(
                reason,
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, available, excessive)
            );
        }
        // The expected ledger is deliberately unchanged after this rejected action.
    }

    function rejectedTransfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 available = expectedBalance[from];
        amount = bound(amount, available + 1, type(uint256).max);
        vm.prank(from);
        (bool success, bytes memory reason) = address(token).call(abi.encodeCall(token.transfer, (to, amount)));
        assertFalse(success, "overdrawn transfers must revert even when from == to");
        assertEq(
            reason, abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, available, amount)
        );
    }

    function rejectedZeroReceiver(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool delegated) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 available = expectedBalance[owner];
        uint256 allowed = expectedAllowance[owner][spender];
        uint256 limit = delegated && allowed < available ? allowed : available;
        amount = bound(amount, 0, limit);
        bytes memory data = delegated
            ? abi.encodeCall(token.transferFrom, (owner, address(0), amount))
            : abi.encodeCall(token.transfer, (address(0), amount));
        vm.prank(delegated ? spender : owner);
        (bool success, bytes memory reason) = address(token).call(data);
        assertFalse(success, "transfers to zero must never burn");
        assertEq(reason, abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        // A delegated failure must roll back any allowance deduction as well.
    }

    function rejectedApproval(uint256 ownerSeed, uint256 amount) external {
        address owner = _actor(ownerSeed);
        vm.prank(owner);
        (bool success, bytes memory reason) = address(token).call(abi.encodeCall(token.approve, (address(0), amount)));
        assertFalse(success, "approval of zero spender must revert");
        assertEq(reason, abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
    }

    function _actor(uint256 seed) private view returns (address) {
        return actors[seed % actors.length];
    }
}

/// @dev Successful actions update the ghost ledger; failures leave it untouched.
/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract VIMDTokenInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    VIMDToken private token;
    TokenHandler private handler;

    function setUp() public {
        token = new VIMDToken();
        handler = new TokenHandler(token);
        // All actors start funded so early sequences can move nonzero value.
        for (uint256 i; i < 4; ++i) {
            assertTrue(token.transfer(handler.actors(i), SUPPLY / 4));
        }

        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = TokenHandler.transfer.selector;
        selectors[1] = TokenHandler.approve.selector;
        selectors[2] = TokenHandler.transferFrom.selector;
        selectors[3] = TokenHandler.rejectedTransferFrom.selector;
        selectors[4] = TokenHandler.rejectedTransfer.selector;
        selectors[5] = TokenHandler.rejectedZeroReceiver.selector;
        selectors[6] = TokenHandler.rejectedApproval.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariantSupplyAndBalancesMatchIndependentLedger() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            uint256 actual = token.balanceOf(actor);
            assertEq(actual, handler.expectedBalance(actor));
            sum += actual;
        }
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function invariantAllowancesMatchIndependentLedger() public view {
        for (uint256 i; i < 4; ++i) {
            assertEq(token.allowance(handler.actors(i), address(0)), 0);
            assertEq(token.allowance(address(0), handler.actors(i)), 0);
            for (uint256 j; j < 4; ++j) {
                address owner = handler.actors(i);
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
        }
    }

    function invariantMetadataNeverChanges() public view {
        assertEq(token.name(), "VisualIdentity.md");
        assertEq(token.symbol(), "VIMD");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
    }
}

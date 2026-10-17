// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {VIMDToken} from "../src/VIMDToken.sol";

/// @dev Local CREATE2 caller used to exercise the launch's deployment and transfer boundary.
contract TokenFactoryHarness {
    function deploy(bytes32 salt) external returns (VIMDToken) {
        return new VIMDToken{salt: salt}();
    }

    function send(VIMDToken token, address recipient, uint256 amount) external {
        require(token.transfer(recipient, amount));
    }
}

contract VIMDTokenTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;

    VIMDToken private token;
    address private deployer;
    address private alice;
    address private bob;
    address private spender;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        deployer = makeAddr("deployer");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        spender = makeAddr("spender");
        vm.prank(deployer);
        token = new VIMDToken();
    }

    function testMetadataAndInitialSupply() public view {
        assertEq(token.name(), "VisualIdentity.md");
        assertEq(token.symbol(), "VIMD");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.allowance(deployer, spender), 0);
    }

    function testConstructorEmitsExactlyOneMint() public {
        vm.recordLogs();
        vm.prank(alice);
        VIMDToken fresh = new VIMDToken();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(fresh));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(alice))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
        assertEq(fresh.balanceOf(alice), SUPPLY);
    }

    function testCreate2MintsToImmediateFactoryCaller() public {
        TokenFactoryHarness factory = new TokenFactoryHarness();
        bytes32 salt = keccak256("VIMD deployment test");
        address predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(bytes1(0xff), address(factory), salt, keccak256(type(VIMDToken).creationCode))
                    )
                )
            )
        );
        vm.prank(alice, alice);
        VIMDToken launched = factory.deploy(salt);
        assertEq(address(launched), predicted);
        assertEq(launched.balanceOf(address(factory)), SUPPLY);
        assertEq(launched.balanceOf(alice), 0);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    function testFactoryDistributionAndPoolTransfersArriveWhole() public {
        TokenFactoryHarness factory = new TokenFactoryHarness();
        VIMDToken launched = factory.deploy(keccak256("distribution test"));
        address distributor = makeAddr("distributor");
        address pool = makeAddr("pool manager transfer boundary");
        address remainder = makeAddr("remainder recipient");
        uint256 swarmShare = SUPPLY * 10 / 100;
        uint256 poolShare = SUPPLY * 88 / 100;
        uint256 remainderShare = SUPPLY * 2 / 100;

        factory.send(launched, distributor, swarmShare);
        factory.send(launched, pool, poolShare);
        factory.send(launched, remainder, remainderShare);
        assertEq(launched.balanceOf(address(factory)), 0);
        assertEq(launched.balanceOf(distributor), swarmShare);
        assertEq(launched.balanceOf(pool), poolShare);
        assertEq(launched.balanceOf(remainder), remainderShare);

        vm.prank(distributor);
        assertTrue(launched.transfer(alice, swarmShare));
        assertEq(launched.balanceOf(distributor), 0);
        assertEq(launched.balanceOf(alice), swarmShare);
        vm.prank(pool);
        assertTrue(launched.transfer(bob, 1 ether));
        assertEq(launched.balanceOf(bob), 1 ether);
        vm.prank(bob);
        assertTrue(launched.approve(spender, 1 ether));
        vm.prank(spender);
        assertTrue(launched.transferFrom(bob, pool, 1 ether));
        assertEq(launched.balanceOf(bob), 0);
        assertEq(launched.balanceOf(pool), poolShare);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    function testTransferSmallestUnitThenEntireRemainingBalance() public {
        vm.startPrank(deployer);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(deployer, alice, 1);
        assertTrue(token.transfer(alice, 1));
        assertTrue(token.transfer(alice, SUPPLY - 1));
        vm.stopPrank();
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testZeroValueTransferFromEmptyAccountEmitsEvent() public {
        vm.prank(alice);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testZeroValueTransferFromNeedsNoAllowance() public {
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function testApproveReplacesAndRevokesAllowance() public {
        vm.startPrank(deployer);
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(deployer, spender, 100);
        assertTrue(token.approve(spender, 100));
        assertTrue(token.approve(spender, 25));
        assertEq(token.allowance(deployer, spender), 25);
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(deployer, spender, 0);
        assertTrue(token.approve(spender, 0));
        vm.stopPrank();
        assertEq(token.allowance(deployer, spender), 0);
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        token.transferFrom(deployer, alice, 1);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function testTransferFromSpendsFiniteAllowanceAndEmitsTransfer() public {
        vm.prank(deployer);
        token.approve(spender, 50);
        vm.startPrank(spender);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(deployer, alice, 20);
        assertTrue(token.transferFrom(deployer, alice, 20));
        assertEq(token.allowance(deployer, spender), 30);
        assertTrue(token.transferFrom(deployer, alice, 30));
        vm.stopPrank();
        assertEq(token.allowance(deployer, spender), 0);
        assertEq(token.balanceOf(alice), 50);
        assertEq(token.balanceOf(deployer), SUPPLY - 50);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testInfiniteAllowanceIsNotReduced() public {
        vm.prank(deployer);
        token.approve(spender, type(uint256).max);
        vm.startPrank(spender);
        assertTrue(token.transferFrom(deployer, alice, 1));
        assertTrue(token.transferFrom(deployer, bob, SUPPLY - 1));
        vm.stopPrank();
        assertEq(token.allowance(deployer, spender), type(uint256).max);
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.balanceOf(alice) + token.balanceOf(bob), SUPPLY);
    }

    function testSelfTransferFromPreservesBalanceButSpendsAllowance() public {
        vm.prank(deployer);
        token.approve(spender, 10);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, deployer, 10));
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.allowance(deployer, spender), 0);
    }

    function testOwnerStillNeedsAllowanceForTransferFrom() public {
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, deployer, 0, 1));
        token.transferFrom(deployer, alice, 1);
    }

    function testTransferFromInsufficientBalanceRollsBackAllowance() public {
        vm.prank(alice);
        token.approve(spender, 10);
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 10));
        token.transferFrom(alice, bob, 10);
        assertEq(token.allowance(alice, spender), 10);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testTransferFromZeroReceiverRollsBackAllowance() public {
        vm.prank(deployer);
        token.approve(spender, 10);
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transferFrom(deployer, address(0), 10);
        assertEq(token.allowance(deployer, spender), 10);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
    }

    function testZeroSenderCannotTransferEvenZeroTokens() public {
        vm.prank(address(0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        token.transfer(alice, 0);
    }

    function testZeroOwnerCannotApprove() public {
        vm.prank(address(0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        token.approve(spender, 1);
    }

    function testNoMintBurnOrAdministrativeEntrypoints() public {
        bytes[] memory calls = new bytes[](18);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", alice, 1);
        calls[1] = abi.encodeWithSignature("mint(uint256)", 1);
        calls[2] = abi.encodeWithSignature("mint()");
        calls[3] = abi.encodeWithSignature("burn(uint256)", 1);
        calls[4] = abi.encodeWithSignature("burnFrom(address,uint256)", alice, 1);
        calls[5] = abi.encodeWithSignature("initialize(address)", alice);
        calls[6] = abi.encodeWithSignature("setMinter(address)", alice);
        calls[7] = abi.encodeWithSignature("transferOwnership(address)", alice);
        calls[8] = abi.encodeWithSignature("owner()");
        calls[9] = abi.encodeWithSignature("pause()");
        calls[10] = abi.encodeWithSignature("unpause()");
        calls[11] = abi.encodeWithSignature("blacklist(address)", alice);
        calls[12] = abi.encodeWithSignature("freeze(address)", alice);
        calls[13] = abi.encodeWithSignature("setBlacklist(address,bool)", alice, true);
        calls[14] = abi.encodeWithSignature("seize(address)", alice);
        calls[15] = abi.encodeWithSignature("upgradeTo(address)", bob);
        calls[16] = abi.encodeWithSignature("disableTransfers()");
        calls[17] = abi.encodeWithSignature("setTransfersEnabled(bool)", false);

        vm.prank(deployer);
        token.transfer(alice, 100);
        for (uint256 i; i < calls.length; ++i) {
            vm.prank(deployer);
            (bool deployerSucceeded,) = address(token).call(calls[i]);
            assertFalse(deployerSucceeded);
            vm.prank(bob);
            (bool strangerSucceeded,) = address(token).call(calls[i]);
            assertFalse(strangerSucceeded);
        }
        assertEq(token.balanceOf(alice), 100);
        assertEq(token.balanceOf(deployer), SUPPLY - 100);
        assertEq(token.totalSupply(), SUPPLY);
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, deployer, 0, 1));
        token.transferFrom(alice, deployer, 1);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 100));
        assertEq(token.balanceOf(bob), 100);
    }

    function testRuntimeHasNoDelegationOrDestructionOpcodes() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 opcode = uint8(runtime[i]);
            if (opcode >= 0x60 && opcode <= 0x7f) {
                i += opcode - 0x5f;
            } else {
                assertTrue(opcode != 0xf4 && opcode != 0xf2 && opcode != 0xff);
            }
        }
    }

    function testFuzzTransferConservesSupply(address recipient, uint256 amount) public {
        vm.assume(recipient != address(0) && recipient != deployer);
        amount = bound(amount, 0, SUPPLY);
        vm.prank(deployer);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(deployer), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzSelfTransferPreservesBalance(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        vm.prank(deployer);
        assertTrue(token.transfer(deployer, amount));
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzTransferOverBalanceReverts(uint256 amount) public {
        amount = bound(amount, SUPPLY + 1, type(uint256).max);
        vm.prank(deployer);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, amount)
        );
        token.transfer(alice, amount);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzTransferToZeroReverts(uint256 amount) public {
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), amount);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzApproveZeroSpenderReverts(uint256 amount) public {
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), amount);
        assertEq(token.allowance(deployer, address(0)), 0);
    }

    function testFuzzTransferFromCannotExceedAllowance(uint256 approved, uint256 requested) public {
        approved = bound(approved, 0, SUPPLY - 1);
        requested = bound(requested, approved + 1, SUPPLY);
        vm.prank(deployer);
        token.approve(spender, approved);
        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, requested)
        );
        token.transferFrom(deployer, alice, requested);
        assertEq(token.allowance(deployer, spender), approved);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function testFuzzTransferFromConservesSupply(uint256 approved, uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        approved = bound(approved, amount, type(uint256).max);
        vm.prank(deployer);
        token.approve(spender, approved);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, amount));
        uint256 remaining = approved == type(uint256).max ? approved : approved - amount;
        assertEq(token.allowance(deployer, spender), remaining);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(deployer), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }
}

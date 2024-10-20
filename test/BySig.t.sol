// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { CoreTest, CometHelpers, CometWrapper, ICometRewards } from "./CoreTest.sol";

// Tests for `permit` and `encumberBySig`
abstract contract BySigTest is CoreTest {
    bytes32 internal constant PERMIT_TYPEHASH = keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    function aliceAuthorization(uint256 amount, uint256 nonce, uint256 expiry) internal view returns (uint8, bytes32, bytes32) {
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, alice, bob, amount, nonce, expiry));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", cometWrapper.DOMAIN_SEPARATOR(), structHash));
        return vm.sign(alicePrivateKey, digest);
    }

    function aliceContractAuthorization(uint256 amount, uint256 nonce, uint256 expiry) internal view returns (uint8, bytes32, bytes32) {
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, aliceContract, bob, amount, nonce, expiry));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", cometWrapper.DOMAIN_SEPARATOR(), structHash));
        return vm.sign(alicePrivateKey, digest);
    }

    function aliceEncumberAuthorization(uint256 amount, uint256 nonce, uint256 expiry) internal view returns (uint8, bytes32, bytes32) {
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, alice, bob, amount, nonce, expiry));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", cometWrapper.DOMAIN_SEPARATOR(), structHash));
        return vm.sign(alicePrivateKey, digest);
    }

    function aliceContractEncumberAuthorization(uint256 amount, uint256 nonce, uint256 expiry) internal view returns (uint8, bytes32, bytes32) {
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, aliceContract, bob, amount, nonce, expiry));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", cometWrapper.DOMAIN_SEPARATOR(), structHash));
        return vm.sign(alicePrivateKey, digest);
    }

    /* ===== Permit ===== */

    function test_permit() public {
        // bob's allowance from alice is 0
        assertEq(cometWrapper.allowance(alice, bob), 0);

        uint256 allowance = 123e18;
        uint256 nonce = cometWrapper.nonces(alice);
        uint256 expiry = block.timestamp + 1000;

        (uint8 v, bytes32 r, bytes32 s) = aliceAuthorization(allowance, nonce, expiry);

        // bob calls permit with the signature
        vm.prank(bob);
        cometWrapper.permit(alice, bob, allowance, expiry, v, r, s);

        // bob's allowance from alice equals allowance
        assertEq(cometWrapper.allowance(alice, bob), allowance);

        // alice's nonce is incremented
        assertEq(cometWrapper.nonces(alice), nonce + 1);
    }

    function test_permit_revertsForBadOwner() public {
        // bob's allowance from alice is 0
        assertEq(cometWrapper.allowance(alice, bob), 0);

        uint256 allowance = 123e18;
        uint256 nonce = cometWrapper.nonces(alice);
        uint256 expiry = block.timestamp + 1000;

        (uint8 v, bytes32 r, bytes32 s) = aliceAuthorization(allowance, nonce, expiry);

        // bob calls permit with the signature, but he manipulates the owner
        vm.prank(bob);
        vm.expectRevert(CometWrapper.BadSignatory.selector);
        cometWrapper.permit(charlie, bob, allowance, expiry, v, r, s);

        // bob's allowance from alice is unchanged
        assertEq(cometWrapper.allowance(alice, bob), 0);

        // alice's nonce is not incremented
        assertEq(cometWrapper.nonces(alice), nonce);
    }

    function test_permit_revertsForBadSpender() public {
        // bob's allowance from alice is 0
        assertEq(cometWrapper.allowance(alice, bob), 0);

        uint256 allowance = 123e18;
        uint256 nonce = cometWrapper.nonces(alice);
        uint256 expiry = block.timestamp + 1000;

        (uint8 v, bytes32 r, bytes32 s) = aliceAuthorization(allowance, nonce, expiry);

        // bob calls permit with the signature, but he manipulates the spender
        vm.prank(bob);
        vm.expectRevert(CometWrapper.BadSignatory.selector);
        cometWrapper.permit(alice, charlie, allowance, expiry, v, r, s);

        // bob's allowance from alice is unchanged
        assertEq(cometWrapper.allowance(alice, bob), 0);

        // alice's nonce is not incremented
        assertEq(cometWrapper.nonces(alice), nonce);
    }

    function test_permit_revertsForBadAmount() public {
        // bob's allowance from alice is 0
        assertEq(cometWrapper.allowance(alice, bob), 0);

        uint256 allowance = 123e18;
        uint256 nonce = cometWrapper.nonces(alice);
        uint256 expiry = block.timestamp + 1000;

        (uint8 v, bytes32 r, bytes32 s) = aliceAuthorization(allowance, nonce, expiry);

        // bob calls permit with the signature, but he manipulates the allowance
        vm.prank(bob);
        vm.expectRevert(CometWrapper.BadSignatory.selector);
        cometWrapper.permit(alice, bob, allowance + 1 wei, expiry, v, r, s);

        // bob's allowance from alice is unchanged
        assertEq(cometWrapper.allowance(alice, bob), 0);

        // alice's nonce is not incremented
        assertEq(cometWrapper.nonces(alice), nonce);
    }

    function test_permit_revertsForBadExpiry() public {
        // bob's allowance from alice is 0
        assertEq(cometWrapper.allowance(alice, bob), 0);

        uint256 allowance = 123e18;
        uint256 nonce = cometWrapper.nonces(alice);
        uint256 expiry = block.timestamp + 1000;

        (uint8 v, bytes32 r, bytes32 s) = aliceAuthorization(allowance, nonce, expiry);

        // bob calls permit with the signature, but he manipulates the expiry
        vm.prank(bob);
        vm.expectRevert(CometWrapper.BadSignatory.selector);
        cometWrapper.permit(alice, bob, allowance, expiry + 1, v, r, s);

        // bob's allowance from alice is unchanged
        assertEq(cometWrapper.allowance(alice, bob), 0);

        // alice's nonce is not incremented
        assertEq(cometWrapper.nonces(alice), nonce);
    }

    function test_permit_revertsForBadNonce() public {
        // bob's allowance from alice is 0
        assertEq(cometWrapper.allowance(alice, bob), 0);

        // alice signs an authorization with an invalid nonce
        uint256 allowance = 123e18;
        uint256 nonce = cometWrapper.nonces(alice);
        uint256 badNonce = nonce + 1;
        uint256 expiry = block.timestamp + 1000;

        (uint8 v, bytes32 r, bytes32 s) = aliceAuthorization(allowance, badNonce, expiry);

        // bob calls permit with the signature with an invalid nonce
        vm.prank(bob);
        vm.expectRevert(CometWrapper.BadSignatory.selector);
        cometWrapper.permit(alice, bob, allowance, expiry, v, r, s);

        // bob's allowance from alice is unchanged
        assertEq(cometWrapper.allowance(alice, bob), 0);

        // alice's nonce is not incremented
        assertEq(cometWrapper.nonces(alice), nonce);
    }

    function test_permit_revertsOnRepeatedCall() public {
        // bob's allowance from alice is 0
        assertEq(cometWrapper.allowance(alice, bob), 0);

        uint256 allowance = 123e18;
        uint256 nonce = cometWrapper.nonces(alice);
        uint256 expiry = block.timestamp + 1000;

        (uint8 v, bytes32 r, bytes32 s) = aliceAuthorization(allowance, nonce, expiry);

        // bob calls permit with the signature
        vm.prank(bob);
        cometWrapper.permit(alice, bob, allowance, expiry, v, r, s);

        // bob's allowance from alice equals allowance
        assertEq(cometWrapper.allowance(alice, bob), allowance);

        // alice's nonce is incremented
        assertEq(cometWrapper.nonces(alice), nonce + 1);

        // alice revokes bob's allowance
        vm.prank(alice);
        cometWrapper.approve(bob, 0);
        assertEq(cometWrapper.allowance(alice, bob), 0);

        // bob tries to reuse the same signature twice
        vm.prank(bob);
        vm.expectRevert(CometWrapper.BadSignatory.selector);
        cometWrapper.permit(alice, bob, allowance, expiry, v, r, s);

        // bob's allowance from alice is unchanged
        assertEq(cometWrapper.allowance(alice, bob), 0);

        // alice's nonce is not incremented
        assertEq(cometWrapper.nonces(alice), nonce + 1);
    }

    function test_permit_revertsForExpiredSignature() public {
        // bob's allowance from alice is 0
        assertEq(cometWrapper.allowance(alice, bob), 0);

        uint256 allowance = 123e18;
        uint256 nonce = cometWrapper.nonces(alice);
        uint256 expiry = block.timestamp + 1000;

        (uint8 v, bytes32 r, bytes32 s) = aliceAuthorization(allowance, nonce, expiry);

        // the expiry block arrives
        vm.warp(expiry + 1);

        // bob calls permit with the signature after the expiry
        vm.prank(bob);
        vm.expectRevert(CometWrapper.SignatureExpired.selector);
        cometWrapper.permit(alice, bob, allowance, expiry, v, r, s);

        // bob's allowance from alice is unchanged
        assertEq(cometWrapper.allowance(alice, bob), 0);

        // alice's nonce is not incremented
        assertEq(cometWrapper.nonces(alice), nonce);
    }

    function test_permit_revertsInvalidS() public {
        // bob's allowance from alice is 0
        assertEq(cometWrapper.allowance(alice, bob), 0);

        uint256 allowance = 123e18;
        uint256 nonce = cometWrapper.nonces(alice);
        uint256 expiry = block.timestamp + 1000;

        (uint8 v, bytes32 r, ) = aliceAuthorization(allowance, nonce, expiry);

        // 1 greater than the max value of s
        bytes32 invalidS = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A1;

        // bob calls permit with the signature with invalid `s` value
        vm.prank(bob);
        vm.expectRevert(CometWrapper.InvalidSignatureS.selector);
        cometWrapper.permit(alice, bob, allowance, expiry, v, r, invalidS);

        // bob's allowance from alice is unchanged
        assertEq(cometWrapper.allowance(alice, bob), 0);

        // alice's nonce is not incremented
        assertEq(cometWrapper.nonces(alice), nonce);
    }

    /* ===== EIP1271 Tests ===== */

    function test_permitEIP1271() public {
        // bob's allowance from alice's contract is 0
        assertEq(cometWrapper.allowance(aliceContract, bob), 0);

        uint256 allowance = 123e18;
        uint256 nonce = cometWrapper.nonces(aliceContract);
        uint256 expiry = block.timestamp + 1000;

        (uint8 v, bytes32 r, bytes32 s) = aliceContractAuthorization(allowance, nonce, expiry);

        // bob calls permit with the signature
        vm.prank(bob);
        cometWrapper.permit(aliceContract, bob, allowance, expiry, v, r, s);

        // bob's allowance from alice's contract equals allowance
        assertEq(cometWrapper.allowance(aliceContract, bob), allowance);

        // alice's contract's nonce is incremented
        assertEq(cometWrapper.nonces(aliceContract), nonce + 1);
    }

    function test_permit_revertsForBadOwnerEIP1271() public {
        // bob's allowance from alice's contract is 0
        assertEq(cometWrapper.allowance(aliceContract, bob), 0);

        uint256 allowance = 123e18;
        uint256 nonce = cometWrapper.nonces(aliceContract);
        uint256 expiry = block.timestamp + 1000;

        (uint8 v, bytes32 r, bytes32 s) = aliceContractAuthorization(allowance, nonce, expiry);

        // bob calls permit with the signature, but he manipulates the owner
        vm.prank(bob);
        vm.expectRevert(CometWrapper.BadSignatory.selector);
        cometWrapper.permit(charlie, bob, allowance, expiry, v, r, s);

        // bob's allowance from alice's contract is unchanged
        assertEq(cometWrapper.allowance(aliceContract, bob), 0);

        // alice's contract's nonce is not incremented
        assertEq(cometWrapper.nonces(aliceContract), nonce);
    }

    function test_permit_revertsForBadSpenderEIP1271() public {
        // bob's allowance from alice's contract is 0
        assertEq(cometWrapper.allowance(aliceContract, bob), 0);

        uint256 allowance = 123e18;
        uint256 nonce = cometWrapper.nonces(aliceContract);
        uint256 expiry = block.timestamp + 1000;

        (uint8 v, bytes32 r, bytes32 s) = aliceContractAuthorization(allowance, nonce, expiry);

        // bob calls permit with the signature, but he manipulates the spender
        vm.prank(bob);
        vm.expectRevert(CometWrapper.BadSignatory.selector);
        cometWrapper.permit(aliceContract, charlie, allowance, expiry, v, r, s);

        // bob's allowance from alice's contract is unchanged
        assertEq(cometWrapper.allowance(aliceContract, bob), 0);

        // alice's contract's nonce is not incremented
        assertEq(cometWrapper.nonces(aliceContract), nonce);
    }

    function test_permit_revertsForBadAmountEIP1271() public {
        // bob's allowance from alice's contract is 0
        assertEq(cometWrapper.allowance(aliceContract, bob), 0);

        uint256 allowance = 123e18;
        uint256 nonce = cometWrapper.nonces(aliceContract);
        uint256 expiry = block.timestamp + 1000;

        (uint8 v, bytes32 r, bytes32 s) = aliceContractAuthorization(allowance, nonce, expiry);

        // bob calls permit with the signature, but he manipulates the allowance
        vm.prank(bob);
        vm.expectRevert(CometWrapper.BadSignatory.selector);
        cometWrapper.permit(aliceContract, bob, allowance + 1 wei, expiry, v, r, s);

        // bob's allowance from alice's contract is unchanged
        assertEq(cometWrapper.allowance(aliceContract, bob), 0);

        // alice's contract's nonce is not incremented
        assertEq(cometWrapper.nonces(aliceContract), nonce);
    }

    function test_permit_revertsForBadExpiryEIP1271() public {
        // bob's allowance from alice's contract is 0
        assertEq(cometWrapper.allowance(aliceContract, bob), 0);

        uint256 allowance = 123e18;
        uint256 nonce = cometWrapper.nonces(aliceContract);
        uint256 expiry = block.timestamp + 1000;

        (uint8 v, bytes32 r, bytes32 s) = aliceContractAuthorization(allowance, nonce, expiry);

        // bob calls permit with the signature, but he manipulates the expiry
        vm.prank(bob);
        vm.expectRevert(CometWrapper.BadSignatory.selector);
        cometWrapper.permit(aliceContract, bob, allowance, expiry + 1, v, r, s);

        // bob's allowance from alice's contract is unchanged
        assertEq(cometWrapper.allowance(aliceContract, bob), 0);

        // alice's contract's nonce is not incremented
        assertEq(cometWrapper.nonces(alice), nonce);
    }

    function test_permit_revertsForBadNonceEIP1271() public {
        // bob's allowance from alice's contract is 0
        assertEq(cometWrapper.allowance(aliceContract, bob), 0);

        // alice signs an authorization with an invalid nonce
        uint256 allowance = 123e18;
        uint256 nonce = cometWrapper.nonces(aliceContract);
        uint256 badNonce = nonce + 1;
        uint256 expiry = block.timestamp + 1000;

        (uint8 v, bytes32 r, bytes32 s) = aliceContractAuthorization(allowance, badNonce, expiry);

        // bob calls permit with the signature with an invalid nonce
        vm.prank(bob);
        vm.expectRevert(CometWrapper.BadSignatory.selector);
        cometWrapper.permit(aliceContract, bob, allowance, expiry, v, r, s);

        // bob's allowance from alice's contract is unchanged
        assertEq(cometWrapper.allowance(aliceContract, bob), 0);

        // alice's contract's nonce is not incremented
        assertEq(cometWrapper.nonces(aliceContract), nonce);
    }

    function test_permit_revertsOnRepeatedCallEIP1271() public {
        // bob's allowance from alice's contract is 0
        assertEq(cometWrapper.allowance(aliceContract, bob), 0);

        uint256 allowance = 123e18;
        uint256 nonce = cometWrapper.nonces(aliceContract);
        uint256 expiry = block.timestamp + 1000;

        (uint8 v, bytes32 r, bytes32 s) = aliceContractAuthorization(allowance, nonce, expiry);

        // bob calls permit with the signature
        vm.prank(bob);
        cometWrapper.permit(aliceContract, bob, allowance, expiry, v, r, s);

        // bob's allowance from alice's contract equals allowance
        assertEq(cometWrapper.allowance(aliceContract, bob), allowance);

        // alice's contract's nonce is incremented
        assertEq(cometWrapper.nonces(aliceContract), nonce + 1);

        // alice revokes bob's allowance
        vm.prank(aliceContract);
        cometWrapper.approve(bob, 0);
        assertEq(cometWrapper.allowance(aliceContract, bob), 0);

        // bob tries to reuse the same signature twice
        vm.prank(bob);
        vm.expectRevert(CometWrapper.BadSignatory.selector);
        cometWrapper.permit(aliceContract, bob, allowance, expiry, v, r, s);

        // bob's allowance from alice's contract is unchanged
        assertEq(cometWrapper.allowance(aliceContract, bob), 0);

        // alice's contract's nonce is not incremented
        assertEq(cometWrapper.nonces(aliceContract), nonce + 1);
    }

    function test_permit_revertsForExpiredSignatureEIP1271() public {
        // bob's allowance from alice's contract is 0
        assertEq(cometWrapper.allowance(aliceContract, bob), 0);

        uint256 allowance = 123e18;
        uint256 nonce = cometWrapper.nonces(aliceContract);
        uint256 expiry = block.timestamp + 1000;

        (uint8 v, bytes32 r, bytes32 s) = aliceContractAuthorization(allowance, nonce, expiry);

        // the expiry block arrives
        vm.warp(expiry + 1);

        // bob calls permit with the signature after the expiry
        vm.prank(bob);
        vm.expectRevert(CometWrapper.SignatureExpired.selector);
        cometWrapper.permit(aliceContract, bob, allowance, expiry, v, r, s);

        // bob's allowance from alice's contract is unchanged
        assertEq(cometWrapper.allowance(aliceContract, bob), 0);

        // alice's contract's nonce is not incremented
        assertEq(cometWrapper.nonces(aliceContract), nonce);
    }

    function test_permit_revertsInvalidVEIP1271() public {
        // bob's allowance from alice's contract is 0
        assertEq(cometWrapper.allowance(aliceContract, bob), 0);

        uint256 allowance = 123e18;
        uint256 nonce = cometWrapper.nonces(aliceContract);
        uint256 expiry = block.timestamp + 1000;

        (, bytes32 r, bytes32 s) = aliceContractAuthorization(allowance, nonce, expiry);
        uint8 invalidV = 26;

        // bob calls permit with the signature with invalid `v` value
        vm.prank(bob);
        vm.expectRevert(CometWrapper.EIP1271VerificationFailed.selector);
        cometWrapper.permit(aliceContract, bob, allowance, expiry, invalidV, r, s);

        // bob's allowance from alice's contract is unchanged
        assertEq(cometWrapper.allowance(aliceContract, bob), 0);

        // alice's contract's nonce is not incremented
        assertEq(cometWrapper.nonces(aliceContract), nonce);
    }

    function test_permit_revertsInvalidSEIP1271() public {
        // bob's allowance from alice's contract is 0
        assertEq(cometWrapper.allowance(aliceContract, bob), 0);

        uint256 allowance = 123e18;
        uint256 nonce = cometWrapper.nonces(aliceContract);
        uint256 expiry = block.timestamp + 1000;

        (uint8 v, bytes32 r, ) = aliceContractAuthorization(allowance, nonce, expiry);

        // 1 greater than the max value of s
        bytes32 invalidS = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A1;

        // bob calls permit with the signature with invalid `s` value
        vm.prank(bob);
        vm.expectRevert(CometWrapper.EIP1271VerificationFailed.selector);
        cometWrapper.permit(aliceContract, bob, allowance, expiry, v, r, invalidS);

        // bob's allowance from alice's contract is unchanged
        assertEq(cometWrapper.allowance(aliceContract, bob), 0);

        // alice's contract's nonce is not incremented
        assertEq(cometWrapper.nonces(aliceContract), nonce);
    }
}

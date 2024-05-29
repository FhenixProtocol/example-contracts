// SPDX-License-Identifier: MIT
// Description: ERC20 contract with support for encrypted balance and transfer.
pragma solidity ^0.8.19;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { FHE, euint32, inEuint32 } from "@fhenixprotocol/contracts/FHE.sol";
import { Permissioned, Permission } from "@fhenixprotocol/contracts/access/Permissioned.sol";

error ErrorInsufficientFunds();

contract WrappingERC20 is ERC20, Permissioned {

    // A mapping from address to an encrypted balance.
    mapping(address => euint32) internal _encBalances;
    mapping(address => mapping(address => euint32)) internal _allowed;

    euint32 internal totalEncryptedSupply = FHE.asEuint32(0);

    constructor(string memory name, string memory symbol)
        ERC20(
            bytes(name).length == 0 ? "FHE Token" : name,
            bytes(symbol).length == 0 ? "FHE" : symbol
        )
    {
        // Mint 100 tokens to msg.sender
        // _mint(msg.sender, 100 * 10 ** uint(decimals()));
    }

    function _allowanceEncrypted(address owner, address spender) public view virtual returns (euint32) {
        return _allowed[owner][spender];
    }
    function allowanceEncrypted(
        address spender,
        Permission calldata permission
    ) public view virtual onlySender(permission) returns (string memory) {
        return FHE.sealoutput(_allowanceEncrypted(msg.sender, spender), permission.publicKey);
    }

    function approveEncrypted(address spender, inEuint32 calldata value) public virtual returns (bool) {
        _approve(msg.sender, spender, FHE.asEuint32(value));
        return true;
    }

    function _approve(address owner, address spender, euint32 value) internal {
        if (owner == address(0)) {
            revert ERC20InvalidApprover(address(0));
        }
        if (spender == address(0)) {
            revert ERC20InvalidSpender(address(0));
        }
        _allowed[owner][spender] = value;
    }

    function _spendAllowance(address owner, address spender, euint32 value) internal virtual returns (euint32) {
        euint32 currentAllowance = _allowanceEncrypted(owner, spender);
        euint32 spent = FHE.min(currentAllowance, value);
        _approve(owner, spender, (currentAllowance - spent));

        return spent;
    }



    function wrap(uint32 amount) public {
        if (balanceOf(msg.sender) < amount) {
            revert ErrorInsufficientFunds();
        }

        _burn(msg.sender, amount);
        euint32 eAmount = FHE.asEuint32(amount);
        _encBalances[msg.sender] =_encBalances[msg.sender] + eAmount;
        totalEncryptedSupply = totalEncryptedSupply + eAmount;
    }

    function unwrap(uint32 amount) public {
        euint32 encAmount = FHE.asEuint32(amount);

        euint32 amountToUnwrap = FHE.select(_encBalances[msg.sender].gt(encAmount), FHE.asEuint32(0), encAmount);

        _encBalances[msg.sender] = _encBalances[msg.sender] - amountToUnwrap;
        totalEncryptedSupply = totalEncryptedSupply - amountToUnwrap;

        _mint(msg.sender, FHE.decrypt(amountToUnwrap));
    }

    function mint(uint256 amount) public {
        _mint(msg.sender, amount);
    }

    function mintEncrypted(inEuint32 calldata encryptedAmount) public {
        euint32 amount = FHE.asEuint32(encryptedAmount);
        if (!FHE.isInitialized(_encBalances[msg.sender])) {
            _encBalances[msg.sender] = amount;
        } else {
            _encBalances[msg.sender] = _encBalances[msg.sender] + amount;
        }

        totalEncryptedSupply = totalEncryptedSupply + amount;
    }

    function transferEncrypted(address to, inEuint32 calldata encryptedAmount) public {
        _transferEncrypted(to, FHE.asEuint32(encryptedAmount));
    }

    // Transfers an amount from the message sender address to the `to` address.
    function _transferEncrypted(address to, euint32 amount) internal {
        _transferImpl(msg.sender, to, amount);
    }

        // Transfers an encrypted amount.
    function _transferImpl(address from, address to, euint32 amount) internal {
        // Make sure the sender has enough tokens.
        euint32 amountToSend = FHE.select(amount.lte(_encBalances[from]), amount, FHE.asEuint32(0));

        // Add to the balance of `to` and subract from the balance of `from`.
        _encBalances[to] = _encBalances[to] + amountToSend;
        _encBalances[from] = _encBalances[from] - amountToSend;
    }

    function balanceOfEncrypted(
        address account, Permission memory auth
    ) virtual public view onlyPermitted(auth, account) returns (string memory) {
        return _encBalances[account].seal(auth.publicKey);
    }

    function getEncryptedTotalSupply(
        Permission calldata permission
    ) public view onlySender(permission) returns (string memory) {
        return totalEncryptedSupply.seal(permission.publicKey);
    }

}

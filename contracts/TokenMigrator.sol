// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20, ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract NewToken is ERC20, ERC20Burnable, ERC20Permit, Ownable {
    constructor() ERC20("NewToken", "RAISE") ERC20Permit("NewToken") {
        _mint(msg.sender, 210000000 * 10 ** decimals());
    }

    function mint(address _to, uint _amount) external onlyOwner {
        _mint(_to, _amount * 10 ** decimals());
    }
}

contract Migrator is Ownable {
    IERC20 public immutable oldToken;
    NewToken public newToken;
    uint256 public constant MIGRATE_RATE = 10;
    bool public migrationEnabled = true;

    event Migrated(address indexed migrant, uint256 indexed destinationAmount);

    constructor(address _oldToken, address _newToken) {
        oldToken = IERC20(_oldToken);
        newToken = NewToken(_newToken);
    }

    modifier migrationEnabledOnly() {
        require(migrationEnabled, "Migration is currently disabled");
        _;
    }

    function enableMigration() external onlyOwner {
        migrationEnabled = true;
    }

    function disableMigration() external onlyOwner {
        migrationEnabled = false;
    }

    function migrate() external migrationEnabledOnly {
        uint256 _oldTokenAmount = oldToken.balanceOf(msg.sender);
        uint256 _destinationAmount = _oldTokenAmount * MIGRATE_RATE;
        oldToken.transferFrom(msg.sender, address(this), _oldTokenAmount);
        newToken.mint(msg.sender, _destinationAmount);
        emit Migrated(msg.sender, _destinationAmount);
    }
}

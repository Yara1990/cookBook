// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

interface INonStandardERC20 {
    function totalSupply() external view returns (uint256);

    function balanceOf(address owner) external view returns (uint256 balance);

    ///
    /// !!!!!!!!!!!!!!
    /// !!! NOTICE !!! transfer does not return a value, in violation of the ERC-20 specification
    /// !!!!!!!!!!!!!!
    ///
    function transfer(address dst, uint256 amount) external;

    ///
    /// !!!!!!!!!!!!!!
    /// !!! NOTICE !!! transferFrom does not return a value, in violation of the ERC-20 specification
    /// !!!!!!!!!!!!!!
    ///
    function transferFrom(address src, address dst, uint256 amount) external;

    function approve(
        address spender,
        uint256 amount
    ) external returns (bool success);

    function allowance(
        address owner,
        address spender
    ) external view returns (uint256 remaining);

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 amount
    );
}

contract Sale is Ownable {
    using SafeMath for uint256;
    event ClaimableAmount(address _user, uint256 _claimableAmount);
    // address public owner;
    uint256 public rate; //Sale rate = (1 / 1 token price in usd) * (10**12)
    bool public presaleOver;
    IERC20 public usdt; //0xc2132d05d31c914a87c6611c10748aeb04b58e8f
    mapping(address => uint256) public claimable;
    uint256 public hardcap; //sale hardcap = usd value * (10**6)
    uint256 public totalRaised;
    uint256 public totalTokenPurchase;
    address[] public participatedUsers;

    constructor(uint256 _rate, address _usdt, uint256 _hardcap) {
        rate = _rate;
        usdt = IERC20(_usdt);
        presaleOver = false;
        hardcap = _hardcap;
    }

    modifier isPresaleOver() {
        require(presaleOver == true, "The Sale is not over yet");
        _;
    }

    function changeHardCap(uint256 _hardcap) public onlyOwner {
        hardcap = _hardcap;
    }

    function changeRate(uint256 _rate) public onlyOwner {
        rate = _rate;
    }

    function getTotalParticipatedUser() public view returns (uint256) {
        return participatedUsers.length;
    }

    function endPresale() external onlyOwner returns (bool) {
        presaleOver = true;
        return presaleOver;
    }

    function startPresale() external onlyOwner returns (bool) {
        presaleOver = false;
        return presaleOver;
    }

    function buyTokenWithUSDT(uint256 _amount) external {
        require(presaleOver == false, "Sale is over");
        uint256 tokensPurchased = _amount.mul(rate);
        uint256 userUpdatedBalance = claimable[msg.sender].add(tokensPurchased);
        require(
            _amount.add(usdt.balanceOf(address(this))) <= hardcap,
            "Hardcap reached"
        );
        // for USDT
        doTransferIn(address(usdt), msg.sender, _amount);
        claimable[msg.sender] = userUpdatedBalance;
        participatedUsers.push(msg.sender);
        totalRaised = totalRaised.add(_amount);
        totalTokenPurchase = totalTokenPurchase.add(tokensPurchased);
        emit ClaimableAmount(msg.sender, tokensPurchased);
    }

    function getUsersList(
        uint startIndex,
        uint endIndex
    )
        external
        view
        returns (address[] memory userAddress, uint[] memory amount)
    {
        uint length = endIndex.sub(startIndex);
        address[] memory _userAddress = new address[](length);
        uint[] memory _amount = new uint[](length);

        for (uint i = startIndex; i < endIndex; i = i.add(1)) {
            address user = participatedUsers[i];
            uint listIndex = i.sub(startIndex);
            _userAddress[listIndex] = user;
            _amount[listIndex] = claimable[user];
        }

        return (_userAddress, _amount);
    }

    function doTransferIn(
        address tokenAddress,
        address from,
        uint256 amount
    ) internal returns (uint256) {
        INonStandardERC20 _token = INonStandardERC20(tokenAddress);
        uint256 balanceBefore = INonStandardERC20(tokenAddress).balanceOf(
            address(this)
        );
        _token.transferFrom(from, address(this), amount);
        bool success;
        assembly {
            switch returndatasize()
            case 0 {
                // This is a non-standard ERC-20
                success := not(0) // set success to true
            }
            case 32 {
                // This is a compliant ERC-20
                returndatacopy(0, 0, 32)
                success := mload(0) // Set success = returndata of external call
            }
            default {
                // This is an excessively non-compliant ERC-20, revert.
                revert(0, 0)
            }
        }
        require(success, "TOKEN_TRANSFER_IN_FAILED");
        // Calculate the amount that was actually transferred
        uint256 balanceAfter = INonStandardERC20(tokenAddress).balanceOf(
            address(this)
        );
        require(balanceAfter >= balanceBefore, "TOKEN_TRANSFER_IN_OVERFLOW");
        return balanceAfter.sub(balanceBefore); // underflow already checked above, just subtract
    }

    function doTransferOut(
        address tokenAddress,
        address to,
        uint256 amount
    ) internal {
        INonStandardERC20 _token = INonStandardERC20(tokenAddress);
        _token.transfer(to, amount);
        bool success;
        assembly {
            switch returndatasize()
            case 0 {
                // This is a non-standard ERC-20
                success := not(0) // set success to true
            }
            case 32 {
                // This is a complaint ERC-20
                returndatacopy(0, 0, 32)
                success := mload(0) // Set success = returndata of external call
            }
            default {
                // This is an excessively non-compliant ERC-20, revert.
                revert(0, 0)
            }
        }
        require(success, "TOKEN_TRANSFER_OUT_FAILED");
    }

    function fundsWithdrawal(uint256 _value) external onlyOwner isPresaleOver {
        doTransferOut(address(usdt), _msgSender(), _value);
    }

    function transferAnyERC20Tokens(
        address _tokenAddress,
        uint256 _value
    ) external onlyOwner {
        doTransferOut(address(_tokenAddress), _msgSender(), _value);
    }
}

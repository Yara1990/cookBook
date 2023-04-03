// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract LINKStaking is Ownable {
    using SafeMath for uint;
    using EnumerableSet for EnumerableSet.AddressSet;

    event RewardsTransferred(address holder, uint amount);

    address public tokenAddress;
    // reward rate 65.00% per year - 6500
    uint public rewardRate;
    // 365 days // in seconds
    uint256 public rewardInterval;
    // staking fee 1.50 percent - 150
    uint public stakingFeeRate;
    // unstaking fee 0.50 percent - 50
    uint public unstakingFeeRate;
    // unstaking possible after 72 hours
    uint public cliffTime;

    uint public stakingStartTime;

    uint public totalClaimedRewards;

    uint public totalStaked;

    EnumerableSet.AddressSet private holders;

    mapping(address => uint) public depositedTokens;
    mapping(address => uint) public stakingTime;
    mapping(address => uint) public lastClaimedTime;
    mapping(address => uint) public totalEarnedTokens;

    constructor(
        address _tokenAddress,
        uint256 _rewardRate,
        uint256 _rewardInterval,
        uint256 _stakingFeeRate,
        uint256 _unstakingFeeRate,
        uint256 _cliffTime
    ) {
        tokenAddress = _tokenAddress;
        rewardRate = _rewardRate;
        rewardInterval = _rewardInterval;
        stakingFeeRate = _stakingFeeRate;
        unstakingFeeRate = _unstakingFeeRate;
        cliffTime = _cliffTime;
        stakingStartTime = block.timestamp;
    }

    function setRewardRate(uint256 _rewardRate) public onlyOwner {
        rewardRate = _rewardRate;
    }

    function setRewardInterval(uint256 _rewardInterval) public onlyOwner {
        rewardInterval = _rewardInterval;
    }

    function setStakingFeeRate(uint256 _stakingFeeRate) public onlyOwner {
        stakingFeeRate = _stakingFeeRate;
    }

    function setUnstakingFeeRate(uint256 _unstakingFeeRate) public onlyOwner {
        unstakingFeeRate = _unstakingFeeRate;
    }

    function setCliffTime(uint256 _cliffTime) public onlyOwner {
        cliffTime = _cliffTime;
    }

    function updateAccount(address account) private {
        uint pendingDivs = getPendingDivs(account);
        if (pendingDivs > 0) {
            require(
                IERC20(tokenAddress).transfer(account, pendingDivs),
                "Could not transfer tokens."
            );
            totalEarnedTokens[account] = totalEarnedTokens[account].add(
                pendingDivs
            );
            totalClaimedRewards = totalClaimedRewards.add(pendingDivs);
            emit RewardsTransferred(account, pendingDivs);
        }
        lastClaimedTime[account] = block.timestamp;
    }

    function getPendingDivs(address _holder) public view returns (uint) {
        if (!holders.contains(_holder)) return 0;
        if (depositedTokens[_holder] == 0) return 0;
        uint contractBal = IERC20(tokenAddress).balanceOf(address(this));
        if (contractBal <= totalStaked) return 0;

        uint rewardEndTime = stakingStartTime + rewardInterval;
        uint timeDiff;

        if (block.timestamp < rewardEndTime)
            timeDiff = block.timestamp.sub(lastClaimedTime[_holder]);
        else {
            if (lastClaimedTime[_holder] < rewardEndTime)
                timeDiff = rewardEndTime.sub(lastClaimedTime[_holder]);
            else return 0;
        }

        uint stakedAmount = depositedTokens[_holder];
        uint pendingDivs = stakedAmount
            .mul(rewardRate)
            .mul(timeDiff)
            .div(rewardInterval)
            .div(1e4);

        if (contractBal < totalStaked.add(pendingDivs))
            pendingDivs = contractBal.sub(totalStaked);

        return pendingDivs;
    }

    function getNumberOfHolders() public view returns (uint) {
        return holders.length();
    }

    function deposit(uint amountToStake) public {
        require(amountToStake > 0, "Cannot deposit 0 Tokens");
        require(
            IERC20(tokenAddress).transferFrom(
                msg.sender,
                address(this),
                amountToStake
            ),
            "Insufficient IERC20 Allowance"
        );

        updateAccount(msg.sender);

        uint fee = amountToStake.mul(stakingFeeRate).div(1e4);
        uint amountAfterFee = amountToStake.sub(fee);
        require(
            IERC20(tokenAddress).transfer(owner(), fee),
            "Could not transfer deposit fee."
        );

        depositedTokens[msg.sender] = depositedTokens[msg.sender].add(
            amountAfterFee
        );
        totalStaked = totalStaked.add(amountAfterFee);

        if (!holders.contains(msg.sender)) {
            holders.add(msg.sender);
            stakingTime[msg.sender] = block.timestamp;
        }
    }

    function withdraw(uint amountToWithdraw) public {
        require(
            depositedTokens[msg.sender] >= amountToWithdraw,
            "Invalid amount to withdraw"
        );
        require(
            block.timestamp.sub(stakingTime[msg.sender]) > cliffTime,
            "You recently staked, please wait before withdrawing."
        );

        updateAccount(msg.sender);

        uint fee = amountToWithdraw.mul(unstakingFeeRate).div(1e4);
        uint amountAfterFee = amountToWithdraw.sub(fee);

        require(
            IERC20(tokenAddress).transfer(owner(), fee),
            "Could not transfer withdraw fee."
        );
        require(
            IERC20(tokenAddress).transfer(msg.sender, amountAfterFee),
            "Could not transfer tokens."
        );

        depositedTokens[msg.sender] = depositedTokens[msg.sender].sub(
            amountToWithdraw
        );
        totalStaked = totalStaked.sub(amountToWithdraw);

        if (holders.contains(msg.sender) && depositedTokens[msg.sender] == 0) {
            holders.remove(msg.sender);
        }
    }

    function claimDivs() public {
        updateAccount(msg.sender);
    }

    function getStakersList(
        uint startIndex,
        uint endIndex
    )
        public
        view
        returns (
            address[] memory stakers,
            uint[] memory stakingTimestamps,
            uint[] memory lastClaimedTimeStamps,
            uint[] memory stakedTokens
        )
    {
        require(startIndex < endIndex);

        uint length = endIndex.sub(startIndex);
        address[] memory _stakers = new address[](length);
        uint[] memory _stakingTimestamps = new uint[](length);
        uint[] memory _lastClaimedTimeStamps = new uint[](length);
        uint[] memory _stakedTokens = new uint[](length);

        for (uint i = startIndex; i < endIndex; i = i.add(1)) {
            address staker = holders.at(i);
            uint listIndex = i.sub(startIndex);
            _stakers[listIndex] = staker;
            _stakingTimestamps[listIndex] = stakingTime[staker];
            _lastClaimedTimeStamps[listIndex] = lastClaimedTime[staker];
            _stakedTokens[listIndex] = depositedTokens[staker];
        }

        return (
            _stakers,
            _stakingTimestamps,
            _lastClaimedTimeStamps,
            _stakedTokens
        );
    }

    // function to allow admin to claim *other* ERC20 tokens sent to this contract (by mistake)
    // Admin cannot transfer out reward token from this smart contract
    function transferAnyERC20Tokens(
        address _tokenAddr,
        address _to,
        uint _amount
    ) public onlyOwner {
        require(_tokenAddr != tokenAddress, "Cannot transfer out reward token");
        IERC20(_tokenAddr).transfer(_to, _amount);
    }
}

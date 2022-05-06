// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/utils/SafeERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/math/SafeMath.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC721/ERC721.sol";
import "./Kinoko.sol";
import "./ONI.sol";


contract MasterChef is Ownable {

    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    
    // Info of each user.
    struct UserInfo {
        uint256 amount;         // How many LP tokens the user has provided.
        uint256 rewardDebt;     // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of KINO
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accKINOPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accKinoPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. KINO to distribute per block.
        uint256 lastRewardBlock;  // Last block number that KINO distribution occurs.
        uint256 accKINOPerShare;   // Accumulated KINO per share, times 1e12. See below.
        uint16 depositFeeBP;      // Deposit fee in basis points
        bool isKinoToken;
    }

    // The KINO TOKEN
    KinokoToken public KINO;
    // ONI 
    ONIS public oni;
    // Dev address.
    address public devaddr;
    // KNO tokens created per block.
    uint256 public KINOPerBlock;
    // Deposit Fee address
    address public feeAddress;
    // ONI address 
    address public oniAddress;
    // status of ONI
    bool public oniActive = false;


    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when KNO mining starts.
    uint256 public startBlock;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        KinokoToken _KINO,
        address _devaddr,
        address _feeAddress,
        uint256 _KINOPerBlock,
        uint256 _startBlock
    ) {
        KINO = _KINO;
        devaddr = _devaddr;
        feeAddress = _feeAddress;
        KINOPerBlock = _KINOPerBlock;
        startBlock = _startBlock;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(uint256 _allocPoint, IERC20 _lpToken, uint16 _depositFeeBP, bool _withUpdate, bool _isKinoToken) public onlyOwner {
        require(_depositFeeBP <= 500, "add: invalid deposit fee basis points");
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accKINOPerShare: 0,
            depositFeeBP: _depositFeeBP, 
            isKinoToken: _isKinoToken
        }));
    }

    // Update the given pool's KINO allocation point and deposit fee. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, uint16 _depositFeeBP, bool _withUpdate, bool _isKinoToken) public onlyOwner {
        require(_depositFeeBP <= 500, "set: invalid deposit fee basis points");
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].depositFeeBP = _depositFeeBP;
        poolInfo[_pid].isKinoToken = _isKinoToken;
    }

    function hasONI(address _address) public view returns (bool) {
        require(oniActive, "hasONI: oni not set");
        return oni.balanceOf(_address) > 0;
    }

    function oniMultiplier() public view returns (uint256) {
        require(oniActive, "oniMultiplier: oni not set");
        return oni.kinokoMultiplier();
    }

    function oniBoost(uint256 _pending, address _farmer) internal {
        uint256 kinoMultiplier = oniMultiplier();
        uint256 boostAmt = _pending.mul(kinoMultiplier).div(1e6);
        KINO.mint(address(this), boostAmt);
        safeKINOTransfer(_farmer, boostAmt);
    }

    function getKinoBurn() internal view returns (uint256) {
        return KINO.burnRate();
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public pure returns (uint256) {
        return _to.sub(_from);
    }

    // View function to see pending KNO on frontend.
    function pendingKINO(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accKINOPerShare = pool.accKINOPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 KINOReward = multiplier.mul(KINOPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accKINOPerShare = accKINOPerShare.add(KINOReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accKINOPerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 KINOReward = multiplier.mul(KINOPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        KINO.mint(devaddr, KINOReward.div(100));
        KINO.mint(address(this), KINOReward);
        pool.accKINOPerShare = pool.accKINOPerShare.add(KINOReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to Masterchef for KINO allocation.
    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accKINOPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                safeKINOTransfer(msg.sender, pending);
            }
            if(oniActive) {
                bool oniCheck = hasONI(msg.sender);
                if(oniCheck) {
                    oniBoost(pending, msg.sender);                                        
                }
            }
        }
        if(_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            if(pool.depositFeeBP > 0){
                uint256 depositFee = _amount.mul(pool.depositFeeBP).div(10000);
                pool.lpToken.safeTransfer(feeAddress, depositFee);
                user.amount = user.amount.add(_amount).sub(depositFee);
            }
            else if(pool.isKinoToken){
                uint256 burn = getKinoBurn();
                uint256 burnAmt = _amount * burn / 10000;
                user.amount = user.amount.add(_amount).sub(burnAmt);
            }else{
                user.amount = user.amount.add(_amount);
            }
        }
        user.rewardDebt = user.amount.mul(pool.accKINOPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from Masterchef.
    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accKINOPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
            safeKINOTransfer(msg.sender, pending);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accKINOPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // Safe kinoko transfer function, just in case if rounding error causes pool to not have enough KINO.
    function safeKINOTransfer(address _to, uint256 _amount) internal {
        uint256 KINOBal = KINO.balanceOf(address(this));
        if (_amount > KINOBal) {
            KINO.transfer(_to, KINOBal);
        } else {
            KINO.transfer(_to, _amount);
        }
    }

    // Update dev address by the previous dev.
    function dev(address _devaddr) public {
        require(msg.sender == devaddr, "dev: wut?");
        devaddr = _devaddr;
    }

    function setFeeAddress(address _feeAddress) public {
        require(msg.sender == feeAddress, "setFeeAddress: FORBIDDEN");
        feeAddress = _feeAddress;
    }

    function setONIAddress(address _oniAddress) public {
        require(msg.sender == devaddr, "setONIAddress: you are not dr satoshi");
        oniAddress = _oniAddress;
        oni = ONIS(_oniAddress);
        if (!oniActive) {
            oniActive = true;
        }
    }

    function updateEmissionRate(uint256 _KINOPerBlock) public onlyOwner {
        massUpdatePools();
        KINOPerBlock = _KINOPerBlock;
    }

    //Only update before start of farm
    function updateStartBlock(uint256 _startBlock) public onlyOwner {
        startBlock = _startBlock;
        for (uint256 i = 0; i < poolInfo.length; i++) {
            poolInfo[i].lastRewardBlock = _startBlock;
        }
    }

}

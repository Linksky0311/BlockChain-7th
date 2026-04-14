// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title SimpleStaking
 * @author Student Assignment
 * @notice A basic ETH staking contract with rewards, time-lock, and emergency withdrawal
 * @dev Deployed on Sepolia Testnet
 */
contract SimpleStaking {
    // ============================================
    //  State Variables
    // ============================================

    address public owner;
    uint256 public constant LOCK_PERIOD = 7 days;       // 최소 락업 기간 (7일)
    uint256 public constant APR = 10;                    // 연간 보상률 10%
    uint256 public constant EMERGENCY_PENALTY = 10;      // 긴급 인출 패널티 10%
    uint256 public constant SECONDS_IN_YEAR = 365 days;  // 1년(초)

    // 스테이커 정보 구조체
    struct StakeInfo {
        uint256 amount;        // 스테이킹된 금액 (wei)
        uint256 startTime;     // 스테이킹 시작 시간
        uint256 lastClaimTime; // 마지막 보상 청구 시간
        bool isStaking;        // 현재 스테이킹 중 여부
    }

    // 주소 => 스테이크 정보 매핑
    mapping(address => StakeInfo) public stakes;

    // 전체 스테이킹된 총량
    uint256 public totalStaked;

    // ============================================
    //  Events
    // ============================================

    event Staked(address indexed user, uint256 amount, uint256 timestamp);
    event Withdrawn(address indexed user, uint256 amount, uint256 reward, uint256 timestamp);
    event EmergencyWithdrawn(address indexed user, uint256 amount, uint256 penalty, uint256 timestamp);
    event RewardClaimed(address indexed user, uint256 reward, uint256 timestamp);

    // ============================================
    //  Modifiers
    // ============================================

    modifier onlyOwner() {
        require(msg.sender == owner, "Not the contract owner");
        _;
    }

    modifier hasStake() {
        require(stakes[msg.sender].isStaking, "No active stake found");
        require(stakes[msg.sender].amount > 0, "Stake amount is zero");
        _;
    }

    // ============================================
    //  Constructor
    // ============================================

    constructor() payable {
        owner = msg.sender;
    }

    // ============================================
    //  Main Functions
    // ============================================

    /**
     * @notice ETH를 예치(스테이킹)합니다
     * @dev 기존 스테이크가 있으면 보상을 정산 후 추가 적립
     */
    function stake() external payable {
        require(msg.value > 0, "Must stake more than 0 ETH");

        StakeInfo storage userStake = stakes[msg.sender];

        // 기존 스테이킹이 있는 경우: 보상을 먼저 누적 후 추가
        if (userStake.isStaking && userStake.amount > 0) {
            uint256 pendingReward = _calculateReward(msg.sender);
            // 보상분을 컨트랙트가 감당할 수 있는지 확인 후 amount에 복리로 적립
            if (address(this).balance >= pendingReward + msg.value) {
                userStake.amount += pendingReward;
                totalStaked += pendingReward; // ✅ 버그 수정: 보상도 totalStaked에 반영
            }
            userStake.amount += msg.value;
            userStake.lastClaimTime = block.timestamp;
        } else {
            // 새로운 스테이킹
            userStake.amount = msg.value;
            userStake.startTime = block.timestamp;
            userStake.lastClaimTime = block.timestamp;
            userStake.isStaking = true;
        }

        totalStaked += msg.value;

        emit Staked(msg.sender, msg.value, block.timestamp);
    }

    /**
     * @notice 스테이킹된 ETH와 보상을 인출합니다
     * @dev 락업 기간(7일)이 지나야 인출 가능
     * @param amount 인출할 금액 (0 입력 시 전체 인출)
     */
    function withdraw(uint256 amount) external hasStake {
        StakeInfo storage userStake = stakes[msg.sender];

        require(
            block.timestamp >= userStake.startTime + LOCK_PERIOD,
            "Tokens are still locked (7 day lock period)"
        );

        uint256 reward = _calculateReward(msg.sender);
        uint256 withdrawAmount = (amount == 0) ? userStake.amount : amount;

        require(withdrawAmount <= userStake.amount, "Insufficient staked balance");
        require(address(this).balance >= withdrawAmount + reward, "Insufficient contract balance");

        // 상태 업데이트 (Checks-Effects-Interactions 패턴)
        userStake.amount -= withdrawAmount;
        totalStaked -= withdrawAmount;
        userStake.lastClaimTime = block.timestamp;

        if (userStake.amount == 0) {
            userStake.isStaking = false;
        }

        uint256 totalTransfer = withdrawAmount + reward;
        payable(msg.sender).transfer(totalTransfer);

        emit Withdrawn(msg.sender, withdrawAmount, reward, block.timestamp);
    }

    /**
     * @notice 락업 기간 중 긴급 인출 (10% 패널티 적용)
     * @dev 보상 없이 원금의 90%만 돌려받음
     */
    function emergencyWithdraw() external hasStake {
        StakeInfo storage userStake = stakes[msg.sender];

        uint256 stakedAmount = userStake.amount;
        uint256 penalty = (stakedAmount * EMERGENCY_PENALTY) / 100;
        uint256 returnAmount = stakedAmount - penalty;

        require(address(this).balance >= returnAmount, "Insufficient contract balance");

        // 상태 초기화
        totalStaked -= stakedAmount;
        userStake.amount = 0;
        userStake.isStaking = false;

        // 패널티는 컨트랙트에 남음 (오너가 수령 가능)
        payable(msg.sender).transfer(returnAmount);

        emit EmergencyWithdrawn(msg.sender, returnAmount, penalty, block.timestamp);
    }

    // ============================================
    //  View Functions
    // ============================================

    /**
     * @notice 내 스테이킹 잔액 조회
     */
    function getBalance() external view returns (uint256) {
        return stakes[msg.sender].amount;
    }

    /**
     * @notice 현재 누적된 보상 조회
     */
    function calculateReward() external view returns (uint256) {
        return _calculateReward(msg.sender);
    }

    /**
     * @notice 스테이킹 상세 정보 조회
     * @return amount 스테이킹 금액
     * @return startTime 스테이킹 시작 시간
     * @return timeStaked 스테이킹 경과 시간 (초)
     * @return pendingReward 미청구 보상
     * @return canWithdraw 락업 해제 여부
     * @return timeUntilUnlock 락업 해제까지 남은 시간 (초)
     */
    function getStakeInfo() external view returns (
        uint256 amount,
        uint256 startTime,
        uint256 timeStaked,
        uint256 pendingReward,
        bool canWithdraw,
        uint256 timeUntilUnlock
    ) {
        StakeInfo storage userStake = stakes[msg.sender];
        amount = userStake.amount;
        startTime = userStake.startTime;
        timeStaked = userStake.isStaking ? block.timestamp - userStake.startTime : 0;
        pendingReward = _calculateReward(msg.sender);
        canWithdraw = userStake.isStaking && (block.timestamp >= userStake.startTime + LOCK_PERIOD);

        if (userStake.isStaking && block.timestamp < userStake.startTime + LOCK_PERIOD) {
            timeUntilUnlock = (userStake.startTime + LOCK_PERIOD) - block.timestamp;
        } else {
            timeUntilUnlock = 0;
        }
    }

    /**
     * @notice 컨트랙트 전체 잔액 조회
     */
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }

    // ============================================
    //  Owner Functions
    // ============================================

    /**
     * @notice 오너가 패널티로 누적된 수익을 인출
     */
    function ownerWithdraw(uint256 amount) external onlyOwner {
        require(amount <= address(this).balance - totalStaked, "Cannot withdraw staked funds");
        payable(owner).transfer(amount);
    }

    /**
     * @notice 컨트랙트에 ETH를 추가 공급 (보상 풀)
     */
    function fundContract() external payable onlyOwner {
        require(msg.value > 0, "Must send ETH");
    }

    // ============================================
    //  Internal Functions
    // ============================================

    /**
     * @dev 보상 계산: (원금 * APR * 경과시간) / (100 * 1년)
     */
    function _calculateReward(address user) internal view returns (uint256) {
        StakeInfo storage userStake = stakes[user];
        if (!userStake.isStaking || userStake.amount == 0) {
            return 0;
        }
        uint256 elapsed = block.timestamp - userStake.lastClaimTime;
        return (userStake.amount * APR * elapsed) / (100 * SECONDS_IN_YEAR);
    }

    // ============================================
    //  Fallback
    // ============================================

    receive() external payable {}
}

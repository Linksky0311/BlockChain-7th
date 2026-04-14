# SimpleStaking 배포 가이드 (Sepolia Testnet)

## 📁 파일 위치
`/Users/parkhaneul/Desktop/7주차과제/SimpleStaking.sol`

---

## Step 1: MetaMask 준비

1. Chrome/Brave 브라우저에 MetaMask 확장 설치 확인
2. MetaMask 열기 → 네트워크 선택 → **"Sepolia 테스트 네트워크"** 선택
   - 없으면: 설정 → 고급 → 테스트 네트워크 표시 ON
3. Sepolia ETH 잔액 확인 (최소 0.05 ETH 필요)
   - 없으면 faucet에서 받기:
     - https://sepoliafaucet.com
     - https://faucets.chain.link/sepolia
     - https://www.alchemy.com/faucets/ethereum-sepolia

---

## Step 2: Remix IDE 접속 및 파일 생성

1. **https://remix.ethereum.org** 접속
2. 좌측 파일 탐색기(File Explorer)에서 **"+"** 버튼 클릭
3. 파일명 입력: `SimpleStaking.sol`
4. 아래 전체 코드를 복사하여 붙여넣기:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract SimpleStaking {
    address public owner;
    uint256 public constant LOCK_PERIOD = 7 days;
    uint256 public constant APR = 10;
    uint256 public constant EMERGENCY_PENALTY = 10;
    uint256 public constant SECONDS_IN_YEAR = 365 days;

    struct StakeInfo {
        uint256 amount;
        uint256 startTime;
        uint256 lastClaimTime;
        bool isStaking;
    }

    mapping(address => StakeInfo) public stakes;
    uint256 public totalStaked;

    event Staked(address indexed user, uint256 amount, uint256 timestamp);
    event Withdrawn(address indexed user, uint256 amount, uint256 reward, uint256 timestamp);
    event EmergencyWithdrawn(address indexed user, uint256 amount, uint256 penalty, uint256 timestamp);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not the contract owner");
        _;
    }

    modifier hasStake() {
        require(stakes[msg.sender].isStaking, "No active stake found");
        require(stakes[msg.sender].amount > 0, "Stake amount is zero");
        _;
    }

    constructor() payable {
        owner = msg.sender;
    }

    function stake() external payable {
        require(msg.value > 0, "Must stake more than 0 ETH");
        StakeInfo storage userStake = stakes[msg.sender];
        if (userStake.isStaking && userStake.amount > 0) {
            uint256 pendingReward = _calculateReward(msg.sender);
            if (address(this).balance >= pendingReward + msg.value) {
                userStake.amount += pendingReward;
            }
            userStake.amount += msg.value;
            userStake.lastClaimTime = block.timestamp;
        } else {
            userStake.amount = msg.value;
            userStake.startTime = block.timestamp;
            userStake.lastClaimTime = block.timestamp;
            userStake.isStaking = true;
        }
        totalStaked += msg.value;
        emit Staked(msg.sender, msg.value, block.timestamp);
    }

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

    function emergencyWithdraw() external hasStake {
        StakeInfo storage userStake = stakes[msg.sender];
        uint256 stakedAmount = userStake.amount;
        uint256 penalty = (stakedAmount * EMERGENCY_PENALTY) / 100;
        uint256 returnAmount = stakedAmount - penalty;
        require(address(this).balance >= returnAmount, "Insufficient contract balance");
        totalStaked -= stakedAmount;
        userStake.amount = 0;
        userStake.isStaking = false;
        payable(msg.sender).transfer(returnAmount);
        emit EmergencyWithdrawn(msg.sender, returnAmount, penalty, block.timestamp);
    }

    function getBalance() external view returns (uint256) {
        return stakes[msg.sender].amount;
    }

    function calculateReward() external view returns (uint256) {
        return _calculateReward(msg.sender);
    }

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

    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function ownerWithdraw(uint256 amount) external onlyOwner {
        require(amount <= address(this).balance - totalStaked, "Cannot withdraw staked funds");
        payable(owner).transfer(amount);
    }

    function fundContract() external payable onlyOwner {
        require(msg.value > 0, "Must send ETH");
    }

    function _calculateReward(address user) internal view returns (uint256) {
        StakeInfo storage userStake = stakes[user];
        if (!userStake.isStaking || userStake.amount == 0) {
            return 0;
        }
        uint256 elapsed = block.timestamp - userStake.lastClaimTime;
        return (userStake.amount * APR * elapsed) / (100 * SECONDS_IN_YEAR);
    }

    receive() external payable {}
}
```

---

## Step 3: 컴파일

1. 좌측 메뉴에서 **"Solidity Compiler"** 탭 클릭 (S 모양 아이콘)
2. Compiler 버전: **`0.8.19`** 선택
3. **"Compile SimpleStaking.sol"** 버튼 클릭
4. ✅ 초록색 체크 표시 확인 (에러 없어야 함)

---

## Step 4: 배포 (Deploy)

1. 좌측 메뉴에서 **"Deploy & Run Transactions"** 탭 클릭 (로켓 아이콘)
2. **Environment** 드롭다운 → **"Injected Provider - MetaMask"** 선택
3. MetaMask 팝업이 뜨면 **"연결"** 클릭
4. Account 항목에서 MetaMask 지갑 주소가 표시되는지 확인
5. Network이 **"Sepolia (11155111)"** 인지 확인
6. Contract 드롭다운에서 **"SimpleStaking"** 선택
7. Value 입력란에 **`0.01`** 입력, 단위를 **"ether"** 로 변경 (초기 보상 풀)
8. **"Deploy"** 버튼 클릭
9. MetaMask 팝업 → **"확인"** 클릭
10. ⏳ 트랜잭션 처리 대기 (10~30초)

### 📋 배포 후 기록할 정보:
- **Contract Address**: `0x...` (Deployed Contracts 섹션에 표시됨)
- **Deployment Tx Hash**: MetaMask 활동 내역 또는 Remix 콘솔에서 확인

---

## Step 5: Stake 트랜잭션

1. Deploy & Run 탭 → **"Deployed Contracts"** 섹션 확장
2. **`stake`** 함수 옆 Value 입력란에 `0.01` 입력, 단위 `ether`
3. **`stake`** 버튼 클릭
4. MetaMask 팝업 → **"확인"**
5. ✅ 콘솔에서 트랜잭션 해시 복사

---

## Step 6: Withdraw 트랜잭션

> ⚠️ **주의**: 일반 withdraw는 7일 락업이 있으므로, 과제 제출용으로는 `emergencyWithdraw`를 사용하세요!

### emergencyWithdraw (즉시 인출, 10% 패널티):
1. **`emergencyWithdraw`** 버튼 클릭
2. MetaMask 팝업 → **"확인"**
3. ✅ 트랜잭션 해시 복사

---

## Step 7: Etherscan에서 검증

1. https://sepolia.etherscan.io 접속
2. 검색창에 **Contract Address** 입력
3. 각 트랜잭션 해시를 검색하여 확인
4. **"Contract"** 탭 → **"Verify and Publish"** 로 소스코드 검증 (선택사항)

---

## 📝 제출 정보 기록표

| 항목 | 값 |
|------|-----|
| Contract Address | `0x...` |
| Deployment Tx Hash | `0x...` |
| Stake Tx Hash | `0x...` |
| Withdraw Tx Hash | `0x...` |
| Sepolia Etherscan URL | https://sepolia.etherscan.io/address/`0x...` |

---

## ⚠️ 자주 발생하는 문제

| 문제 | 해결 방법 |
|------|----------|
| MetaMask 연결 안됨 | Remix에서 Environment → Injected Provider 재선택 |
| Gas 에러 | Gas limit을 300000으로 늘려보기 |
| Sepolia ETH 부족 | faucet에서 추가 수령 |
| 컴파일 에러 | 컴파일러 버전 0.8.19 확인 |

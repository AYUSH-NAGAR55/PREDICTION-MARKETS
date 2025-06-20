
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title PredictionMarkets
 * @dev A decentralized prediction market platform where users can create markets,
 *      place bets on outcomes, and earn rewards based on correct predictions
 */
contract PredictionMarkets {
    
    struct Market {
        uint256 id;
        string question;
        string[] options;
        uint256[] optionTotals;
        uint256 totalPool;
        uint256 endTime;
        uint256 winningOption;
        bool resolved;
        address creator;
        mapping(address => mapping(uint256 => uint256)) userBets;
        mapping(address => bool) hasClaimed;
    }
    
    struct UserBet {
        uint256 marketId;
        uint256 option;
        uint256 amount;
    }
    
    mapping(uint256 => Market) public markets;
    mapping(address => UserBet[]) public userBets;
    
    uint256 public marketCounter;
    uint256 public constant MIN_BET = 0.01 ether;
    uint256 public constant PLATFORM_FEE = 2; // 2% platform fee
    
    event MarketCreated(
        uint256 indexed marketId,
        address indexed creator,
        string question,
        uint256 endTime
    );
    
    event BetPlaced(
        uint256 indexed marketId,
        address indexed user,
        uint256 option,
        uint256 amount
    );
    
    event MarketResolved(
        uint256 indexed marketId,
        uint256 winningOption,
        uint256 totalPool
    );
    
    event WinningsClaimed(
        uint256 indexed marketId,
        address indexed user,
        uint256 amount
    );
    
    modifier marketExists(uint256 _marketId) {
        require(_marketId < marketCounter, "Market does not exist");
        _;
    }
    
    modifier marketActive(uint256 _marketId) {
        require(block.timestamp < markets[_marketId].endTime, "Market has ended");
        require(!markets[_marketId].resolved, "Market already resolved");
        _;
    }
    
    modifier onlyMarketCreator(uint256 _marketId) {
        require(msg.sender == markets[_marketId].creator, "Only market creator can resolve");
        _;
    }
    
    /**
     * @dev Creates a new prediction market
     * @param _question The question for the prediction market
     * @param _options Array of possible outcomes
     * @param _duration Duration of the market in seconds
     */
    function createMarket(
        string memory _question,
        string[] memory _options,
        uint256 _duration
    ) external returns (uint256) {
        require(bytes(_question).length > 0, "Question cannot be empty");
        require(_options.length >= 2, "At least 2 options required");
        require(_duration > 0, "Duration must be positive");
        
        uint256 marketId = marketCounter++;
        Market storage newMarket = markets[marketId];
        
        newMarket.id = marketId;
        newMarket.question = _question;
        newMarket.options = _options;
        newMarket.optionTotals = new uint256[](_options.length);
        newMarket.endTime = block.timestamp + _duration;
        newMarket.creator = msg.sender;
        newMarket.resolved = false;
        newMarket.winningOption = type(uint256).max; // Invalid value initially
        
        emit MarketCreated(marketId, msg.sender, _question, newMarket.endTime);
        
        return marketId;
    }
    
    /**
     * @dev Places a bet on a specific option in a market
     * @param _marketId The ID of the market
     * @param _option The option index to bet on
     */
    function placeBet(uint256 _marketId, uint256 _option) 
        external 
        payable 
        marketExists(_marketId) 
        marketActive(_marketId) 
    {
        require(msg.value >= MIN_BET, "Bet amount too low");
        require(_option < markets[_marketId].options.length, "Invalid option");
        
        Market storage market = markets[_marketId];
        
        // Update market totals
        market.optionTotals[_option] += msg.value;
        market.totalPool += msg.value;
        
        // Update user bet
        market.userBets[msg.sender][_option] += msg.value;
        
        // Store user bet for tracking
        userBets[msg.sender].push(UserBet({
            marketId: _marketId,
            option: _option,
            amount: msg.value
        }));
        
        emit BetPlaced(_marketId, msg.sender, _option, msg.value);
    }
    
    /**
     * @dev Resolves a market with the winning option
     * @param _marketId The ID of the market to resolve
     * @param _winningOption The index of the winning option
     */
    function resolveMarket(uint256 _marketId, uint256 _winningOption) 
        external 
        marketExists(_marketId) 
        onlyMarketCreator(_marketId) 
    {
        Market storage market = markets[_marketId];
        require(block.timestamp >= market.endTime, "Market still active");
        require(!market.resolved, "Market already resolved");
        require(_winningOption < market.options.length, "Invalid winning option");
        
        market.winningOption = _winningOption;
        market.resolved = true;
        
        emit MarketResolved(_marketId, _winningOption, market.totalPool);
    }
    
    /**
     * @dev Allows users to claim their winnings from resolved markets
     * @param _marketId The ID of the resolved market
     */
    function claimWinnings(uint256 _marketId) 
        external 
        marketExists(_marketId) 
        returns (uint256) 
    {
        Market storage market = markets[_marketId];
        require(market.resolved, "Market not resolved yet");
        require(!market.hasClaimed[msg.sender], "Already claimed");
        
        uint256 userWinningBet = market.userBets[msg.sender][market.winningOption];
        require(userWinningBet > 0, "No winning bet found");
        
        uint256 winningPool = market.optionTotals[market.winningOption];
        require(winningPool > 0, "No winning pool");
        
        // Calculate winnings: (user's winning bet / total winning pool) * total pool
        uint256 platformFeeAmount = (market.totalPool * PLATFORM_FEE) / 100;
        uint256 distributionPool = market.totalPool - platformFeeAmount;
        uint256 winnings = (userWinningBet * distributionPool) / winningPool;
        
        market.hasClaimed[msg.sender] = true;
        
        (bool success, ) = payable(msg.sender).call{value: winnings}("");
        require(success, "Transfer failed");
        
        emit WinningsClaimed(_marketId, msg.sender, winnings);
        
        return winnings;
    }
    
    // View functions
    function getMarket(uint256 _marketId) 
        external 
        view 
        marketExists(_marketId) 
        returns (
            string memory question,
            string[] memory options,
            uint256[] memory optionTotals,
            uint256 totalPool,
            uint256 endTime,
            bool resolved,
            uint256 winningOption
        ) 
    {
        Market storage market = markets[_marketId];
        return (
            market.question,
            market.options,
            market.optionTotals,
            market.totalPool,
            market.endTime,
            market.resolved,
            market.winningOption
        );
    }
    
    function getUserBet(uint256 _marketId, uint256 _option, address _user) 
        external 
        view 
        marketExists(_marketId) 
        returns (uint256) 
    {
        return markets[_marketId].userBets[_user][_option];
    }
    
    function getUserBetsHistory(address _user) 
        external 
        view 
        returns (UserBet[] memory) 
    {
        return userBets[_user];
    }
    
    function getMarketCount() external view returns (uint256) {
        return marketCounter;
    }
    
    // Owner functions for platform fee withdrawal
    address public owner;
    
    constructor() {
        owner = msg.sender;
    }
    
    function withdrawPlatformFees() external {
        require(msg.sender == owner, "Only owner can withdraw");
        uint256 balance = address(this).balance;
        (bool success, ) = payable(owner).call{value: balance}("");
        require(success, "Transfer failed");
    }
}

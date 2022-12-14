// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract DEX {
    using SafeMath for uint256;
    IERC20 public immutable token0;
    IERC20 public immutable token1;

    uint256 constant MAX_TRANSACTIONS = 50;

    struct Subscription {
        bool isSubscribed;
        uint256 counter;
        uint256 lastSubscribed;
    }

    uint256 public reserve0;
    uint256 public reserve1;

    uint256 public totalSupply;

    mapping(address => uint256) private balanceOf;

    mapping(address => Subscription) public subscriptions;

    constructor(address _token0, address _token1) {
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
    }

    modifier isSubscribed(address caller) {
        require(subscriptions[caller].isSubscribed, "User not subscribed");
        _;
    }

    modifier transactionsLeft(address caller) {
        require(subscriptions[caller].counter < MAX_TRANSACTIONS, "Max transactions reached");
        _;
    }

    modifier timeLeft(address caller) {
        require(block.timestamp - subscriptions[caller].lastSubscribed < 30*86400*1000, "Subscription expired");
        _;
    }

    modifier notAlreadySubscribed(address caller){
        require(!subscriptions[caller].isSubscribed, "Already subscribed");
        _;
    }

    function _mint(address _to, uint256 _amount) private {
        balanceOf[_to] += _amount;
        totalSupply += _amount;
    }

    function _burn(address _from, uint256 _amount) private {
        balanceOf[_from] -= _amount;
        totalSupply -= _amount;
    }

    function updateReserve(uint256 _reserve0, uint256 _reserve1) private {
        reserve0 = _reserve0;
        reserve1 = _reserve1;
    }

    function swap(address _inputToken, uint256 _inputAmount)
        external isSubscribed(msg.sender) transactionsLeft(msg.sender) timeLeft(msg.sender)
        returns (uint256 outputAmount)
    {
        require(_inputToken == address(token0) || _inputToken == address(token1), "Invalid_Token");

        require(_inputAmount > 0, "Amount cannot be 0");

        bool isToken0 = _inputToken == address(token0);

        (IERC20 tokenIn, IERC20 tokenOut, uint256 inputReserve, uint256 outputReserve) = isToken0
            ? (token0, token1, reserve0, reserve1)
            : (token1, token0, reserve1, reserve0);

        tokenIn.transferFrom(msg.sender, address(this), _inputAmount);

        uint256 inputAmountWithFee = (_inputAmount * 997) / 1000; //997/1000 = 0.3% = fees

        uint256 numerator = inputAmountWithFee.mul(outputReserve);
        uint256 denominator = inputReserve.add(inputAmountWithFee);

        outputAmount = numerator.div(denominator);

        tokenOut.transfer(msg.sender, outputAmount);

        updateReserve(token0.balanceOf(address(this)), token1.balanceOf(address(this)));
    }

    function addLiquidity(uint256 amount0, uint256 amount1) external isSubscribed(msg.sender) transactionsLeft(msg.sender) timeLeft(msg.sender) returns (uint256 shares) {
        token0.transfer(address(this), amount0);
        token1.transfer(address(this), amount1);

        if (reserve0 > 0 || reserve1 > 0) {
            require(reserve0.mul(amount1) == reserve1.mul(amount0), "amount_not_balanced");
        }

        if (totalSupply == 0) {
            shares = _sqrt(amount0 * amount1);
        } else {
            shares = _min((amount0 * totalSupply) / reserve0, (amount1 * totalSupply) / reserve1);
        }

        require(shares > 0, "shares = 0");

        _mint(msg.sender, shares);

        updateReserve(token0.balanceOf(address(this)), token1.balanceOf(address(this)));
    }

    function removeLiquidity(uint256 _shares) external isSubscribed(msg.sender) transactionsLeft(msg.sender) timeLeft(msg.sender) returns (uint256 amount0, uint256 amount1) {
        uint256 bal0 = token0.balanceOf(address(this));
        uint256 bal1 = token1.balanceOf(address(this));

        amount0 = (_shares.mul(bal0)).div(totalSupply);
        amount1 = (_shares.mul(bal1)).div(totalSupply);
        require(amount0 > 0 && amount1 > 0, "amount0 or amount1 = 0");

        _burn(msg.sender, _shares);
        updateReserve(bal0.sub(amount0), bal1.sub(amount1));

        token0.transfer(msg.sender, amount0);
        token1.transfer(msg.sender, amount1);
    }

    function subscribe() notAlreadySubscribed(msg.sender) external {
        require(msg.sender != address(0), "Not valid address");
        Subscription memory newSubscription = Subscription(true, 0, block.timestamp);
        subscriptions[msg.sender] = newSubscription;
    }

    function _sqrt(uint256 y) private pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    function _min(uint256 x, uint256 y) private pure returns (uint256) {
        return x <= y ? x : y;
    }

    function getBalanceOf(address _owner) public view returns (uint256) {
        return balanceOf[_owner];
    }

    function getSubscription(address user) public isSubscribed(user) view returns(Subscription memory) {
        return subscriptions[user];
    }


}
pragma solidity 0.6.12;

import "https://github.com/aave/flashloan-box/blob/Remix/contracts/aave/FlashLoanReceiverBase.sol";
import "https://github.com/aave/flashloan-box/blob/Remix/contracts/aave/ILendingPoolAddressesProvider.sol";
import "https://github.com/aave/flashloan-box/blob/Remix/contracts/aave/ILendingPool.sol";
import "https://github.com/sushiswap/sushiswap/blob/master/contracts/uniswapv2/interfaces/IUniswapV2Router02.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/math/SafeMath.sol";
import "./ICurveFunctions.sol";

contract FlashArbTrader is FlashLoanReceiverBase {
    using SafeMath for uint256;
    IUniswapV2Router02 uniswapV2Router;
    ICurveFunctions curveFunctions;
    uint256 deadline;
    IERC20 dai;
    IERC20 usdc;
    address pool;
    address daiTokenAddress;
    address usdcTokenAddress;
    uint256 amountToTrade;
    uint256 tokensOut;


    event swapedfordai(uint256);
    event swapedforusdc(uint256);
    event swapedforeth(uint256);
    event Received(address, uint);
  
  
    constructor(
        address _aaveLendingPool,
        IUniswapV2Router02 _uniswapV2Router,
        ICurveFunctions _curveInterface
    ) public FlashLoanReceiverBase(_aaveLendingPool) {
        curveFunctions = ICurveFunctions(address(_curveInterface));
        uniswapV2Router = IUniswapV2Router02(address(_uniswapV2Router));
        deadline = block.timestamp + 300; // 5 minutes
    }
    fallback() external payable {
        emit Received(msg.sender, msg.value);
    }
    /**
        FlashLoan logic
     */
    function executeOperation(
        address _reserve,
        uint256 _amount,
        uint256 _fee,
        bytes calldata _params
    ) external override {
        require(
            _amount <= getBalanceInternal(address(this), _reserve),
            "Invalid balance"
        );
        this.executeArbitrage();
        uint256 totalDebt = _amount.add(_fee);
        transferFundsBackToPoolInternal(_reserve, totalDebt);// return loan plus fee required to execute flash loan
    }

    function executeArbitrage() public {
        uniswapV2Router.swapETHForExactTokens{value: amountToTrade}(
            amountToTrade,
            getPathForETHToToken(daiTokenAddress),
            address(this),
            deadline
        ); // swap ETH to DAI 
        uint256 DAISwaped = dai.balanceOf(address(this));
        uint256 minper = (DAISwaped.mul(5)).div(100);
        uint256 minReturn = DAISwaped.sub(minper);
        emit swapedfordai(DAISwaped);
        dai.approve(address(curveFunctions), DAISwaped);

        curveFunctions.exchange(
            pool,
            daiTokenAddress,
            usdcTokenAddress,
            DAISwaped,
            minReturn
        );// swap DAI to USDC on curve
        uint256 USDCswaped = usdc.balanceOf(address(this));
        uint256 tokenAmountInWEI = USDCswaped.mul(1000000);
        uint256 estimatedETH = getEstimatedETHForToken(
            USDCswaped,
            usdcTokenAddress
        )[0];
        usdc.approve(address(uniswapV2Router), USDCswaped);
        emit swapedforusdc(USDCswaped);

        uniswapV2Router.swapExactTokensForETH(
            tokenAmountInWEI,
            estimatedETH,
            getPathForTokenToETH(usdcTokenAddress),
            address(this),
            deadline
        );// swap USDC to ETH 

        emit swapedforeth(address(this).balance);
    }

    function WithdrawBalance() public payable onlyOwner {
        msg.sender.call{value: address(this).balance}("");
        dai.transfer(msg.sender, dai.balanceOf(address(this)));
        usdc.transfer(msg.sender, usdc.balanceOf(address(this)));
    }

    function flashloan(
        address _flashAsset, // loan asset address 
        uint256 _flashAmount, // loan amount
        address _daiTokenAddress, // DAI token address
        address _usdcTokenAddress, // USDC token address
        address _pool, // Curve pool address
        uint256 _amountToTrade // arbitrage amount
    ) public onlyOwner {
        bytes memory data = "";
        pool = address(_pool);
        daiTokenAddress = address(_daiTokenAddress);
        dai = IERC20(daiTokenAddress);
        usdcTokenAddress = address(_usdcTokenAddress);
        usdc = IERC20(usdcTokenAddress);
        amountToTrade = _amountToTrade;
        ILendingPool lendingPool = ILendingPool(
            addressesProvider.getLendingPool()
        );
        lendingPool.flashLoan(
            address(this),
            _flashAsset,
            uint256(_flashAmount),
            data
        );
    }

    function getPathForETHToToken(address ERC20Token)
        private
        view
        returns (address[] memory)
    {
        address[] memory path = new address[](2);
        path[0] = uniswapV2Router.WETH();
        path[1] = ERC20Token;

        return path;
    }

    function getPathForTokenToETH(address ERC20Token)
        private
        view
        returns (address[] memory)
    {
        address[] memory path = new address[](2);
        path[0] = ERC20Token;
        path[1] = uniswapV2Router.WETH();

        return path;
    }

    function getEstimatedETHForToken(uint256 _tokenAmount, address ERC20Token)
        public
        view
        returns (uint256[] memory)
    {
        return
            uniswapV2Router.getAmountsOut(
                _tokenAmount,
                getPathForTokenToETH(ERC20Token)
            );
    }
}

//SPDX-License-Identifier: Unlicensed

pragma solidity ^0.8.26;

import "@openzeppelin/contracts/access/Ownable.sol";

import "./DividendWrappedNative.sol";

contract ZinuToken is IZRC20, Ownable, Zodiac {
    using SafeMath for uint256;

    string public _name;
    string public _symbol;
    uint8 constant _decimals = 9;

    address DEAD = 0x000000000000000000000000000000000000dEaD;
    address ZERO = 0x0000000000000000000000000000000000000000;

    uint256 _totalSupply = 20000 * 10**5 * (10**_decimals); //2Bil 9 decimals
    uint256 public _maxTxAmount = 20000 * 10**5 * (10**_decimals);
    uint256 public _walletMax = 20000 * 10**5 * (10**_decimals);

    bool public restrictWhales = true;

    mapping(address => uint256) _balances;
    mapping(address => mapping(address => uint256)) _allowances;

    mapping(address => bool) public isFeeExempt;
    mapping(address => bool) public isTxLimitExempt;
    mapping(address => bool) public isDividendExempt;

    uint256 public liquidityFee = 1; //WNETZ/TOKEN
    uint256 public marketingFee = 1; //Project funding
    uint256 public rewardsFee = 1; //WNETZ Rewards based on volume
    uint256 public extraFeeOnSell = 0; //Anti jeet

    uint256 public totalFee = 0;
    uint256 public totalFeeIfSelling = 0;

    address public marketingWallet;
    address public liquidityReceiver;
    address public pair;

    uint256 public launchedAt;
    bool public tradingOpen = false;

    DividendWrappedNativeDistributor public dividendDistributor;
    uint256 distributorGas = 300000;

    bool inSwapAndLiquify;

    bool public swapAndLiquifyEnabled = true;
    bool public swapAndLiquifyByLimitOnly = false;

    uint256 public swapThreshold = 200 * 10**5 * (10**_decimals);

    modifier lockTheSwap() {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }

    constructor(
        address _owner,
        address _marketingWallet,
        address _liquidityReceiver,
        string memory __name,
        string memory __symbol
    ) Ownable(msg.sender) {
        _name = __name;
        _symbol = __symbol;

        liquidityReceiver = _liquidityReceiver;
        marketingWallet = _marketingWallet;

        pair = INETZFactory(router.factory()).createPair(
            router.WETH(),
            address(this)
        );

        _allowances[address(this)][address(router)] = type(uint256).max;

        dividendDistributor = new DividendWrappedNativeDistributor();

        isFeeExempt[_owner] = true;
        isFeeExempt[address(this)] = true;

        isTxLimitExempt[_owner] = true;
        isTxLimitExempt[pair] = true;

        isDividendExempt[pair] = true;
        isDividendExempt[_owner] = true;
        isDividendExempt[address(this)] = true;
        isDividendExempt[DEAD] = true;
        isDividendExempt[ZERO] = true;

        totalFee = liquidityFee.add(marketingFee).add(rewardsFee);
        totalFeeIfSelling = totalFee.add(extraFeeOnSell);

        _balances[_owner] = _totalSupply;
        emit Transfer(address(0), _owner, _totalSupply);
        transferOwnership(_owner);
    }

    receive() external payable {}

    function name() external view override returns (string memory) {
        return _name;
    }

    function symbol() external view override returns (string memory) {
        return _symbol;
    }

    function decimals() external pure override returns (uint8) {
        return _decimals;
    }

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function getOwner() external view override returns (address) {
        return owner();
    }

    function getCirculatingSupply() public view returns (uint256) {
        return _totalSupply.sub(balanceOf(DEAD)).sub(balanceOf(ZERO));
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function allowance(address holder, address spender)
        external
        view
        override
        returns (uint256)
    {
        return _allowances[holder][spender];
    }

    function approve(address spender, uint256 amount)
        public
        override
        returns (bool)
    {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function approveMax(address spender) external returns (bool) {
        return approve(spender, type(uint256).max);
    }

    function launched() internal view returns (bool) {
        return launchedAt != 0;
    }

    function launch() internal {
        launchedAt = block.number;
    }

    function changeTxLimit(uint256 newLimit) external onlyOwner {
        _maxTxAmount = newLimit;
    }

    function changeWalletLimit(uint256 newLimit) external onlyOwner {
        _walletMax = newLimit;
    }

    function changeRestrictWhales(bool newValue) external onlyOwner {
        restrictWhales = newValue;
    }

    function changeIsFeeExempt(address holder, bool exempt) external onlyOwner {
        isFeeExempt[holder] = exempt;
    }

    function changeIsTxLimitExempt(address holder, bool exempt)
        external
        onlyOwner
    {
        isTxLimitExempt[holder] = exempt;
    }

    function changeIsDividendExempt(address holder, bool exempt)
        external
        onlyOwner
    {
        require(holder != address(this) && holder != pair);
        isDividendExempt[holder] = exempt;

        if (exempt) {
            dividendDistributor.setShare(holder, 0);
        } else {
            dividendDistributor.setShare(holder, _balances[holder]);
        }
    }

    function changeFees(
        uint256 newLiqFee,
        uint256 newRewardFee,
        uint256 newMarketingFee,
        uint256 newExtraSellFee
    ) external onlyOwner {
        liquidityFee = newLiqFee;
        rewardsFee = newRewardFee;
        marketingFee = newMarketingFee;
        extraFeeOnSell = newExtraSellFee;

        totalFee = liquidityFee.add(marketingFee).add(rewardsFee);
        totalFeeIfSelling = totalFee.add(extraFeeOnSell);
    }

    function changeFeeReceivers(
        address _newMarketingWallet,
        address _newLiquidityReceiver
    ) external onlyOwner {
        marketingWallet = _newMarketingWallet;
        liquidityReceiver = _newLiquidityReceiver;
    }

    function changeSwapBackSettings(
        bool enableSwapBack,
        uint256 newSwapBackLimit,
        bool swapByLimitOnly
    ) external onlyOwner {
        swapAndLiquifyEnabled = enableSwapBack;
        swapThreshold = newSwapBackLimit;
        swapAndLiquifyByLimitOnly = swapByLimitOnly;
    }

    function changeDistributionCriteria(
        uint256 newinPeriod,
        uint256 newMinDistribution
    ) external onlyOwner {
        dividendDistributor.setDistributionCriteria(
            newinPeriod,
            newMinDistribution
        );
    }

    function changeDistributorSettings(uint256 gas) external onlyOwner {
        require(gas < 300000);
        distributorGas = gas;
    }

    function transfer(address recipient, uint256 amount)
        external
        override
        returns (bool)
    {
        return _transferFrom(msg.sender, recipient, amount);
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external override returns (bool) {
        if (_allowances[sender][msg.sender] != type(uint256).max) {
            _allowances[sender][msg.sender] = _allowances[sender][msg.sender]
                .sub(amount, "Insufficient Allowance");
        }
        return _transferFrom(sender, recipient, amount);
    }

    function _transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) internal returns (bool) {
        if (inSwapAndLiquify) {
            return _basicTransfer(sender, recipient, amount);
        }

        require(
            amount <= _maxTxAmount || isTxLimitExempt[sender],
            "TX Limit Exceeded"
        );

        if (
            msg.sender != pair &&
            sender != pair &&
            !inSwapAndLiquify &&
            swapAndLiquifyEnabled &&
            _balances[address(this)] >= swapThreshold
        ) {
            swapBack();
        }

        if (!launched() && recipient == pair) {
            require(_balances[sender] > 0);
            launch();
        }

        //Exchange tokens
        _balances[sender] = _balances[sender].sub(
            amount,
            "Insufficient Balance"
        );

        if (!isTxLimitExempt[recipient] && restrictWhales) {
            require(_balances[recipient].add(amount) <= _walletMax);
        }

        uint256 finalAmount = isFeeExempt[sender] ||
            isFeeExempt[recipient] ||
            (recipient != pair && sender != pair)
            ? amount
            : takeFee(sender, recipient, amount);

        _balances[recipient] = _balances[recipient].add(finalAmount);

        // Dividend tracker›
        if (!isDividendExempt[sender]) {
            try
                dividendDistributor.setShare(sender, _balances[sender])
            {} catch {}
        }

        if (!isDividendExempt[recipient]) {
            try
                dividendDistributor.setShare(recipient, _balances[recipient])
            {} catch {}
        }

        try dividendDistributor.process(distributorGas) {} catch {}

        emit Transfer(sender, recipient, finalAmount);
        return true;
    }

    function _basicTransfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal returns (bool) {
        _balances[sender] = _balances[sender].sub(
            amount,
            "Insufficient Balance"
        );
        _balances[recipient] = _balances[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
        return true;
    }

    function takeFee(
        address sender,
        address recipient,
        uint256 amount
    ) internal returns (uint256) {
        uint256 feeApplicable = pair == recipient
            ? totalFeeIfSelling
            : totalFee;
        uint256 feeAmount = amount.mul(feeApplicable).div(100);

        _balances[address(this)] = _balances[address(this)].add(feeAmount);
        emit Transfer(sender, address(this), feeAmount);

        return amount.sub(feeAmount);
    }

    function tradingStatus(bool newStatus) public onlyOwner {
        tradingOpen = newStatus;
    }

    function swapBack() internal lockTheSwap {
        uint256 tokensToLiquify = _balances[address(this)];
        uint256 amountToLiquify = tokensToLiquify
            .mul(liquidityFee)
            .div(totalFee)
            .div(2);
        uint256 amountToSwap = tokensToLiquify.sub(amountToLiquify);

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WETH();

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amountToSwap,
            0,
            path,
            address(this),
            block.timestamp
        );

        uint256 amountNETZ = address(this).balance;

        uint256 totalNETZFee = totalFee.sub(liquidityFee.div(2));

        uint256 amountNETZLiquidity = amountNETZ
            .mul(liquidityFee)
            .div(totalNETZFee)
            .div(2);
        uint256 amountNETZReflection = amountNETZ.mul(rewardsFee).div(
            totalNETZFee
        );
        uint256 amountNETZMarketing = amountNETZ.sub(amountNETZLiquidity).sub(
            amountNETZReflection
        );

        try
            dividendDistributor.deposit{value: amountNETZReflection}()
        {} catch {}

        (bool tmpSuccess, ) = payable(marketingWallet).call{
            value: amountNETZMarketing,
            gas: 30000
        }("");

        // only to supress warning msg
        tmpSuccess = false;

        if (amountToLiquify > 0) {
            router.addLiquidityETH{value: amountNETZLiquidity}(
                address(this),
                amountToLiquify,
                0,
                0,
                liquidityReceiver,
                block.timestamp
            );
            emit AutoLiquify(amountNETZLiquidity, amountToLiquify);
        }
    }

    event AutoLiquify(uint256 amountNETZ, uint256 amountBOG);
}

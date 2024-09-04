// SPDX-License-Identifier: MIT

// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.18;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {Owned} from "solmate/auth/Owned.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import {InvInterestRateModel} from "./InvInterestRateModel.sol";
import {InvRewardManager} from "./InvRewardManager.sol";
import {InvFeeManager} from "./InvFeeManager.sol";
import {InvToken} from "./InvariantToken.sol";
import {WrapToken} from "./WrapToken.sol";
import {IInvToken} from "./Interfaces/IInvToken.sol";

/**
 * @title InvEngine
 * @author Victor
 *
 * @dev This contract is used to manage the lending and borrowing of assets.
 *      It allows users to deposit assets as collateral and borrow other assets.
 *      It also allows users to repay borrowed assets and withdraw their collateral.
 *      The contract ensures that the health factor of the user remains within acceptable limits.
 */
contract InvEngine is Owned, ReentrancyGuard {
    using SafeTransferLib for ERC20;

    /*///////////////////////////////////////////////////////////////
                          ERRORS
    //////////////////////////////////////////////////////////////*/
    error INVEngine__NeedsMoreThanZero();
    error INVEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error INVEngine__NotAllowedToken();
    error INVEngine__TokenAlreadyConfigured();
    error INVEngine__TransferFailed();
    error INVEngine__MintFailed();
    error INVEngine__BreaksHealthFactor(uint256 healthFactor);
    error INVEngine__UserCannotBorrow();
    error INVEngine__CannotRepayMoreThanBorrowed();
    error INVEngine__NotBorrowed(address tokenCollateralAddress);
    error INVEngine__NoLiquidityAvailable();
    error INVEngine__CannotLiquidateHealthyUser();
    error INVEngine__HealthFactorNotImproved();
    error INVEngine__InterestDueMustBeMoreThanZero();
    error INVEngine__NotALender();
    error INVEngine__LiquidationTresholdMustBeMoreThanLendFactor();
    error INVEngine__ShouldBeLessThanMaxPercentage();
    error INVEngine__NotZeroAddress();
    error INVEngine__UserHasNotEnoughCollateral();
    error INVEngine__InsufficientCollateral();
    error INVEngine__InsufficientDebt();

    /*///////////////////////////////////////////////////////////////
                          TYPE DECLARATIONS 
    //////////////////////////////////////////////////////////////*/
    struct Configuration {
        uint256 lendFactor;
        uint256 borrowFactor;
        uint256 liquidationThreshold;
        address interestRateModel;
        address rewardManager;
    }

    struct Collateral {
        address user;
        address token;
    }

    /*///////////////////////////////////////////////////////////////
                          STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    InvFeeManager private s_feeManager;

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address token => address wrapToken) private s_wrapTokens;
    mapping(address token => address vault) private s_vaults;
    mapping(address token => uint256 decimals) private s_baseUnits;
    mapping(address token => uint256 amount) private s_totalInternalBalances;
    mapping(address user => mapping(address token => uint256 amount)) private s_internalBalances;
    mapping(address user => mapping(address token => uint256 amount)) private s_internalDebt;
    mapping(address token => uint256 amount) private s_totalInternalDebt;
    mapping(address token => mapping(address wrapToken => uint256 amount)) private s_wrapTokensMinted;
    mapping(address token => Configuration configuration) private s_configurations;
    mapping(address user => address[] tokens) private s_userCollateral;
    mapping(address user => address[] tokens) private s_userBorrowed;
    mapping(address token => bool isCollateral) private s_collaterals;

    // InvariantToken private immutable i_invToken;
    address[] private s_collateralTokens;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LEND_FACTOR_PRECISION = 100;
    uint256 private constant PROTOCOL_FEE = 95;
    uint256 private constant PROTOCOL_FEE_PRECISION = 10000;
    // it needs be dynamic for each collateral
    uint256 private constant LIQUIDATION_BONUS = 10; // 10%
    uint256 constant MINIMUM_LIQUIDITY = 1000;

    /*///////////////////////////////////////////////////////////////
                          EVENTS
    //////////////////////////////////////////////////////////////*/
    event ConfigureAsset(
        address user,
        address[] indexed tokens,
        address[] indexed priceFeeds,
        address[] indexed wrapTokens,
        Configuration[] configuration
    );
    event UpdateAsset(address user, address indexed tokens, address indexed priceFeeds, Configuration configuration);
    event Supply(address indexed user, address indexed token, uint256 indexed amount);
    event RedeemCollateral(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );
    event Borrow(address indexed user, address indexed token, uint256 indexed amount);
    event Repay(address indexed user, address indexed token, uint256 indexed amount);
    event WrapTokenMinted(address indexed user, address indexed token, address indexed wrapToken, uint256 amount);

    /*///////////////////////////////////////////////////////////////
                          MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert INVEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (isCollateralToken(token)) {
            revert INVEngine__NotAllowedToken();
        }
        _;
    }

    modifier notZeroAddress(address _address) {
        if (_address == address(0)) {
            revert INVEngine__NotZeroAddress();
        }
        _;
    }

    /*///////////////////////////////////////////////////////////////
                          FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    constructor(address owner) Owned(owner) {}

    /*///////////////////////////////////////////////////////////////
                          EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Adds new assets to the INVEngine contract, allowing them to be used as collateral.
     *
     * @dev This function is used to configure assets for lending and borrowing within the INVEngine.
     * It associates token addresses with their respective price feed addresses and wrap tokens.
     * This enables these assets to be used as collateral in the lending protocol.
     *
     * @param tokenAddresses The addresses of the underlying assets to be added.
     * @param priceFeedAddresses The addresses of Chainlink oracles providing price feeds for the assets.
     * @param wrapTokens The addresses of wrap tokens associated with the assets.
     *
     * @dev It is essential that the lengths of all three input arrays match, as each asset must have
     * a corresponding price feed and wrap token.
     *
     * @dev Only authorized users are allowed to execute this function.
     */
    function configureAsset(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses,
        address[] memory wrapTokens,
        Configuration[] memory configuration
    ) external {
        if (tokenAddresses.length != priceFeedAddresses.length && tokenAddresses.length != wrapTokens.length) {
            revert INVEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }
        for (uint256 i = 0; i < priceFeedAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_wrapTokens[tokenAddresses[i]] = wrapTokens[i];
            // s_baseUnits[tokenAddresses[i]] = 10 ** ERC20(tokenAddresses[i]).decimals();
            s_configurations[tokenAddresses[i]] = configuration[i];
            s_collateralTokens.push(tokenAddresses[i]);
            s_collaterals[priceFeedAddresses[i]] = true;
        }

        emit ConfigureAsset(msg.sender, tokenAddresses, priceFeedAddresses, wrapTokens, configuration);
    }

    // @custom:todo maybe we should remove this func
    function updateAsset(address tokenAddress, address priceFeedAddress, Configuration memory configuration) external {
        s_priceFeeds[tokenAddress] = priceFeedAddress;
        s_configurations[tokenAddress] = configuration;

        emit UpdateAsset(msg.sender, tokenAddress, priceFeedAddress, configuration);
    }

    /**
     * @notice This function is used to update the interest rate model of an asset.
     * @param tokenAddress The address of the asset to update.
     * @param interestRateModel The address of the new interest rate model.
     */
    function updateAssetInterestRateModel(address tokenAddress, address interestRateModel)
        external
        onlyOwner
        notZeroAddress(interestRateModel)
    {
        s_configurations[tokenAddress].interestRateModel = interestRateModel;
    }

    /**
     * @notice This function is used to update the reward manager of an asset.
     * @param tokenAddress The address of the asset to update.
     * @param rewardManager The address of the new reward manager.
     */
    function updateAssetRewardManager(address tokenAddress, address rewardManager)
        external
        onlyOwner
        notZeroAddress(rewardManager)
    {
        s_configurations[tokenAddress].rewardManager = rewardManager;
    }

    /**
     * @notice This function is used to update the price feed of an asset.
     * @param tokenAddress The address of the asset to update.
     * @param priceFeedAddress The address of the new price feed.
     */
    function updateAssetPriceFeed(address tokenAddress, address priceFeedAddress)
        external
        onlyOwner
        notZeroAddress(priceFeedAddress)
    {
        s_priceFeeds[tokenAddress] = priceFeedAddress;
    }

    /**
     * @notice This function is used to update the lend factor and liquidation threshold of an asset.
     * @param tokenAddress The address of the asset to update.
     * @param lendFactor The new lend factor.
     * @param liquidationThreshold The new liquidation threshold.
     * @dev The lend factor and liquidation threshold must be less than 100.
     * @dev The liquidation threshold must be greater than the lend factor.
     */
    function updateAssetFactors(address tokenAddress, uint256 lendFactor, uint256 liquidationThreshold)
        external
        onlyOwner
        moreThanZero(lendFactor)
        moreThanZero(liquidationThreshold)
    {
        if (liquidationThreshold < lendFactor) {
            revert INVEngine__LiquidationTresholdMustBeMoreThanLendFactor();
        }

        if (lendFactor > 100 || liquidationThreshold > 100) {
            revert INVEngine__ShouldBeLessThanMaxPercentage();
        }

        s_configurations[tokenAddress].lendFactor = lendFactor;
        s_configurations[tokenAddress].liquidationThreshold = liquidationThreshold;
    }

    /**
     * @notice This function is used to update the fee manager of the protocol.
     * @param feeManager The address of the new fee manager.
     * @dev Only authorized users are allowed to execute this function.
     */
    function setFeeManager(address feeManager) external onlyOwner notZeroAddress(feeManager) {
        s_feeManager = InvFeeManager(feeManager);
    }

    /**
     * @notice This is a experimental version of the borrow func. It needs be improved and reviewed
     * @dev This function allows users to borrow an equivalent amount of a token.
     *      It also ensures that the health factor of the user remains within acceptable limits.
     * @param tokenToBorrowAddress The address of the token to borrow.
     * @param amountToBorrow The amount of the token to borrow.
     */
    function borrow(address tokenToBorrowAddress, uint256 amountToBorrow)
        external
        isAllowedToken(tokenToBorrowAddress)
        moreThanZero(amountToBorrow)
        nonReentrant
    {
        // Get reward manager
        InvRewardManager rewardManager = InvRewardManager(s_configurations[tokenToBorrowAddress].rewardManager);
        rewardManager.snapshotInterestDue(msg.sender);
        _updateUserTimestamp(msg.sender, tokenToBorrowAddress);

        if (_isAvailableLiquidityToBorrow(tokenToBorrowAddress, amountToBorrow) == false) {
            revert INVEngine__NoLiquidityAvailable();
        }

        // Ensure the user is able to execute this borrow
        if (_canBorrowSpecificToken(msg.sender, tokenToBorrowAddress, amountToBorrow) == false) {
            revert INVEngine__UserCannotBorrow();
        }

        // Update the internal debt balance of the user
        unchecked {
            s_internalDebt[msg.sender][tokenToBorrowAddress] += amountToBorrow;
        }

        // Update the total internal debt of the asset
        s_totalInternalDebt[tokenToBorrowAddress] += amountToBorrow;
        s_userBorrowed[msg.sender].push(tokenToBorrowAddress);
        // Emit an event to record the borrow
        emit Borrow(msg.sender, tokenToBorrowAddress, amountToBorrow);

        // Transfer the borrowed amount to the user
        bool success = ERC20(tokenToBorrowAddress).transfer(msg.sender, amountToBorrow);
        if (!success) {
            revert INVEngine__TransferFailed();
        }

        // Update global accumulated rate
        // @custom:todo Accrue interest here
        rewardManager.accrueInterest();

        // Ensure the user's health factor is not broken
        // @custom:todo is this necessary?
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice This is a experimental version of the repay func. It needs be improved and reviewed
     * @dev This function allows users to repay an equivalent amount of wrap tokens.
     *      The repaid wrap tokens are associated with the collateral token.
     *      It also ensures that the health factor of the user remains within acceptable limits.
     * @param tokenBorrowedAddress The address of the borrowed token.
     * @param amountToRepay The amount of wrap tokens to repay.
     */
    function repay(address tokenBorrowedAddress, uint256 amountToRepay)
        external
        isAllowedToken(tokenBorrowedAddress)
        moreThanZero(amountToRepay)
        nonReentrant
        returns (uint256)
    {
        // Get reward manager
        InvRewardManager rewardManager = InvRewardManager(s_configurations[tokenBorrowedAddress].rewardManager);

        // @todo I think this is unnecessary
        rewardManager.accrueInterest();

        // Get User Interest
        uint256 userInterest = rewardManager.calculateUserInterestDue(msg.sender);

        // Get the user's internal debt of the token
        uint256 userInternalDebtOfTheToken = s_internalDebt[msg.sender][tokenBorrowedAddress];

        // Check if the user has borrowed this token
        if (_isBorrowing(msg.sender, tokenBorrowedAddress) == false) {
            revert INVEngine__NotBorrowed(tokenBorrowedAddress);
        }
        if (amountToRepay > userInternalDebtOfTheToken + userInterest) {
            revert INVEngine__CannotRepayMoreThanBorrowed();
        }

        // @todo remove the fee calc from here
        // Update unpaid interest
        if (amountToRepay < userInterest) {
            uint256 amountUnpaid = userInterest - amountToRepay;
            rewardManager.updateUserInterest(msg.sender, amountUnpaid, amountToRepay);

            // Transfer the repaid amount to the contract
            bool successTransferToRM =
                ERC20(tokenBorrowedAddress).transferFrom(msg.sender, address(rewardManager), amountToRepay);
            if (!successTransferToRM) {
                revert INVEngine__TransferFailed();
            }
        } else {
            // Reset unpaid interest to zero if all interest is paid
            rewardManager.updateUserInterest(msg.sender, 0, userInterest);

            // If 'amountToRepay' exceeds 'userInterest', the excess pays down the principal.
            // Otherwise, the entire payment covers interest, leaving the principal untouched.
            uint256 principalRepaid = amountToRepay > userInterest ? amountToRepay - userInterest : 0;

            // Update the internal debt balance of the user
            s_internalDebt[msg.sender][tokenBorrowedAddress] -= principalRepaid;

            // Cannot underflow because the user balance will
            // never be greater than the total supply.
            // Update the total internal debt of the asset
            unchecked {
                s_totalInternalDebt[tokenBorrowedAddress] -= principalRepaid;
            }

            // Transfer the user interest amount to the contract
            bool successTransferToRM =
                ERC20(tokenBorrowedAddress).transferFrom(msg.sender, address(rewardManager), userInterest);
            if (!successTransferToRM) {
                revert INVEngine__TransferFailed();
            }

            // Transfer the repaid amount to the contract
            bool successTransferToEngine =
                ERC20(tokenBorrowedAddress).transferFrom(msg.sender, address(this), amountToRepay - userInterest);
            if (!successTransferToEngine) {
                revert INVEngine__TransferFailed();
            }
        }

        // set timestamp to calc last user interaction to current timestamp
        _updateUserTimestamp(msg.sender, tokenBorrowedAddress);
        // rewardManager.snapshotInterestDue(msg.sender);

        // Emit an event to record the repayment
        emit Repay(msg.sender, tokenBorrowedAddress, amountToRepay);

        return userInterest;
    }

    /**
     * @notice follows CEI
     * @param token The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     */
    function supply(address token, uint256 amountCollateral)
        external
        isAllowedToken(token)
        moreThanZero(amountCollateral)
        nonReentrant
    {
        // Get Reward Manager
        InvRewardManager rewardManager = InvRewardManager(s_configurations[token].rewardManager);
        rewardManager.snapshotInterestDue(msg.sender);
        _updateUserTimestamp(msg.sender, token);

        // If user is not using this token as collateral, so now he's going
        if (s_internalBalances[msg.sender][token] == 0) {
            s_userCollateral[msg.sender].push(token);
        }

        // Modify the internal balance of the sender.
        s_internalBalances[msg.sender][token] += amountCollateral;
        emit Supply(msg.sender, token, amountCollateral);

        // Add to the token's total internal supply.
        s_totalInternalBalances[token] += amountCollateral;

        // Transfer underlying in from the user.
        bool success = ERC20(token).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert INVEngine__TransferFailed();
        }

        // Notify deposit on reward manager
        rewardManager.notifyDeposit(msg.sender, amountCollateral);

        // wrap token
        address wrapToken = s_wrapTokens[token];

        _revertIfHealthFactorIsBroken(msg.sender);

        // get total internal supply
        uint256 totalPool = s_totalInternalBalances[token];

        // calc amount of wraptokens to be minted
        // the amount is proportional to the value of the supply by total internal supply
        uint256 wrapTokenTotalSupply = s_wrapTokensMinted[token][wrapToken];
        s_wrapTokensMinted[token][wrapToken] += amountCollateral; // add after get totalsupply
        uint256 tokensToMint;

        if (wrapTokenTotalSupply == 0) {
            tokensToMint = amountCollateral - MINIMUM_LIQUIDITY;
            // mint wrap tokens
            _mintWrapToken(address(wrapToken), address(s_feeManager), MINIMUM_LIQUIDITY);
        } else {
            tokensToMint = (amountCollateral * wrapTokenTotalSupply) / totalPool;
        }
        // mint wrap tokens
        _mintWrapToken(address(wrapToken), msg.sender, tokensToMint);

        // Update the interest variables for the user
        rewardManager.accrueInterest();

        emit WrapTokenMinted(msg.sender, token, wrapToken, amountCollateral);
    }

    /**
     * @notice This is a experimental version of the withdraw func. It needs be improved and reviewed
     * @dev This function allows users to withdraw an equivalent amount of collateral.
     *     It also ensures that the health factor of the user remains within acceptable limits.
     * @param token The address of the collateral token.
     * @param amountToWithdraw The amount of the collateral to withdraw.
     */
    function withdraw(address token, uint256 amountToWithdraw)
        external
        isAllowedToken(token)
        moreThanZero(amountToWithdraw)
        nonReentrant
    {
        if (s_internalBalances[msg.sender][token] < amountToWithdraw) {
            revert INVEngine__UserHasNotEnoughCollateral();
        }

        // Get balance deposited by user
        uint256 userDepositedBalance = s_internalBalances[msg.sender][token];
        uint256 totalSupplyToken = s_totalInternalBalances[token];

        // Get Reward Manager
        InvRewardManager rewardManager = InvRewardManager(s_configurations[token].rewardManager);
        rewardManager.snapshotInterestDue(msg.sender);
        _updateUserTimestamp(msg.sender, token);

        // Update the interest
        rewardManager.accrueInterest();

        // Modify the internal balance of the sender.
        s_internalBalances[msg.sender][token] -= amountToWithdraw;
        emit RedeemCollateral(msg.sender, msg.sender, token, amountToWithdraw);

        // Removes the asset's total internal supply.
        s_totalInternalBalances[token] -= amountToWithdraw;

        // Get the reward
        uint256 userEarned = earned(msg.sender, token);

        // get wrapTokens back
        address wrapToken = s_wrapTokens[token];
        uint256 totalSupplyWrapToken = s_wrapTokensMinted[token][wrapToken];
        uint256 userWrapTokens = ERC20(wrapToken).balanceOf(msg.sender);
        uint256 tokensToBurn = calculateTokensToBurn(amountToWithdraw, totalSupplyWrapToken, totalSupplyToken);
        s_wrapTokensMinted[token][wrapToken] -= tokensToBurn;
        bool wrapTokenBack = WrapToken(wrapToken).transferFrom(msg.sender, address(this), tokensToBurn);
        if (!wrapTokenBack) {
            revert INVEngine__TransferFailed();
        }

        // finally burns the wrapToken
        WrapToken(wrapToken).burn(tokensToBurn);

        // claimYield from the user
        if (userEarned > 0) {
            claimYield(msg.sender, token);
        }

        // Transfer underlying  to the user.
        bool success = ERC20(token).transfer(msg.sender, amountToWithdraw);
        if (!success) {
            revert INVEngine__TransferFailed();
        }

        // Notify deposit on reward manager
        rewardManager.notifyWithdraw(msg.sender, amountToWithdraw);

        // Ensure the user's health factor is not broken
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @dev This function allows users to liquidate a borrower's position.
     *      It also ensures that the health factor of the user remains within acceptable limits.
     *      We are checking is `repayAsset` is a collateral token because currently all borrow tokens
     *      are collateral tokens too. So if a token is a collateral token it is an allowed token.
     * @param user The address of the borrower.
     * @param repayAsset The address of the borrowed token.
     * @param seizeAsset The address of the collateral token to get.
     * @param amountToRepay The amount of the borrowed token to repay.
     */
    // function liquidate(address user, address repayAsset, address seizeAsset, uint256 amountToRepay)
    //     external
    //     nonReentrant
    //     isAllowedToken(repayAsset)
    //     isAllowedToken(seizeAsset)
    //     moreThanZero(amountToRepay)
    //     returns (uint256, uint256)
    // {
    //     // Need to check the health factor of the user
    //     uint256 startingUserHealthFactor = _healthFactor(user);
    //     if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
    //         revert INVEngine__CannotLiquidateHealthyUser();
    //     }

    //     // Get amount to repay after discount and amount to seize
    //     (uint256 totalAmountToRepayAfterDiscount, uint256 totalAmountToSeizeInSeizeAsset) =
    //         _calculateRepayAmountOnLiquidation(seizeAsset, repayAsset, amountToRepay);

    //     // Redeem collateral
    //     _redeemCollateral(seizeAsset, totalAmountToSeizeInSeizeAsset, user, msg.sender);
    //     _repayUserDebt(repayAsset, user, msg.sender, amountToRepay, totalAmountToRepayAfterDiscount);

    //     // Need to check the health factor of the user
    //     uint256 endingUserHealthFactor = _healthFactor(user);
    //     // @custom:todo this is necessary? yes it is, but is bugged
    //     // If the health factor of the user has not improved, revert
    //     // if (endingUserHealthFactor <= startingUserHealthFactor) {
    //     //     revert INVEngine__HealthFactorNotImproved();
    //     // }
    //     _revertIfHealthFactorIsBroken(msg.sender);
    //     return (startingUserHealthFactor, endingUserHealthFactor);
    // }

    /**
     * @dev This function allows users to liquidate a borrower's position.
     *      It also ensures that the health factor of the user remains within acceptable limits.
     *      We are checking is `repayAsset` is a collateral token because currently all borrow tokens
     *      are collateral tokens too. So if a token is a collateral token it is an allowed token.
     * @param user The address of the borrower.
     * @param repayAsset The address of the borrowed token.
     * @param seizeAsset The address of the collateral token to get.
     * @param amountToRepay The amount of the borrowed token to repay.
     */
    function liquidate(address user, address repayAsset, address seizeAsset, uint256 amountToRepay)
        external
        nonReentrant
        isAllowedToken(repayAsset)
        isAllowedToken(seizeAsset)
        moreThanZero(amountToRepay)
        returns (uint256, uint256)
    {
        // Cheque: Verificar o fator de saúde do usuário
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert INVEngine__CannotLiquidateHealthyUser();
        }

        // Efeito: Calcular valores para liquidação
        (uint256 totalAmountToRepayAfterDiscount, uint256 totalAmountToSeizeInSeizeAsset) =
            _calculateRepayAmountOnLiquidation(seizeAsset, repayAsset, amountToRepay);

        // Atualizar estado antes de fazer chamadas externas
        _updateStateForLiquidation(
            user, seizeAsset, repayAsset, amountToRepay, totalAmountToRepayAfterDiscount, totalAmountToSeizeInSeizeAsset
        );

        // Interação: Executar transferências
        _executeLiquidationTransfers(
            seizeAsset, repayAsset, msg.sender, totalAmountToRepayAfterDiscount, totalAmountToSeizeInSeizeAsset
        );

        // Checar novamente o fator de saúde
        uint256 endingUserHealthFactor = _healthFactor(user);
        //  If the health factor of the user has not improved, revert
        // if (endingUserHealthFactor <= startingUserHealthFactor) {
        //     revert INVEngine__HealthFactorNotImproved();
        // }
        _revertIfHealthFactorIsBroken(msg.sender);
        return (startingUserHealthFactor, endingUserHealthFactor);
    }

    function _updateStateForLiquidation(
        address user,
        address seizeAsset,
        address repayAsset,
        uint256 amountToRepay,
        uint256 amountToRepayAfterDiscount,
        uint256 totalAmountToSeizeInSeizeAsset
    ) private {
        // Verifica se o usuário tem colateral suficiente para ser liquidado
        if (s_internalBalances[user][seizeAsset] < totalAmountToSeizeInSeizeAsset) {
            revert INVEngine__InsufficientCollateral();
        }

        // Verifica se a dívida do usuário é pelo menos o montante que está sendo liquidado
        if (s_internalDebt[user][repayAsset] < amountToRepay) {
            revert INVEngine__InsufficientDebt();
        }

        // Atualiza o balanço interno do usuário para refletir a redução do colateral
        s_internalBalances[user][seizeAsset] -= totalAmountToSeizeInSeizeAsset;
        s_totalInternalBalances[seizeAsset] -= totalAmountToSeizeInSeizeAsset;

        // Atualiza a dívida interna do usuário
        s_internalDebt[user][repayAsset] -= amountToRepay;
        s_totalInternalDebt[repayAsset] -= amountToRepay;

        // Caso haja lógica adicional relacionada ao gerenciamento de colateral ou dívida
        // você pode adicionar aqui. Por exemplo, ajustar o fator de saúde do usuário,
        // atualizar qualquer índice de utilização, etc.

        // Emita eventos para registrar a atualização de estado
        // emit CollateralSeized(user, seizeAsset, totalAmountToSeizeInSeizeAsset);
        // emit DebtRepaid(user, repayAsset, amountToRepay);
    }

    function _executeLiquidationTransfers(
        address seizeAsset,
        address repayAsset,
        address liquidator,
        uint256 amountToRepayAfterDiscount,
        uint256 totalAmountToSeizeInSeizeAsset
    ) private {
        // Transfere o colateral do usuário para o liquidante
        bool successCollateral = ERC20(seizeAsset).transfer(liquidator, totalAmountToSeizeInSeizeAsset);
        if (!successCollateral) {
            revert INVEngine__TransferFailed();
        }

        // O liquidante paga a dívida do usuário
        bool successDebt = ERC20(repayAsset).transferFrom(liquidator, address(this), amountToRepayAfterDiscount);
        if (!successDebt) {
            revert INVEngine__TransferFailed();
        }

        // Emita eventos conforme necessário
        // ...
    }

    /*///////////////////////////////////////////////////////////////
                          PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function claimYield(address user, address token) public isAllowedToken(token) returns (uint256) {
        InvRewardManager rewardManager = InvRewardManager(s_configurations[token].rewardManager);
        (uint256 reward) = rewardManager.getReward(user);
        return reward;
    }

    /**
     * @notice Get the collateral value of a user.
     * @param user The address of the user to check.
     * @return totalUserCollateralValueInUsd The collateral value of the user.
     */
    function getAccountCollateralValue(address user) public view returns (uint256 totalUserCollateralValueInUsd) {
        // loop through each collateral token, get the amount they have deposited and map it to
        // the price, to  get USD value
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_internalBalances[user][token];
            totalUserCollateralValueInUsd += getUsdValue(token, amount);
        }

        return totalUserCollateralValueInUsd;
    }

    /**
     * @notice Get the borrow value of a user.
     * @param user The address of the user to check.
     * @return totalUserBorrowValueInUsd The borrow value of the user.
     */
    function getAccountBorrowValue(address user) public view returns (uint256 totalUserBorrowValueInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_internalDebt[user][token];
            totalUserBorrowValueInUsd += getUsdValue(token, amount);
        }

        return totalUserBorrowValueInUsd;
    }

    /**
     * @notice Get the interest due value of a user.
     * @param user The address of the user to check.
     * @return totalUserInterestDueValueInUsd The interest due value of the user.
     */
    function getAccountInterestDueValue(address user) public view returns (uint256 totalUserInterestDueValueInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];

            InvRewardManager rewardManager = InvRewardManager(s_configurations[token].rewardManager);
            uint256 interest = rewardManager.simulateUserInterestDue(user);

            if (interest > 0) {
                totalUserInterestDueValueInUsd += getUsdValue(token, interest);
            }
        }

        return totalUserInterestDueValueInUsd;
    }

    /**
     * @dev Get the USD value of a given token amount using Chainlink Price Feeds.
     * @param token The address of the token for which the USD value is to be calculated.
     * @param amount The amount of the token for which the USD value is to be calculated.
     * @return The USD value of the specified token amount with 18 decimal places of precision.
     */
    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();

        // if 1 ETH = $1000
        // the returned value from ChainLink will be 1000 * 1e8
        // as the amount param is something * 1e18, we need the ADDITIONAL_FEED_PRECISION
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    /**
     * @notice This function is used to get the amount of tokens from USD
     * @param token The address of the token to check.
     * @param usdAmountInWei The amount of USD in wei.
     * @return The amount of tokens.
     */
    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        // $100e18 USD Debt
        // 1 ETH = 2000 USD
        // The returned value from Chainlink will be 2000 * 1e8
        // Most USD pairs have 8 decimals, so we will just pretend they all do
        return ((usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION));
    }

    /**
     * @notice Get the collateral value of the protocol.
     * @return totalCollateralValueInUsd The collateral value of the protocol.
     */
    function getTotalCollateralValue() public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_totalInternalBalances[token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }

        return totalCollateralValueInUsd;
    }

    /**
     * @notice Get the borrow value.
     * @return totalBorrowValueInUsd The borrow value of the protocol.
     */
    function getTotalBorrowValue() public view returns (uint256 totalBorrowValueInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_totalInternalDebt[token];
            totalBorrowValueInUsd += getUsdValue(token, amount);
        }

        return totalBorrowValueInUsd;
    }

    /**
     * @notice Get the max borrow value.
     * @return maximumBorrowable The max borrow amount for the user (in USD 1*18)
     * @return borrowValueRemaining The borrow amount remaining based
     *         on current borrows (in USD 1*18)
     */
    function maxBorrowable(address user) public view returns (uint256, uint256) {
        (, uint256 borrowValueInUSD) = _getAccountInformation(user);

        // Retrieve the user's utilized assets.
        address[] memory utilized = s_userCollateral[user];

        // Initialize variables to track the total collateral value adjusted for the lend factor
        address currentAsset;
        uint256 maximumBorrowable;

        // Iterate through the user's utilized assets.
        for (uint256 i = 0; i < utilized.length; i++) {
            // Current user utilized asset.
            currentAsset = utilized[i];

            uint256 assetLendFactor = s_configurations[currentAsset].lendFactor;
            uint256 userBalanceOfCurrentAsset = s_internalBalances[user][currentAsset];
            // Get the USD value of the current asset.
            uint256 collateralValue = getUsdValue(currentAsset, userBalanceOfCurrentAsset);
            // Adjust the collateral value for the lend factor of the current asset.
            uint256 collateralAdjustedForLendFactor = (collateralValue * assetLendFactor) / LEND_FACTOR_PRECISION;
            // Add the adjusted collateral value to the total collateral value.
            maximumBorrowable += collateralAdjustedForLendFactor;
        }

        uint256 borrowValueRemaining = maximumBorrowable - borrowValueInUSD;

        // Return the health factor.
        return (maximumBorrowable, borrowValueRemaining);
    }

    /*///////////////////////////////////////////////////////////////
                    PRIVATE AND INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function calculateFee(uint256 amount) internal pure returns (uint256) {
        uint256 feeProtocol = amount * PROTOCOL_FEE / PROTOCOL_FEE_PRECISION;

        return feeProtocol;
    }

    function _mintWrapToken(address wrapToken, address to, uint256 amount) internal returns (bool) {
        bool minted = WrapToken(wrapToken).mint(to, amount);
        if (!minted) {
            revert INVEngine__MintFailed();
        }

        return minted;
    }

    function calculateTokensToBurn(uint256 amountXToWithdraw, uint256 wrapTokenTotalSupply, uint256 totalPool)
        internal
        pure
        returns (uint256 tokensToBurn)
    {
        if (wrapTokenTotalSupply <= MINIMUM_LIQUIDITY) {
            revert("Insufficient liquidity");
        }

        // Ajusta o total supply para o cálculo, removendo o MINIMUM_LIQUIDITY
        uint256 adjustedTotalSupply = wrapTokenTotalSupply - MINIMUM_LIQUIDITY;

        // Calcula a quantidade de tokensY a serem queimados para a retirada
        tokensToBurn = (amountXToWithdraw * adjustedTotalSupply) / (totalPool - MINIMUM_LIQUIDITY);

        return tokensToBurn;
    }

    function _updateUserTimestamp(address user, address token) internal {
        // Get reward manager
        InvRewardManager rewardManager = InvRewardManager(s_configurations[token].rewardManager);

        rewardManager.updateUserTimestamp(user);
    }

    /**
     * @notice This function is used to get the account information of a user.
     * @param user The address of the user to check.
     * @return CollateralValueInUSD The collateral value of the user in USD.
     * @return BorrowValueInUSD The borrow value of the user in USD.
     */
    function _getAccountInformation(address user)
        private
        view
        returns (uint256 CollateralValueInUSD, uint256 BorrowValueInUSD)
    {
        CollateralValueInUSD = getAccountCollateralValue(user);
        BorrowValueInUSD = getAccountBorrowValue(user);
    }

    /**
     * @notice This function is used get the health factor of a user.
     * @param user The address of the user to check.
     * @return The health factor of the user.
     */
    function _healthFactor(address user) private view returns (uint256) {
        return _calculateHealthFactor(user);
    }

    /**
     * @notice This function is used to calculate the health factor of a user.
     * @return The health factor of the user. It's in 18 decimals. 1e18 == 1
     * custom:todo this is returning max uint256 value if user has no borrow value.
     *             is that approach right? Answer (10 JAN 24) -> I think yes, it is.
     */
    function _calculateHealthFactor(address user) internal view returns (uint256) {
        // Get the total USD value of the user's collateral assets
        (, uint256 borrowValueInUSD) = _getAccountInformation(user);

        // If the user has no borrow value, return the max health factor.
        if (borrowValueInUSD == 0) return type(uint256).max;

        // Retrieve the user's utilized assets.
        address[] memory utilized = s_userCollateral[user];

        // Initialize variables to track the total collateral value adjusted for the lend factor
        address currentAsset;
        uint256 totalCollateralMulLTValue;

        // Iterate through the user's utilized assets.
        for (uint256 i = 0; i < utilized.length; i++) {
            // Current user utilized asset.
            currentAsset = utilized[i];
            // Liquidation Threshold
            uint256 assetLiquidationThreshold = s_configurations[currentAsset].liquidationThreshold;
            // Get the lend factor for the current asset.
            // uint256 assetLendFactor = s_configurations[currentAsset].lendFactor;
            // Get the balance of the current asset.
            uint256 balanceOfCurrentAsset = s_internalBalances[user][currentAsset];
            // Get the USD value of the current asset.
            uint256 collateralValue = getUsdValue(currentAsset, balanceOfCurrentAsset);
            // Adjust the collateral value for the lend factor of the current asset.
            uint256 collateralAdjustedForThreshold =
                (collateralValue * assetLiquidationThreshold) / LIQUIDATION_PRECISION;
            // Add the adjusted collateral value to the total collateral value.
            totalCollateralMulLTValue += collateralAdjustedForThreshold;
        }

        // Calculate the health factor.
        uint256 healthFactor = (totalCollateralMulLTValue * PRECISION) / (borrowValueInUSD);

        // Return the health factor.
        return healthFactor;
    }

    /**
     * @notice This function is used to revert if the user's health factor is broken.
     * @param user The address of the user to check.
     */
    function _revertIfHealthFactorIsBroken(address user) internal view {
        // Get the user's health factor.
        uint256 userHealthFactor = _healthFactor(user);

        // If the user's health factor is less than the minimum health factor, revert.
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert INVEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    /**
     * @notice This function is used to determine whether a user is able to borrow any tokens.
     * @param user The address of the user to check.
     * @return Whether the user is able to borrow any tokens.
     */
    function _canBorrow(address user) internal view returns (bool) {
        // Ensure the user's health factor will be greater than 1.
        return _healthFactor(user) >= 1e18;
    }

    /**
     * @notice This function is used to determine whether a user is borrowing a specific token.
     * @param user The address of the user to check.
     * @param tokenAddress The address of the token to check.
     * @return Whether the user is borrowing the specified token.
     */
    function _isBorrowing(address user, address tokenAddress) internal view returns (bool) {
        return s_internalDebt[user][tokenAddress] > 0;
    }

    function _calculateCollateralAdjustedForLendFactor(address user, address tokenToBorrow)
        internal
        view
        returns (uint256)
    {
        // Get the lend factor for the token to borrow
        uint256 tokenLendFactor = s_configurations[tokenToBorrow].lendFactor;

        // Get the total USD value of the user's collateral assets
        (uint256 userCollateralValueInUSD,) = _getAccountInformation(user);

        // Adjust the user's collateral value for the lend factor of the token to borrow
        uint256 collateralAdjustedForLendFactor = (userCollateralValueInUSD * tokenLendFactor) / LEND_FACTOR_PRECISION;

        return collateralAdjustedForLendFactor;
    }

    /**
     * @notice This function is used to determine whether a user is able to borrow a specific token.
     * @param user The address of the user to check.
     * @param tokenToBorrow The address of the token to borrow.
     * @param amountToBorrow The amount of the token to borrow.
     * @return Whether the user is able to borrow the specified token.
     */
    function _canBorrowSpecificToken(address user, address tokenToBorrow, uint256 amountToBorrow)
        internal
        view
        isAllowedToken(tokenToBorrow)
        moreThanZero(amountToBorrow)
        returns (bool)
    {
        // Get the user's collateral and borrow value information
        (, uint256 userBorrowValueInUsd) = _getAccountInformation(user);

        // Calculate collateral adjusted for lend factor
        uint256 collateralAdjustedForLendFactor = _calculateCollateralAdjustedForLendFactor(user, tokenToBorrow);

        // Get the USD value of the amount to borrow
        uint256 amountToBorrowConvertedToUsd = getUsdValue(tokenToBorrow, amountToBorrow);

        // Get the user's borrow value in USD plus the amount to borrow
        uint256 userBorrowValueInUsdPlusNewAmountToBorrow = amountToBorrowConvertedToUsd + userBorrowValueInUsd;

        // Ensure the user's health factor will be greater than 1 and that the user's collateral value
        // adjusted for lend factor is greater than or equal to the borrow value + amount to borrow
        return
            _healthFactor(user) >= 1e18 && collateralAdjustedForLendFactor >= userBorrowValueInUsdPlusNewAmountToBorrow;
    }

    /**
     * @notice This function is used to determine whether there is enough liquidity to borrow a specific token.
     * @param tokenToBorrowAddress The address of the token to borrow.
     * @param amountToBorrow The amount of the token to borrow.
     * @return Whether there is enough liquidity to borrow the specified token.
     */
    function _isAvailableLiquidityToBorrow(address tokenToBorrowAddress, uint256 amountToBorrow)
        internal
        view
        returns (bool)
    {
        (uint256 availableLiquidityToBorrow) = _availableLiquidity(tokenToBorrowAddress);
        return availableLiquidityToBorrow >= amountToBorrow;
    }

    /**
     * @notice This function is used to determine the available liquidity to a specific token.
     * @param token The address of the token to check.
     * @return The available liquidity to the specified token.
     */
    function _availableLiquidity(address token) internal view returns (uint256) {
        uint256 totalInternalBalance = s_totalInternalBalances[token];
        uint256 totalInternalDebt = s_totalInternalDebt[token];
        uint256 tokenAvailableLiquidity = totalInternalBalance - totalInternalDebt;
        return tokenAvailableLiquidity;
    }

    /**
     * @notice Calculates the utilization ratio for a specific token.
     * @dev The utilization ratio is the proportion of the total borrowed amount
     *      to the total liquidity available in the pool for a particular token,
     *      expressed as a percentage.
     * @param token The address of the token for which the utilization ratio is to be calculated.
     * @return The utilization ratio for the specified token, scaled by 1e2 (i.e., a result of 8e17 corresponds to a 80% utilization ratio).
     */
    function _calculateUtilization(address token) internal view returns (uint256) {
        uint256 totalBorrowed = s_totalInternalDebt[token];
        uint256 totalLiquidity = s_totalInternalBalances[token]; // assumindo que esta é a liquidez total
        if (totalLiquidity == 0) {
            return 0;
        }
        uint256 utilization = (totalBorrowed * PRECISION) / totalLiquidity;
        return utilization;
    }

    /**
     * @param tokenCollateralAddress The address of the collateral token
     * @param amountToWithdraw The amount of the collateral to withdraw
     * @param from The address of the user to redeem collateral from
     * @param to The address of ther user is paying the debt
     */
    function _redeemCollateral(address tokenCollateralAddress, uint256 amountToWithdraw, address from, address to)
        private
        moreThanZero(amountToWithdraw)
        nonReentrant
    {
        // Modify the internal balance of the sender.
        s_internalBalances[from][tokenCollateralAddress] -= amountToWithdraw;
        emit RedeemCollateral(from, to, tokenCollateralAddress, amountToWithdraw);

        // Removes the asset's total internal supply.
        s_totalInternalBalances[tokenCollateralAddress] -= amountToWithdraw;

        // Transfer underlying  to the user.
        bool success = ERC20(tokenCollateralAddress).transfer(to, amountToWithdraw);
        if (!success) {
            revert INVEngine__TransferFailed();
        }

        // Ensure the user's health factor is not broken
        _revertIfHealthFactorIsBroken(to);
    }

    /**
     * @param seizeAsset The address of the collateral token to get.
     * @param repayAsset The address of the borrowed token.
     * @param amountToRepay The amount of the borrowed token to repay.
     * @return totalAmountToRepay The amount of the borrowed token with discount to repay.
     */
    function _calculateRepayAmountOnLiquidation(address seizeAsset, address repayAsset, uint256 amountToRepay)
        internal
        view
        isAllowedToken(seizeAsset)
        isAllowedToken(repayAsset)
        moreThanZero(amountToRepay)
        returns (uint256, uint256)
    {
        uint256 amount = 1e18;

        // Fetch the price of the assets involved
        uint256 repayAssetPrice = getUsdValue(repayAsset, amount);
        uint256 seizeAssetPrice = getUsdValue(seizeAsset, amount);

        // Calculate the discount on the amount to repay
        uint256 discount = (amountToRepay * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalAmountToRepayAfterDiscount = amountToRepay - discount;

        // Calculate the amount to seize
        uint256 ratioBetweenRepayAssetPriceAndSeizeAssetPrice = (repayAssetPrice * PRECISION) / seizeAssetPrice;
        uint256 totalAmountToSeizeInSeizeAsset =
            (amountToRepay * ratioBetweenRepayAssetPriceAndSeizeAssetPrice) / PRECISION;

        return (totalAmountToRepayAfterDiscount, totalAmountToSeizeInSeizeAsset);
    }

    /**
     * @param repayAsset The address of the borrowed token.
     * @param repayer The address of the repayer.
     * @param amountToRepay The amount of borrow token to repay.
     */
    function _repayUserDebt(
        address repayAsset,
        address user,
        address repayer,
        uint256 amountToRepay,
        uint256 amountToRepayAfterDiscount
    ) public nonReentrant 
    // returns (uint256, uint256, uint256)
    {
        // Modify user internal debt and total internal debt
        s_internalDebt[user][repayAsset] -= amountToRepay;
        s_totalInternalDebt[repayAsset] -= amountToRepay;
        bool success = ERC20(repayAsset).transferFrom(repayer, address(this), amountToRepayAfterDiscount);
        if (!success) {
            revert INVEngine__TransferFailed();
        }

        _revertIfHealthFactorIsBroken(msg.sender); // I don't think tihs would ever hit...
    }

    /*///////////////////////////////////////////////////////////////
                    VIEW & PURE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @param user The address of the user to get earns
     * @param token The address of the token
     * @return The amount earned by user (in wei - 1e18)
     */
    function earned(address user, address token) public view returns (uint256) {
        InvRewardManager rewardManager = InvRewardManager(s_configurations[token].rewardManager);
        uint256 earn = rewardManager.earned(user);
        return earn;
    }

    /**
     * @param asset The address of the token to get borrow rate.
     * @return rate The borrow rate percentage per block (in wei - 1e18)
     */
    function borrowRate(address asset) external view returns (uint256 rate) {
        uint256 totalLiquidity = s_totalInternalBalances[asset];
        uint256 totalBorrow = s_totalInternalDebt[asset];
        address interestRateModel = s_configurations[asset].interestRateModel;

        rate = InvInterestRateModel(interestRateModel).getBorrowRate(totalLiquidity, totalBorrow);
    }

    function getWrapTokenAddress(address tokenCollaterallAddress) external view returns (address) {
        return s_wrapTokens[tokenCollaterallAddress];
    }

    function canBorrow(address user) external view returns (bool) {
        return _canBorrow(user);
    }

    function canBorrowSpecificToken(address user, address tokenToBorrow, uint256 amountToBorrow)
        external
        view
        returns (bool)
    {
        return _canBorrowSpecificToken(user, tokenToBorrow, amountToBorrow);
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 CollateralValueInUSD, uint256 BorrowValueInUSD)
    {
        (CollateralValueInUSD, BorrowValueInUSD) = _getAccountInformation(user);
    }

    function getUserHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    function isAvailableLiquidityToBorrow(address tokenToBorrowAddress, uint256 amountToBorrow)
        external
        view
        returns (bool)
    {
        return _isAvailableLiquidityToBorrow(tokenToBorrowAddress, amountToBorrow);
    }

    function getAvailableLiquidity(address tokenToBorrowAddress) external view returns (uint256) {
        return _availableLiquidity(tokenToBorrowAddress);
    }

    function getUtilization(address token) external view returns (uint256) {
        return _calculateUtilization(token);
    }

    function getUserInterestDue(address user, address token) public returns (uint256) {
        // Get Reward Manager
        InvRewardManager rewardManager = InvRewardManager(s_configurations[token].rewardManager);
        return rewardManager.calculateUserInterestDue(user);
    }

    function calculateRepayAmountOnLiquidation(address seizeAsset, address repayAsset, uint256 amountToRepay)
        external
        view
        returns (uint256, uint256)
    {
        return _calculateRepayAmountOnLiquidation(seizeAsset, repayAsset, amountToRepay);
    }

    function isBorrowing(address user, address tokenAddress) public view returns (bool) {
        return s_internalDebt[user][tokenAddress] > 0;
    }

    function getPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }

    function getWrapToken(address token) external view returns (address) {
        return s_wrapTokens[token];
    }

    function getVault(address token) external view returns (address) {
        return s_vaults[token];
    }

    function getDecimals(address token) external view returns (uint256) {
        return s_baseUnits[token];
    }

    function getTotalInternalBalances(address token) external view returns (uint256) {
        return s_totalInternalBalances[token];
    }

    function getInternalBalance(address user, address token) external view returns (uint256) {
        return s_internalBalances[user][token];
    }

    function getUserInternalDebt(address user, address token) external view returns (uint256) {
        return s_internalDebt[user][token];
    }

    function getTotalInternalDebt(address token) external view returns (uint256) {
        return s_totalInternalDebt[token];
    }

    function getWrapTokensTotalSuppply(address token, address wrapToken) external view returns (uint256) {
        return s_wrapTokensMinted[token][wrapToken];
    }

    function getConfiguration(address token) external view returns (Configuration memory) {
        return s_configurations[token];
    }

    function getCollateralToken(uint256 index) public view returns (address) {
        return s_collateralTokens[index];
    }

    function getCollateralTokensCount() public view returns (uint256) {
        return s_collateralTokens.length;
    }

    function getUserCollateralCount(address user) public view returns (uint256) {
        return s_userCollateral[user].length;
    }

    function getUserCollateralByIndex(address user, uint256 index) public view returns (address) {
        return s_userCollateral[user][index];
    }

    function isCollateralToken(address token) public view returns (bool) {
        return s_collaterals[token];
    }
}

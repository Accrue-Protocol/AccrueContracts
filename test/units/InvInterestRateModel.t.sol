import {Test, console} from "forge-std/Test.sol";
import {InvInterestRateModel} from "../../src/InvInterestRateModel.sol";

contract InvInterestRateModelTest is Test {
    InvInterestRateModel rateModel;

    function setUp() public {
        rateModel = new InvInterestRateModel(
            2e16,  // s_baseRatePerYear
            1e17,  // s_multiplierPerYear
            2e17,  // s_jumpMultiplierPerYear
            8e17,  // s_inflectionPoint
            2e17,  // s_smoothingFactor
            4e17,  // s_maxRatePerYear
            1e16,  // s_minRatePerYear
            address(this)  // owner
        );
    }

    function testInitialSetup() public {
        assertEq(rateModel.getBaseRatePerYear(), 2e16);
        assertEq(rateModel.getMultiplierPerYear(), 1e17);
        assertEq(rateModel.getJumpMultiplierPerYear(), 2e17);
        assertEq(rateModel.getInflectionPoint(), 8e17);
        assertEq(rateModel.getSmoothingFactor(), 2e17);
        assertEq(rateModel.getMaxRatePerYear(), 4e17);
        assertEq(rateModel.getMinRatePerYear(), 1e16);
    }

    function testGetBorrowRateLowUtilization() public {
        uint256 totalLiquidity = 1e18; // 100%
        uint256 totalBorrow = 5e17; // 50% utilization
        uint256 result = rateModel.getBorrowRate(totalLiquidity, totalBorrow);
        uint256 expected = 3e16; // 3%
        assertEq(result, expected);
    }

    function testGetBorrowRateHighUtilization() public {
        uint256 totalLiquidity = 1e18; // 100%
        uint256 totalBorrow = 9e17; // 90% utilization
        uint256 result = rateModel.getBorrowRate(totalLiquidity, totalBorrow);
        uint256 expected = 4e16; // 4%
        assertEq(result, expected);
    }

    function testSetParamsByOwner() public {
        rateModel.setParams(
            3e16, // new baseRatePerYear
            2e17, // new multiplierPerYear
            3e17, // new jumpMultiplierPerYear
            7e17, // new inflectionPoint
            1e17, // new smoothingFactor
            5e17, // new maxRatePerYear
            5e16 // new minRatePerYear
        );
        // Verifique se os valores foram atualizados corretamente
        assertEq(rateModel.getBaseRatePerYear(), 3e16);
        assertEq(rateModel.getMultiplierPerYear(), 2e17);
        // ... outros asserts
    }

    function testFailSetParamsByNonOwner() public {
        InvInterestRateModel newRateModel = new InvInterestRateModel(
            2e16, 1e17, 2e17, 8e17, 2e17, 4e17, 1e16, msg.sender  // owner is `msg.sender` not `this`
        );
        newRateModel.setParams(3e16, 2e17, 3e17, 7e17, 1e17, 5e17, 5e16); // this should fail
    }
}

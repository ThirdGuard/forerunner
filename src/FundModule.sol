// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
// import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "zodiac/core/Module.sol";
import "@gnosis.pm/safe-contracts/contracts/common/Enum.sol";
import "forge-std/console.sol";
import "./WhitelistManager.sol";
import "./FundToken.sol";
import "./compliance/IModularCompliance.sol";
import "./IRoles.sol";
import "zodiac-modifier-roles/Types.sol";

contract FundModule is Module, FundToken, WhitelistManager {
    struct FundState {
        uint256 totalAssets; //NAV of fund
        uint256 sharePrice; //Price per share of fund
        uint256 highWaterMark; //A share price level that needs to be exceeded for performance to be due
        uint256 lastValuationTime; //last time the accountant/fund admin valued the fund
        uint256 lastAumFeeCalcTime; //last time a aum fee calculation was made
        uint256 pendingAumFees; //pending but unpaid aum fees
        uint256 pendingPerfFees; //pending but unpaid performance fees
        uint256 aumFeeRatePerSecond; //aum fee charge per second to simplfy fee calcs
        uint256 perfFeeRate; //performance fee amount
        uint256 lastCrystalised; //timestamp of last time performance fees where crystalised and paid
        uint256 crystalisationPeriod; //how much time needs to pass before performance fees can be claimed periodically
    }

    //investors wanting to withdraw/invest queue an action to do so, this action is stored in a PendingTransaction
    struct PendingTransaction {
        address investor;
        uint256 valueOrShares; //this is either a value or shares amount :/
        bool isInflow;
    }

    //map an investor's addy to their PendingTransaction
    mapping(address => PendingTransaction) private _transactionQueue;

    mapping(address => bytes32) public managerPermissionTiers;

    error ManagerNotPermissioned();
    error RolesNotConnected();

    address public manager;
    address public accountant;
    address public guardian;
    FundState public fundState;
    IERC20Metadata public baseAsset;
    address[] private _investors;

    IRoles public roles;

    // error ModuleTransactionFailed();

    // event ModifiedWhitelist(address indexed investor, uint256 timestamp, bool isWhitelisted);
    event Invested(
        address indexed baseAsset, address indexed investor, uint256 timestamp, uint256 amount, uint256 shares
    );
    event Withdrawn(
        address indexed baseAsset, address indexed investor, uint256 timestamp, uint256 amount, uint256 shares
    );
    event Priced(uint256 totalAssets, uint256 sharePrice, uint256 timestamp);

    event ComplianceAdded(address indexed _compliance);

    constructor(
        string memory _name,
        string memory _symbol,
        address _manager,
        address _accountant,
        address _fundSafe,
        address _baseAsset,
        uint256 _aumFeeRatePerSecond,
        uint256 _perfFeeRate,
        uint256 _crystalisationPeriod
    ) FundToken(_name, _symbol) WhitelistManager(_accountant) {
        bytes memory initializeParams = abi.encode(
            _manager, _accountant, _fundSafe, _baseAsset, _aumFeeRatePerSecond, _perfFeeRate, _crystalisationPeriod
        );
        setUp(initializeParams);
    }

    /// @dev Initialize function, will be triggered when a new proxy is deployed
    /// @param initializeParams Parameters of initialization encoded
    function setUp(bytes memory initializeParams) public virtual override initializer {
        //This func is needed for modules as they are minimal proxies pointing to a master copy so its like a constructor work around
        __Ownable_init();
        (
            address _manager,
            address _accountant,
            address _fundSafe,
            address _baseAsset,
            uint256 _aumFeeRatePerSecond,
            uint256 _perfFeeRate,
            uint256 _crystalisationPeriod
        ) = abi.decode(initializeParams, (address, address, address, address, uint256, uint256, uint256));
        manager = _manager;
        accountant = _accountant;
        fundState = FundState({
            totalAssets: 0,
            sharePrice: 1 ether,
            highWaterMark: 1 ether,
            lastValuationTime: block.timestamp,
            lastAumFeeCalcTime: block.timestamp,
            pendingAumFees: 0,
            pendingPerfFees: 0,
            aumFeeRatePerSecond: _aumFeeRatePerSecond,
            perfFeeRate: _perfFeeRate,
            lastCrystalised: block.timestamp,
            crystalisationPeriod: _crystalisationPeriod
        });
        //IERC20Metadata was needed as it also exposes decimals()
        baseAsset = IERC20Metadata(_baseAsset);
        require(baseAsset.decimals() <= 18); //@note precision errors will arise if decimals > 18
        //This module will execute tx's on behalf of this avatar (aka sc wallet)
        setAvatar(_fundSafe);
        //Safe modules call on the Target contract (in our case its the safe too) so it to be set
        setTarget(_fundSafe);
        transferOwnership(_fundSafe);
    }

    bytes32 ROLE_KEY = 0x000000000000000000000000000000000000000000000000000000000000000f;
    bytes32 ROLE_KEY1 = 0x0000000000000000000000000000000000000000000000000000000000000001;

    function setPolicyEngine(address _roles, address _guardian) public {
        //@todo add gate
        roles = IRoles(_roles);
        _assignTier(ROLE_KEY, true);
        guardian = _guardian;
    }

    //Module inherits from ContextUpgradable.sol and ERC20 inherits from Context.sol, and both have an implementation for _msgSender & _msgData. Hence the need to override them here.
    //@audit Can this be abused? We are forced to implement something here. Come back to this
    function _msgSender() internal view virtual override(ContextUpgradeable, Context) returns (address) {
        // return ContextUpgradeable._msgSender();
        // return address(0);
        return super._msgSender();
    }

    function _msgData() internal view virtual override(ContextUpgradeable, Context) returns (bytes calldata) {
        // return ContextUpgradeable._msgData();
        // return hex"";
        return super._msgData();
    }

    modifier onlyManager() {
        require(msg.sender == manager, "Only the manager can call this function.");
        _;
    }

    modifier onlyGuardian() {
        require(msg.sender == guardian, "Only the guardian can call this function.");
        _;
    }

    modifier onlyAccountant() {
        require(msg.sender == accountant, "Only the accountant can call this function.");
        _;
    }

    //Allows investors queue actions to invest
    function queueInvestment(uint256 _amount) public onlyWhitelisted {
        require(_amount > 0, "invest <= 0");
        console.log("base asset of inv:", baseAsset.balanceOf(msg.sender));
        require(baseAsset.balanceOf(msg.sender) >= _amount, "Insufficient baseAsset");
        require(_transactionQueue[msg.sender].investor == address(0), "investor already in queue");
        _transactionQueue[msg.sender] = PendingTransaction(msg.sender, _amount, true);
    }

    //Allows investors queue actions to withdraw
    function queueWithdrawal(uint256 _shares) public onlyWhitelisted {
        require(_shares > 0, "shares <= 0");
        require(balanceOf(msg.sender) >= _shares, "insufficient shares");
        require(_transactionQueue[msg.sender].investor == address(0), "investor already in queue");
        _transactionQueue[msg.sender] = PendingTransaction(msg.sender, _shares, false);
    }

    //Allows investors to cancel a previously queuedAction
    function cancelQueuedAction() public onlyWhitelisted {
        PendingTransaction memory transaction = _transactionQueue[msg.sender];
        if (transaction.investor != address(0)) {
            delete _transactionQueue[msg.sender];
        }
    }

    //Fund admin calls this to price the fund, and subsequent actions can be processed like investments, withdrawals and fee payments.
    //@audit fixme - Investors can grief this heavily by queueing an invest and removing the approval before updateStateWithPrice called making this whole thing fail
    function updateStateWithPrice(uint256 netAssetValue) public onlyAccountant {
        //value fund so shares can be accurately issued and burnt
        _customValuation(netAssetValue);
        // fee logic I stripped out needs to go here
        //@todo Do we need to process withdrawals first before we process investments? worried about inaccurate share issuance if we don't do it seperatley [verify this!]
        for (uint256 i = 0; i < _whitelistAddresses.length; i++) {
            address investor = _whitelistAddresses[i];
            PendingTransaction memory transaction = _transactionQueue[investor];
            //empty struct default value is the zero for that type so here we are basically checking transaction is not empty
            if (transaction.investor != address(0)) {
                //     //transaction is a withdrawal
                if (!transaction.isInflow) {
                    //if pending fees are zero then isPendingUncrystalised will false as all fees would be paid up already
                    //@todo is isPendingUncrystalised bool necessary? maybe the zero value if fees paid up won't cause issues with withdraw
                    if (fundState.pendingPerfFees != 0) {
                        _withdraw(transaction.investor, transaction.valueOrShares, true);
                    } else {
                        _withdraw(transaction.investor, transaction.valueOrShares, false);
                    }
                    //transaction is an investment
                } else {
                    _invest(transaction.investor, transaction.valueOrShares);
                }
                delete _transactionQueue[investor];
            }
        }
    }

    //Process the investment action, to be called when processing transaction queue
    function _invest(address _investor, uint256 _amount) internal {
        require(_amount > 0, "Invest <= 0");
        require(baseAsset.balanceOf(_investor) >= _amount, "Insufficient baseAsset");
        baseAsset.transferFrom(_investor, this.avatar(), _amount);
        // Share issuance formula:
        // s = i/(i+a) * (t + s) simplifies to s = it/a
        //@todo does newShares bug out if we start a fund with 18 decimals?
        _amount = (_amount * 1 ether) / 10 ** baseAsset.decimals();
        // Transfer the base tokens to the Safe
        // @audit lol not sure how i missed this but we aren't even pulling baseAsset from the investor. Will do this next!
        uint256 newShares = _amount; //first shares are issued at 1
        if (totalSupply() != 0) {
            newShares = (_amount * totalSupply() / (1 ether)) * (1 ether) / fundState.totalAssets;
        }
        mint(_investor, newShares);
        fundState.totalAssets += _amount;
        fundState.sharePrice = fundState.totalAssets * (1 ether) / totalSupply();
        emit Invested(address(baseAsset), _investor, block.timestamp, _amount, newShares);
    }

    //Process the withdraw action, to be called when processing the transaction queue only
    function _withdraw(address _investor, uint256 _shares, bool isPendingUncrystalised) internal {
        require(balanceOf(_investor) >= _shares, "insufficient shares");
        //Investors share of assets
        uint256 grossPayout = _shares * fundState.sharePrice * 10 ** (baseAsset.decimals()) / 1 ether / 1 ether;
        //we need to deduct perfomance fees that may not have been crystalised yet before an investor leaves the fund. Without this manager gets screwed.
        uint256 netPayout;
        if (isPendingUncrystalised) {
            //investors share of uncrystalised performance fees
            uint256 crystalisedShareOfFees = _shares * fundState.pendingPerfFees / totalSupply() / 1 ether; //@todo fix weimath here - also could there be a case of zero total supply?
            //ensure investor receives netPayout and not gross as fees are owed to the manager
            netPayout = grossPayout - crystalisedShareOfFees;
            fundState.pendingPerfFees -= crystalisedShareOfFees;
            _pay(manager, crystalisedShareOfFees);
        } else {
            //here no perf fee is due
            netPayout = grossPayout;
        }
        burn(_investor, _shares);
        fundState.totalAssets = fundState.totalAssets - (grossPayout * 1 ether / 10 ** (baseAsset.decimals()));
        //if total supply is 0 because of a full withdrawal we will get div 0 error without this
        if (totalSupply() != 0) {
            fundState.sharePrice = fundState.totalAssets * (1 ether) / totalSupply();
        } else {
            fundState.sharePrice = 1 ether;
        }
        _pay(_investor, netPayout);
        emit Withdrawn(address(baseAsset), msg.sender, block.timestamp, netPayout, _shares);
    }

    //Allows fund admin to price the fund via other func
    function _customValuation(uint256 netAssetValue) internal {
        fundState.lastValuationTime = block.timestamp;
        fundState.totalAssets = netAssetValue;
        if (fundState.totalAssets == 0) {
            fundState.sharePrice = 1 ether;
        } else {
            fundState.sharePrice = fundState.totalAssets * (1 ether) / totalSupply();
        }
        emit Priced(fundState.totalAssets, fundState.sharePrice, block.timestamp);
    }

    //legacy, remove or change: originally here in case of emergency where baseAsset has some issue and needs to be changed for redemption purposes
    function changeBaseAsset(address newBaseAsset) public onlyManager {
        require(newBaseAsset != address(0), "!address");
        require(IERC20Metadata(newBaseAsset).decimals() <= 18); //precision errors will arise if decimals > 18
        baseAsset = IERC20Metadata(newBaseAsset);
    }

    //Helper just to send baseAsset around (to manager for fees for example)
    function _pay(address to, uint256 amount) internal {
        exec(
            address(baseAsset), 0, abi.encodeWithSelector(baseAsset.transfer.selector, to, amount), Enum.Operation.Call
        );
    }

    function getFundState() public view returns (FundState memory) {
        return fundState;
    }

    /**
     *  @dev See {IToken-compliance}.
     */
    function compliance() external view returns (IModularCompliance) {
        return _tokenCompliance;
    }
    /**
     *  @dev See {IToken-setCompliance}.
     */

    function setCompliance(address _compliance) public onlyOwner {
        if (address(_tokenCompliance) != address(0)) {
            _tokenCompliance.unbindToken(address(this));
        }
        _tokenCompliance = IModularCompliance(_compliance);
        _tokenCompliance.bindToken(address(this));
        emit ComplianceAdded(_compliance);
    }

    /**
     *  @dev check the permissions on the roles contract & execute on the safe.
     */
    function execWithPermission(address to, uint256 value, bytes calldata data, Enum.Operation operation)
        public
        onlyManager
        returns (bool success)
    {
        bytes32 managerRole = managerPermissionTiers[msg.sender];
        if (managerRole == bytes32(0)) {
            revert ManagerNotPermissioned();
        }
        //@todo evaluate compliance here
        if (address(roles) != address(0)) {
            roles.execTransactionWithRole(to, value, data, uint8(operation), managerRole, true);
        } else {
            // off chain policy engine is being used
            exec(to, value, data, Enum.Operation.Call);
        }
    }

    //this should be guardian/manager multisig
    function modifyManager(address _manager, bytes32 roleKey) external onlyGuardian {
        //@todo ensure the roleKey exists within the roles mapping
        managerPermissionTiers[_manager] = roleKey;
    }

    //assign the fund module a role in the roles contract
    function _assignTier(bytes32 roleKey, bool active) internal {
        if (address(roles) == address(0)) {
            revert RolesNotConnected();
        }
        bool[] memory memberOf = new bool[](1);
        memberOf[0] = active;
        bytes32[] memory keys = new bytes32[](1);
        keys[0] = roleKey;
        roles.assignRoles(address(this), keys, memberOf);
    }

    function assignTier(bytes32 roleKey, bool active) external onlyGuardian {
        _assignTier(roleKey, active);
    }

    function allowTarget(bytes32 roleKey, address targetAddress, ExecutionOptions options) external onlyGuardian {
        if (address(roles) == address(0)) {
            revert RolesNotConnected();
        }
        roles.allowTarget(roleKey, targetAddress, uint8(options));
    }

    // function setDefaultRole(address module, bytes32 roleKey) external {}
}

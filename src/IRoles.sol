pragma solidity ^0.8.10;

interface IRoles {
    event AllowFunction(bytes32 roleKey, address targetAddress, bytes4 selector, uint8 options);
    event AllowTarget(bytes32 roleKey, address targetAddress, uint8 options);
    event AssignRoles(address module, bytes32[] roleKeys, bool[] memberOf);
    event AvatarSet(address indexed previousAvatar, address indexed newAvatar);
    event ChangedGuard(address guard);
    event ConsumeAllowance(bytes32 allowanceKey, uint128 consumed, uint128 newBalance);
    event DisabledModule(address module);
    event EnabledModule(address module);
    event ExecutionFromModuleFailure(address indexed module);
    event ExecutionFromModuleSuccess(address indexed module);
    event Initialized(uint8 version);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event RevokeFunction(bytes32 roleKey, address targetAddress, bytes4 selector);
    event RevokeTarget(bytes32 roleKey, address targetAddress);
    event RolesModSetup(address indexed initiator, address indexed owner, address indexed avatar, address target);
    event ScopeFunction(
        bytes32 roleKey, address targetAddress, bytes4 selector, ConditionFlat[] conditions, uint8 options
    );
    event ScopeTarget(bytes32 roleKey, address targetAddress);
    event SetAllowance(
        bytes32 allowanceKey,
        uint128 balance,
        uint128 maxBalance,
        uint128 refillAmount,
        uint64 refillInterval,
        uint64 refillTimestamp
    );
    event SetDefaultRole(address module, bytes32 defaultRoleKey);
    event SetUnwrapAdapter(address to, bytes4 selector, address adapter);
    event TargetSet(address indexed previousTarget, address indexed newTarget);

    struct ConditionFlat {
        uint8 parent;
        uint8 paramType;
        uint8 operator;
        bytes compValue;
    }

    function allowFunction(bytes32 roleKey, address targetAddress, bytes4 selector, uint8 options) external;
    function allowTarget(bytes32 roleKey, address targetAddress, uint8 options) external;
    function allowances(bytes32)
        external
        view
        returns (
            uint128 refillAmount,
            uint128 maxBalance,
            uint64 refillInterval,
            uint128 balance,
            uint64 refillTimestamp
        );
    function assignRoles(address module, bytes32[] memory roleKeys, bool[] memory memberOf) external;
    function avatar() external view returns (address);
    function defaultRoles(address) external view returns (bytes32);
    function disableModule(address prevModule, address module) external;
    function enableModule(address module) external;
    function execTransactionFromModule(address to, uint256 value, bytes memory data, uint8 operation)
        external
        returns (bool success);
    function execTransactionFromModuleReturnData(address to, uint256 value, bytes memory data, uint8 operation)
        external
        returns (bool success, bytes memory returnData);
    function execTransactionWithRole(
        address to,
        uint256 value,
        bytes memory data,
        uint8 operation,
        bytes32 roleKey,
        bool shouldRevert
    ) external returns (bool success);
    function execTransactionWithRoleReturnData(
        address to,
        uint256 value,
        bytes memory data,
        uint8 operation,
        bytes32 roleKey,
        bool shouldRevert
    ) external returns (bool success, bytes memory returnData);
    function getGuard() external view returns (address _guard);
    function getModulesPaginated(address start, uint256 pageSize)
        external
        view
        returns (address[] memory array, address next);
    function guard() external view returns (address);
    function isModuleEnabled(address _module) external view returns (bool);
    function owner() external view returns (address);
    function renounceOwnership() external;
    function revokeFunction(bytes32 roleKey, address targetAddress, bytes4 selector) external;
    function revokeTarget(bytes32 roleKey, address targetAddress) external;
    function scopeFunction(
        bytes32 roleKey,
        address targetAddress,
        bytes4 selector,
        ConditionFlat[] memory conditions,
        uint8 options
    ) external;
    function scopeTarget(bytes32 roleKey, address targetAddress) external;
    function setAllowance(
        bytes32 key,
        uint128 balance,
        uint128 maxBalance,
        uint128 refillAmount,
        uint64 refillInterval,
        uint64 refillTimestamp
    ) external;
    function setAvatar(address _avatar) external;
    function setDefaultRole(address module, bytes32 roleKey) external;
    function setGuard(address _guard) external;
    function setTarget(address _target) external;
    function setTransactionUnwrapper(address to, bytes4 selector, address adapter) external;
    function setUp(bytes memory initParams) external;
    function target() external view returns (address);
    function transferOwnership(address newOwner) external;
    function unwrappers(bytes32) external view returns (address);
}

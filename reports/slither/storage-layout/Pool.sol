
Pool:
+-------------------+-------------------------------------------------+------+--------+
|        Name       |                       Type                      | Slot | Offset |
+-------------------+-------------------------------------------------+------+--------+
|     ERC20.name    |                      string                     |  0   |   0    |
|    ERC20.symbol   |                      string                     |  1   |   0    |
|   ERC20.decimals  |                      uint8                      |  2   |   0    |
| ERC20.totalSupply |                     uint256                     |  3   |   0    |
|  ERC20.balanceOf  |           mapping(address => uint256)           |  4   |   0    |
|  ERC20.allowance  | mapping(address => mapping(address => uint256)) |  5   |   0    |
|    ERC20.nonces   |           mapping(address => uint256)           |  6   |   0    |
|     Pool.asset    |                     address                     |  7   |   0    |
|    Pool.manager   |                     address                     |  8   |   0    |
|    Pool._locked   |                     uint256                     |  9   |   0    |
+-------------------+-------------------------------------------------+------+--------+

ILoanManagerLike:
+------+------+------+--------+
| Name | Type | Slot | Offset |
+------+------+------+--------+
+------+------+------+--------+

ILoanManagerInitializerLike:
+------+------+------+--------+
| Name | Type | Slot | Offset |
+------+------+------+--------+
+------+------+------+--------+

ILiquidatorLike:
+------+------+------+--------+
| Name | Type | Slot | Offset |
+------+------+------+--------+
+------+------+------+--------+

ILoanV3Like:
+------+------+------+--------+
| Name | Type | Slot | Offset |
+------+------+------+--------+
+------+------+------+--------+

ILoanLike:
+------+------+------+--------+
| Name | Type | Slot | Offset |
+------+------+------+--------+
+------+------+------+--------+

IMapleGlobalsLike:
+------+------+------+--------+
| Name | Type | Slot | Offset |
+------+------+------+--------+
+------+------+------+--------+

IMapleLoanFeeManagerLike:
+------+------+------+--------+
| Name | Type | Slot | Offset |
+------+------+------+--------+
+------+------+------+--------+

IMapleProxyFactoryLike:
+------+------+------+--------+
| Name | Type | Slot | Offset |
+------+------+------+--------+
+------+------+------+--------+

IPoolDelegateCoverLike:
+------+------+------+--------+
| Name | Type | Slot | Offset |
+------+------+------+--------+
+------+------+------+--------+

IPoolLike:
+------+------+------+--------+
| Name | Type | Slot | Offset |
+------+------+------+--------+
+------+------+------+--------+

IPoolManagerLike:
+------+------+------+--------+
| Name | Type | Slot | Offset |
+------+------+------+--------+
+------+------+------+--------+

IWithdrawalManagerLike:
+------+------+------+--------+
| Name | Type | Slot | Offset |
+------+------+------+--------+
+------+------+------+--------+

ERC20Helper:
+------+------+------+--------+
| Name | Type | Slot | Offset |
+------+------+------+--------+
+------+------+------+--------+

IERC20Like:
+------+------+------+--------+
| Name | Type | Slot | Offset |
+------+------+------+--------+
+------+------+------+--------+

modules/pool-v2/contracts/Pool.sol analyzed (20 contracts)

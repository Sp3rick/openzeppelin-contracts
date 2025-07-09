// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.4.0) (governance/utils/VotesExtended.sol)
pragma solidity ^0.8.20;

import {IVotes} from "./IVotes.sol";

interface IMultiVotes is IVotes {

    /**
    * @dev Delegation units exceeded, introducing a risk of votes overflowing.
    */
    error MultiVotesExceededAvaiableUnits(uint256 units, uint256 left);

    /**
    * @dev Mismatch between number of given delegates and correspective units.
    */
    error MultiVotesDelegatesAndUnitsMismatch(address[] delegates, uint256[] units);

    /**
    * @dev Invalid operation, you should give at least one delegate.
    */
    error MultiVotesNoDelegatesGiven();

    /**
    * @dev Invalid, start should be equal or smaller than end.
    */
    error StartIsBiggerThanEnd(uint256 start, uint256 end);

    /**
    * @dev Emitted when a delegate is added to a delegation list.
    */
    event DelegateAdded(address indexed delegator, address indexed delegate, uint256 units);

    /**
    * @dev Emitted when units of already exhisting delegate are modified.
    */
    event DelegateModified(address indexed delegator, address indexed delegate, uint256 fromUnits, uint256 toUnits);

    /**
    * @dev Emitted when a delegate is removed from a delegation list.
    */
    event DelegateRemoved(address indexed delegator, address indexed delegate, uint256 units);

    /**
    * @dev Returns `account` delegations starting from `start` to `end`.
    */
    function multiDelegates(address account, uint256 start, uint256 end) external view returns (address[] memory);

    /**
     * @dev Use multi delegation mode and adds given delegates to the multi delegation list.
     */
    function multiDelegate(address[] calldata delegatess, uint256[] calldata units) external;

    /**
     * @dev Multi delegate votes from signer to `delegatess`.
     */
    function multiDelegateBySig(address[] calldata delegatess, uint256[] calldata units, uint256 nonce, uint256 expiry, uint8 v, bytes32 r, bytes32 s) external;

    /**
     * @dev Remove a list of delegates from delegates list of caller
     */
    function multiUnDelegate(address[] calldata delegatess) external;

    /**
     * @dev Multi undelegate votes from signer to `delegatess`.
     */
    function multiUnDelegateBySig(address[] calldata delegatess, uint256 nonce, uint256 expiry, uint8 v, bytes32 r, bytes32 s) external;

    /**
     * @dev Returns number of units a multi delegate of `account` has.
     *
     * NOTE: This function returns only the multi delegation value, defaulted units are not counted
     */
    function getDelegatedUnits(address account, address delegatee) external returns (uint256);

    /**
     * @dev Returns number of remaining units that defaulted delegation on `account` has.
     */
    function getDefaultedUnits(address account, address delegatee) external returns (uint256);

}

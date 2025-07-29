// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.4.0) (governance/utils/VotesExtended.sol)
pragma solidity ^0.8.20;

import {Checkpoints} from "../../utils/structs/Checkpoints.sol";
import {Votes} from "./Votes.sol";
import {SafeCast} from "../../utils/math/SafeCast.sol";
import {ECDSA} from "../../utils/cryptography/ECDSA.sol";
import "./IMultiVotes.sol";

/**
 * @dev Extension of {Votes} adding support for partial delegation.
 * You can give a fixed amount of voting power to each delegate and select one as "defaulted" wich takes all of the remaining votes
 * even when avaiable votes changes
 */
abstract contract MultiVotes is Votes, IMultiVotes {

    bytes32 private constant MULTI_DELEGATION_TYPEHASH =
        keccak256("MultiDelegation(address[] delegatees,uint256[] units,uint256 nonce,uint256 expiry)");

    bytes32 private constant MULTI_UNDELEGATION_TYPEHASH =
        keccak256("MultiUnDelegation(address[] delegatees,uint256[] units,uint256 nonce,uint256 expiry)");

    /**
     * NOTE: If you work directly with these mappings be careful.
     * Only _delegatesList is assured to have up to date and coherent data.
     * Values on _delegatesIndex and _delegatesUnits may be left dangling to save on gas.
     * So always use _accountHasDelegate() before giving trust to _delegatesIndex and _delegatesUnits values.
     */
    mapping(address account => address[]) private _delegatesList;
    mapping(address account => mapping(address delegatee => uint256)) private _delegatesIndex;
    mapping(address account => mapping(address delegatee => uint256)) private _delegatesUnits;

    mapping(address account => uint256) private _usedUnits;

    /**
     * @inheritdoc Votes
     */
    function _delegate(address account, address delegatee) internal override virtual {
        address oldDelegate = delegates(account);
        _setDelegate(account, delegatee);

        emit DelegateChanged(account, oldDelegate, delegatee);
        _moveDelegateVotes(oldDelegate, delegatee, _getAvaiableUnits(account));
    }

    /**
     * @dev Returns `account` multi delegations list starting from `start` to `end`.
     */
    function multiDelegates(address account, uint256 start, uint256 end) public view virtual returns (address[] memory) {
        uint256 maxLength = _delegatesList[account].length;
        require(end >= start, StartIsBiggerThanEnd(start, end));
        require(maxLength > start, StartIsBiggerThanEnd(start, maxLength));

        if(_delegatesList[account].length == 0) {
            return _delegatesList[account];
        }

        if (end >= maxLength) {
            end = maxLength - 1;
        }

        uint256 length = (end + 1) - start;
        address[] memory list = new address[](length);

        for(uint256 i; i < length; i++) {
            list[i] = _delegatesList[account][start + i];
        }

        return list;
    }

    /**
     * @dev Use multi delegation mode and select delegates and correspective power.
     */
    function multiDelegate(address[] calldata delegatess, uint256[] calldata units) public virtual {
        address account = _msgSender();
        _addDelegates(account, delegatess, units);
    }

    /**
     * @dev Multi delegate votes from signer to `delegatess`.
     */
    function multiDelegateBySig(
        address[] calldata delegatess,
        uint256[] calldata units, 
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual {
        if (block.timestamp > expiry) {
            revert VotesExpiredSignature(expiry);
        }

        bytes32 delegatesHash = keccak256(abi.encode(delegatess));
        bytes32 unitsHash = keccak256(abi.encode(units));
        bytes32 structHash = keccak256(
            abi.encode(
                MULTI_DELEGATION_TYPEHASH,
                delegatesHash,
                unitsHash,
                nonce,
                expiry
            )
        );

        address signer = ECDSA.recover(
            _hashTypedDataV4(structHash),
            v, r, s
        );

        _useCheckedNonce(signer, nonce);
        _addDelegates(signer, delegatess, units);
    }

    /**
     * @dev Remove a list of delegates from delegates list of caller.
     */
    function multiUnDelegate(address[] calldata delegatess) public virtual {
        address account = _msgSender();
        _removeDelegates(account, delegatess);
    }

    /**
     * @dev Multi undelegate votes from signer to `delegatess`.
     */
    function multiUnDelegateBySig(
        address[] calldata delegatess,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual {
        if (block.timestamp > expiry) {
            revert VotesExpiredSignature(expiry);
        }

        bytes32 delegatesHash = keccak256(abi.encode(delegatess));
        bytes32 structHash = keccak256(
            abi.encode(MULTI_UNDELEGATION_TYPEHASH, delegatesHash, nonce, expiry)
        );

        address signer = ECDSA.recover(
            _hashTypedDataV4(structHash),
            v, r, s
        );

        _useCheckedNonce(signer, nonce);
        _removeDelegates(signer, delegatess);
    }
    
    /**
     * @dev Add delegates to the multi delegation list or modify units of already exhisting.
     *
     * Emits multiple events {IMultiVotes-DelegateAdded} and {IMultiVotes-DelegateModified}.
     */
    function _addDelegates(address account, address[] calldata delegatess, uint256[] calldata unitsList) internal virtual {
        require(delegatess.length == unitsList.length, MultiVotesDelegatesAndUnitsMismatch(delegatess, unitsList));
        require(delegatess.length > 0, MultiVotesNoDelegatesGiven());

        uint256 givenUnits;
        uint256 removedUnits;
        for(uint256 i; i < delegatess.length; i++) {
            address delegatee = delegatess[i];
            uint256 units = unitsList[i];
            
            if(_accountHasDelegate(account, delegatee)) {
                (uint256 difference, bool refunded) = _modifyDelegate(account, delegatee, units);
                refunded ? givenUnits += difference : removedUnits += difference;
                continue;
            }

            _addDelegate(account, delegatee, units);
            givenUnits += units;
        }
        
        if(removedUnits >= givenUnits) {
            uint256 refundedUnits;
            /**
             * Cannot Underflow: code logic assures that _usedUnits[account] is just a sum of active delegates units
             * refundedUnits cannot be higher than _usedUnits[account].
             */
            unchecked {
                refundedUnits = removedUnits - givenUnits;
                _usedUnits[account] -= refundedUnits;
            }
            _moveDelegateVotes(address(0), delegates(account), refundedUnits);
        } else {
            uint256 addedUnits = givenUnits - removedUnits;
            uint256 avaiableUnits = _getAvaiableUnits(account);
            require(avaiableUnits >= addedUnits, MultiVotesExceededAvaiableUnits(addedUnits, avaiableUnits));

            _usedUnits[account] += addedUnits;
            _moveDelegateVotes(delegates(account), address(0), addedUnits);
        }
        
    }

    /**
     * @dev Add a delegate to multi delegations.
     */
    function _addDelegate(address account, address delegatee, uint256 units) internal virtual {
        if(units == 0) {
            return;
        }

        uint256 delegateIndex = _delegatesIndex[account][delegatee];

        delegateIndex = _delegatesList[account].length;
        _delegatesIndex[account][delegatee] = delegateIndex;
        _delegatesUnits[account][delegatee] = units;
        _delegatesList[account].push(delegatee);

        _moveDelegateVotes(address(0), delegatee, units);

        emit DelegateAdded(account, delegatee, units);
    }

    /**
     * @dev Modify units number of specific delegate.
     */
    function _modifyDelegate(
        address account,
        address delegatee,
        uint256 units
    ) internal virtual returns (uint256 difference, bool refunded) {
        if(units == 0) {
            return (0, false);
        }
        
        emit DelegateModified(account, delegatee, _delegatesUnits[account][delegatee], units);
                
        if(_delegatesUnits[account][delegatee] > units) {
            difference = _delegatesUnits[account][delegatee] - units;
            _moveDelegateVotes(delegatee, address(0), difference);
        } else {
            difference = units - _delegatesUnits[account][delegatee];
            refunded = true;
            _moveDelegateVotes(address(0), delegatee, difference);
        }

        _delegatesUnits[account][delegatee] = units;
        return (difference, refunded);
    }

    /**
     * @dev Remove a delegate from multi delegations list.
     *
     * Emits event {IMultiVotes-DelegateRemoved}.
     */
    function _removeDelegate(address account, address delegatee) internal virtual {
        if(!_accountHasDelegate(account, delegatee)) return;

        uint256 delegateIndex = _delegatesIndex[account][delegatee];
        uint256 lastDelegateIndex = _delegatesList[account].length-1;
        address lastDelegate = _delegatesList[account][lastDelegateIndex];
        uint256 refundedUnits = _delegatesUnits[account][delegatee];

        _delegatesList[account][delegateIndex] = lastDelegate;
        _delegatesIndex[account][lastDelegate] = delegateIndex;
        _delegatesList[account].pop();
        emit DelegateRemoved(account, delegatee, refundedUnits);

        /**
        * Cannot Underflow: code logic assures that _usedUnits[account] is just a sum of active delegates units
        * _delegatesUnits[account][delegatee] references to one of these active delegates units and right before in this
        * function it's removed from _delegatesList, so there is no way to uncount twice.
        */
        unchecked {
            _usedUnits[account] -= refundedUnits;
        }
        _moveDelegateVotes(delegatee, delegates(account), refundedUnits);
    }

    /**
     * @dev Remove list of delegates from the multi delegation list.
     */
    function _removeDelegates(address account, address[] memory delegatess) internal virtual {
        require(delegatess.length > 0, MultiVotesNoDelegatesGiven());

        for(uint256 i; i < delegatess.length; i++) {
            _removeDelegate(account, delegatess[i]);
        }
    }

    /**
     * @dev Returns number of units a multi delegate of `account` has.
     *
     * NOTE: This function returns only the multi delegation value, defaulted units are not counted
     */
    function getDelegatedUnits(address account, address delegatee) public view virtual returns (uint256) {
        if(!_accountHasDelegate(account, delegatee)) {
            return 0;
        }
        return _delegatesUnits[account][delegatee];
    }

    /**
     * @dev Returns number of units defaulted delegation `account` has.
     */
    function getDefaultedUnits(address account) public view virtual returns (uint256) {
        return _getAvaiableUnits(account);
    }
    
    /**
     * @dev Returns true if account has a specific delegate.
     *
     * NOTE: This works only assuming that everytime a value is added to _delegatesList
     * _delegatesUnits and _delegatesIndex are updated.
     */
    function _accountHasDelegate(address account, address delegatee) internal view virtual returns (bool) {
        uint256 delegateIndex = _delegatesIndex[account][delegatee];

        if(_delegatesList[account].length <= delegateIndex) {
            return false;
        }

        if(delegatee == _delegatesList[account][delegateIndex]) {
            return true;
        } else {
            return false;
        }
    }

    function _getAvaiableUnits(address account) internal view virtual returns (uint256) {
        return _getVotingUnits(account) - _usedUnits[account];
    }
    
}
